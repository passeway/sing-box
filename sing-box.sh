#!/bin/bash

# 定义颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
RESET='\033[0m'

# 定义常量
CONFIG_DIR="/etc/sing-box"
CONFIG_FILE="${CONFIG_DIR}/config.json"
SERVICE_NAME="sing-box"
CLIENT_CONFIG_FILE="${CONFIG_DIR}/client.txt"

# 检查 root 权限
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}请使用 root 权限执行此脚本！${RESET}"
        exit 1
    fi
}

# 检查 sing-box 是否已安装
is_sing_box_installed() {
    if command -v sing-box &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# 检查 sing-box 运行状态
is_sing_box_running() {
    systemctl is-active --quiet "${SERVICE_NAME}"
    return $?
}

# 检查 ss 命令是否可用
check_ss_command() {
    if ! command -v ss &> /dev/null; then
        echo -e "${YELLOW}ss 命令未找到，正在尝试自动安装 iproute2 ${RESET}"
        
        # 检测包管理器并安装
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y iproute2
        elif command -v yum &> /dev/null; then
            sudo yum install -y iproute
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y iproute
        elif command -v pacman &> /dev/null; then
            sudo pacman -Sy --noconfirm iproute2
        elif command -v zypper &> /dev/null; then
            sudo zypper install -y iproute2
        else
            echo -e "${RED}无法检测到支持的包管理器，请手动安装 iproute2 包${RESET}"
            exit 1
        fi
        
        # 再次检查是否安装成功
        if command -v ss &> /dev/null; then
            echo -e "${GREEN}iproute2 安装成功，ss 命令已可用${RESET}"
        else
            echo -e "${RED}自动安装失败，请手动安装 iproute2 包${RESET}"
            exit 1
        fi
    else
        echo -e "${GREEN}ss 命令可用${RESET}"
    fi
}


# 检查端口是否已被使用
is_port_available() {
    local port=$1
    if ss -tuln | grep -q ":$port "; then
        return 1 # 端口已被使用
    else
        return 0 # 端口可用
    fi
}

# 生成未被占用的端口
generate_unused_port() {
    local port
    while true; do
        port=$(shuf -i 1025-65535 -n 1)
        if is_port_available $port; then
            echo $port
            return
        fi
    done
}

# 安装 sing-box
install_sing_box() {
    echo -e "${CYAN}正在安装 sing-box${RESET}"

    # 下载并运行 sing-box 安装脚本
    bash <(curl -fsSL https://sing-box.app/deb-install.sh) || {
        echo -e "${RED}sing-box 安装失败！请检查网络连接或安装脚本来源。${RESET}"
        exit 1
    }

    # 生成随机端口和密码
    check_ss_command
    is_port_available
    vless_port=$(generate_unused_port)
    hysteria_port=$(generate_unused_port)
    anytls_port=$(generate_unused_port)
    shadowtls_port=$(generate_unused_port)
    shadowsocks_port=$(generate_unused_port)
    ss_password=$(sing-box generate rand 16 --base64)
    password=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12)

    # 生成 UUID 和 Reality 密钥对
    uuid=$(sing-box generate uuid)
    reality_output=$(sing-box generate reality-keypair)
    private_key=$(echo "${reality_output}" | grep -oP 'PrivateKey:\s*\K.*')
    public_key=$(echo "${reality_output}" | grep -oP 'PublicKey:\s*\K.*')

    # 生成自签名证书
    mkdir -p "${CONFIG_DIR}"
    openssl ecparam -genkey -name prime256v1 -out "${CONFIG_DIR}/private.key" || {
        echo -e "${RED}生成私钥失败${RESET}"
        exit 1
    }
    openssl req -new -x509 -days 3650 -key "${CONFIG_DIR}/private.key" -out "${CONFIG_DIR}/cert.pem" -subj "/CN=bing.com" || {
        echo -e "${RED}生成证书失败${RESET}"
        exit 1
    }

    # 获取本机 IP 地址和所在国家
    host_ip=$(curl -s http://checkip.amazonaws.com)
    ip_country=$(curl -s http://ipinfo.io/${host_ip}/country)



    # 生成配置文件
    cat > "${CONFIG_FILE}" << EOF
{
  "log": {
    "level": "warn",
    "timestamp": true,
    "output": "stdout"
  },
  "inbounds": [
    {
      "type": "hysteria2",
      "tag": "hysteria-in",
      "listen": "::",
      "listen_port": ${hysteria_port},
      "users": [
        {
          "password": "${password}"
        }
      ],
      "masquerade": "https://bing.com",
      "tls": {
        "enabled": true,
        "alpn": [
          "h3"
        ],
        "certificate_path": "${CONFIG_DIR}/cert.pem",
        "key_path": "${CONFIG_DIR}/private.key"
      }
    },
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": ${vless_port},
      "users": [
        {
          "uuid": "${uuid}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "www.tesla.com",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "www.tesla.com",
            "server_port": 443
          },
          "private_key": "${private_key}",
          "short_id": [
            "123abc"
          ]
        }
      }
    },
    {
      "type": "anytls",
      "tag": "anytls-in",
      "listen": "::",
      "listen_port": ${anytls_port},
      "users": [
        {
          "name": "${uuid}",
          "password": "${public_key}"
        }
      ],
      "tls": {
        "enabled": true,
        "certificate_path": "${CONFIG_DIR}/cert.pem",
        "key_path": "${CONFIG_DIR}/private.key"
      }
    },
    {
      "type": "shadowtls",
      "listen": "::",
      "listen_port": ${shadowtls_port},
      "detour": "shadowsocks-in",
      "version": 3,
      "users": [
        {
          "password": "${password}"
        }
      ],
      "handshake": {
        "server": "www.bing.com",
        "server_port": 443
      },
      "strict_mode": true
    },
    {
      "type": "shadowsocks",
      "tag": "shadowsocks-in",
      "listen": "127.0.0.1",
      "listen_port": ${shadowsocks_port},
      "method": "2022-blake3-aes-128-gcm",
      "password": "${ss_password}",
      "multiplex": {
        "enabled": true
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF

    # 启用并启动 sing-box 服务
    systemctl enable "${SERVICE_NAME}" || {
        echo -e "${RED}无法启用 ${SERVICE_NAME} 服务！${RESET}"
        exit 1
    }

    systemctl start "${SERVICE_NAME}" || {
        echo -e "${RED}无法启动 ${SERVICE_NAME} 服务！${RESET}"
        exit 1
    }

    # 检查服务状态
    if ! is_sing_box_running; then
        echo -e "${RED}${SERVICE_NAME} 服务未成功启动！${RESET}"
        systemctl status "${SERVICE_NAME}"
        exit 1
    fi

    # 输出客户端配置到文件
    {
        cat << EOF
  - name: ${ip_country}
    type: hysteria2
    server: ${hysteria_port}
    port: ${hport}
    password: ${password}
    alpn:
      - h3
    sni: www.bing.com
    skip-cert-verify: true
    fast-open: true

  - name: ${ip_country}
    type: vless
    server: ${host_ip}
    port: ${vless_port}
    uuid: ${uuid}
    network: tcp
    udp: true
    tls: true
    flow: xtls-rprx-vision
    servername: www.tesla.com
    reality-opts:
      public-key: ${public_key}
      short-id: 123abc
    client-fingerprint: chrome

  - name: ${ip_country}
    type: ss
    server: ${host_ip}
    port: ${shadowtls_port}
    cipher: 2022-blake3-aes-128-gcm
    password: ${ss_password}
    udp: true
    plugin: shadow-tls
    client-fingerprint: chrome
    plugin-opts:
      mode: tls
      host: www.bing.com
      password: ${password}
      version: 3
    smux:
      enabled: true
EOF

        echo
        echo "hy2://${password}@${host_ip}:${hysteria_port}?insecure=1&sni=www.bing.com#${ip_country}"
        echo
        echo "${ip_country} = hysteria2, ${host_ip}, ${hysteria_port}, password = ${password}, skip-cert-verify=true, sni=www.bing.com"
        echo
        echo "${ip_country} = anytls, ${host_ip}, ${anytls_port}, password = ${public_key}, skip-cert-verify=true, sni=www.bing.com"
        echo
        echo "anytls://${public_key}@${host_ip}:${anytls_port}?security=tls&sni=www.bing.com&allowInsecure=1&type=tcp#${ip_country}"
        echo
        echo "${ip_country} = ss, ${host_ip}, ${shadowtls_port}, encrypt-method=2022-blake3-aes-128-gcm, password=${ss_password}, shadow-tls-password=${password}, shadow-tls-sni=www.bing.com, shadow-tls-version=3, udp-relay=true"
        echo 
        echo "vless://${uuid}@${host_ip}:${vless_port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.tesla.com&fp=chrome&pbk=${public_key}&sid=123abc&type=tcp&headerType=none#${ip_country}"
        echo
    } > "${CLIENT_CONFIG_FILE}"

    echo -e "${GREEN}sing-box 安装成功${RESET}"
    cat "${CLIENT_CONFIG_FILE}"
}

uninstall_sing_box() {
    read -p "$(echo -e "${RED}确定要卸载 sing-box 吗? (Y/n) ${RESET}")" choice
    choice=${choice:-Y}  # 默认设置为 Y
    case "${choice}" in
        y|Y)
            echo -e "${CYAN}正在卸载 sing-box${RESET}"

            # 停止 sing-box 服务
            systemctl stop "${SERVICE_NAME}" || {
                echo -e "${RED}停止 sing-box 服务失败。${RESET}"
            }

            # 禁用 sing-box 服务
            systemctl disable "${SERVICE_NAME}" || {
                echo -e "${RED}禁用 sing-box 服务失败。${RESET}"
            }

            # 卸载 sing-box
            dpkg --purge sing-box || {
                echo -e "${YELLOW}无法通过 dpkg 卸载 sing-box，可能未通过 apt 安装。${RESET}"
            }


            # 重新加载 systemd
            systemctl daemon-reload || {
                echo -e "${YELLOW}无法重新加载 systemd 守护进程。${RESET}"
            }

            # 删除 sing-box 可执行文件，如果存在
            if [ -f "/usr/local/bin/sing-box" ]; then
                rm /usr/local/bin/sing-box || {
                    echo -e "${YELLOW}无法删除 /usr/local/bin/sing-box。${RESET}"
                }
            fi

            echo -e "${GREEN}sing-box 卸载成功${RESET}"
            ;;
        *)
            echo -e "${YELLOW}已取消卸载操作${RESET}"
            ;;
    esac
}

# 启动 sing-box
start_sing_box() {
    systemctl start "${SERVICE_NAME}"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}${SERVICE_NAME} 服务成功启动${RESET}"
    else
        echo -e "${RED}${SERVICE_NAME} 服务启动失败${RESET}"
    fi
}

# 停止 sing-box
stop_sing_box() {
    systemctl stop "${SERVICE_NAME}"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}${SERVICE_NAME} 服务成功停止${RESET}"
    else
        echo -e "${RED}${SERVICE_NAME} 服务停止失败${RESET}"
    fi
}

