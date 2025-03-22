#!/bin/bash
set -e

# 检查是否以 root 身份运行

if [ "$EUID" -ne 0 ]; then
    echo "请使用 root 权限运行此脚本，例如: sudo $0"
    exit 1
fi

# 配置参数

REPO="heiher/hev-socks5-tunnel"

# 获取最新版本 linux-x86_64 二进制下载链接

DOWNLOAD_URL=$(curl -s https://api.github.com/repos/$REPO/releases/latest | grep "browser_download_url" | grep "linux-x86_64" | cut -d '"' -f 4)

if [ -z "$DOWNLOAD_URL" ]; then
    echo "未找到适用于 linux-x86_64 的二进制文件下载链接，请检查网络或手动下载。"
    exit 1
fi

# 定义安装路径和文件位置

INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/tun2socks"
SERVICE_FILE="/etc/systemd/system/tun2socks.service"
BINARY_PATH="$INSTALL_DIR/tun2socks"

echo "正在下载最新二进制文件："
echo "$DOWNLOAD_URL"
curl -L -o "$BINARY_PATH" "$DOWNLOAD_URL"
chmod +x "$BINARY_PATH"

echo "创建配置文件..."
mkdir -p "$CONFIG_DIR"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
cat > "$CONFIG_FILE" <<'EOF'
tunnel:
  name: tun0
  mtu: 8500
  multi-queue: true
  ipv4: 198.18.0.1

socks5:
  port: 40000
  address: '2a14:67c0:100::af'
  udp: 'udp'
  username: 'alice'
  password: 'alicefofo123..@'
EOF

echo "生成 systemd 服务文件 (tun2socks.service)..."
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Tun2Socks Tunnel Service
After=network.target

[Service]
Type=simple
ExecStart=$BINARY_PATH $CONFIG_FILE
ExecStartPost=/sbin/ip route add default dev tun0
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

echo "重新加载 systemd 配置..."
systemctl daemon-reload

echo "设置服务开机自启动..."
systemctl enable tun2socks.service

echo "启动服务..."
systemctl start tun2socks.service

echo "安装完成！您可以使用 'systemctl status tun2socks.service' 查看服务状态"
