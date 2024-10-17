#!/bin/bash

# 确保安装 `jd` 命令
if ! command -v jd &> /dev/null; then
    echo "正在安装jd..."
    if [[ $(uname -s) == "Linux" ]]; then
        sudo apt update
        sudo apt install -y jq
    else
        echo "请手动安装 jq"
        exit 1
    fi
fi

# 使用 GitHub API 获取 wgcf 的最新版本
WGCF_LATEST_VERSION=$(curl -s https://api.github.com/repos/ViRb3/wgcf/releases/latest | jq -r .tag_name)

echo "获取到的最新版本: $WGCF_LATEST_VERSION"

# 检查系统类型
OS=$(uname -s)
ARCH="amd64"
FILE_NAME=""

if [[ "$OS" == "Linux" ]]; then
    FILE_NAME="wgcf_${WGCF_LATEST_VERSION}_linux_${ARCH}"
elif [[ "$OS" == "FreeBSD" ]]; then
    FILE_NAME="wgcf_${WGCF_LATEST_VERSION}_freebsd_${ARCH}"
else
    echo "不支持的操作系统: $OS"
    exit 1
fi

# 获取下载URL
DOWNLOAD_URL="https://github.com/ViRb3/wgcf/releases/download/${WGCF_LATEST_VERSION}/${FILE_NAME}"

echo "下载链接: $DOWNLOAD_URL"

# 下载对应的wgcf文件
wget $DOWNLOAD_URL -O wgcf

# 赋予执行权限
chmod +x wgcf

# 移动到系统路径
sudo mv wgcf /usr/local/bin/

# 注册账户
wgcf register

# 生成配置文件
wgcf generate

# 输出配置文件内容
cat wgcf-profile.conf

echo "wgcf设置已完成，WireGuard配置已生成。"
