#!/usr/bin/env bash
# Debian / Ubuntu / Alpine multi-protocol server manager.
SING_BOX_VERSION="1.14.2"
CONFIG_DIR="/etc/sing-box"
CONFIG_FILE="$CONFIG_DIR/config.json"
CLIENT_CONFIG_FILE="$CONFIG_DIR/client.txt"
META_FILE="$CONFIG_DIR/client-meta.json"
BINARY="/usr/local/bin/sing-box"
SERVICE_NAME="sing-box"

fail() { printf '错误：%s\n' "$*" >&2; return 1; }
get_system_type() {
    local ID=""
    [ -r /etc/os-release ] && . /etc/os-release
    case "$ID" in debian|ubuntu|alpine) printf '%s\n' "$ID";; *) return 1;; esac
}
get_architecture() {
    case "$(uname -m)" in x86_64|amd64) echo amd64;; aarch64|arm64) echo arm64;; *) fail "仅支持 AMD64 / ARM64";; esac
}
install_dependencies() {
    case "$(get_system_type)" in
        debian|ubuntu)
            apt-get update && apt-get -o DPkg::Lock::Timeout=120 install -y curl ca-certificates tar gzip openssl python3 iproute2 || return 1;;
        alpine)
            apk add --no-cache bash curl ca-certificates tar gzip openssl python3 iproute2 openrc busybox-initscripts logrotate gcompat libstdc++ || return 1;;
        *) fail "仅支持 Debian、Ubuntu、Alpine"; return 1;;
    esac
}
is_installed() { command -v sing-box >/dev/null 2>&1 || [ -x "$BINARY" ]; }
service_action() {
    if [ "$(get_system_type)" = alpine ]; then rc-service "$SERVICE_NAME" "$1"
    else systemctl "$1" "$SERVICE_NAME"; fi
}
is_running() {
    if [ "$(get_system_type)" = alpine ]; then rc-service "$SERVICE_NAME" status >/dev/null 2>&1
    else systemctl is-active --quiet "$SERVICE_NAME"; fi
}
write_file() (
    local target="$1" mode="$2" temporary
    temporary=$(mktemp "${target}.tmp.XXXXXX") || return 1
    trap 'rm -f "$temporary"' EXIT
    trap 'exit 1' INT TERM HUP
    cat > "$temporary" && chown root:root "$temporary" && chmod "$mode" "$temporary" && mv -f "$temporary" "$target" || {
        fail "写入文件失败：$target"; return 1;
    }
)
fetch_text() { curl -4fsS --connect-timeout 3 --max-time 8 "$1"; }
valid_address() {
    python3 - "$1" <<'PY'
import ipaddress, sys
try:
    ip=ipaddress.ip_address(sys.argv[1])
    assert not ip.is_unspecified and not ip.is_multicast
except (ValueError, AssertionError):
    sys.exit(1)
PY
}
get_public_ip() {
    local url address
    for url in https://checkip.amazonaws.com https://api.ipify.org https://ipv4.icanhazip.com; do
        address=$(fetch_text "$url" 2>/dev/null) || continue
        address=${address//$'\r'/}; address=${address//$'\n'/}
        if valid_address "$address"; then printf '%s\n' "$address"; return; fi
    done
    echo "无法自动获取公网 IP。" >&2
    while read -r -p '请输入公网 IPv4/IPv6（留空取消）: ' address; do
        [ -n "$address" ] || return 1
        if valid_address "$address"; then printf '%s\n' "$address"; return; fi
        echo "IP 地址无效。" >&2
    done
    return 1
}
prepare_metadata() {
    [ -s "$META_FILE" ] && return 0
    local address country
    address=$(get_public_ip) || return 1
    country=$(fetch_text "https://ipinfo.io/$address/country" 2>/dev/null) || country=Snell
    country=${country//$'\r'/}; country=${country//$'\n'/}
    [[ "$country" =~ ^[A-Z]{2}$ ]] || country=Proxy
    printf '{"address":"%s","name":"%s"}\n' "$address" "$country" | write_file "$META_FILE" 600
}

# JSON generation and export use a parser, not string substitutions of secrets.
config_tool() {
    python3 - "$@" <<'PY'
import base64, ipaddress, json, os, re, secrets, socket, subprocess, sys, uuid
from urllib.parse import quote

def read(path):
    with open(path) as f: return json.load(f)
def write(path, value):
    with open(path, 'w') as f: json.dump(value, f, indent=2); f.write('\n')
    os.chmod(path, 0o600)
def public_key(private):
    raw=base64.urlsafe_b64decode(private + '=' * (-len(private) % 4))
    if len(raw)!=32: raise ValueError('Reality private key must be 32 bytes')
    der=bytes.fromhex('302e020100300506032b656e04220420')+raw
    result=subprocess.run(['openssl','pkey','-inform','DER','-pubout','-outform','DER'],input=der,capture_output=True,check=True)
    return base64.urlsafe_b64encode(result.stdout[-32:]).decode().rstrip('=')
def choose_port(used):
    # Probe TCP and UDP, including IPv6 where available; reserve all selected values in this batch.
    for _ in range(200):
        port=secrets.randbelow(35000)+30000
        if port in used: continue
        sockets=[]
        try:
            for family,host in [(socket.AF_INET,'0.0.0.0'),(socket.AF_INET6,'::')]:
                if family==socket.AF_INET6 and not socket.has_ipv6: continue
                for kind in (socket.SOCK_STREAM,socket.SOCK_DGRAM):
                    try: s=socket.socket(family,kind)
                    except OSError:
                        if family==socket.AF_INET6: continue
                        raise
                    sockets.append(s)
                    if family==socket.AF_INET6: s.setsockopt(socket.IPPROTO_IPV6,socket.IPV6_V6ONLY,1)
                    s.bind((host,port))
            used.add(port)
            return port
        except OSError: pass
        finally:
            for s in sockets: s.close()
    raise RuntimeError('Cannot allocate an unused port')
def listen_address():
    try:
        with socket.socket(socket.AF_INET6,socket.SOCK_STREAM) as s: s.bind(('::',0))
        return '::'
    except OSError: return '0.0.0.0'
def make_config(directory, binary):
    keys=subprocess.run([binary,'generate','reality-keypair'],capture_output=True,text=True,check=True).stdout
    private=re.search(r'PrivateKey:\s*(\S+)',keys).group(1)
    public=public_key(private)
    identity=str(uuid.uuid4()); password=secrets.token_urlsafe(24); used=set()
    tls={'enabled':True,'certificate_path':directory+'/cert.pem','key_path':directory+'/key.pem'}
    def inbound(kind,tag): return {'type':kind,'tag':tag,'listen':listen_address(),'listen_port':choose_port(used)}
    hy=inbound('hysteria2','hysteria-in'); hy.update(users=[{'password':password}],masquerade='https://bing.com',tls=dict(tls,alpn=['h3']))
    vl=inbound('vless','vless-in'); vl.update(users=[{'uuid':identity,'flow':'xtls-rprx-vision'}],tls={'enabled':True,'server_name':'www.ua.edu','reality':{'enabled':True,'handshake':{'server':'www.ua.edu','server_port':443},'private_key':private,'short_id':['123abc']}})
    anytls=inbound('anytls','anytls-in'); anytls.update(users=[{'name':identity,'password':public}],tls=tls)
    ss=inbound('shadowsocks','shadowsocks-in'); ss.update(method='2022-blake3-aes-128-gcm',password=base64.b64encode(secrets.token_bytes(16)).decode(),multiplex={'enabled':True})
    snell=inbound('snell','snell-in'); snell.update(version=6,psk=secrets.token_urlsafe(36),mode='default')
    return {'log':{'level':'warn','timestamp':True},'inbounds':[hy,vl,anytls,ss,snell],'outbounds':[{'type':'direct','tag':'direct'}]}
def migrate(config):
    inbounds=config.get('inbounds',[])
    removed={x.get('tag') for x in inbounds if x['type']=='shadowtls'}-{None}
    config['inbounds']=[x for x in inbounds if x['type']!='shadowtls']
    # Refuse dangling custom routing rather than silently changing its intent.
    for rule in config.get('route',{}).get('rules',[]):
        refs=rule.get('inbound',[]); refs=[refs] if isinstance(refs,str) else refs
        if removed.intersection(refs): raise ValueError('Custom route references removed ShadowTLS; adjust it first')
    for x in config['inbounds']:
        if x.get('tag')=='shadowsocks-in' and x['type']=='shadowsocks':
            if x.get('listen') in ('127.0.0.1','::1'): x['listen']=listen_address()
    if not any(x['type']=='snell' for x in config['inbounds']):
        tags={x.get('tag') for x in config['inbounds']}
        if 'snell-in' in tags: raise ValueError('snell-in tag already used by another inbound')
        used={x['listen_port'] for x in config['inbounds'] if 'listen_port' in x}
        config['inbounds'].append({'type':'snell','tag':'snell-in','listen':listen_address(),'listen_port':choose_port(used),'version':6,'psk':secrets.token_urlsafe(36),'mode':'default'})
    if config.get('log',{}).get('output')=='stdout': config['log'].pop('output')
    return config

def export(config,meta):
    host=str(ipaddress.ip_address(meta['address'])); authority='['+host+']' if ':' in host else host
    name=str(meta.get('name','Proxy'))
    name=re.sub(r'[\r\n,=]','_',name)
    proxies=[]; surge=[]; links=[]
    for x in config['inbounds']:
        kind=x['type']; port=x.get('listen_port')
        if kind not in ('hysteria2','vless','anytls','shadowsocks','snell') or not port: continue
        tag=x.get('tag',kind); label=name+'-'+tag
        p={'name':label,'type':kind,'server':host,'port':port}
        tls=x.get('tls',{}); sni=tls.get('server_name','www.bing.com')
        if kind=='hysteria2':
            password=x['users'][0]['password']; p.update(password=password,alpn=tls.get('alpn',['h3']),sni=sni,**{'skip-cert-verify':True})
            surge.append(f'{label} = hysteria2, {host}, {port}, password={password}, skip-cert-verify=true, sni={sni}')
            links.append(f'hy2://{quote(password,safe="")}@{authority}:{port}?insecure=1&sni={quote(sni)}#{quote(label)}')
        elif kind=='vless':
            user=x['users'][0]; reality=tls['reality']; public=public_key(reality['private_key']); sid=reality.get('short_id',[''])[0]
            p.update(uuid=user['uuid'],network='tcp',udp=True,tls=True,flow=user.get('flow',''),servername=sni,**{'reality-opts':{'public-key':public,'short-id':sid},'client-fingerprint':'chrome'})
            links.append(f'vless://{user["uuid"]}@{authority}:{port}?encryption=none&flow={quote(user.get("flow",""))}&security=reality&sni={quote(sni)}&fp=chrome&pbk={public}&sid={sid}&type=tcp#{quote(label)}')
        elif kind=='anytls':
            password=x['users'][0]['password']; p.update(password=password,sni=sni,**{'skip-cert-verify':True})
            surge.append(f'{label} = anytls, {host}, {port}, password={password}, skip-cert-verify=true, sni={sni}')
            links.append(f'anytls://{quote(password,safe="")}@{authority}:{port}?security=tls&sni={quote(sni)}&allowInsecure=1#{quote(label)}')
        elif kind=='shadowsocks':
            p.update(type='ss',cipher=x['method'],password=x['password'],udp=True)
            surge.append(f'{label} = ss, {host}, {port}, encrypt-method={x["method"]}, password={x["password"]}, udp-relay=true')
            userinfo=base64.urlsafe_b64encode((x['method']+':'+x['password']).encode()).decode().rstrip('=')
            links.append(f'ss://{userinfo}@{authority}:{port}#{quote(label)}')
        else:
            surge.append(f'{label} = snell, {host}, {port}, psk={x["psk"]}, version={x["version"]}, mode={x.get("mode","default")}, reuse=true')
            continue  # Snell v6 entry is exported for Surge, not assumed supported by Mihomo.
        proxies.append(p)
    return '# Clash / Mihomo: JSON is also valid YAML\n'+json.dumps({'proxies':proxies},ensure_ascii=False,indent=2)+'\n\n# Surge\n'+'\n'.join(surge)+'\n\n# Share links\n'+'\n'.join(links)+'\n'
try:
    action=sys.argv[1]
    if action=='new': write(sys.argv[2],make_config(sys.argv[3],sys.argv[4]))
    elif action=='migrate': write(sys.argv[3],migrate(read(sys.argv[2])))
    elif action=='clients':
        content=export(read(sys.argv[2]),read(sys.argv[3]))
        with open(sys.argv[4],'w') as f: f.write(content)
        os.chmod(sys.argv[4],0o600)
    else: raise ValueError('Unknown operation')
except Exception as error:
    # Do not include configuration values or secrets in error messages.
    print('Configuration operation failed ('+type(error).__name__+'); check configuration structure and dependencies.',file=sys.stderr)
    sys.exit(1)
PY
}

show_logs() {
    if [ "${1:-}" = follow ]; then
        local result
        trap ':' INT
        (trap - INT; if [ "$(get_system_type)" = alpine ]; then exec tail -n 50 -F /var/log/sing-box.log; else exec journalctl -u "$SERVICE_NAME" -f -o cat; fi)
        result=$?
        trap 'exit 130' INT
        [ "$result" -eq 130 ] && return 0
        return "$result"
    elif [ "$(get_system_type)" = alpine ]; then tail -n 30 /var/log/sing-box.log
    else journalctl -u "$SERVICE_NAME" -n 30 --no-pager; fi
}
configure_service() {
    if [ "$(get_system_type)" = alpine ]; then
        write_file /etc/init.d/sing-box 755 <<EOF || return 1
#!/sbin/openrc-run
name="sing-box"
command="$BINARY"
command_args="run -c $CONFIG_FILE"
supervisor="supervise-daemon"
respawn_delay=3
respawn_max=5
respawn_period=60
output_log="/var/log/sing-box.log"
error_log="/var/log/sing-box.log"
rc_ulimit="-n 32768"
depend() { after net; }
start_pre() { checkpath --file --mode 0600 --owner root:root /var/log/sing-box.log; }
EOF
        mkdir -p /etc/periodic/hourly /var/lib/logrotate || return 1
        write_file "$CONFIG_DIR/logrotate.conf" 600 <<'EOF' || return 1
/var/log/sing-box.log {
    size 1M
    rotate 3
    compress
    missingok
    notifempty
    copytruncate
    su root root
}
EOF
        write_file /etc/periodic/hourly/sing-box-logrotate 755 <<EOF || return 1
#!/bin/sh
exec /usr/sbin/logrotate -s /var/lib/logrotate/sing-box.status "$CONFIG_DIR/logrotate.conf"
EOF
        rc-update add crond default && rc-update add sing-box default || return 1
        rc-service crond status >/dev/null 2>&1 || rc-service crond start || return 1
    else
        write_file /etc/systemd/system/sing-box.service 644 <<EOF || return 1
[Unit]
Description=sing-box proxy service
After=network-online.target
Wants=network-online.target
[Service]
ExecStart=$BINARY run -c $CONFIG_FILE
Restart=on-failure
RestartSec=3
LimitNOFILE=32768
UMask=0077
[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload && systemctl enable sing-box || return 1
    fi
}
validate_config() { "$BINARY" check -c "$CONFIG_FILE"; }
restart_service() {
    validate_config || { fail "配置检查失败，未重启服务"; return 1; }
    service_action restart || return 1
    sleep 3
    is_running || { show_logs; fail "服务未保持运行"; return 1; }
}
refresh_clients() (
    local temporary
    [ -f "$CONFIG_FILE" ] || { fail "服务端配置不存在"; return 1; }
    prepare_metadata || { fail "客户端地址未设置，可从菜单 7 重试"; return 1; }
    temporary=$(mktemp "$CONFIG_DIR/.clients.XXXXXX") || return 1
    trap 'rm -f "$temporary"' EXIT
    local normalized
    normalized=$(mktemp "$CONFIG_DIR/.normalized.XXXXXX") || return 1
    trap 'rm -f "$temporary" "$normalized"' EXIT
    "$BINARY" format -c "$CONFIG_FILE" > "$normalized" || return 1
    config_tool clients "$normalized" "$META_FILE" "$temporary" &&
        chown root:root "$temporary" && chmod 600 "$temporary" && mv -f "$temporary" "$CLIENT_CONFIG_FILE" || return 1
    cat "$CLIENT_CONFIG_FILE"
)
install_or_update() (
    local operation="${1:-install}" architecture stage extracted
    architecture=$(get_architecture) || return 1
    install_dependencies || return 1
    mkdir -p "$CONFIG_DIR" "$(dirname "$BINARY")" || return 1
    chown root:root "$CONFIG_DIR" && chmod 700 "$CONFIG_DIR" || return 1
    stage=$(mktemp -d "$(dirname "$BINARY")/.sing-box-install.XXXXXX") || return 1
    trap 'rm -rf "$stage"' EXIT
    trap 'exit 1' INT TERM HUP
    curl -fL --retry 2 --connect-timeout 10 --max-time 180 "https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}/sing-box-${SING_BOX_VERSION}-linux-${architecture}.tar.gz" -o "$stage/release.tar.gz" || return 1
    tar --no-same-owner -xzf "$stage/release.tar.gz" -C "$stage" "sing-box-${SING_BOX_VERSION}-linux-${architecture}/sing-box" || return 1
    extracted="$stage/sing-box-${SING_BOX_VERSION}-linux-${architecture}/sing-box"
    chmod 755 "$extracted" && "$extracted" version || return 1
    if [ "$operation" = update ]; then
        [ -f "$CONFIG_FILE" ] || { fail "没有现有配置，请先安装"; return 1; }
        # sing-box itself accepts JSONC; normalize it with the new core before Python reads it.
        "$extracted" format -c "$CONFIG_FILE" > "$stage/current.json" || return 1
        config_tool migrate "$stage/current.json" "$stage/config.json" || return 1
    else
        if [ -f "$CONFIG_FILE" ]; then fail "已有配置，请使用菜单 8 更新/迁移"; return 1; fi
        openssl ecparam -genkey -name prime256v1 -out "$stage/key.pem" &&
            openssl req -new -x509 -days 3650 -key "$stage/key.pem" -out "$stage/cert.pem" -subj /CN=www.bing.com || return 1
        write_file "$CONFIG_DIR/key.pem" 600 < "$stage/key.pem" && write_file "$CONFIG_DIR/cert.pem" 644 < "$stage/cert.pem" || return 1
        config_tool new "$stage/config.json" "$CONFIG_DIR" "$extracted" || return 1
    fi
    "$extracted" check -c "$stage/config.json" || { fail "新配置检查失败，未替换现有配置和内核"; return 1; }
    # No binary backup. Failures before this point leave the active binary/configuration intact.
    write_file "$CONFIG_FILE" 600 < "$stage/config.json" || return 1
    chown root:root "$extracted" && mv -f "$extracted" "$BINARY" || return 1
    for private in "$CONFIG_DIR/key.pem" "$CLIENT_CONFIG_FILE" "$META_FILE"; do
        if [ -f "$private" ]; then chown root:root "$private" && chmod 600 "$private" || return 1; fi
    done
    configure_service || return 1
    restart_service || return 1
    refresh_clients || { fail "服务已启动，但客户端配置生成失败，可从菜单 7 重试"; return 1; }
    echo "sing-box 安装/更新成功"
)
uninstall_service() {
    local answer
    read -r -p '确定卸载 sing-box 并删除配置？[y/N]: ' answer || return 0
    case "$answer" in y|Y) ;; *) echo "已取消"; return 0;; esac
    if is_running; then service_action stop || return 1; fi
    if [ "$(get_system_type)" = alpine ]; then
        rc-update del sing-box default || return 1
        # Remove a previously package-installed copy too, so it cannot reappear after reboot.
        if apk info -e sing-box >/dev/null 2>&1; then apk del sing-box || return 1; fi
        rm -f /etc/init.d/sing-box /etc/periodic/hourly/sing-box-logrotate /var/lib/logrotate/sing-box.status || return 1
    else
        systemctl disable sing-box || return 1
        if dpkg-query -W -f='${Status}' sing-box 2>/dev/null | grep -q 'install ok installed'; then
            apt-get purge -y sing-box || return 1
        fi
        rm -f /etc/systemd/system/sing-box.service && systemctl daemon-reload || return 1
    fi
    rm -f "$BINARY" && rm -rf "$CONFIG_DIR" || return 1
    echo "sing-box 卸载成功"
}
show_menu() {
    local installed=false running=false
    is_installed && installed=true
    is_running && running=true
    clear
    echo '=== sing-box 管理工具 ==='
    if "$installed"; then echo '安装状态: 已安装'; else echo '安装状态: 未安装'; fi
    if "$running"; then echo '运行状态: 已运行'; else echo '运行状态: 未运行'; fi
    echo
    echo '1. 安装 sing-box 服务'
    echo '2. 卸载 sing-box 服务'
    if "$installed"; then
        if "$running"; then echo '3. 停止 sing-box 服务'; else echo '3. 启动 sing-box 服务'; fi
        printf '%s\n' '4. 重启 sing-box 服务' '5. 查看 sing-box 状态' '6. 查看 sing-box 日志' '7. 查看 sing-box 配置' '8. 更新 sing-box 内核'
    fi
    echo '0. 退出'
    echo '======================'
    read -r -p '请输入选项编号: ' choice
}
main() {
    [ "$(id -u)" -eq 0 ] || { fail "请使用 root"; return 1; }
    get_system_type >/dev/null || { fail "仅支持 Debian、Ubuntu、Alpine"; return 1; }
    trap 'exit 130' INT
    trap 'exit 0' HUP TERM
    while show_menu; do
        case "$choice" in
            1) if is_installed; then echo '已安装，请选择 8 更新/迁移'; else install_or_update install; fi;;
            2) uninstall_service;;
            3) if is_running; then service_action stop; else restart_service; fi;;
            4) restart_service;;
            5) service_action status;;
            6) show_logs follow;;
            7) refresh_clients;;
            8) install_or_update update;;
            0) return 0;;
            *) echo '无效选项';;
        esac
        read -r -p '按 Enter 键继续...' || return 0
    done
    return 0
}
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
