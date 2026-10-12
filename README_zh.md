<div align="center">

# sing-box

### 五种协议，一个菜单，官方内核

**[sing-box](https://github.com/SagerNet/sing-box)** 一键安装与管理脚本，支持 Debian、Ubuntu、Alpine。<br>
一次部署 Hysteria2、VLESS Reality、AnyTLS、Shadowsocks 2022 和 Snell v6，并直接生成可导入的客户端节点。

[![Checks](https://img.shields.io/github/actions/workflow/status/passeway/sing-box/check.yml?branch=main&style=flat-square&label=Checks)](https://github.com/passeway/sing-box/actions/workflows/check.yml)
[![Core](https://img.shields.io/badge/Core-Latest%20stable-2563eb?style=flat-square)](https://github.com/SagerNet/sing-box/releases/latest)
![Linux](https://img.shields.io/badge/Linux-Debian%20%7C%20Ubuntu%20%7C%20Alpine-18181B?style=flat-square)
![Architecture](https://img.shields.io/badge/Arch-AMD64%20%7C%20ARM64-18181B?style=flat-square)

[English](README.md) · **简体中文**

[项目亮点](#项目亮点) · [快速开始](#快速开始) · [连接客户端](#连接客户端) · [管理菜单](#管理菜单) · [内核更新](#内核更新) · [故障排查](#故障排查)

</div>

---

## 项目亮点

| | |
| :--- | :--- |
| **只用官方内核** | 直接从 SagerNet/sing-box 下载最新稳定版，拒绝预发布版本，并校验安装包与当前架构一致。 |
| **一次装好五种协议** | 随机分配空闲端口（同时检查 TCP、UDP 和 IPv6），独立生成各协议凭据、自签名证书和 Reality 密钥对。 |
| **节点直接可用** | 输出 Mihomo（Clash Meta）、Surge 配置和 v2rayN 等客户端的分享链接，按地区命名，例如 `HK-vless-in`。 |
| **放行端口提示** | 安装结果直接列出需要放行的 TCP 和 UDP 端口。 |
| **服务自动恢复** | 内核崩溃后由 systemd / OpenRC 在 3 秒后自动拉起；60 秒内连续失败 5 次后停止重试，不会无限重启。 |
| **安全更新内核** | 先用新内核校验现有配置；更新失败时恢复原内核、配置、服务定义和运行状态。 |

## 快速开始

使用 **root** 账户运行，支持 **AMD64 / ARM64**。Debian、Ubuntu 使用 systemd，Alpine 使用 OpenRC。服务器需要能访问 GitHub 下载官方安装包。

**Debian / Ubuntu**（需已安装 `bash`、`curl` 和 `ca-certificates`）

```bash
bash <(curl -fsSL https://sing-box-sigma.vercel.app)
```

**Alpine**

```sh
apk add --no-cache bash curl ca-certificates
bash -c 'bash <(curl -fsSL https://sing-box-sigma.vercel.app)'
```

1. 选择 **1** 安装，依赖、内核、配置和服务一次完成。
2. 按安装结果在云安全组和服务器防火墙中放行端口：

   ```text
   🎉sing-box 安装成功，请在云安全组和系统防火墙中放行 TCP 端口 34359/40789/42000/47903，UDP 端口 38183/42000，项目地址: https://github.com/passeway/sing-box
   ```

3. 将这一行下面输出的节点导入客户端。

再次运行同一条命令即可打开管理菜单。监听地址跟随系统：IPv6 可用时使用 `::`，否则使用 `0.0.0.0`，不会修改系统 IPv6 设置。

<details>
<summary>备用入口：从 GitHub 直接运行</summary>

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/passeway/sing-box/main/sing-box.sh)
```

</details>

## 连接客户端

安装完成后自动输出节点，之后也可以随时通过菜单 **7** 重新导出。节点按服务器所在国家或地区代码命名，识别失败时使用 `Proxy` 前缀。

| 协议 | 默认配置 | 端口 | Mihomo | Surge | 分享链接 |
| :--- | :--- | :---: | :---: | :---: | :---: |
| Hysteria2 | QUIC，单端口 | UDP | ✓ | ✓ | ✓ |
| VLESS Reality | TCP，Vision | TCP | ✓ | — | ✓ |
| AnyTLS | TLS，独立随机密码 | TCP | ✓ | ✓ | ✓ |
| Shadowsocks 2022 | `2022-blake3-aes-128-gcm` | TCP + UDP | ✓ | ✓ | ✓ |
| Snell v6 | 原生入站，`mode=default` | TCP | — | ✓ | — |

输出分为三部分，请分别复制。内容只包含节点，不含完整的规则和策略组。

| 部分 | 用法 |
| :--- | :--- |
| `# Clash / Mihomo` | 将 `proxies` 下的节点合并到自己的配置；JSON 同时也是合法的 YAML。 |
| `# Surge` | 将代理行加入配置文件的 `[Proxy]` 部分。 |
| `# Share links` | 将对应协议的链接导入 v2rayN 等支持该协议的客户端。 |

> [!NOTE]
> Hysteria2 和 AnyTLS 使用自签名证书，导出的节点带有 `skip-cert-verify` 或 `insecure=1`。如果换成受信任证书，请在客户端重新开启证书验证。

VLESS Reality 的公钥、short-id、SNI 和 flow 必须与服务端一致。Hysteria2 默认不设置端口跳跃。Snell v6 使用 sing-box 原生入站，客户端需支持 v6。

## 管理菜单

菜单顶部显示安装状态、运行状态和内核版本。未安装时只提供 **1**、**2**、**0**，其他编号视为无效选项。

| 选项 | 功能 | 说明 |
| :---: | :--- | :--- |
| `1` | 安装服务 | 下载最新稳定版内核，生成五种协议配置，启动服务并列出需放行的端口。 |
| `2` | 卸载服务 | 输入 `y` 确认后，删除服务、内核、配置和日志；未安装时也会清理残留文件。 |
| `3` | 启动 / 停止 | 根据当前运行状态切换。 |
| `4` | 重启服务 | 先校验配置，重启后确认内核进程持续运行。 |
| `5` | 查看状态 | 显示服务管理器报告的状态。 |
| `6` | 查看日志 | 实时跟踪日志，按 `Ctrl+C` 返回菜单。 |
| `7` | 导出节点 | 根据当前配置重新生成并显示客户端节点。 |
| `8` | 更新内核 | 安装最新稳定版内核，配置原样保留。 |
| `0` | 退出 | 关闭管理菜单。 |

如果内核持续启动失败（例如端口被其他程序占用），服务管理器在 60 秒内重试 5 次后停止。排除原因后，通过菜单 **3** 或 **4** 重新启动即可。

### 文件位置

| 路径 | 用途 |
| :--- | :--- |
| `/usr/local/bin/sing-box` | 内核程序 |
| `/etc/sing-box/config.json` | 服务端配置 |
| `/etc/sing-box/client.txt` | 最近一次导出的客户端节点 |
| `/etc/sing-box/client-meta.json` | 导出地址 `address` 与名称前缀 `name` |
| `/etc/sing-box/cert.pem`、`key.pem` | Hysteria2 / AnyTLS 使用的证书与私钥 |

修改服务端配置后，选择 **4** 重启，再选择 **7** 导出。公网 IP 或名称前缀变化时，编辑 `client-meta.json` 后重新导出；该文件不会自动刷新。

## 内核更新

菜单 **8** 替换内核并刷新服务定义，保留配置、端口和凭据，不增删协议，也不做历史配置迁移。

- **替换前校验**：无法获取版本信息、安装包缺失或现有配置未通过新内核校验时，终止更新。
- **失败自动恢复**：替换文件、写入服务或重启失败时，恢复原内核、配置、服务定义和运行状态；恢复也失败时，保留恢复文件并打印路径。
- **成功后导出节点**：如果只是导出失败，新内核继续运行，可从菜单 **7** 重试。

这种临时恢复机制不能替代备份，也无法应对断电或 `SIGKILL`。

## 故障排查

依次检查服务状态、端口放行、客户端参数和日志。

```bash
/usr/local/bin/sing-box check -c /etc/sing-box/config.json
```

<details>
<summary>Debian / Ubuntu：服务状态与日志</summary>

```bash
systemctl status sing-box --no-pager
journalctl -u sing-box -n 50 --no-pager
```

</details>

<details>
<summary>Alpine：服务状态与日志</summary>

```sh
rc-service sing-box status
tail -n 50 /var/log/sing-box.log
```

日志每小时检查一次，超过 1 MiB 时轮转，保留 3 份压缩归档。两次检查之间文件仍可能增长，`copytruncate` 轮转时可能丢失少量日志。

</details>

提交 [Issue](https://github.com/passeway/sing-box/issues) 时，请附上系统与架构、内核与客户端版本、复现步骤和相关日志，并隐藏密码、PSK、私钥及完整节点链接。

## 测试

[持续集成](https://github.com/passeway/sing-box/actions/workflows/check.yml) 在 AMD64 和 ARM64 的 Debian 12/13、Ubuntu 24.04、Alpine 3.22 容器中运行，使用对应架构的官方内核：

- 脚本语法、配置生成、节点导出和更新回滚
- 五种协议的真实本地代理流量
- 真实 systemd / OpenRC 下的安装、崩溃自动重启、重启次数上限、内核更新与卸载

真实 VPS 的开机自启、外网连通性和 UDP 转发仍需在实际环境中确认。

## 许可证

本项目是基于 [SagerNet/sing-box](https://github.com/SagerNet/sing-box) 官方内核的独立管理脚本，源代码与许可证见 [sing-box.sh](sing-box.sh) 和 [LICENSE](LICENSE)。
