#!/usr/bin/env bash
# Debian / Ubuntu / Alpine multi-protocol server manager.
CONFIG_DIR="/etc/sing-box"
CONFIG_FILE="$CONFIG_DIR/config.json"
CLIENT_CONFIG_FILE="$CONFIG_DIR/client.txt"
META_FILE="$CONFIG_DIR/client-meta.json"
BINARY="/usr/local/bin/sing-box"
SERVICE_NAME="sing-box"
SYSTEMD_UNIT="/etc/systemd/system/sing-box.service"

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
            apt-get -o DPkg::Lock::Timeout=120 update && apt-get -o DPkg::Lock::Timeout=120 install -y curl ca-certificates tar gzip openssl python3 iproute2 || return 1;;
        alpine)
            apk add --no-cache bash curl ca-certificates tar gzip openssl python3 iproute2 openrc busybox-openrc logrotate gcompat libstdc++ || return 1;;
        *) fail "仅支持 Debian、Ubuntu、Alpine"; return 1;;
    esac
}
is_installed() { command -v sing-box >/dev/null 2>&1 || [ -x "$BINARY" ]; }
service_action() {
    if [ "$(get_system_type)" = alpine ]; then rc-service "$SERVICE_NAME" "$1"; return; fi
    case "$1" in
        start|restart)
            if [ "$(systemctl show "$SERVICE_NAME" -p LoadState --value 2>/dev/null)" = loaded ]; then
                systemctl reset-failed "$SERVICE_NAME" || return 1
            fi;;
    esac
    systemctl "$1" "$SERVICE_NAME"
}
is_running() {
    if [ "$(get_system_type)" = alpine ]; then rc-service "$SERVICE_NAME" status >/dev/null 2>&1
    else systemctl is-active --quiet "$SERVICE_NAME"; fi
}
systemd_running() { [ -d /run/systemd/system ]; }
service_pid() {
    local helper
    if [ "$(get_system_type)" = alpine ]; then
        for helper in /usr/libexec/rc/bin/service_get_value /lib/rc/bin/service_get_value /usr/lib/rc/bin/service_get_value; do
            [ -x "$helper" ] && { RC_SVCNAME="$SERVICE_NAME" "$helper" child_pid; return; }
        done
        return 1
    fi
    systemctl show "$SERVICE_NAME" -p MainPID --value
}
wait_running() {
    local attempt stable=0 pid previous="" delay
    for ((attempt=0; attempt<8; attempt++)); do
        case $attempt in 0) delay=0.5;; 1) delay=1;; *) delay=2;; esac
        sleep "$delay"
        if is_running && pid=$(service_pid) && [[ "$pid" =~ ^[1-9][0-9]*$ ]] && [ -d "/proc/$pid" ]; then
            if [ "$pid" = "$previous" ]; then stable=$((stable+1)); else stable=1; fi
            previous="$pid"
        else
            stable=0; previous=""
        fi
        [ "$stable" -ge 3 ] && return 0
    done
    return 1
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
fetch_text() { curl -fsS --connect-timeout 3 --max-time 8 "$1"; }
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
    for url in https://checkip.amazonaws.com https://api.ipify.org https://ipv4.icanhazip.com https://ipv6.icanhazip.com https://api6.ipify.org; do
        address=$(fetch_text "$url" 2>/dev/null) || continue
        address=${address//$'\r'/}; address=${address//$'\n'/}
        if valid_address "$address"; then printf '%s\n' "$address"; return; fi
    done
    echo "无法自动获取公网 IP。" >&2
    while read -r -t 30 -p '请输入公网 IPv4/IPv6（留空取消）: ' address; do
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
    country=$(fetch_text "https://ipinfo.io/$address/country" 2>/dev/null) || country=Proxy
    country=${country//$'\r'/}; country=${country//$'\n'/}
    [[ "$country" =~ ^[A-Z]{2}$ ]] || country=Proxy
    printf '{"address":"%s","name":"%s"}\n' "$address" "$country" | write_file "$META_FILE" 600
}

config_tool() {
    python3 - "$@" <<'PY'
import base64, errno, ipaddress, json, os, re, secrets, socket, subprocess, sys, uuid
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
    for _ in range(200):
        port=secrets.randbelow(35000)+30000
        if port in used: continue
        sockets=[]
        try:
            for family,host in [(socket.AF_INET,'0.0.0.0'),(socket.AF_INET6,'::')]:
                if family==socket.AF_INET6 and not socket.has_ipv6: continue
                for kind in (socket.SOCK_STREAM,socket.SOCK_DGRAM):
                    try:
                        s=socket.socket(family,kind)
                        sockets.append(s)
                        if family==socket.AF_INET6: s.setsockopt(socket.IPPROTO_IPV6,socket.IPV6_V6ONLY,1)
                        s.bind((host,port))
                    except OSError as error:
                        if family==socket.AF_INET6 and error.errno in (
                            errno.EAFNOSUPPORT, errno.EPROTONOSUPPORT, errno.EADDRNOTAVAIL,
                            errno.ENODEV):
                            continue
                        raise
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
    identity=str(uuid.uuid4()); password=secrets.token_urlsafe(24); used=set()
    tls={'enabled':True,'certificate_path':directory+'/cert.pem','key_path':directory+'/key.pem'}
    def inbound(kind,tag): return {'type':kind,'tag':tag,'listen':listen_address(),'listen_port':choose_port(used)}
    hy=inbound('hysteria2','hysteria-in'); hy.update(users=[{'password':password}],masquerade='https://bing.com',tls=dict(tls,alpn=['h3']))
    vl=inbound('vless','vless-in'); vl.update(users=[{'uuid':identity,'flow':'xtls-rprx-vision'}],tls={'enabled':True,'server_name':'www.ua.edu','reality':{'enabled':True,'handshake':{'server':'www.ua.edu','server_port':443},'private_key':private,'short_id':['123abc']}})
    anytls=inbound('anytls','anytls-in'); anytls.update(users=[{'name':identity,'password':secrets.token_urlsafe(32)}],tls=tls)
    ss=inbound('shadowsocks','shadowsocks-in'); ss.update(method='2022-blake3-aes-128-gcm',password=base64.b64encode(secrets.token_bytes(16)).decode(),multiplex={'enabled':True})
    snell=inbound('snell','snell-in'); snell.update(version=6,psk=secrets.token_urlsafe(36),mode='default')
    return {'log':{'level':'warn','timestamp':True},'inbounds':[hy,vl,anytls,ss,snell],'outbounds':[{'type':'direct','tag':'direct'}]}
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
            user=x['users'][0]; reality=tls['reality']; public=public_key(reality['private_key']); short_ids=reality.get('short_id',[])
            sid=short_ids if isinstance(short_ids,str) else (short_ids[0] if short_ids else '')
            p.update(uuid=user['uuid'],network='tcp',udp=True,tls=True,flow=user.get('flow',''),servername=sni,**{'reality-opts':{'public-key':public,'short-id':sid},'client-fingerprint':'chrome'})
            links.append(f'vless://{user["uuid"]}@{authority}:{port}?encryption=none&flow={quote(user.get("flow",""))}&security=reality&sni={quote(sni)}&fp=chrome&pbk={public}&sid={sid}&type=tcp#{quote(label)}')
        elif kind=='anytls':
            password=x['users'][0]['password']; p.update(password=password,sni=sni,**{'skip-cert-verify':True})
            surge.append(f'{label} = anytls, {host}, {port}, password={password}, skip-cert-verify=true, sni={sni}')
            links.append(f'anytls://{quote(password,safe="")}@{authority}:{port}?security=tls&sni={quote(sni)}&insecure=1&type=tcp&headerType=none#{quote(label)}')
        elif kind=='shadowsocks':
            p.update(type='ss',cipher=x['method'],password=x['password'],udp=True)
            surge.append(f'{label} = ss, {host}, {port}, encrypt-method={x["method"]}, password={x["password"]}, udp-relay=true')
            if x['method'].startswith('2022-'):
                userinfo=quote(x['method'],safe='')+':'+quote(x['password'],safe='')
            else:
                userinfo=base64.urlsafe_b64encode((x['method']+':'+x['password']).encode()).decode().rstrip('=')
            links.append(f'ss://{userinfo}@{authority}:{port}#{quote(label)}')
        else:
            surge.append(f'{label} = snell, {host}, {port}, psk={x["psk"]}, version={x["version"]}, mode={x.get("mode","default")}, reuse=true')
            continue
        proxies.append(p)
    return '# Clash / Mihomo: JSON is also valid YAML\n'+json.dumps({'proxies':proxies},ensure_ascii=False,indent=2)+'\n\n# Surge\n'+'\n'.join(surge)+'\n\n# Share links\n'+'\n'.join(links)+'\n'
def firewall_ports(config):
    networks={'tcp':set(),'udp':set()}
    for x in config.get('inbounds',[]):
        port=x.get('listen_port')
        if not isinstance(port,int) or isinstance(port,bool) or not port: continue
        if x.get('type') in ('hysteria','hysteria2','tuic'): used=['udp']
        elif x.get('type')=='shadowsocks': used=[x['network']] if x.get('network') in networks else ['tcp','udp']
        else: used=['tcp']
        for network in used: networks[network].add(port)
    return '，'.join(f'{network.upper()} 端口 '+'/'.join(map(str,sorted(ports))) for network,ports in networks.items() if ports)
try:
    action=sys.argv[1]
    if action=='new': write(sys.argv[2],make_config(sys.argv[3],sys.argv[4]))
    elif action=='ports': print(firewall_ports(read(sys.argv[2])))
    elif action=='clients':
        content=export(read(sys.argv[2]),read(sys.argv[3]))
        with open(sys.argv[4],'w') as f: f.write(content)
        os.chmod(sys.argv[4],0o600)
    else: raise ValueError('Unknown operation')
except Exception as error:
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
        write_file "$SYSTEMD_UNIT" 644 <<EOF || return 1
[Unit]
Description=sing-box proxy service
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=60
StartLimitBurst=5
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
    service_action restart && wait_running || { show_logs; fail "服务未保持运行"; return 1; }
}
normalized_config_tool() (
    local action="$1" normalized
    shift
    normalized=$(mktemp "$CONFIG_DIR/.normalized.XXXXXX") || return 1
    trap 'rm -f "$normalized"' EXIT
    "$BINARY" format -c "$CONFIG_FILE" > "$normalized" || return 1
    config_tool "$action" "$normalized" "$@"
)
firewall_ports() { normalized_config_tool ports; }
refresh_clients() (
    local temporary
    [ -f "$CONFIG_FILE" ] || { fail "服务端配置不存在"; return 1; }
    prepare_metadata || { fail "客户端地址未设置，可从菜单 7 重试"; return 1; }
    temporary=$(mktemp "$CONFIG_DIR/.clients.XXXXXX") || return 1
    trap 'rm -f "$temporary"' EXIT
    normalized_config_tool clients "$META_FILE" "$temporary" &&
        chown root:root "$temporary" && chmod 600 "$temporary" && mv -f "$temporary" "$CLIENT_CONFIG_FILE" || return 1
    cat "$CLIENT_CONFIG_FILE"
)
latest_release_version() {
    local architecture="$1" metadata="$2" location tag asset_url
    # Fast path: the release page redirect is not rate-limited and resolves in <1s.
    # The regex below rejects pre-release tags such as v1.15.0-beta.1.
    location=$(curl -fsS -o /dev/null -w '%{redirect_url}' --retry 2 --connect-timeout 10 --max-time 30 \
        https://github.com/SagerNet/sing-box/releases/latest) || location=""
    tag=${location##*/}
    if [[ "$location" == https://github.com/SagerNet/sing-box/releases/tag/* && "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        # Confirm the architecture-specific asset exists before trusting the redirect.
        asset_url="https://github.com/SagerNet/sing-box/releases/download/${tag}/sing-box-${tag#v}-linux-${architecture}.tar.gz"
        if curl -fsS --head --retry 1 --connect-timeout 5 --max-time 10 "$asset_url" 2>/dev/null | grep -q '^HTTP/.* 200'; then
            printf '%s\n' "${tag#v}"; return 0
        fi
    fi
    # Fallback: GitHub API (60 unauthenticated requests per hour per IP).
    if ! curl -fsSL --retry 2 --connect-timeout 10 --max-time 30 \
        https://api.github.com/repos/SagerNet/sing-box/releases/latest -o "$metadata"; then
        fail "无法获取最新稳定版信息，未替换现有内核和配置"; return 1
    fi
    python3 - "$metadata" "$architecture" <<'PYRELEASE'
import json, re, sys
try:
    with open(sys.argv[1]) as source:
        release = json.load(source)
    tag = release.get('tag_name', '')
    if release.get('draft') is not False or release.get('prerelease') is not False:
        raise ValueError('不是正式发布版本')
    if not isinstance(tag, str) or not re.fullmatch(r'v[0-9]+\.[0-9]+\.[0-9]+', tag):
        raise ValueError('版本号无效')
    version = tag[1:]
    name = f'sing-box-{version}-linux-{sys.argv[2]}.tar.gz'
    url = f'https://github.com/SagerNet/sing-box/releases/download/{tag}/{name}'
    if not any(a.get('name') == name and a.get('browser_download_url') == url
               for a in release.get('assets', [])):
        raise ValueError('缺少当前架构的官方安装包')
    print(version)
except (OSError, ValueError, TypeError, AttributeError) as error:
    print(f'无法解析最新稳定版信息：{error}', file=sys.stderr)
    sys.exit(1)
PYRELEASE
}
managed_service_files() {
    if [ "$(get_system_type)" = alpine ]; then
        printf '%s\n' /etc/init.d/sing-box /etc/periodic/hourly/sing-box-logrotate
    else printf '%s\n' "$SYSTEMD_UNIT"; fi
}
service_enabled() {
    if [ "$(get_system_type)" = alpine ]; then [ -e /etc/runlevels/default/sing-box ]
    else systemctl is-enabled --quiet "$SERVICE_NAME"; fi
}
restore_autostart() {
    if [ "$(get_system_type)" = alpine ]; then
        if [ "$1" = true ]; then rc-update add "$SERVICE_NAME" default
        elif service_enabled; then rc-update del "$SERVICE_NAME" default; fi
    elif [ "$1" = true ]; then systemctl enable "$SERVICE_NAME"
    else systemctl disable "$SERVICE_NAME"; fi
}
commit_update() (
    local stage="$1" extracted="$2" backup path index=0 dirty=false restart_attempted=false
    local was_running=false was_enabled=false service_touched=false
    local -a paths=("$CONFIG_FILE" "$BINARY" "$CONFIG_DIR/logrotate.conf")
    while IFS= read -r path; do paths+=("$path"); done < <(managed_service_files)
    backup="$stage/rollback"
    mkdir -m 700 "$backup" || return 1
    is_running && was_running=true
    service_enabled && was_enabled=true
    for path in "${paths[@]}"; do
        printf '%s\t%s\n' "$index" "$path" >> "$backup/manifest.txt" || return 1
        if [ -e "$path" ] || [ -L "$path" ]; then
            cp -a "$path" "$backup/$index" || return 1
        fi
        index=$((index+1))
    done
    rollback_update() {
        local result="$?" failed=false target temporary i=0
        trap - EXIT INT TERM HUP
        if "$dirty"; then
            if "$restart_attempted"; then service_action stop || failed=true; fi
            for target in "${paths[@]}"; do
                if [ -e "$backup/$i" ] || [ -L "$backup/$i" ]; then
                    temporary="${target}.rollback.$$"
                    if cp -a "$backup/$i" "$temporary" && mv -f "$temporary" "$target"; then :
                    else rm -f "$temporary"; failed=true; fi
                else rm -f "$target" || failed=true; fi
                i=$((i+1))
            done
            if "$service_touched"; then
                if [ "$(get_system_type)" != alpine ]; then systemctl daemon-reload || failed=true; fi
                restore_autostart "$was_enabled" || failed=true
            fi
            if "$restart_attempted" && "$was_running"; then
                restart_service || failed=true
            fi
            if "$failed"; then
                fail "自动恢复未完全成功，恢复文件保留在 $backup；请检查服务状态"
            else
                rm -f "$stage/KEEP"
                fail "更新失败，已恢复原内核、配置和服务状态"
            fi
        fi
        return "$result"
    }
    trap rollback_update EXIT
    trap 'exit 1' INT TERM HUP
    touch "$stage/KEEP" || return 1
    dirty=true
    write_file "$CONFIG_FILE" 600 < "$stage/config.json" || return 1
    chown root:root "$extracted" && mv -f "$extracted" "$BINARY" || return 1
    service_touched=true
    configure_service || return 1
    if "$was_running"; then
        restart_attempted=true
        restart_service || return 1
    fi
    rm -f "$stage/KEEP" || return 1
    dirty=false
)
install_or_update() (
    local operation="${1:-install}" architecture stage extracted release_version clients ports
    if [ "$operation" = update ] && [ ! -f "$CONFIG_FILE" ]; then fail "没有现有配置，请先通过菜单 1 安装"; return 1; fi
    if [ "$operation" = install ] && [ -f "$CONFIG_FILE" ]; then fail "检测到残留配置，请先通过菜单 2 清理后重新安装"; return 1; fi
    architecture=$(get_architecture) || return 1
    install_dependencies || return 1
    mkdir -p "$CONFIG_DIR" "$(dirname "$BINARY")" || return 1
    chown root:root "$CONFIG_DIR" && chmod 700 "$CONFIG_DIR" || return 1
    stage=$(mktemp -d "$(dirname "$BINARY")/.sing-box-install.XXXXXX") || return 1
    trap '[ -f "$stage/KEEP" ] || rm -rf "$stage"' EXIT
    trap 'exit 1' INT TERM HUP
    release_version=$(latest_release_version "$architecture" "$stage/release.json") || return 1
    printf '下载 sing-box 最新稳定版：%s\n' "$release_version"
    curl -fL --retry 2 --connect-timeout 10 --max-time 180 "https://github.com/SagerNet/sing-box/releases/download/v${release_version}/sing-box-${release_version}-linux-${architecture}.tar.gz" -o "$stage/release.tar.gz" || return 1
    tar --no-same-owner -xzf "$stage/release.tar.gz" -C "$stage" "sing-box-${release_version}-linux-${architecture}/sing-box" || return 1
    extracted="$stage/sing-box-${release_version}-linux-${architecture}/sing-box"
    chmod 755 "$extracted" && "$extracted" version || return 1
    if [ "$operation" = update ]; then
        cp "$CONFIG_FILE" "$stage/config.json" || return 1
    else
        openssl ecparam -genkey -name prime256v1 -out "$stage/key.pem" &&
            openssl req -new -x509 -days 3650 -key "$stage/key.pem" -out "$stage/cert.pem" -subj /CN=www.bing.com || return 1
        write_file "$CONFIG_DIR/key.pem" 600 < "$stage/key.pem" && write_file "$CONFIG_DIR/cert.pem" 644 < "$stage/cert.pem" || return 1
        config_tool new "$stage/config.json" "$CONFIG_DIR" "$extracted" || return 1
    fi
    "$extracted" check -c "$stage/config.json" || { fail "新配置检查失败，未替换现有配置和内核"; return 1; }
    if [ "$operation" = update ]; then
        commit_update "$stage" "$extracted" || return 1
    else
        write_file "$CONFIG_FILE" 600 < "$stage/config.json" || return 1
        chown root:root "$extracted" && mv -f "$extracted" "$BINARY" || return 1
        configure_service || return 1
        restart_service || return 1
    fi
    for private in "$CONFIG_DIR/key.pem" "$CLIENT_CONFIG_FILE" "$META_FILE"; do
        if [ -f "$private" ]; then chown root:root "$private" && chmod 600 "$private" || return 1; fi
    done
    clients=$(refresh_clients) || { fail "服务已启动，但客户端配置生成失败，可从菜单 7 重试"; return 1; }
    echo ""
    if [ "$operation" = update ]; then
        echo "🎉sing-box 内核已更新至 ${release_version}，项目地址: https://github.com/passeway/sing-box"
        is_running || echo "服务未运行，可通过菜单 3 启动"
    else
        ports=$(firewall_ports) || ports=""
        echo "🎉sing-box 安装成功${ports:+，请在云安全组和系统防火墙中放行 ${ports}}，项目地址: https://github.com/passeway/sing-box"
    fi
    printf '%s\n' "$clients"
)
uninstall_service() {
    local answer
    read -r -p '确定卸载 sing-box 并删除配置？[y/N]: ' answer || return 0
    case "$answer" in y|Y) ;; *) echo "已取消"; return 0;; esac
    local found=false path
    for path in "$BINARY" "$CONFIG_DIR" /etc/init.d/sing-box "$SYSTEMD_UNIT"; do
        if [ -e "$path" ] || [ -L "$path" ]; then found=true; fi
    done
    local stop=false
    if is_running; then found=true; stop=true; fi
    if [ -f /etc/init.d/sing-box ] || { [ -f "$SYSTEMD_UNIT" ] && systemd_running; }; then stop=true; fi
    if "$stop"; then service_action stop || return 1; fi
    if [ "$(get_system_type)" = alpine ]; then
        if [ -e /etc/runlevels/default/sing-box ]; then rc-update del sing-box default || return 1; fi
        if apk info -e sing-box >/dev/null 2>&1; then found=true; apk del sing-box || return 1; fi
        rm -f /etc/init.d/sing-box /etc/periodic/hourly/sing-box-logrotate /var/lib/logrotate/sing-box.status \
            /var/log/sing-box.log /var/log/sing-box.log.* || return 1
    else
        if [ -f "$SYSTEMD_UNIT" ]; then systemctl disable sing-box || return 1; fi
        if dpkg-query -W -f='${Status}' sing-box 2>/dev/null | grep -q 'install ok installed'; then
            found=true; apt-get purge -y sing-box || return 1
        fi
        rm -f "$SYSTEMD_UNIT" || return 1
        if systemd_running; then
            systemctl daemon-reload || return 1
            systemctl reset-failed sing-box 2>/dev/null || true
        fi
    fi
    rm -f "$BINARY" && rm -rf "$CONFIG_DIR" || return 1
    if "$found"; then echo "sing-box 卸载成功"; else echo "未发现已安装的 sing-box，残留文件已清理"; fi
}
show_menu() {
    local installed=false running=false version='—' version_output core="$BINARY"
    is_installed && installed=true
    is_running && running=true
    if "$installed"; then
        version='未知'
        [ -x "$core" ] || core=$(command -v sing-box)
        if version_output=$("$core" version 2>/dev/null); then
            version_output=${version_output%%$'\n'*}
            if [[ "$version_output" == "sing-box version "* ]]; then
                version=${version_output#sing-box version }
            fi
        fi
    fi
    clear
    echo '=== sing-box 管理工具 ==='
    if "$installed"; then echo '安装状态: 已安装'; else echo '安装状态: 未安装'; fi
    if "$running"; then echo '运行状态: 已运行'; else echo '运行状态: 未运行'; fi
    printf '运行版本: %s\n' "$version"
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
        if ! is_installed; then case "$choice" in [3-8]) choice=hidden;; esac; fi
        case "$choice" in
            1) if is_installed; then echo '已安装，请选择 8 更新内核'; else install_or_update install; fi;;
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
