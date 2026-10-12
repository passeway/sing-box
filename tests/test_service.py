"""Real systemd/OpenRC lifecycle checks in disposable, native-architecture CI containers."""
import http.server
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import tarfile
import tempfile
import threading
import time
import unittest

from test_manager import CORE, ROOT

SCRIPT = ROOT / 'sing-box.sh'
CONFIG = Path('/etc/sing-box/config.json')
VERSION = '1.99.0'


def free_port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


@unittest.skipUnless(os.environ.get('SING_BOX_SERVICE_TESTS') == '1' and CORE and Path(CORE).exists(),
                     'requires a disposable container with a real service manager')
class ServiceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.architecture = self.probe('get_architecture').stdout.strip()
        self.fixture = Path(self.tmp.name) / 'release.tar.gz'
        with tarfile.open(self.fixture, 'w:gz') as archive:
            archive.add(CORE, arcname=f'sing-box-{VERSION}-linux-{self.architecture}/sing-box')
        self.alpine = self.probe('get_system_type').stdout.strip() == 'alpine'

    def probe(self, command):
        return subprocess.run(['bash', '-c', 'source "$1"; ' + command, 'probe', str(SCRIPT)],
                              capture_output=True, text=True, timeout=30)

    def shell(self, command, data='', expected=0):
        # Packages were installed by install_dependencies when building the image;
        # only the release download and public address lookup use local fixtures.
        setup = f'''source "$1"
install_dependencies() {{ :; }}
latest_release_version() {{ echo {VERSION}; }}
curl() {{ cp "{self.fixture}" "${{@: -1}}"; }}
get_public_ip() {{ echo 203.0.113.1; }}
fetch_text() {{ return 1; }}
'''
        result = subprocess.run(['bash', '-c', setup + command, 'service-test', str(SCRIPT)],
                                input=data, text=True, capture_output=True, timeout=90)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result

    def pid(self):
        result = self.probe('service_pid')
        pid = result.stdout.strip()
        return pid if result.returncode == 0 and pid.isdigit() and pid != '0' and Path(f'/proc/{pid}').exists() else ''

    def wait_for(self, probe, seconds, message):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            value = probe()
            if value:
                return value
            time.sleep(0.5)
        self.fail(message)

    def wait_for_quietly(self, probe, seconds):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if probe():
                return True
            time.sleep(0.5)
        return False

    def systemd_property(self, name):
        return subprocess.run(['systemctl', 'show', 'sing-box', '-p', name, '--value'],
                              capture_output=True, text=True, timeout=10).stdout.strip()

    def shadowsocks(self):
        return next(x for x in json.loads(CONFIG.read_text())['inbounds'] if x['type'] == 'shadowsocks')

    def assert_traffic(self):
        inbound = self.shadowsocks()
        local_port = free_port()
        client = Path(self.tmp.name) / 'client.json'
        client.write_text(json.dumps({
            'log': {'level': 'warn'},
            'inbounds': [{'type': 'mixed', 'listen': '127.0.0.1', 'listen_port': local_port}],
            'outbounds': [{'type': 'shadowsocks', 'server': '127.0.0.1', 'server_port': inbound['listen_port'],
                           'method': inbound['method'], 'password': inbound['password']}],
        }))
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200); self.end_headers(); self.wfile.write(b'service-traffic-ok')

            def log_message(self, *args):
                pass

        web = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=web.serve_forever, daemon=True)
        thread.start()
        try:
            with (Path(self.tmp.name) / 'client.log').open('w+') as log:
                process = subprocess.Popen([CORE, 'run', '-c', str(client)], stdout=log, stderr=subprocess.STDOUT)
                try:
                    def ready():
                        with socket.socket() as s:
                            return s.connect_ex(('127.0.0.1', local_port)) == 0
                    self.wait_for(ready, 10, 'local client did not start')
                    response = subprocess.run([
                        'curl', '-fsS', '--noproxy', '', '--max-time', '10', '--socks5-hostname',
                        f'127.0.0.1:{local_port}', f'http://127.0.0.1:{web.server_port}/',
                    ], capture_output=True, timeout=15)
                    self.assertEqual(response.returncode, 0, response.stderr.decode())
                    self.assertEqual(response.stdout, b'service-traffic-ok')
                finally:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill(); process.wait()
        finally:
            web.shutdown(); web.server_close(); thread.join(timeout=3)

    def test_real_install_crash_recovery_update_and_uninstall(self):
        self.assertFalse(CONFIG.exists(), 'service test must start in a clean container')
        try:
            installed = self.shell('install_or_update install')
            self.assertIn('🎉sing-box 安装成功，请在云安全组和系统防火墙中放行 TCP 端口 ', installed.stdout)
            self.assertIn('，UDP 端口 ', installed.stdout)
            self.assertIn('项目地址: https://github.com/passeway/sing-box', installed.stdout)
            self.assertTrue(self.pid())
            self.assert_traffic()

            # The service manager itself, not the script, restarts a crashed core.
            crashed = self.pid()
            os.kill(int(crashed), signal.SIGKILL)
            self.wait_for(lambda: self.pid() not in ('', crashed), 30,
                          'service manager did not restart a crashed core')
            self.assert_traffic()

            # A port stolen while the service is stopped: the supervisor may keep
            # reporting "started" while respawning, so the restart must still fail.
            self.shell('service_action stop')
            inbound = self.shadowsocks()
            with socket.socket(socket.AF_INET6 if inbound['listen'] == '::' else socket.AF_INET) as occupied:
                # Earlier traffic leaves TIME_WAIT connections on the port; they must not block the bind.
                # SO_REUSEADDR still refuses a port another socket is listening on.
                occupied.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                def bound():
                    try:
                        occupied.bind((inbound['listen'], inbound['listen_port']))
                        return True
                    except OSError:
                        return False
                if not bound() and not self.wait_for_quietly(bound, 10):
                    sockets = subprocess.run(['ss', '-tanp'], capture_output=True, text=True).stdout
                    self.fail(f'port {inbound["listen_port"]} still busy after stopping the service:\n{sockets}')
                occupied.listen()
                failed = self.shell('restart_service', expected=1)
                self.assertIn('服务未保持运行', failed.stderr)
                # The core keeps failing; the manager must give up instead of restarting forever.
                if self.alpine:
                    status = lambda: subprocess.run(['rc-service', 'sing-box', 'status'],
                                                    capture_output=True, timeout=10).returncode
                    self.wait_for(lambda: status() not in (0, 8), 90, 'supervise-daemon never gave up')
                    print(f'OpenRC status after giving up: {status()}', flush=True)
                else:
                    self.wait_for(lambda: self.systemd_property('ActiveState') == 'failed', 90,
                                  'systemd kept restarting a core that cannot start')
                    print(f'systemd restarts before giving up: {self.systemd_property("NRestarts")}', flush=True)
                    self.assertGreaterEqual(int(self.systemd_property('NRestarts')), 1)
                    # The limit is real: a start without reset-failed is refused.
                    self.assertNotEqual(subprocess.run(['systemctl', 'start', 'sing-box'],
                                                       capture_output=True, timeout=20).returncode, 0)
            # Recovers from the menu because service_action clears the limit first.
            self.shell('restart_service')
            self.assert_traffic()

            # Update refreshes an outdated service definition and keeps the configuration.
            if self.alpine:
                script = Path('/etc/init.d/sing-box')
                script.write_text(script.read_text().replace('respawn_max=5\n', ''))
            else:
                unit = Path('/etc/systemd/system/sing-box.service')
                unit.write_text(unit.read_text().replace('StartLimitIntervalSec=60\nStartLimitBurst=5\n', '')
                                .replace('Restart=on-failure', 'Restart=always'))
                subprocess.run(['systemctl', 'daemon-reload'], check=True, timeout=30)
                self.assertEqual(self.systemd_property('Restart'), 'always')
            configuration = CONFIG.read_bytes()
            running = self.pid()
            updated = self.shell('install_or_update update')
            self.assertIn(f'🎉sing-box 内核已更新至 {VERSION}，项目地址: https://github.com/passeway/sing-box', updated.stdout)
            self.assertNotIn(self.pid(), ('', running))
            self.assertEqual(CONFIG.read_bytes(), configuration)
            if self.alpine:
                self.assertIn('respawn_max=5\n', script.read_text())
            else:
                self.assertEqual(self.systemd_property('StartLimitIntervalUSec'), '1min')
                self.assertEqual(self.systemd_property('Restart'), 'on-failure')
                self.assertEqual(self.systemd_property('UnitFileState'), 'enabled')
            self.assert_traffic()

            # Updating a stopped service keeps it stopped.
            self.shell('service_action stop')
            stopped = self.shell('install_or_update update')
            self.assertIn('服务未运行，可通过菜单 3 启动', stopped.stdout)
            self.assertNotEqual(self.probe('is_running').returncode, 0)
            self.assertEqual(CONFIG.read_bytes(), configuration)

            uninstalled = self.shell('uninstall_service', 'y\n')
            self.assertIn('sing-box 卸载成功', uninstalled.stdout)
            for path in ('/usr/local/bin/sing-box', '/etc/sing-box', '/etc/init.d/sing-box',
                         '/etc/systemd/system/sing-box.service', '/var/log/sing-box.log'):
                self.assertFalse(Path(path).exists(), path)
            again = self.shell('uninstall_service', 'y\n')
            self.assertIn('未发现已安装的 sing-box，残留文件已清理', again.stdout)
        finally:
            # The container is discarded by CI even if a check fails.
            subprocess.run(['bash', '-c', 'source "$1"; service_action stop', 'cleanup', str(SCRIPT)],
                           capture_output=True, timeout=30)


if __name__ == '__main__':
    unittest.main()
