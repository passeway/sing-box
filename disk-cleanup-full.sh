#!/usr/bin/env bash
# Conservative cache/log cleanup. Never remove packages, kernels or arbitrary /tmp trees.
set -uo pipefail
cleanup_main() {
    [ "$(id -u)" -eq 0 ] || { echo '请使用 root 权限运行' >&2; return 1; }
    local failed=0
    echo '清理前：'; df -h /
    echo "保留所有已安装软件包及内核（当前内核：$(uname -r)）"
    if command -v journalctl >/dev/null 2>&1; then
        journalctl --vacuum-time=3d || failed=1
    fi
    # Let the OS apply configured age/ownership/lock rules. On non-systemd hosts, skip.
    if command -v systemd-tmpfiles >/dev/null 2>&1; then
        systemd-tmpfiles --clean || failed=1
    fi
    if command -v apt-get >/dev/null 2>&1; then
        apt-get clean || failed=1
    elif command -v dnf >/dev/null 2>&1; then
        dnf clean all || failed=1
    elif command -v yum >/dev/null 2>&1; then
        yum clean all || failed=1
    elif command -v apk >/dev/null 2>&1; then
        apk cache clean || failed=1
    fi
    echo '清理后：'; df -h /
    if [ "$failed" -ne 0 ]; then
        echo '部分清理步骤失败，请检查上方错误。' >&2
        return 1
    fi
    echo '清理完成；未执行内核卸载、autoremove 或任意临时目录递归删除。'
}
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then cleanup_main "$@"; fi
