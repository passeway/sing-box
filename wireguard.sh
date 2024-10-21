#!/usr/bin/bash

ERROR="\e[1;31m"    
WARN="\e[93m"       
END="\e[0m"         

# 检测系统包管理器并设置相应的安装命令
package_manager() {
    if [[ "$(type -P apt)" ]]; then
        # Debian/Ubuntu 系统
        PACKAGE_MANAGEMENT_INSTALL='apt -y --no-install-recommends install'
        PACKAGE_MANAGEMENT_REMOVE='apt purge'
        package_provide_tput='ncurses-bin'
    elif [[ "$(type -P dnf)" ]]; then
        # 新版 Red Hat 系统
        PACKAGE_MANAGEMENT_INSTALL='dnf -y install'
        PACKAGE_MANAGEMENT_REMOVE='dnf remove'
        package_provide_tput='ncurses'
    elif [[ "$(type -P yum)" ]]; then
        # 旧版 Red Hat 系统
        PACKAGE_MANAGEMENT_INSTALL='yum -y install'
        PACKAGE_MANAGEMENT_REMOVE='yum remove'
        package_provide_tput='ncurses'
    elif [[ "$(type -P zypper)" ]]; then
        # SUSE 系统
        PACKAGE_MANAGEMENT_INSTALL='zypper install -y --no-recommends'
        PACKAGE_MANAGEMENT_REMOVE='zypper remove'
        package_provide_tput='ncurses-utils'
    elif [[ "$(type -P pacman)" ]]; then
        # Arch Linux 系统
        PACKAGE_MANAGEMENT_INSTALL='pacman -Syu --noconfirm'
        PACKAGE_MANAGEMENT_REMOVE='pacman -Rsn'
        package_provide_tput='ncurses'
    elif [[ "$(type -P emerge)" ]]; then
        # Gentoo 系统
        PACKAGE_MANAGEMENT_INSTALL='emerge -qv'
        PACKAGE_MANAGEMENT_REMOVE='emerge -Cv'
        package_provide_tput='ncurses'
    else
        echo -e "${ERROR}错误:${END} 此操作系统的包管理器不受支持。"
        exit 1
    fi
}

# 安装所需的软件包
install_software() {
    package_name="$1"
    file_to_detect="$2"
    # 检查软件是否已安装
    type -P "$file_to_detect" > /dev/null 2>&1 && return || echo -e "${WARN}警告:${END} $package_name 未安装，正在安装。" && sleep 1
    if ${PACKAGE_MANAGEMENT_INSTALL} "$package_name"; then
        echo "信息: $package_name 已安装完成。"
    else
        echo -e "${ERROR}错误:${END} $package_name 安装失败，请检查网络连接。"
        exit 1
    fi
}

# 注册 WARP 账户并生成密钥对
reg() {
    # 生成 X25519 密钥对
    keypair=$(openssl genpkey -algorithm X25519 | openssl pkey -text -noout)
    # 提取私钥并进行 base64 编码
    private_key=$(echo "$keypair" | awk '/priv:/{flag=1; next} /pub:/{flag=0} flag' | tr -d '[:space:]' | xxd -r -p | base64)
    # 提取公钥并进行 base64 编码
    public_key=$(echo "$keypair" | awk '/pub:/{flag=1} flag' | tr -d '[:space:]' | xxd -r -p | base64)

    # 调用 Cloudflare API 进行注册
    warp_info=$(curl -X POST 'https://api.cloudflareclient.com/v0a2158/reg' -sL --tlsv1.3 \
        -H 'CF-Client-Version: a-7.21-0721' -H 'Content-Type: application/json' \
        -d '{"key":"'"${public_key}"'", "tos":"'$(date +"%Y-%m-%dT%H:%M:%S.000Z")'"}')

    # 输出响应数据并添加私钥信息
    echo "$warp_info"
    echo "$warp_info" | python3 -m json.tool | sed "/\"account_type\"/i\         \"private_key\": \"$private_key\","
}

