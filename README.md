# sing-box 多协议管理脚本

支持 Debian、Ubuntu（systemd）及 Alpine（OpenRC），支持 AMD64、ARM64。目前使用官方 sing-box **1.14.2**，Snell 入站要求 1.14 或更新版本。

## 一键运行

```bash
bash <(curl -fsSL sing-box-sigma.vercel.app)
```

Alpine 首次运行：

```sh
apk add --no-cache bash curl ca-certificates
bash -c 'bash <(curl -fsSL sing-box-sigma.vercel.app)'
```

## 协议

| 协议 | 服务端配置 | 客户端输出 |
| --- | --- | --- |
| Hysteria2 | 随机 UDP 端口、自签名 TLS | Clash/Mihomo、Surge、分享链接 |
| VLESS Reality | 随机 TCP 端口、Vision | Clash/Mihomo、分享链接 |
| AnyTLS | 随机 TCP 端口；按项目约定复用 Reality 公钥作为密码 | Clash/Mihomo、Surge、分享链接 |
| Shadowsocks | 独立对外入站，2022-blake3-aes-128-gcm | Clash/Mihomo、Surge、分享链接 |
| Snell | v6、mode=default、独立随机 PSK | Surge |

已移除 ShadowTLS。导出文件中的 Clash/Mihomo 部分使用 JSON 格式（也属于合法 YAML），与 Surge 行及分享链接分开复制。节点名称带协议/入站标签，避免重名。TLS 使用自签名证书，相应客户端条目保持 `skip-cert-verify` / `insecure` 设置。

Hysteria2 目前为单端口；没有自动修改防火墙实现端口跳跃。请在云安全组/本机防火墙放行各协议所需端口；Shadowsocks 如需 UDP 转发，还需放行相同端口的 UDP。

## 已有安装与迁移

运行新版脚本，选择 **8：更新内核并迁移协议配置**：

- 保留已有入站的端口、凭据、AnyTLS 密码及其他配置。
- 删除 ShadowTLS 入站，将原 `shadowsocks-in` 的本地监听改成对外监听，补上 Snell v6。
- 使用新内核检查配置，检查失败时不替换现有内核/配置。自定义旧版字段如不兼容，需要按错误提示手动迁移。
- 使用 `/usr/local/bin/sing-box` 及脚本生成的服务定义，只加载 `/etc/sing-box/config.json`。原包管理器安装的二进制不会在更新时删除；卸载时一并处理。
- 不创建二进制备份。通过校验后若写入或重启失败，脚本报告错误，不宣称成功。

独立 Shadowsocks 使用原本的 Shadowsocks 端口，不再使用 ShadowTLS 的端口，客户端需要替换为新导出的条目。

## 管理与排错

- 菜单 **7** 根据当前服务端配置重新生成客户端信息。公网地址和节点名前缀保存在 `/etc/sing-box/client-meta.json`，可编辑后重新导出。更改服务端配置后需选择 **4** 重启生效。
- 公网 IP 获取有超时、备用接口和手动输入回退。
- 配置目录权限为 `700`，配置、私钥、客户端信息为 `600`；服务由 root 运行。
- 启动/重启前执行 `sing-box check`，重启后检查服务是否保持运行。安装与更新会检查下载、生成及写入失败。
- 输入关闭时退出；卸载必须明确输入 `y`；查看实时日志按 Ctrl+C 返回菜单。
- Alpine 日志 `/var/log/sing-box.log` 每小时检查，超过 1 MiB 时轮转，保留 3 份压缩归档。检查之间仍可能增长；copytruncate 有短暂的复制/截断丢日志窗口。
- Debian/Ubuntu 日志使用 journal。手动排错优先使用 `sing-box check -c /etc/sing-box/config.json` 和服务日志，避免在现有服务运行时再启动第二个实例导致端口冲突。

仓库 `config.json` 是需替换占位符的五协议示例，不是安装时直接下载的配置。脚本通过结构化 JSON 生成实际配置。

## 磁盘清理

`disk-cleanup-full.sh` 只清理包管理器缓存、按时间裁剪 journal，并在可用时调用系统 `systemd-tmpfiles --clean` 策略。不自动卸载内核或软件包，不递归删除自定义临时目录，不按 `core.*` 文件名删除任意文件。

## 开发验证

```sh
SING_BOX_TEST_BINARY=/path/to/sing-box python3 -m unittest discover -s tests -v
```

CI 在 Debian、Ubuntu、Alpine 容器中运行回归检查和官方内核的本地代理流量测试。容器测试不替代真实 VPS 上的开机自启和服务管理测试；ARM64 需要对应机器进一步验证。

上游项目：[SagerNet/sing-box](https://github.com/SagerNet/sing-box)。
