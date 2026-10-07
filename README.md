<div align="center">

<h1>sing-box</h1>

<p><strong>多协议代理，统一部署与管理。</strong></p>

<p>从服务安装到客户端连接，一个脚本完成。</p>

<p>
  <a href="https://github.com/passeway/sing-box/actions/workflows/check.yml"><img src="https://img.shields.io/github/actions/workflow/status/passeway/sing-box/check.yml?branch=main&amp;style=flat-square&amp;label=Checks" alt="Checks"></a>
  <a href="https://github.com/SagerNet/sing-box/releases/latest"><img src="https://img.shields.io/badge/Core-Latest%20stable-2563eb?style=flat-square" alt="Latest stable sing-box core"></a>
  <img src="https://img.shields.io/badge/Linux-Debian%20%7C%20Ubuntu%20%7C%20Alpine-475569?style=flat-square" alt="Debian, Ubuntu, Alpine">
  <img src="https://img.shields.io/badge/Arch-AMD64%20%7C%20ARM64-475569?style=flat-square" alt="AMD64, ARM64">
</p>

<p>
  <a href="#快速开始">快速开始</a> &nbsp;·&nbsp;
  <a href="#协议与客户端">协议与客户端</a> &nbsp;·&nbsp;
  <a href="#服务管理">服务管理</a> &nbsp;·&nbsp;
  <a href="https://github.com/passeway/sing-box/issues">反馈问题</a>
</p>

<br>

</div>

为 Debian、Ubuntu 和 Alpine 提供轻量级 sing-box 管理工具。使用官方内核，自动适配 systemd 与 OpenRC，通过交互菜单完成部署和维护。

- **自动部署** — 安装依赖、分配随机端口、生成连接参数，并配置开机自启。
- **直接连接** — 导出 Mihomo 节点、Surge 代理行与分享链接，以 `HK`、`US` 等国家或地区代码命名。
- **持续维护** — 管理服务、查看日志、更新内核，并根据当前服务端配置重新导出节点。

## 快速开始

使用 **root** 账户，在 **AMD64 / ARM64** 服务器上运行。安装与更新时自动获取官方 **最新稳定版**；获取失败会终止操作，不回退到固定版本。

**Debian / Ubuntu**

终端需已安装 `bash`、`curl`。

```bash
bash <(curl -fsSL https://sing-box-sigma.vercel.app)
```

**Alpine**

```sh
apk add --no-cache bash curl ca-certificates
bash -c 'bash <(curl -fsSL https://sing-box-sigma.vercel.app)'
```

选择菜单 **1** 安装，完成后放行实际生成的端口，再导入客户端配置。重新运行上面的命令即可进入管理菜单。

> **端口放行**
>
> 云安全组与服务器防火墙均需配置。Hysteria2 使用 UDP；VLESS Reality、AnyTLS、Snell 使用 TCP；Shadowsocks 使用 TCP，启用 UDP 转发时还需放行同端口 UDP。

<details>
<summary>备用入口 · 直接从 GitHub 下载</summary>

在已安装 `bash`、`curl` 和 CA 证书的终端执行：

```sh
curl -fsSL https://raw.githubusercontent.com/passeway/sing-box/main/sing-box.sh -o /tmp/sing-box-manager.sh &&
bash /tmp/sing-box-manager.sh
```

</details>

## 协议与客户端

一次安装配置五种协议。下表表示**脚本提供的导出格式**，客户端需使用支持对应协议的版本。

| 协议 | 默认方案 | Mihomo | Surge | 分享链接 |
| :--- | :--- | :---: | :---: | :---: |
| **Hysteria2** | QUIC · 单 UDP 端口 | ✓ | ✓ | ✓ |
| **VLESS Reality** | TCP · Vision | ✓ | — | ✓ |
| **AnyTLS** | TCP · TLS | ✓ | ✓ | ✓ |
| **Shadowsocks 2022** | `2022-blake3-aes-128-gcm` | ✓ | ✓ | ✓ |
| **Snell v6** | 原生入站 · `mode=default` | — | ✓ | — |

### 导入节点

**Mihomo** — 将导出的 `proxies` 节点合并到自己的配置中。输出使用 JSON 表示，也属于合法 YAML。

**Surge** — 将对应代理行加入配置文件的 `[Proxy]` 部分。

**v2rayN 等客户端** — 复制相应的分享链接，导入支持该协议的客户端及内核。