# 处理并格式化保留信息
reserved() {
    # 从响应中提取 client_id
    reserved_str=$(echo "$warp_info" | grep -o '"client_id": "[^"]*"' | cut -d'"' -f4)
    # 转换为十六进制格式
    reserved_hex=$(echo "$reserved_str" | base64 -d | xxd -p)
    # 转换为十进制数组格式
    reserved_dec=$(echo "$reserved_hex" | fold -w2 | while read HEX; do printf '%d ' "0x${HEX}"; done | awk '{print "["$1", "$2", "$3"]"}')
    
    # 输出格式化后的保留信息
    echo -e "{\n    \"reserved_dec\": $reserved_dec,"
    echo -e "    \"reserved_hex\": \"0x$reserved_hex\","    
    echo -e "    \"reserved_str\": \"$reserved_str\"\n}"
}

# 格式化最终配置输出
format() {
    local config="{"
    config+=$'\n    "endpoint":{'

    # 处理 IPv4 和 IPv6 地址
    config+="$(echo "$warp_info" | grep -P "(v4|v6)" | grep -vP "(\"v4\": \"172.16.0.2\"|\"v6\": \"2)" | sed "s/ //g" | sed 's/:"/: "/g' | sed 's/^"/       "/g' | sed 's/:0",$/",/g')"

    # 添加保留信息和密钥
    config+=$'\n    },'
    config+="$(echo "$warp_reserved" | grep -P "reserved" | sed "s/ //g" | sed 's/:"/: "/g' | sed 's/:\[/: \[/g' | sed 's/\([0-9]\+\),\([0-9]\+\),\([0-9]\+\)/\1, \2, \3/' | sed 's/^"/    "/g' | sed 's/"$/",/g')"
    config+="$(echo "$warp_info" | grep -P "(private_key|public_key|\"v4\": \"162.159.192.2\"|\"v6\": \"2)" | sed "s/ //g" | sed 's/:"/: "/g' | sed 's/^"/    "/g')"
    config+=$'\n}'

    # 输出完整配置
    echo "$config"

    # 提取并设置环境变量
    # 获取端点 IPv4 地址（而不是接口地址）
    export WARP_IPV4=$(echo "$warp_info" | grep -Po '"v4":\s*"\K[0-9.]+(?=:0")' | head -1)
    # 获取 IPv6 地址
    export WARP_IPV6=$(echo "$warp_info" | grep -oP '"v6": "\K[0-9a-f:]+(?=")' | tail -1)
    # 获取保留值
    export WARP_Reserved=$(echo "$config" | grep -oP '"reserved_dec": \K\[[0-9, ]+\]' | tr -d '[]')
    # 获取私钥
    export WARP_private=$(echo "$config" | grep -oP '"private_key": "\K[^"]+')

    # 显示环境变量
    echo "WARP_IPV4=$WARP_IPV4"
    echo "WARP_IPV6=$WARP_IPV6"
    echo "WARP_private=$WARP_private"
    echo "WARP_Reserved=$WARP_Reserved"
}

# 主函数：执行脚本的主要流程
main() {
    # 初始化包管理器
    package_manager
    # 安装必需的软件包
    install_software "xxd" "xxd"
    install_software "python3" "python3"
    
    # 注册 WARP 并检查执行结果
    warp_info=$(reg) ; exit_code=$?
    if [[ $exit_code != 0 ]];then
        echo "$warp_info"
        echo -e "${ERROR}错误:${END} \"reg\" 函数返回错误码 $exit_code，退出执行。"
        exit $exit_code
    fi

    # 处理保留信息并检查执行结果
    warp_reserved=$(reserved) ; exit_code=$?
    if [[ $exit_code != 0 ]];then
        echo "$warp_reserved"
        echo -e "${ERROR}错误:${END} \"reserved\" 函数返回错误码 $exit_code，退出执行。"
        exit $exit_code
    fi
    
    # 格式化并输出最终配置
    format
}

# 执行主函数
main "$@"
