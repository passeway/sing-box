#!/bin/bash

# 确保脚本在遇到错误时退出，并打印命令
set -e

# 安装 sing-box 的函数
install_sing_box() {
    echo "正在安装 sing-box"
    bash <(curl -fsSL https://sing-box.app/deb-install.sh) || {
        echo "sing-box 安装失败！请检查网络连接或安装脚本来源。"
        exit 1
    }

    # 随机生成端口和密码
    PORT=$(shuf -i 1025-65535 -n 1)
    USERNAME=$(tr -dc A-Za-z < /dev/urandom | head -c 6)
    PASSWORD=$(tr -dc A-Za-z < /dev/urandom | head -c 6)

    # 提示用户输入域名
    read -p "请输入域名: " DOMAIN

    # 检查域名是否为空
    if [[ -z "$DOMAIN" ]]; then
        echo "错误：域名不能为空！"
        exit 1
    fi

    # 验证域名格式
    if ! [[ "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        echo "错误：域名格式不正确！请提供有效的域名。"
        exit 1
    fi

    # 配置文件位置
    CONFIG_FILE="/etc/sing-box/config.json"

    # 确保目录存在
    sudo mkdir -p "$(dirname "$CONFIG_FILE")"

    # 写入config.json配置
    sudo tee "$CONFIG_FILE" <<EOF > /dev/null
{
  "log": {
    "level": "info",
    "timestamp": true,
    "output": "/var/log/singbox.log"
  },
  "inbounds": [
    {
      "type": "naive",
      "tag": "naive-in",
      "listen": "::",
      "listen_port": $PORT,
      "tcp_fast_open": true,
      "users": [
        {
          "username": "$USERNAME",
          "password": "$PASSWORD"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$DOMAIN",
        "acme": {
          "domain": ["$DOMAIN"],
          "data_directory": "/usr/local/etc/sing-box",
          "email": "admin@gmail.com",
          "provider": "letsencrypt"
        }
      }
    }
   ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct-out"
    }
  ]
}
EOF

    # 启用并启动 Sing Box
    sudo systemctl enable sing-box || {
        echo "无法启用 sing-box 服务！"
        exit 1
    }

    sudo systemctl start sing-box || {
        echo "无法启动 sing-box 服务！"
        exit 1
    }

    # 检查服务状态
    if ! sudo systemctl is-active --quiet sing-box; then
        echo "sing-box 服务未成功启动！"
        sudo systemctl status sing-box
        exit 1
    fi

    # 输出代理信息
    echo "sing-box已成功启动NaïveProxy安装完成"
    # 输出NaïveProxy配置
    cat <<EOF
{
  "listen": "socks://127.0.0.1:1080",
  "proxy": "https://$USERNAME:$PASSWORD@$DOMAIN:$PORT"
}
EOF
}

# 卸载 Sing Box 的函数
uninstall_sing_box() {
    echo "正在卸载 sing-box"
    sudo systemctl stop sing-box
    sudo systemctl disable sing-box

    # 卸载 Sing Box
    sudo apt-get remove --purge sing-box -y

    # 删除配置文件和日志
    sudo rm -rf /etc/sing-box
    sudo rm -f /var/log/singbox.log
    sudo rm -rf /usr/local/etc/sing-box

    # 重新加载 systemd
    sudo systemctl daemon-reload

    echo "sing-box 已成功卸载并清理"
}

# 显示菜单
echo "请选择操作："
echo "1. 安装 NaïveProxy"
echo "2. 卸载 NaïveProxy"
read -p "请输入选项 (1或2): " CHOICE

case "$CHOICE" in
    1)
        install_sing_box
        ;;
    2)
        uninstall_sing_box
        ;;
    *)
        echo "无效的选项，请输入 1 或 2"
        exit 1
        ;;
esac