每种格式请分开复制。导出内容包含节点信息，需要与客户端已有的规则和策略组配置配合使用。

<details>
<summary>默认配置与连接说明</summary>

- **Hysteria2 / AnyTLS** 使用自签名证书。导出配置包含 `skip-cert-verify` 或 `insecure=1`，客户端会跳过证书验证；如改用受信任证书，请同步调整客户端设置。
- **VLESS Reality** 的公钥、short-id、SNI 和 flow 必须与服务端一致。
- **AnyTLS** 当前复用 Reality 公钥作为密码。
- **Hysteria2** 当前采用单端口配置，不自动设置端口跳跃。
- **Snell v6** 使用 sing-box 原生入站，需要 1.14 或更新版本的内核，以及支持 Snell v6 的客户端。
- **节点名称** 使用国家或地区代码加上入站标签，例如 `HK-vless-in`；地区识别失败时使用 `Proxy` 前缀。

</details>

## 服务管理

菜单顶部显示安装状态、运行状态和运行版本。常用操作：**3** 启停、**4** 重启、**6** 日志、**7** 导出节点、**8** 更新内核。

修改服务端配置后，选择 **4** 重启，再选择 **7** 重新导出。修改公网地址或节点前缀后，选择 **7** 更新客户端内容。

<details>
<summary>完整菜单</summary>

未安装时显示安装、卸载与退出；安装后显示完整菜单。

| 选项 | 操作 |
| :---: | :--- |
| `1` | 安装 sing-box |
| `2` | 卸载服务并删除配置，需输入 `y` 确认 |
| `3` | 按当前状态启动或停止服务 |
| `4` | 校验配置并重启，检查运行状态 |
| `5` | 查看服务状态 |
| `6` | 查看实时日志，按 `Ctrl+C` 返回 |
| `7` | 根据当前服务端配置重新生成并查看节点 |
| `8` | 更新内核并迁移配置 |
| `0` | 退出 |

</details>

<details>
<summary>配置文件与安装位置</summary>

| 路径 | 用途 |
| :--- | :--- |
| `/usr/local/bin/sing-box` | 服务端程序 |
| `/etc/sing-box/config.json` | 服务端配置 |
| `/etc/sing-box/client.txt` | 客户端节点与分享链接 |
| `/etc/sing-box/client-meta.json` | 公网地址与节点名称前缀 |

</details>

<details>
<summary>更新与迁移</summary>

菜单 **8** 获取官方最新稳定版，并检查当前架构的安装包是否存在；版本信息获取失败时终止操作。旧配置迁移会移除 ShadowTLS，必要时将旧 Shadowsocks 入站从回环监听改为对外监听，并在缺少 Snell 时补充入站。

新配置通过校验后才会写入并替换内核。脚本不自动备份或回滚；有自定义配置时，请先保存备份。若自定义路由仍引用被移除的 ShadowTLS，迁移会停止并提示调整。

</details>

## 排障与反馈

连接异常时，先确认服务状态、端口放行与客户端参数，再查看日志。

<details>
<summary>检查配置与服务日志</summary>

**配置校验**

```bash
/usr/local/bin/sing-box check -c /etc/sing-box/config.json
```

**Debian / Ubuntu**

```bash
systemctl status sing-box --no-pager
journalctl -u sing-box -n 50 --no-pager
```

**Alpine**

```sh
rc-service sing-box status
tail -n 50 /var/log/sing-box.log
```

Alpine 日志每小时检查一次，超过 1 MiB 时轮转，保留 3 份压缩归档。检查间隔内日志仍可能增长；`copytruncate` 在复制与截断之间存在短暂的丢日志窗口。

</details>

提交 [Issue](https://github.com/passeway/sing-box/issues) 时，请提供系统与架构、内核与客户端版本、复现步骤及相关日志，并隐藏密码、PSK 和私钥。

[自动检查](https://github.com/passeway/sing-box/actions/workflows/check.yml) 使用 Debian、Ubuntu 与 Alpine 容器，官方内核测试采用 AMD64 构建。真实 VPS 的开机自启、ARM64 实机运行及外网连通性仍需在实际环境验证。

---

<p align="center">
  基于 <a href="https://github.com/SagerNet/sing-box">SagerNet/sing-box</a> 官方内核 · 独立部署与管理脚本<br>
  <a href="sing-box.sh">查看源码</a> &nbsp;·&nbsp; <a href="https://github.com/passeway/sing-box/issues">问题反馈</a>
</p>
