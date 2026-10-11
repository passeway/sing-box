import contextlib
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import pty
import select
import signal
import socket
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
SOURCE=(ROOT/'sing-box.sh').read_text()
HELPER=SOURCE.split('config_tool() {',1)[1].split("<<'PY'\n",1)[1].split('\nPY\n}',1)[0]
NS={}
exec(HELPER.split('\ntry:\n    action=',1)[0],NS)
CORE=os.environ.get('SING_BOX_TEST_BINARY','')

class ManagerTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)
        self.code=SOURCE.replace('if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi','')
        self.prefix=f'CONFIG_DIR="{self.root}"; CONFIG_FILE="$CONFIG_DIR/config.json"; CLIENT_CONFIG_FILE="$CONFIG_DIR/client.txt"; META_FILE="$CONFIG_DIR/client-meta.json"; BINARY="$CONFIG_DIR/sing-box";\n'
    def shell(self,code,data='',status=0):
        r=subprocess.run(['bash','-c',self.code+'\n'+self.prefix+code],input=data,text=True,capture_output=True,timeout=8)
        self.assertEqual(r.returncode,status,r.stderr+r.stdout)
        return r
    def release_fixture(self, version='1.15.0', architecture='amd64'):
        name=f'sing-box-{version}-linux-{architecture}.tar.gz'
        return {'tag_name':'v'+version,'draft':False,'prerelease':False,
                'assets':[{'name':name,'browser_download_url':f'https://github.com/SagerNet/sing-box/releases/download/v{version}/{name}'}]}
    def resolve_release(self, release, architecture='amd64', status=0):
        (self.root/'fixture.json').write_text(json.dumps(release))
        return self.shell('curl() { cp "$CONFIG_DIR/fixture.json" "${@: -1}"; }; '
                          f'latest_release_version {architecture} "$CONFIG_DIR/release.json"',status=status)
    def test_latest_release_is_dynamic_for_both_architectures(self):
        for architecture in ('amd64','arm64'):
            self.assertEqual(self.resolve_release(self.release_fixture('1.15.0',architecture),architecture).stdout.strip(),'1.15.0')
    def test_latest_release_rejects_invalid_or_unavailable_assets(self):
        for field,value in [('prerelease',True),('draft',True),('tag_name','v1.15.0-beta.1'),('tag_name','../../bad'),('assets',[])]:
            release=self.release_fixture();release[field]=value
            self.resolve_release(release,status=1)
        release=self.release_fixture();release['assets'][0]['browser_download_url']='https://example.com/core.tar.gz'
        self.resolve_release(release,status=1)
    def test_release_lookup_failure_preserves_installation(self):
        for name in ('sing-box','config.json'):(self.root/name).write_text('original')
        r=self.shell('install_dependencies() { :; }; curl() { return 22; }; install_or_update update',status=1)
        self.assertNotIn('安装/更新成功',r.stdout)
        for name in ('sing-box','config.json'):self.assertEqual((self.root/name).read_text(),'original')
        self.assertFalse(list(self.root.glob('.sing-box-install.*')))
    def test_invalid_release_json_fails(self):
        self.shell('curl() { printf broken > "${@: -1}"; }; latest_release_version amd64 "$CONFIG_DIR/release.json"',status=1)
    def test_architectures(self):
        for arch,want in [('x86_64','amd64'),('aarch64','arm64')]:
            self.assertEqual(self.shell(f'uname() {{ echo {arch}; }}; get_architecture').stdout.strip(),want)
        self.shell('uname() { echo armv7l; }; get_architecture',status=1)
    def test_eof_menu_and_continue(self):
        common='id() { echo 0; }; get_system_type() { echo debian; }; clear() { :; }; is_installed() { return 1; }; is_running() { return 1; }; main'
        for data in ['', 'invalid\n']:
            r=self.shell(common,data)
            self.assertEqual(r.stdout.count('=== sing-box 管理工具 ==='),1)
    def test_uninstall_requires_explicit_yes(self):
        for data in ['', '\n','n\n']:
            result=self.shell('service_action() { echo SHOULD_NOT_RUN; }; is_running() { echo SHOULD_NOT_RUN; }; uninstall_service',data)
            self.assertNotIn('SHOULD_NOT_RUN',result.stdout)
    def test_ip_fallback_and_manual(self):
        result=self.shell('fetch_text() { case "$1" in *amazonaws*) echo invalid;; *) echo 203.0.113.8;; esac; }; get_public_ip')
        self.assertEqual(result.stdout.strip(),'203.0.113.8')
        result=self.shell('fetch_text() { return 1; }; get_public_ip','garbage\n2001:db8::8\n')
        self.assertEqual(result.stdout.strip(),'2001:db8::8')
        self.shell('fetch_text() { return 1; }; get_public_ip',status=1)
    def test_atomic_write_failures(self):
        target=self.root/'secret'; target.write_text('previous')
        for cmd in ['cat','chown','chmod','mv']:
            self.shell(f'{cmd}() {{ return 1; }}; write_file "{target}" 600 <<< new',status=1)
            self.assertEqual(target.read_text(),'previous')
            self.assertFalse(list(self.root.glob('secret.tmp.*')))
    def test_config_validation_precedes_restart(self):
        r=self.shell('validate_config() { return 1; }; service_action() { echo SHOULD_NOT_RUN; }; restart_service',status=1)
        self.assertNotIn('SHOULD_NOT_RUN',r.stdout)
    def test_late_failure_is_not_reported_success(self):
        self.shell('validate_config() { :; }; service_action() { :; }; sleep() { :; }; is_running() { return 1; }; show_logs() { :; }; restart_service',status=1)
    def test_ports_avoid_live_listeners_and_batch_duplicates(self):
        with socket.socket() as listener:
            listener.bind(('0.0.0.0',0)); listener.listen(); busy=listener.getsockname()[1]
            used=set()
            with patch.object(NS['secrets'],'randbelow',side_effect=[busy-30000,22001,22001,22002]):
                first=NS['choose_port'](used); second=NS['choose_port'](used)
            self.assertEqual((first,second),(52001,52002))
    def test_migration_preserves_credentials_and_removes_shadowtls(self):
        c={'log':{'output':'stdout'},'inbounds':[
            {'type':'shadowtls','tag':'shadow','listen_port':41000,'detour':'shadowsocks-in'},
            {'type':'shadowsocks','tag':'shadowsocks-in','listen':'127.0.0.1','listen_port':41001,'password':'unchanged'},
            {'type':'anytls','tag':'anytls-in','listen_port':41002,'users':[{'password':'reused-public-key'}]}]}
        migrated=NS['migrate'](copy.deepcopy(c))
        self.assertEqual([x['type'] for x in migrated['inbounds']],['shadowsocks','anytls','snell'])
        self.assertEqual(migrated['inbounds'][0]['password'],'unchanged')
        self.assertNotIn(migrated['inbounds'][0]['listen'],['127.0.0.1','::1'])
        self.assertEqual(migrated['inbounds'][1]['users'],c['inbounds'][2]['users'])
        again=NS['migrate'](copy.deepcopy(migrated))
        self.assertEqual(again,migrated)
    def test_migration_rejects_dangling_routes(self):
        c={'inbounds':[{'type':'shadowtls','tag':'shadow'}],'route':{'rules':[{'inbound':['shadow'],'outbound':'direct'}]}}
        with self.assertRaises(ValueError): NS['migrate'](c)
    def test_client_export_uses_actual_values(self):
        c={'inbounds':[{'type':'hysteria2','listen_port':40123,'tag':'hy','users':[{'password':'secret'}]},
                       {'type':'shadowsocks','listen_port':40456,'tag':'ss','method':'2022-blake3-aes-128-gcm','password':'test'},
                       {'type':'snell','listen_port':40789,'tag':'snell','psk':'some-test-psk','version':6,'mode':'default'}]}
        out=NS['export'](c,{'address':'203.0.113.1','name':'HK'})
        obj=json.loads(out.split('\n\n# Surge')[0].split('\n',1)[1])
        self.assertEqual(obj['proxies'][0]['server'],'203.0.113.1')
        self.assertEqual(obj['proxies'][0]['port'],40123)
        self.assertNotIn('plugin',obj['proxies'][1])
        self.assertIn('psk=some-test-psk, version=6',out)
        c['inbounds'][0]['listen_port']=41111
        self.assertIn('"port": 41111',NS['export'](c,{'address':'203.0.113.1'}))
    def test_v2rayn_share_parameters_and_scalar_short_id(self):
        from urllib.parse import urlsplit, parse_qs
        for short_ids in ['123abc', ['123abc'], '', []]:
            c={'inbounds':[
                {'type':'vless','listen_port':34359,'users':[{'uuid':'test-uuid'}],
                 'tls':{'reality':{'private_key':'test','short_id':short_ids}}},
                {'type':'anytls','listen_port':47903,'users':[{'password':'test-password'}]},
                {'type':'hysteria2','listen_port':38183,'users':[{'password':'test-password'}]}]}
            with patch.dict(NS, {'public_key':lambda _: 'test-public-key'}):
                out=NS['export'](c,{'address':'203.0.113.1'})
            links={urlsplit(line).scheme:parse_qs(urlsplit(line).query,keep_blank_values=True)
                   for line in out.splitlines() if line.startswith(('vless://','anytls://','hy2://'))}
            self.assertEqual(links['vless']['sid'],['123abc' if short_ids else ''])
            self.assertEqual(links['anytls']['insecure'],['1'])
            self.assertEqual(links['hy2']['insecure'],['1'])
    def test_ctrl_c_returns_to_menu(self):
        fake=self.root/'journalctl';fake.write_text('#!/bin/sh\necho LOG_READY\nexec sleep 30\n');fake.chmod(0o755)
        runner=self.root/'runner';runner.write_text(self.code+'\n'+self.prefix+f'export PATH="{self.root}:$PATH"\nget_system_type() {{ echo debian; }}; show_logs follow; echo BACK_TO_MENU\n')
        pid,fd=pty.fork()
        if pid==0: os.execlp('bash','bash',str(runner))
        out=b''
        try:
            deadline=time.monotonic()+5
            while b'LOG_READY' not in out and time.monotonic()<deadline:
                if select.select([fd],[],[],.1)[0]:out+=os.read(fd,4096)
            self.assertIn(b'LOG_READY',out);os.write(fd,b'\x03')
            while b'BACK_TO_MENU' not in out and time.monotonic()<deadline:
                if select.select([fd],[],[],.1)[0]:
                    try: out+=os.read(fd,4096)
                    except OSError: break
            self.assertIn(b'BACK_TO_MENU',out)
        finally:
            try:os.killpg(pid,signal.SIGTERM)
            except ProcessLookupError:pass
            os.waitpid(pid,0);os.close(fd)
    def test_service_and_cron_templates_parse(self):
        for marker in ['#!/sbin/openrc-run','#!/bin/sh\nexec /usr/sbin/logrotate']:
            block=SOURCE.split(marker,1)[1].split('\nEOF',1)[0]
            subprocess.run(['sh','-n'],input=marker+block,text=True,check=True)

    def test_ipv6_disabled_falls_back_but_busy_port_is_rejected(self):
        import errno
        real_socket=socket.socket
        class IPv6Socket:
            def setsockopt(self,*args): pass
            def bind(self,*args): raise OSError(error,'fixture')
            def close(self): pass
        def factory(family,*args,**kwargs):
            return IPv6Socket() if family==socket.AF_INET6 else real_socket(family,*args,**kwargs)
        for error in (errno.EADDRNOTAVAIL,errno.EAFNOSUPPORT,errno.ENODEV):
            with patch.object(socket,'socket',factory),patch.object(socket,'has_ipv6',True):
                self.assertGreaterEqual(NS['choose_port'](set()),30000)
        for error in (errno.EADDRINUSE,errno.EACCES):
            with patch.object(socket,'socket',factory),patch.object(socket,'has_ipv6',True):
                with self.assertRaises(RuntimeError): NS['choose_port'](set())
    def test_ss2022_uri_uses_percent_encoded_credentials(self):
        from urllib.parse import urlsplit,unquote
        import base64
        for method in ('2022-blake3-aes-128-gcm','2022-blake3-aes-256-gcm','aes-128-gcm'):
            password='a+b/c=='
            c={'inbounds':[{'type':'shadowsocks','listen_port':42000,'method':method,'password':password}]}
            out=NS['export'](c,{'address':'2001:db8::1'})
            link=next(line for line in out.splitlines() if line.startswith('ss://'))
            uri=urlsplit(link)
            self.assertEqual(uri.hostname,'2001:db8::1')
            if method.startswith('2022-'):
                self.assertEqual(unquote(uri.username),method)
                self.assertEqual(unquote(uri.password),password)
                self.assertIn('a%2Bb%2Fc%3D%3D',link)
            else:
                raw=uri.username+'='*(-len(uri.username)%4)
                self.assertEqual(base64.urlsafe_b64decode(raw).decode(),method+':'+password)
    def test_only_legacy_anytls_password_is_rotated(self):
        c={'inbounds':[{'type':'vless','tls':{'reality':{'private_key':'fixture'}}},
           {'type':'anytls','users':[{'password':'public-key'},{'password':'independent'}]},
           {'type':'snell'}]}
        with patch.dict(NS,{'public_key':lambda _: 'public-key'}),contextlib.redirect_stderr(io.StringIO()) as output:
            migrated=NS['migrate'](copy.deepcopy(c))
            self.assertNotEqual(migrated['inbounds'][1]['users'][0]['password'],'public-key')
            self.assertEqual(migrated['inbounds'][1]['users'][1]['password'],'independent')
            self.assertEqual(NS['migrate'](copy.deepcopy(migrated)),migrated)
        self.assertIn('重新导入',output.getvalue())
    def transaction(self, failure='', running=True, status=1):
        stage=self.root/'stage';stage.mkdir()
        (stage/'config.json').write_text('new config')
        (stage/'core').write_text('new binary')
        (self.root/'config.json').write_text('old config')
        (self.root/'sing-box').write_text('old binary')
        (self.root/'service').write_text('old service')
        (self.root/'state').write_text('running' if running else 'stopped')
        code = r'''managed_service_files() { echo "$CONFIG_DIR/service"; }
get_system_type() { echo debian; }
service_enabled() { return 1; }
restore_autostart() { echo "$1" > "$CONFIG_DIR/enabled"; }
systemctl() { :; }
is_running() { [ "$(cat "$CONFIG_DIR/state")" = running ]; }
service_action() { echo stopped > "$CONFIG_DIR/state"; }
configure_service() { echo new > "$CONFIG_DIR/service"; echo rotation > "$CONFIG_DIR/logrotate.conf"; }
restart_service() { echo running > "$CONFIG_DIR/state"; }
'''+failure+'\ncommit_update "$CONFIG_DIR/stage" "$CONFIG_DIR/stage/core"'
        return self.shell(code,status=status)
    def assert_restored(self, running):
        self.assertEqual((self.root/'config.json').read_text(),'old config')
        self.assertEqual((self.root/'sing-box').read_text(),'old binary')
        self.assertEqual((self.root/'service').read_text(),'old service')
        self.assertFalse((self.root/'logrotate.conf').exists())
        self.assertEqual((self.root/'state').read_text().strip(),'running' if running else 'stopped')
    def test_binary_replace_failure_restores_config(self):
        self.transaction(r'''touch "$CONFIG_DIR/fail-once"
mv() { if [ "${@: -1}" = "$BINARY" ] && [ -f "$CONFIG_DIR/fail-once" ]; then rm "$CONFIG_DIR/fail-once"; return 1; fi; command mv "$@"; }''')
        self.assert_restored(True)
    def test_service_configuration_failure_restores_files(self):
        self.transaction('configure_service() { echo new > "$CONFIG_DIR/service"; return 1; }')
        self.assert_restored(True)
    def test_restart_failure_restores_running_service(self):
        self.transaction(r'''restart_service() { if [ "$(cat "$BINARY")" = 'new binary' ]; then echo stopped > "$CONFIG_DIR/state"; return 1; fi; echo running > "$CONFIG_DIR/state"; }''')
        self.assert_restored(True)
    def test_restart_failure_preserves_stopped_state(self):
        self.transaction('restart_service() { echo running > "$CONFIG_DIR/state"; return 1; }',running=False)
        self.assert_restored(False)
    def test_rollback_failure_keeps_recovery_files(self):
        self.transaction('configure_service() { return 1; }; mv() { case "$1 $2" in *.rollback.*) return 1;; esac; command mv "$@"; }')
        self.assertTrue((self.root/'stage/KEEP').exists())
        self.assertEqual((self.root/'stage/rollback/0').read_text(),'old config')
    def test_success_commits_pair(self):
        self.transaction(status=0)
        self.assertEqual((self.root/'config.json').read_text(),'new config')
        self.assertEqual((self.root/'sing-box').read_text(),'new binary')
        self.assertFalse((self.root/'stage/KEEP').exists())

