<div align="center">

<h1>sing-box</h1>
<p><strong>Linux 多协议代理部署与管理</strong></p>
<p>官方内核 · 自动配置 · 统一维护</p>

<p>
  <a href="https://github.com/passeway/sing-box/actions/workflows/check.yml"><img src="https://img.shields.io/github/actions/workflow/status/passeway/sing-box/check.yml?branch=main&amp;style=flat-square&amp;label=Checks" alt="CI checks"></a>
  <a href="https://github.com/SagerNet/sing-box/releases/latest"><img src="https://img.shields.io/badge/Core-Latest%20stable-2563eb?style=flat-square" alt="Latest stable core"></a>
  <img src="https://img.shields.io/badge/OS-Debian%20%7C%20Ubuntu%20%7C%20Alpine-475569?style=flat-square" alt="Supported systems">
  <img src="https://img.shields.io/badge/Arch-AMD64%20%7C%20ARM64-475569?style=flat-square" alt="Supported architectures">
</p>

<p>
  <a href="#快速开始">快速开始</a> &nbsp;·&nbsp;
  <a href="#连接客户端">连接客户端</a> &nbsp;·&nbsp;
  <a href="#日常管理">日常管理</a> &nbsp;·&nbsp;
  <a href="#故障排查">故障排查</a>
</p>

</div>

为 Debian、Ubuntu 和 Alpine 提供统一的 sing-box 管理入口。全新安装自动配置 Hysteria2、VLESS Reality、AnyTLS、Shadowsocks 2022 和 Snell v6，并生成客户端节点。

脚本负责依赖安装、随机端口分配、凭据生成与开机自启；后续通过同一菜单完成启停、日志查看和内核更新。

## 快速开始

使用 **root** 账户运行。支持 **AMD64 / ARM64**；Debian、Ubuntu 使用 systemd，Alpine 使用 OpenRC。服务器需要能够访问 GitHub 获取官方安装包。

### Debian / Ubuntu

终端需已安装 `bash`、`curl` 和 `ca-certificates`。

```bash
bash <(curl -fsSL https://sing-box-sigma.vercel.app)
```

### Alpine

```sh
apk add --no-cache bash curl ca-certificates
bash -c 'bash <(curl -fsSL https://sing-box-sigma.vercel.app)'
```

1. 选择 **1**，安装服务并生成节点。
2. 在云安全组和服务器防火墙中放行安装结果提示的 TCP / UDP 端口，协议要求见下表。
3. 按客户端类型导入对应内容，检查连接。

重新运行安装命令即可打开管理菜单。脚本根据系统 IPv6 可用性选择监听地址；IPv6 不可用时使用 IPv4，不修改系统 IPv6 设置。

<details>
<summary>备用入口：从 GitHub 直接运行</summary>

在已安装依赖的 **Bash 终端**中执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/passeway/sing-box/main/sing-box.sh)
```

</details>

## 连接客户端

安装完成后自动显示节点，也可随时通过菜单 **7** 重新导出。节点使用国家或地区代码命名，例如 `HK-vless-in`、`US-snell-in`；识别失败时使用 `Proxy` 前缀。

### 协议与导出格式

下表列出脚本生成的配置。客户端及其内核需支持对应协议；“—”表示脚本不提供该格式的导出。

| 协议 | 默认配置 | 放行端口 | Mihomo | Surge | 分享链接 |
| :--- | :--- | :--- | :---: | :---: | :---: |
| Hysteria2 | QUIC，单端口 | UDP | ✓ | ✓ | ✓ |
| VLESS Reality | TCP，Vision | TCP | ✓ | — | ✓ |
| AnyTLS | TLS，独立随机密码 | TCP | ✓ | ✓ | ✓ |
| Shadowsocks 2022 | `2022-blake3-aes-128-gcm` | TCP / UDP¹ | ✓ | ✓ | ✓ |
| Snell v6 | 原生入站，`mode=default` | TCP | — | ✓ | — |

¹ Shadowsocks 转发 UDP 时，需额外放行同端口 UDP。所有端口均以实际导出结果为准，脚本不自动配置防火墙。

### 导入方式

| 客户端 | 操作 |
| :--- | :--- |
| Mihomo | 将 `# Clash / Mihomo` 下的 `proxies` 节点合并到自己的配置；输出为 JSON，也可作为 YAML 使用。 |
| Surge | 将 `# Surge` 下的代理行加入配置文件的 `[Proxy]` 部分。 |
| v2rayN 等 | 复制 `# Share links` 下对应协议的链接，导入支持该协议的客户端。 |

