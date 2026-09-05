#!/usr/bin/env bash
# disk-cleanup-full.sh
# 通用 VPS 磁盘清理脚本（全自动，无需交互确认）
# 兼容 Debian/Ubuntu (apt) 与 RHEL/CentOS/AlmaLinux/Rocky (yum/dnf)
#
# 用法: sudo ./disk-cleanup-full.sh
#
# 设计原则：
#   - 全自动执行，不需要任何用户交互
#   - 自动检测当前运行内核并保护，绝不删除正在使用的内核
#   - 只清理缓存、日志、临时文件、孤儿依赖、编译中间产物等可再生数据
#   - 不删除任何已安装并正在使用的软件包本体或已编译好的内核模块(.ko)

set -uo pipefail

CURRENT_KERNEL="$(uname -r)"

section() {
    echo
    echo "=================================================="
    echo "  $1"
    echo "=================================================="
}

show_disk() {
    echo
    df -h / 2>/dev/null
}

# 检测包管理器
PKG_MGR=""
if command -v apt-get &>/dev/null; then
    PKG_MGR="apt"
elif command -v dnf &>/dev/null; then
    PKG_MGR="dnf"
elif command -v yum &>/dev/null; then
    PKG_MGR="yum"
fi

section "清理前磁盘使用情况"
show_disk
echo
echo "当前运行内核: $CURRENT_KERNEL （全程自动保护，不会被删除）"
echo "检测到的包管理器: ${PKG_MGR:-未知，跳过软件包相关清理}"

######################################
# 通用清理（不依赖具体发行版）
######################################

section "通用清理"

echo "-- 清理 systemd journal 日志（只保留最近 3 天）--"
if command -v journalctl &>/dev/null; then
    journalctl --vacuum-time=3d 2>/dev/null || true
else
    echo "未检测到 journalctl，跳过。"
fi

echo
echo "-- 清理常见日志文件（只清空超过 50MB 的大文件，避免误清小日志）--"
for f in /var/log/syslog /var/log/messages /var/log/auth.log /var/log/kern.log /var/log/dmesg; do
    if [[ -f "$f" ]]; then
        size=$(du -m "$f" 2>/dev/null | cut -f1)
        if [[ -n "$size" && "$size" -gt 50 ]]; then
            : > "$f"
            echo "  已清空: $f (原大小 ${size}MB)"
        fi
    fi
done

echo
echo "-- 清理 /tmp 和 /var/tmp 中超过 7 天的临时文件 --"
find /tmp -mindepth 1 -mtime +7 -exec rm -rf {} + 2>/dev/null || true
find /var/tmp -mindepth 1 -mtime +7 -exec rm -rf {} + 2>/dev/null || true

echo
echo "-- 清理常见安装工具留下的临时残留（dpkg/apt/dkms 安装中断产物）--"
rm -rf /tmp/apt-dpkg-install-* /tmp/*.tar.gz /tmp/brutalinst.* 2>/dev/null || true

echo
echo "-- 清理 DKMS 编译产生的中间目标文件（保留已编译安装好的 .ko 模块本身）--"
if [[ -d /var/lib/dkms ]]; then
    find /var/lib/dkms -type f \( -name "*.o" -o -name "*.cmd" \) -delete 2>/dev/null || true
fi

echo
echo "-- 清理 core dump 文件 --"
find / -xdev -maxdepth 3 -type f -name "core.*" -exec rm -f {} + 2>/dev/null || true
find /var/crash -mindepth 1 -exec rm -rf {} + 2>/dev/null || true

show_disk

######################################
# 按包管理器分支的清理
######################################

section "包管理器相关清理 (${PKG_MGR:-none})"

case "$PKG_MGR" in
    apt)
        echo "-- 清理 apt 下载缓存 --"
        apt-get clean -y 2>/dev/null || true

        echo
        echo "-- 移除不再需要的自动安装依赖 --"
        apt-get autoremove --purge -y 2>/dev/null || true

        echo
        echo "-- 清理已卸载软件包留下的孤儿配置文件（状态为 rc）--"
        rc_pkgs=$(dpkg -l 2>/dev/null | awk '/^rc/{print $2}')
        if [[ -n "$rc_pkgs" ]]; then
            # shellcheck disable=SC2086
            apt-get purge -y $rc_pkgs 2>/dev/null || true
        fi

        echo
        echo "-- 清理已过期的旧版本软件包缓存索引 --"
        apt-get autoclean -y 2>/dev/null || true

        echo
        echo "-- 自动清理与当前运行内核无关的旧内核包（自动跳过当前内核，无需确认）--"
        old_kernels=$(dpkg -l 2>/dev/null \
            | grep -E '^ii\s+linux-(image|headers)-[0-9]' \
            | awk '{print $2}' \
            | grep -v "$CURRENT_KERNEL" || true)
        if [[ -n "$old_kernels" ]]; then
            echo "发现以下旧内核包，将自动清理："
            echo "$old_kernels"
            # shellcheck disable=SC2086
            apt-get purge -y $old_kernels 2>/dev/null || true
            apt-get autoremove --purge -y 2>/dev/null || true
        else
            echo "没有发现多余的旧内核包。"
        fi
        ;;
    dnf|yum)
        echo "-- 清理 $PKG_MGR 缓存 --"
        "$PKG_MGR" clean all -y 2>/dev/null || true

        echo
        echo "-- 移除不再需要的自动安装依赖 --"
        "$PKG_MGR" autoremove -y 2>/dev/null || true

        echo
        echo "-- 自动清理旧内核，只保留当前运行的和最新的一个版本 --"
        if command -v package-cleanup &>/dev/null; then
            package-cleanup --oldkernels --count=2 -y 2>/dev/null || true
        else
            echo "未安装 package-cleanup（yum-utils/dnf-utils），跳过旧内核自动清理。"
            echo "可执行: $PKG_MGR install -y yum-utils 后重跑本脚本以启用此项。"
        fi
        ;;
    *)
        echo "未识别的包管理器，跳过软件包相关清理步骤。"
        ;;
esac

show_disk

section "清理完成，最终磁盘使用情况"
show_disk

echo
echo "== 当前占用较大的目录 TOP 15（供参考，未自动处理，如需清理请自行判断）=="
du -sh /var/* /usr/* /root/* /home/* 2>/dev/null | sort -rh | head -15