@unittest.skipUnless(CORE and Path(CORE).exists(),'set SING_BOX_TEST_BINARY to run real core tests')
class CoreTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup); self.root=Path(self.tmp.name)
        subprocess.run(['openssl','req','-x509','-newkey','ec','-pkeyopt','ec_paramgen_curve:prime256v1','-nodes','-keyout',str(self.root/'key.pem'),'-out',str(self.root/'cert.pem'),'-days','1','-subj','/CN=www.bing.com'],check=True,capture_output=True)
        self.config=NS['make_config'](str(self.root),CORE)
    def test_real_generated_config_and_independent_password(self):
        p=self.root/'config.json';NS['write'](p,self.config)
        subprocess.run([CORE,'check','-c',str(p)],check=True,capture_output=True)
        types={x['type'] for x in self.config['inbounds']}
        self.assertEqual(types,{'hysteria2','vless','anytls','shadowsocks','snell'})
        vl=self.config['inbounds'][1];anytls=self.config['inbounds'][2]
        self.assertNotEqual(anytls['users'][0]['password'],NS['public_key'](vl['tls']['reality']['private_key']))
        self.assertNotEqual(anytls['users'][0]['password'],self.config['inbounds'][0]['users'][0]['password'])
        self.assertGreaterEqual(len(anytls['users'][0]['password']),43)
        self.assertEqual(len({x['listen_port'] for x in self.config['inbounds']}),5)
    def test_real_migrated_config(self):
        c=copy.deepcopy(self.config);c['inbounds']=[x for x in c['inbounds'] if x['type']!='snell']
        c['inbounds'][3]['listen']='127.0.0.1'
        c['inbounds'].append({'type':'shadowtls','detour':'shadowsocks-in','listen_port':29000})
        NS['write'](self.root/'migrated.json',NS['migrate'](c))
        subprocess.run([CORE,'check','-c',str(self.root/'migrated.json')],check=True,capture_output=True)

if __name__=='__main__':unittest.main()