各类输出应分别复制；节点内容不包含完整的规则和策略组配置。

> **证书设置**
>
> Hysteria2 和 AnyTLS 默认使用自签名证书，导出内容包含 `skip-cert-verify` 或 `insecure=1`。如自行更换为受信任证书，请同时调整客户端的证书验证设置。

VLESS Reality 的公钥、short-id、SNI 和 flow 必须与服务端一致。Hysteria2 默认不设置端口跳跃。Snell v6 使用 sing-box 原生入站，客户端需支持 v6。

## 日常管理

菜单顶部显示安装状态、运行状态和当前内核版本。未安装时仅显示安装、卸载与退出，其他编号视为无效选项；安装后显示完整菜单。

| 选项 | 功能 | 行为 |
| :---: | :--- | :--- |
| `1` | 安装服务 | 下载官方最新稳定版，生成五种协议配置并启动服务，提示需放行的端口。 |
| `2` | 卸载服务 | 输入 `y` 确认后，删除服务、内核、配置及日志；未安装时清理残留文件。 |
| `3` | 启动 / 停止 | 根据当前运行状态切换操作。 |
| `4` | 重启服务 | 先校验配置，重启后确认内核进程持续运行。 |
| `5` | 查看状态 | 显示服务管理器报告的状态。 |
| `6` | 查看日志 | 实时跟踪日志，按 `Ctrl+C` 返回菜单。 |
| `7` | 导出节点 | 根据当前配置重新生成并显示客户端内容。 |
| `8` | 更新内核 | 获取官方最新稳定版，原样保留配置。 |
| `0` | 退出 | 关闭管理菜单。 |

服务异常退出时，systemd / OpenRC 会在 3 秒后自动重启；60 秒内连续失败 5 次后停止重试，避免无限重启。排除原因后，可通过菜单 **3** 或 **4** 重新启动。

### 配置位置

| 路径 | 用途 |
| :--- | :--- |
| `/usr/local/bin/sing-box` | 内核程序 |
| `/etc/sing-box/config.json` | 服务端配置 |
| `/etc/sing-box/client.txt` | 导出的客户端节点 |
| `/etc/sing-box/client-meta.json` | 导出地址 `address` 与名称前缀 `name` |
| `/etc/sing-box/cert.pem`、`key.pem` | Hysteria2 / AnyTLS 使用的证书与私钥 |

修改服务端配置后，选择 **4** 重启，再选择 **7** 导出。公网 IP 或节点前缀发生变化时，编辑 `client-meta.json` 中对应字段，再选择 **7**；已有地址不会自动刷新。

### 内核更新

菜单 **8** 只更新内核并刷新服务定义，保留配置内容、端口和凭据。脚本不执行历史配置迁移，也不增删已有协议。

- **替换前校验：**版本信息获取失败、安装包不可用或现有配置未通过新内核校验时，终止更新。
- **失败恢复：**文件替换、服务配置或重启失败时，尝试恢复旧内核、配置、服务定义及更新前的运行状态。恢复失败会保留恢复文件并打印路径。
- **完成后导出：**更新成功后清理临时备份并重新导出节点；若仅导出失败，保留正常运行的新版本，可从菜单 **7** 重试。

临时恢复机制不替代长期备份，也不覆盖断电或 `SIGKILL`。

## 故障排查

连接异常时，依次检查服务状态、端口放行、客户端参数和日志。

**检查配置**

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

日志每小时检查一次，超过 1 MiB 时轮转，保留 3 份压缩归档。检查间隔内文件仍可能增长；`copytruncate` 在复制与截断之间可能丢失少量日志。

</details>

提交 [Issue](https://github.com/passeway/sing-box/issues) 时，请附上系统与架构、内核与客户端版本、复现步骤和相关日志，并隐藏密码、PSK、私钥及完整节点链接。

## 验证与项目说明

[持续集成](https://github.com/passeway/sing-box/actions/workflows/check.yml) 在 AMD64 与 ARM64 的 Debian 12/13、Ubuntu 24.04、Alpine 3.22 容器中，使用对应架构的官方内核，检查脚本语法、配置生成、节点导出、更新失败恢复和五种协议的本地代理流量，并在真实 systemd / OpenRC 下验证安装、崩溃自动重启、重启次数上限、更新与卸载。

真实 VPS 的开机自启、外网连通性及 UDP 转发仍需在实际部署环境验证。

本项目是基于 [SagerNet/sing-box](https://github.com/SagerNet/sing-box) 官方内核的独立管理脚本。源代码与许可证见 [sing-box.sh](sing-box.sh) 和 [LICENSE](LICENSE)。