# 重启 sing-box
restart_sing_box() {
    systemctl restart "${SERVICE_NAME}"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}${SERVICE_NAME} 服务成功重启${RESET}"
    else
        echo -e "${RED}${SERVICE_NAME} 服务重启失败${RESET}"
    fi
}

# 查看 sing-box 状态
status_sing_box() {
    systemctl status "${SERVICE_NAME}"
}

# 查看 sing-box 日志
log_sing_box() {
    sudo journalctl -u sing-box --output cat -f
}


# 查看 sing-box 配置
check_sing_box() {
    if [ -f "${CLIENT_CONFIG_FILE}" ]; then
        cat "${CLIENT_CONFIG_FILE}"
    else
        echo -e "${YELLOW}配置文件不存在: ${CLIENT_CONFIG_FILE}${RESET}"
    fi
}

# 显示菜单
show_menu() {
    clear
    is_sing_box_installed
    sing_box_installed=$?
    is_sing_box_running
    sing_box_running=$?

    echo -e "${GREEN}=== sing-box 管理工具 ===${RESET}"
    echo -e "安装状态: $(if [ ${sing_box_installed} -eq 0 ]; then echo -e "${GREEN}已安装${RESET}"; else echo -e "${RED}未安装${RESET}"; fi)"
    echo -e "运行状态: $(if [ ${sing_box_running} -eq 0 ]; then echo -e "${GREEN}已运行${RESET}"; else echo -e "${RED}未运行${RESET}"; fi)"
    echo ""
    echo "1. 安装 sing-box 服务"
    echo "2. 卸载 sing-box 服务"
    if [ ${sing_box_installed} -eq 0 ]; then
        if [ ${sing_box_running} -eq 0 ]; then
            echo "3. 停止 sing-box 服务"
        else
            echo "3. 启动 sing-box 服务"
        fi
        echo "4. 重启 sing-box 服务"
        echo "5. 查看 sing-box 状态"
        echo "6. 查看 sing-box 日志"
        echo "7. 查看 sing-box 配置"
    fi
    echo "0. 退出"
    echo -e "${GREEN}=========================${RESET}"
    read -p "请输入选项编号 (0-7): " choice
    echo ""
}

