#!/bin/bash

# 检查系统类型
OS=$(uname -s)
WGCF_VERSION="2.2.22"

# 提供选项
echo "请选择操作选项："
echo "1 安装 wgcf"
echo "2 卸载 wgcf"
read -p "输入选项 : " OPTION

# 根据用户选择执行操作
if [[ "$OPTION" == "1" ]]; then
    # 根据系统类型下载适合的wgcf二进制文件
    if [[ "$OS" == "Linux" ]]; then
        echo "检测到Linux系统，正在下载wgcf..."
        wget https://github.com/ViRb3/wgcf/releases/download/v${WGCF_VERSION}/wgcf_${WGCF_VERSION}_linux_amd64 -O wgcf
    elif [[ "$OS" == "FreeBSD" ]]; then
        echo "检测到FreeBSD系统，正在下载wgcf..."
        wget https://github.com/ViRb3/wgcf/releases/download/v${WGCF_VERSION}/wgcf_${WGCF_VERSION}_freebsd_amd64 -O wgcf
    else
        echo "不支持的操作系统: $OS"
        exit 1
    fi

    # 检查wget命令是否成功
    if [[ $? -ne 0 ]]; then
        echo "下载wgcf失败，请检查网络连接或下载链接。"
        exit 1
    fi

    # 赋予执行权限
    chmod +x wgcf

    # 移动到系统路径
    sudo mv wgcf /usr/local/bin/

    # 检查移动是否成功
    if [[ $? -ne 0 ]]; then
        echo "移动wgcf到/usr/local/bin/失败，请检查权限。"
        exit 1
    fi

    # 检查是否已有账户
    if [[ -f wgcf-account.toml ]]; then
        echo "检测到已有账户，跳过注册步骤。"
    else
        # 注册账户，自动选择"是"
        if ! yes | wgcf register; then
            echo "注册账户失败，请检查wgcf的相关设置。"
            exit 1
        fi
    fi

    # 生成配置文件
    if ! wgcf generate; then
        echo "生成配置文件失败，请检查wgcf的相关设置。"
        exit 1
    fi

    # 输出配置文件内容
    cat wgcf-profile.conf

    echo "wgcf设置已完成，WireGuard配置已生成。"

elif [[ "$OPTION" == "2" ]]; then

    # 删除wgcf主程序
    if [[ -f /usr/local/bin/wgcf ]]; then
        sudo rm /usr/local/bin/wgcf
        
    else
        echo "未找到wgcf主程序，无法卸载。"
    fi

    # 删除账户配置文件
    if [[ -f wgcf-account.toml ]]; then
        rm wgcf-account.toml
        
    else
        echo "未找到wgcf账户配置文件。"
    fi

    # 删除生成的配置文件
    if [[ -f wgcf-profile.conf ]]; then
        rm wgcf-profile.conf
        
    else
        echo "未找到wgcf生成的配置文件。"
    fi

    echo "wgcf已成功卸载"

else
    echo "无效的选项，请输入 1 或 2。"
    exit 1
fi
