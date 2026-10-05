<div align="center">

# sing-box

### 多协议，一站管理。

面向 Debian · Ubuntu · Alpine 的轻量级代理服务管理脚本。

**Hysteria2 · VLESS Reality · AnyTLS · Shadowsocks · Snell**

[![Checks](https://github.com/passeway/sing-box/actions/workflows/check.yml/badge.svg?branch=main)](https://github.com/passeway/sing-box/actions/workflows/check.yml)
![Platforms](https://img.shields.io/badge/Linux-Debian%20%7C%20Ubuntu%20%7C%20Alpine-2563eb?style=flat-square)
![Architecture](https://img.shields.io/badge/Arch-AMD64%20%7C%20ARM64-475569?style=flat-square)

[快速开始](#快速开始) · [协议支持](#协议支持) · [日常管理](#日常管理) · [升级迁移](#升级迁移) · [问题反馈](https://github.com/passeway/sing-box/issues)

</div>

---

从安装、服务管理到客户端配置导出，在一个交互菜单中完成。自动适配 systemd 与 OpenRC，使用官方 sing-box 内核，按当前服务端配置生成连接信息。

| 部署 | 管理 | 连接 | 校验 |
| :--- | :--- | :--- | :--- |
| 三种系统，自动适配 | 启停、重启、状态与日志 | 客户端配置与分享链接 | 配置检查与启动结果检测 |
| 随机端口与凭据生成 | 内核更新与协议迁移 | 支持重新生成导出内容 | 三系统 CI 与代理流量测试 |

## 快速开始

以 **root** 身份运行。当前脚本使用官方 sing-box **1.14.2**。

### Debian / Ubuntu

在已安装 `bash`、`curl` 的终端执行：

```bash
bash <(curl -fsSL sing-box-sigma.vercel.app)
```

### Alpine

首次运行先安装命令依赖：

```sh
apk add --no-cache bash curl ca-certificates
bash -c 'bash <(curl -fsSL sing-box-sigma.vercel.app)'
```

**运行脚本 → 选择 `1` 安装 → 放行对应端口 → 导入客户端配置。**

> [!IMPORTANT]
> 请在云安全组和服务器防火墙中放行实际生成的端口。Hysteria2 使用 UDP；VLESS Reality、AnyTLS、Snell 使用 TCP；Shadowsocks 使用 TCP，启用 UDP 转发时还需放行同端口 UDP。

## 协议支持

下表表示**脚本提供的导出格式**；客户端需使用支持对应协议的版本。

| 协议 | 配置特点 | Clash / Mihomo | Surge | 分享链接 |
| :--- | :--- | :---: | :---: | :---: |
| **Hysteria2** | QUIC · 自签名 TLS · 单 UDP 端口 | ✓ | ✓ | ✓ |
| **VLESS Reality** | Reality · Vision · TCP | ✓ | — | ✓ |
| **AnyTLS** | TLS · TCP | ✓ | ✓ | ✓ |
| **Shadowsocks** | 独立入站 · `2022-blake3-aes-128-gcm` | ✓ | ✓ | ✓ |
| **Snell** | v6 · `mode=default` · 独立随机 PSK | — | ✓ | — |

- **AnyTLS** 按项目约定复用 Reality 公钥作为密码，升级时保留已有密码。
- **Hysteria2** 当前使用单端口，未自动配置端口跳跃。
- **Snell** 使用 sing-box 原生入站，需要 1.14 或更新版本的内核。
- **ShadowTLS** 已移除，Shadowsocks 作为独立协议对外提供服务。

### 客户端导入

| 客户端 | 使用方式 |
| :--- | :--- |
| **v2rayN** | 复制对应协议的分享链接导入；客户端内核需支持该协议 |
| **Clash / Mihomo** | 使用导出内容中的 `proxies` 节点；该部分为 JSON 格式，也属于合法 YAML |
| **Surge** | 复制对应的代理行，放入配置的 `[Proxy]` 部分 |

不同格式请分开复制，导出内容不是一份可整体导入所有客户端的配置。节点名称包含协议或入站标签，方便区分。

> [!NOTE]
> Hysteria2 与 AnyTLS 默认使用自签名证书。导出条目包含相应的 `skip-cert-verify` / `insecure=1` 设置；手动编辑时需保持一致。VLESS Reality 的 short-id 必须与服务端匹配。

## 日常管理

重新运行安装命令即可打开管理菜单。未安装时只显示安装、卸载和退出；安装后显示完整管理选项。

| 选项 | 操作 |
| :---: | :--- |
| `1` | 安装 sing-box 服务 |
| `2` | 卸载 sing-box 服务，需要明确输入 `y` |
| `3` | 按当前状态显示启动或停止 |
| `4` | 重启服务，并检查配置与运行状态 |
| `5` | 查看服务状态 |
| `6` | 查看实时日志，按 `Ctrl+C` 返回菜单 |
| `7` | 根据当前服务端配置重新生成并查看客户端配置 |
| `8` | 更新 sing-box 内核，同时迁移协议配置 |
| `0` | 退出 |

### 常用路径

| 路径 | 用途 |
| :--- | :--- |
| `/usr/local/bin/sing-box` | 脚本安装的内核 |
| `/etc/sing-box/config.json` | 服务端配置 |
| `/etc/sing-box/client.txt` | 生成的客户端配置与分享链接 |
| `/etc/sing-box/client-meta.json` | 公网地址与节点名称前缀 |

修改公网地址或节点前缀后，选择 **7** 重新导出；修改服务端配置后，选择 **4** 重启生效。

## 升级迁移

已有安装可运行新版脚本，选择 **8 · 更新 sing-box 内核**。

1. 下载内核，整理并迁移已有配置。
2. 保留已有入站的端口、凭据及其他配置，删除 ShadowTLS，补上 Snell v6。
3. 将原 `shadowsocks-in` 的本地监听改为对外监听。
4. 使用新内核检查配置，通过后替换、重启并重新导出客户端信息。

> [!NOTE]
> 独立 Shadowsocks 沿用原 Shadowsocks 端口，不是原 ShadowTLS 端口。迁移后请使用新导出的条目。

<details>
<summary><strong>展开：更新行为与配置权限</strong></summary>

- 配置检查失败时，不替换现有内核与配置。自定义旧版字段不兼容时，需根据错误提示手动迁移。
- 不创建二进制备份；写入或重启失败时会报告错误，不提供自动回滚。
- 脚本生成的服务定义只加载 `/etc/sing-box/config.json`，使用 `/usr/local/bin/sing-box`。
- 原包管理器安装的二进制不会在更新时删除；卸载时一并处理。
- 服务由 root 运行。配置目录权限为 `700`，配置、私钥和客户端信息为 `600`。
- 公网 IP 获取包含超时控制、备用接口和手动输入回退；终端输入关闭时退出菜单。

</details>

## 排查问题

先检查配置，再查看对应系统的日志：

```bash
/usr/local/bin/sing-box check -c /etc/sing-box/config.json
```

<details>
<summary><strong>Debian / Ubuntu · systemd</strong></summary>

```bash
systemctl status sing-box --no-pager
journalctl -u sing-box -n 50 --no-pager
```

</details>

<details>
<summary><strong>Alpine · OpenRC</strong></summary>

```sh
rc-service sing-box status
tail -n 50 /var/log/sing-box.log
```

日志每小时检查一次，超过 1 MiB 时轮转，保留 3 份压缩归档。检查间隔内仍可能增长；`copytruncate` 存在短暂的复制与截断丢日志窗口。

</details>

| 现象 | 优先检查 |
| :--- | :--- |
| 自签名证书验证失败 | 客户端是否保留 `insecure=1` 或跳过证书验证设置 |
| VLESS Reality 无法连接 | 公钥、short-id、SNI、flow 是否与服务端一致 |
| Hysteria2 连接超时 | UDP 端口放行情况及客户端错误日志 |
| 修改后仍使用旧节点信息 | 选择菜单 `7`，重新导入生成的配置 |
| 启动提示端口占用 | 是否存在其他服务或手动启动的第二个 sing-box 实例 |

反馈问题时请提供系统、客户端及内核版本、相关错误日志，并隐藏密码、PSK 和私钥。

## 项目文件

| 文件 | 说明 |
| :--- | :--- |
| [sing-box.sh](sing-box.sh) | 安装、更新、服务管理与客户端配置导出 |
| [config.json](config.json) | 五协议配置示例，使用前需替换占位符；安装时由脚本生成实际配置 |
| [disk-cleanup-full.sh](disk-cleanup-full.sh) | 清理包管理器缓存、按时间裁剪 journal，并调用可用的系统临时文件清理策略 |
| [tests](tests) | 管理逻辑回归测试与本地代理流量测试 |
| [GitHub Actions](.github/workflows/check.yml) | Debian、Ubuntu、Alpine 自动检查 |

磁盘清理脚本不自动卸载内核或软件包，不递归删除自定义临时目录，不按 `core.*` 文件名删除任意文件。

<details>
<summary><strong>开发验证</strong></summary>

```sh
SING_BOX_TEST_BINARY=/path/to/sing-box python3 -m unittest discover -s tests -v
```

CI 使用官方内核，在 Debian、Ubuntu、Alpine 容器中运行回归检查与本地代理流量测试。容器测试不替代真实 VPS 的开机自启和服务管理验证；ARM64 仍需在对应机器上进一步验证。

</details>

---

<div align="center">

基于 [SagerNet/sing-box](https://github.com/SagerNet/sing-box) 构建 · 本仓库为独立管理脚本项目

[查看源码](sing-box.sh) · [提交问题](https://github.com/passeway/sing-box/issues) · [查看检查结果](https://github.com/passeway/sing-box/actions)

</div>
