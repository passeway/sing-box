import importlib.util
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
        self.prefix=f'CONFIG_DIR="{self.root}"; CONFIG_FILE="$CONFIG_DIR/config.json"; CLIENT_CONFIG_FILE="$CONFIG_DIR/client.txt"; META_FILE="$CONFIG_DIR/client-meta.json"; BINARY="$CONFIG_DIR/sing-box"; OPERATION_LOCK="$CONFIG_DIR/operation.lock";\n'
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
        # The redirect fast-path passes a URL as the last argument; the API fallback
        # passes a file path.  Route each accordingly so the stub never writes to a URL.
        stub=('curl() { if [[ "${@: -1}" == http* ]]; then printf "%s" "${LOCATION:-}"; '
              'else cp "$CONFIG_DIR/fixture.json" "${@: -1}"; fi; }; ')
        return self.shell(stub+f'latest_release_version {architecture} "$CONFIG_DIR/release.json"',status=status)
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
        self.assertNotIn('🎉',r.stdout)
        for name in ('sing-box','config.json'):self.assertEqual((self.root/name).read_text(),'original')
        self.assertFalse(list(self.root.glob('.sing-box-install.*')))
    def test_redirect_fast_path_beats_rate_limited_api(self):
        # The asset HEAD probe uses a releases/download URL; answer it with a
        # final status code after following the asset redirect.
        stub='curl() { case "$*" in *api.github.com*) return 22;; *releases/download*) printf "200";; *) printf %s "$LOCATION"; esac; }; '
        r=self.shell(stub+'LOCATION=https://github.com/SagerNet/sing-box/releases/tag/v1.15.2; latest_release_version amd64 "$CONFIG_DIR/release.json"')
        self.assertEqual(r.stdout.strip(),'1.15.2')
        for location in ('https://github.com/SagerNet/sing-box/releases/tag/v1.16.0-beta.1',
                         'https://github.com/SagerNet/sing-box/releases/tag/../../x', 'https://example.com/releases/tag/v1.15.2', ''):
            self.shell(stub+f'LOCATION="{location}"; latest_release_version amd64 "$CONFIG_DIR/release.json"',status=1)
    def test_asset_probe_follows_redirect_and_checks_curl_status(self):
        stub = r'''curl() {
case "$*" in
 *api.github.com*) return 22;;
 *releases/download*)
   case "$*" in *-fsSL*"%{http_code}"*) ;; *) return 2;; esac
   printf %s "$ASSET_STATUS"; return "$ASSET_EXIT";;
 *) printf %s https://github.com/SagerNet/sing-box/releases/tag/v1.15.2;;
esac
}; '''
        result=self.shell(stub+'ASSET_STATUS=200; ASSET_EXIT=0; latest_release_version amd64 "$CONFIG_DIR/release.json"')
        self.assertEqual(result.stdout.strip(),'1.15.2')
        for code,exit_status in [('302',0),('404',22),('200',28),('000',7)]:
            self.shell(stub+f'ASSET_STATUS={code}; ASSET_EXIT={exit_status}; latest_release_version amd64 "$CONFIG_DIR/release.json"',status=1)

    def test_operation_lock_rejects_overlap_and_recovers_after_kill(self):
        holder=subprocess.Popen(['bash','-c',self.code+'\n'+self.prefix+
            'hold() { echo READY; read -r ignored; }; with_operation_lock hold'],
            stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        try:
            self.assertEqual(holder.stdout.readline().strip(),'READY')
            result=self.shell('with_operation_lock touch "$CONFIG_DIR/should-not-exist"',status=1)
            self.assertIn('管理操作正在运行',result.stderr)
            self.assertFalse((self.root/'should-not-exist').exists())
            holder.kill();holder.communicate(timeout=5)
            self.shell('with_operation_lock touch "$CONFIG_DIR/recovered"')
            self.assertTrue((self.root/'recovered').exists())
        finally:
            if holder.poll() is None: holder.kill()
            holder.communicate(timeout=5)

    def test_operation_lock_releases_after_failure(self):
        self.shell('with_operation_lock false',status=1)
        self.shell('with_operation_lock true')

    def test_service_commands_do_not_inherit_the_lock(self):
        for system,command in [('alpine','rc-service'),('debian','systemctl')]:
            result=self.shell(f'get_system_type() {{ echo {system}; }}; '+command+
                '() { if ( : >&9 ) 2>/dev/null; then return 1; fi; echo CLOSED; }; '
                'with_operation_lock service_action stop')
            self.assertEqual(result.stdout.strip(),'CLOSED')

    def test_invalid_release_json_fails(self):
        stub='curl() { if [[ "${@: -1}" == http* ]]; then printf "%s" ""; else printf broken > "${@: -1}"; fi; }; '
        self.shell(stub+'latest_release_version amd64 "$CONFIG_DIR/release.json"',status=1)
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
    def test_update_keeps_a_stopped_service_stopped(self):
        self.transaction('restart_service() { echo SHOULD_NOT_RUN; echo running > "$CONFIG_DIR/state"; }',running=False,status=0)
        self.assertEqual((self.root/'state').read_text().strip(),'stopped')
        self.assertEqual((self.root/'sing-box').read_text(),'new binary')
    def test_successful_update_preserves_disabled_autostart(self):
        self.transaction('configure_service() { echo true > "$CONFIG_DIR/enabled"; }',running=False,status=0)
        self.assertEqual((self.root/'enabled').read_text().strip(),'false')
        self.assertEqual((self.root/'state').read_text().strip(),'stopped')

    def test_successful_update_preserves_enabled_autostart(self):
        self.transaction('service_enabled() { return 0; }',status=0)
        self.assertEqual((self.root/'enabled').read_text().strip(),'true')

    def test_autostart_restore_failure_rolls_back_update(self):
        self.transaction(r'''restore_autostart() {
 if [ "$(cat "$BINARY")" = 'new binary' ]; then return 1; fi
 echo "$1" > "$CONFIG_DIR/enabled"
}''')
        self.assert_restored(True)
        self.assertEqual((self.root/'enabled').read_text().strip(),'false')

    def test_rollback_after_late_failure_preserves_stopped_state(self):
        self.transaction('rm() { case "$*" in *KEEP*) return 1;; esac; command rm "$@"; }',running=False)
        self.assert_restored(False)
    def test_rollback_failure_keeps_recovery_files(self):
        self.transaction('configure_service() { return 1; }; mv() { case "$1 $2" in *.rollback.*) return 1;; esac; command mv "$@"; }')
        self.assertTrue((self.root/'stage/KEEP').exists())
        self.assertEqual((self.root/'stage/rollback/0').read_text(),'old config')
    def test_update_preserves_configuration_bytes(self):
        import tarfile
        original='// user comment\n{"inbounds":[],"outbounds":[{"type":"direct"}]}\n'
        (self.root/'config.json').write_text(original)
        core=self.root/'fixture-core'
        core.write_text('#!/bin/sh\nexit 0\n');core.chmod(0o755)
        with tarfile.open(self.root/'fixture.tar.gz','w:gz') as archive:
            archive.add(core,arcname='sing-box-1.14.3-linux-amd64/sing-box')
        self.shell(r'''install_dependencies() { :; }
get_architecture() { echo amd64; }
latest_release_version() { echo 1.14.3; }
curl() { cp "$CONFIG_DIR/fixture.tar.gz" "${@: -1}"; }
managed_service_files() { :; }
is_running() { return 1; }
service_enabled() { return 1; }
restore_autostart() { :; }
configure_service() { :; }
restart_service() { :; }
refresh_clients() { :; }
install_or_update update''')
        self.assertEqual((self.root/'config.json').read_text(),original)
        self.assertFalse(list(self.root.glob('.sing-box-install.*')))
    def test_firewall_ports_follow_each_protocol(self):
        c={'inbounds':[{'type':'hysteria2','listen_port':40001},{'type':'vless','listen_port':40002},
                       {'type':'anytls','listen_port':40003},{'type':'shadowsocks','listen_port':40004},
                       {'type':'snell','listen_port':40005},{'type':'shadowsocks','listen_port':40006,'network':'udp'},
                       {'type':'direct','tag':'no-port'}]}
        self.assertEqual(NS['firewall_ports'](c),'TCP 端口 40002/40003/40004/40005，UDP 端口 40001/40004/40006')
        self.assertEqual(NS['firewall_ports']({'inbounds':[{'type':'vless','listen_port':443}]}),'TCP 端口 443')
        self.assertEqual(NS['firewall_ports']({'inbounds':[]}),'')
    def test_hidden_options_are_invalid_until_installed(self):
        stubs=('id() { echo 0; }; get_system_type() { echo debian; }; clear() { :; }; is_running() { return 1; }; '
               'install_or_update() { echo SHOULD_NOT_RUN; }; service_action() { echo SHOULD_NOT_RUN; }; '
               'restart_service() { echo SHOULD_NOT_RUN; }; show_logs() { echo SHOULD_NOT_RUN; }; refresh_clients() { echo SHOULD_NOT_RUN; }; ')
        r=self.shell(stubs+'is_installed() { return 1; }; main','3\n\n4\n\n5\n\n6\n\n7\n\n8\n\n0\n')
        self.assertNotIn('SHOULD_NOT_RUN',r.stdout)
        self.assertEqual(r.stdout.count('无效选项'),6)
        r=self.shell(stubs+'is_installed() { :; }; main','8\n\n0\n')
        self.assertIn('SHOULD_NOT_RUN',r.stdout)
    def test_leftover_configuration_blocks_install_before_download(self):
        (self.root/'config.json').write_text('{}')
        r=self.shell('install_dependencies() { echo SHOULD_NOT_RUN; }; curl() { echo SHOULD_NOT_RUN; }; install_or_update install',status=1)
        self.assertNotIn('SHOULD_NOT_RUN',r.stdout)
        self.assertIn('请先通过菜单 2 清理后重新安装',r.stderr)
    def test_uninstall_stops_a_unit_between_crash_restarts(self):
        stubs=(f'SYSTEMD_UNIT="{self.root}/unit"; get_system_type() {{ echo debian; }}; is_running() {{ return 1; }}; systemd_running() {{ :; }}; '
               'dpkg-query() { return 1; }; systemctl() { echo "systemctl $*"; }; service_action() { echo "STOP $1"; }; ')
        # Without a unit file there is nothing to stop.
        r=self.shell(stubs+'uninstall_service','y\n')
        self.assertNotIn('STOP',r.stdout)
        self.root.mkdir(); (self.root/'unit').write_text('[Service]\n')
        r=self.shell(stubs+'uninstall_service','y\n')
        self.assertIn('STOP stop',r.stdout)
        self.assertIn('systemctl disable sing-box',r.stdout)
        self.assertIn('sing-box 卸载成功',r.stdout)
    def test_update_without_configuration_fails_before_download(self):
        r=self.shell('install_dependencies() { echo SHOULD_NOT_RUN; }; curl() { echo SHOULD_NOT_RUN; }; install_or_update update',status=1)
        self.assertNotIn('SHOULD_NOT_RUN',r.stdout)
        self.assertIn('请先通过菜单 1 安装',r.stderr)
    def test_uninstall_without_installation_cleans_residue(self):
        (self.root/'leftover').write_text('x')
        stubs=('get_system_type() { echo debian; }; is_running() { return 1; }; systemd_running() { return 1; }; '
               'dpkg-query() { return 1; }; systemctl() { echo "systemctl $*" >&2; return 1; }; ')
        r=self.shell(stubs+'uninstall_service','y\n')
        self.assertIn('sing-box 卸载成功',r.stdout)  # the configuration directory existed
        self.assertFalse(self.root.exists())
        r=self.shell(stubs+'uninstall_service','y\n')
        self.assertIn('未发现已安装的 sing-box，残留文件已清理',r.stdout)
        self.assertNotIn('systemctl',r.stderr)
    def test_manual_start_resets_crash_limit(self):
        stub='get_system_type() { echo debian; }; systemctl() { if [ "$1" = show ]; then echo "$STATE"; else echo "systemctl $*"; fi; }; '
        r=self.shell(stub+'STATE=loaded; service_action restart; service_action start; service_action stop')
        self.assertEqual(r.stdout.splitlines(),['systemctl reset-failed sing-box','systemctl restart sing-box',
            'systemctl reset-failed sing-box','systemctl start sing-box','systemctl stop sing-box'])
        r=self.shell(stub+'STATE=not-found; service_action restart')
        self.assertEqual(r.stdout.splitlines(),['systemctl restart sing-box'])
    def test_wait_running_requires_the_same_live_process(self):
        common='sleep() { :; }; is_running() { :; }; '
        self.shell(common+'service_pid() { echo $$; }; wait_running')
        # A respawning core gets a new PID each time; the counter lives in a file because service_pid runs in $(...).
        self.shell(common+'service_pid() { echo x >> "$CONFIG_DIR/calls"; if [ $(($(wc -l < "$CONFIG_DIR/calls") % 2)) = 1 ]; then echo $$; else echo $PPID; fi; }; wait_running',status=1)
        self.shell(common+'service_pid() { echo 999999999; }; wait_running',status=1)
        self.shell(common+'service_pid() { echo 0; }; wait_running',status=1)
        self.shell('sleep() { :; }; is_running() { return 1; }; service_pid() { echo $$; }; wait_running',status=1)
    def test_install_summary_lists_ports_project_and_clients(self):
        import tarfile
        core=self.root/'fixture-core'
        core.write_text('#!/bin/sh\nexit 0\n');core.chmod(0o755)
        with tarfile.open(self.root/'fixture.tar.gz','w:gz') as archive:
            archive.add(core,arcname='sing-box-1.14.3-linux-amd64/sing-box')
        r=self.shell(r'''install_dependencies() { :; }
get_architecture() { echo amd64; }
latest_release_version() { echo 1.14.3; }
curl() { cp "$CONFIG_DIR/fixture.tar.gz" "${@: -1}"; }
config_tool() { echo '{}' > "$2"; }
configure_service() { :; }
restart_service() { echo SERVICE_LOG; }
refresh_clients() { printf 'CLIENT-A\nCLIENT-B\n'; }
firewall_ports() { echo 'TCP 端口 40002，UDP 端口 40001'; }
install_or_update install''')
        self.assertEqual(r.stdout.splitlines()[-4:],['',
            '🎉sing-box 安装成功，请在云安全组和系统防火墙中放行 TCP 端口 40002，UDP 端口 40001，项目地址: https://github.com/passeway/sing-box',
            'CLIENT-A','CLIENT-B'])
        update=r'''install_dependencies() { :; }
get_architecture() { echo amd64; }
latest_release_version() { echo 1.14.3; }
curl() { cp "$CONFIG_DIR/fixture.tar.gz" "${@: -1}"; }
commit_update() { :; }
refresh_clients() { echo CLIENT-A; }
is_running() { [ "$STATE" = running ]; }
'''
        updated='🎉sing-box 内核已更新至 1.14.3，项目地址: https://github.com/passeway/sing-box'
        r=self.shell(update+'STATE=running; install_or_update update')
        self.assertEqual(r.stdout.splitlines()[-3:],['',updated,'CLIENT-A'])
        r=self.shell(update+'STATE=stopped; install_or_update update')
        self.assertEqual(r.stdout.splitlines()[-4:],['',updated,'服务未运行，可通过菜单 3 启动','CLIENT-A'])
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
if __name__=='__main__':unittest.main()