# 捕获 Ctrl+C 信号
trap 'echo -e "${RED}已取消操作${RESET}"; exit' INT

# 主循环
check_root

while true; do
    show_menu
    case "${choice}" in
        1)
            if [ ${sing_box_installed} -eq 0 ]; then
                echo -e "${YELLOW}sing-box 已经安装！${RESET}"
            else
                install_sing_box
            fi
            ;;
        2)
            if [ ${sing_box_installed} -eq 0 ]; then
                uninstall_sing_box
            else
                echo -e "${YELLOW}sing-box 尚未安装！${RESET}"
            fi
            ;;
        3)
            if [ ${sing_box_installed} -eq 0 ]; then
                if [ ${sing_box_running} -eq 0 ]; then
                    stop_sing_box
                else
                    start_sing_box
                fi
            else
                echo -e "${RED}sing-box 尚未安装！${RESET}"
            fi
            ;;
        4)
            if [ ${sing_box_installed} -eq 0 ]; then
                restart_sing_box
            else
                echo -e "${RED}sing-box 尚未安装！${RESET}"
            fi
            ;;
        5)
            if [ ${sing_box_installed} -eq 0 ]; then
                status_sing_box
            else
                echo -e "${RED}sing-box 尚未安装！${RESET}"
            fi
            ;;
        6)
            if [ ${sing_box_installed} -eq 0 ]; then
                log_sing_box
            else
                echo -e "${RED}sing-box 尚未安装！${RESET}"
            fi
            ;;
        7)
            if [ ${sing_box_installed} -eq 0 ]; then
                check_sing_box
            else
                echo -e "${RED}sing-box 尚未安装！${RESET}"
            fi
            ;;
        0)
            echo -e "${GREEN}已退出 sing-box 管理工具${RESET}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效的选项，请输入有效的编号 (0-7)${RESET}"
            ;;
    esac
    read -p "按 Enter 键继续..."
done
