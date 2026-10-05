"""Real local proxy traffic tests with the official sing-box release (no external server)."""
import http.server
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import time
import unittest
from test_manager import NS, CORE

@unittest.skipUnless(CORE and Path(CORE).exists(),'requires official sing-box binary')
class ProxyTests(unittest.TestCase):
    def test_local_protocol_connections(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder)
            subprocess.run(['openssl','req','-x509','-newkey','ec','-pkeyopt','ec_paramgen_curve:prime256v1','-nodes','-keyout',str(root/'key.pem'),'-out',str(root/'cert.pem'),'-days','1','-subj','/CN=www.bing.com'],check=True,capture_output=True)
            config=NS['make_config'](folder,CORE)
            class Handler(http.server.BaseHTTPRequestHandler):
                def do_GET(self):
                    self.send_response(200);self.end_headers();self.wfile.write(b'proxy-regression-ok')
                def log_message(self,*args):pass
            http_server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
            thread=threading.Thread(target=http_server.serve_forever,daemon=True);thread.start()
            processes=[];logs=[]
            def launch(args,name):
                log=open(root/name,'w+');logs.append(log)
                proc=subprocess.Popen(args,stdout=log,stderr=subprocess.STDOUT);processes.append(proc)
                return proc
            try:
                # A local TLS 1.3 handshake target keeps the Reality test independent of the Internet.
                used={x['listen_port'] for x in config['inbounds']}
                tlsport=NS['choose_port'](used)
                launch(['openssl','s_server','-quiet','-accept',str(tlsport),'-cert',str(root/'cert.pem'),'-key',str(root/'key.pem'),'-tls1_3'],'tls.log')
                vless=next(x for x in config['inbounds'] if x['type']=='vless')
                vless['tls']['server_name']='www.bing.com'
                vless['tls']['reality']['handshake']={'server':'127.0.0.1','server_port':tlsport}
                for x in config['inbounds']:x['listen']='127.0.0.1'
                NS['write'](root/'server.json',config)
                server=launch([CORE,'run','-c',str(root/'server.json')],'server.log')
                time.sleep(.4)
                self.assertIsNone(server.poll(),(root/'server.log').read_text())
                for inbound in config['inbounds']:
                    with self.subTest(protocol=inbound['type']):
                        kind=inbound['type']
                        out={'type':kind,'tag':'proxy','server':'127.0.0.1','server_port':inbound['listen_port']}
                        if kind in ('hysteria2','anytls'):
                            out.update(password=inbound['users'][0]['password'],tls={'enabled':True,'server_name':'www.bing.com','insecure':True})
                        elif kind=='shadowsocks':out.update(method=inbound['method'],password=inbound['password'])
                        elif kind=='snell':out.update(version=6,psk=inbound['psk'],mode='default')
                        else:
                            reality=inbound['tls']['reality'];user=inbound['users'][0]
                            out.update(uuid=user['uuid'],flow=user['flow'],tls={'enabled':True,'server_name':'www.bing.com','utls':{'enabled':True,'fingerprint':'chrome'},'reality':{'enabled':True,'public_key':NS['public_key'](reality['private_key']),'short_id':reality['short_id'][0]}})
                        localport=NS['choose_port'](used)
                        client={'log':{'level':'warn'},'inbounds':[{'type':'mixed','listen':'127.0.0.1','listen_port':localport}],'outbounds':[out]}
                        NS['write'](root/'client.json',client)
                        subprocess.run([CORE,'check','-c',str(root/'client.json')],check=True,capture_output=True)
                        process=launch([CORE,'run','-c',str(root/'client.json')],kind+'.log')
                        try:
                            time.sleep(.2)
                            r=subprocess.run(['curl','-fsS','--noproxy','','--max-time','8','--socks5-hostname',f'127.0.0.1:{localport}',f'http://127.0.0.1:{http_server.server_port}/'],capture_output=True)
                            if r.returncode:
                                log=logs[-1];log.flush()
                                self.fail(f'{kind} proxy failed: {r.stderr.decode()}\n'+(root/(kind+'.log')).read_text())
                            self.assertEqual(r.stdout,b'proxy-regression-ok')
                        finally:
                            process.terminate();process.wait(timeout=5)
            finally:
                for p in processes:
                    if p.poll() is None:p.terminate();p.wait(timeout=5)
                for log in logs:log.close()
                http_server.shutdown();http_server.server_close();thread.join(timeout=3)

if __name__=='__main__':unittest.main()
