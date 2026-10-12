<div align="center">

# sing-box

### Five protocols. One menu. The official core.

A one-command installer and manager for **[sing-box](https://github.com/SagerNet/sing-box)** on Debian, Ubuntu and Alpine.<br>
It deploys Hysteria2, VLESS Reality, AnyTLS, Shadowsocks 2022 and Snell v6 at once, then hands you ready-to-import client nodes.

[![Checks](https://img.shields.io/github/actions/workflow/status/passeway/sing-box/check.yml?branch=main&style=flat-square&label=Checks)](https://github.com/passeway/sing-box/actions/workflows/check.yml)
[![Core](https://img.shields.io/badge/Core-Latest%20stable-2563eb?style=flat-square)](https://github.com/SagerNet/sing-box/releases/latest)
![Linux](https://img.shields.io/badge/Linux-Debian%20%7C%20Ubuntu%20%7C%20Alpine-18181B?style=flat-square)
![Architecture](https://img.shields.io/badge/Arch-AMD64%20%7C%20ARM64-18181B?style=flat-square)

**English** · [简体中文](README_zh.md)

[Quick start](#quick-start) · [Protocols](#protocols) · [Connect clients](#connect-clients) · [Menu](#management-menu) · [FAQ](#faq) · [Troubleshooting](#troubleshooting)

</div>

---

## Highlights

- **Official core only.** The latest stable release comes straight from SagerNet/sing-box. Pre-releases are rejected, and the package must match your CPU architecture.
- **Five protocols in one install.** Random free ports (checked on TCP, UDP and IPv6), independent credentials, a self-signed certificate and a Reality key pair.
- **Nodes ready to import.** Mihomo (Clash Meta), Surge and share links for v2rayN and similar clients, named by region, such as `HK-vless-in`.
- **Tells you what to open.** The install result lists the exact TCP and UDP ports for your firewall.
- **Recovers from crashes.** systemd or OpenRC restarts a crashed core after 3 seconds, and gives up after 5 failures in 60 seconds instead of looping forever.
- **Safe core updates.** The new core checks your configuration before anything is replaced; a failed update rolls everything back.

> The management menu is in Simplified Chinese.

## Quick start

| Requirement | |
| :--- | :--- |
| Account | `root` |
| System | Debian or Ubuntu (systemd), Alpine (OpenRC) |
| CPU | AMD64 or ARM64 |
| Network | Access to GitHub to download the official release |

**Debian / Ubuntu** (needs `bash`, `curl` and `ca-certificates`)

```bash
bash <(curl -fsSL https://sing-box-sigma.vercel.app)
```

**Alpine**

```sh
apk add --no-cache bash curl ca-certificates
bash -c 'bash <(curl -fsSL https://sing-box-sigma.vercel.app)'
```

1. Choose **1**. Dependencies, the core, the configuration and the service are set up in one go.
2. Open the ports from the result in your cloud security group and the server firewall:

   ```text
   🎉sing-box 安装成功，请在云安全组和系统防火墙中放行 TCP 端口 34359/40789/42000/47903，UDP 端口 38183/42000，项目地址: https://github.com/passeway/sing-box
   ```

3. Import the nodes printed below that line into your client ([how](#connect-clients)).

Run the same command again to open the menu. The service listens on `::` when IPv6 is available and on `0.0.0.0` otherwise; system IPv6 settings are never changed.

<details>
<summary>Alternative: run directly from GitHub</summary>

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/passeway/sing-box/main/sing-box.sh)
```

</details>

## Protocols

All five are installed together, each on its own random port. Import the ones your client supports.

| Protocol | Transport | Open | Good for |
| :--- | :--- | :---: | :--- |
| **Hysteria2** | QUIC | UDP | Lossy or long-distance links; needs UDP to get through |
| **VLESS Reality** | TCP + Vision | TCP | No domain or certificate needed; the handshake borrows a real website's TLS |
| **AnyTLS** | TLS | TCP | A TLS proxy designed to blur TLS-in-TLS traffic patterns |
| **Shadowsocks 2022** | `2022-blake3-aes-128-gcm` | TCP + UDP | Lightweight, low overhead, wide client support |
| **Snell v6** | Native sing-box inbound | TCP | Surge users |

## Connect clients

Nodes are printed after installation and can be exported again at any time with menu **7**. The output has three sections; copy each one separately. They contain nodes only, not rules or policy groups.

| Section | Client | How to use it |
| :--- | :--- | :--- |
| `# Clash / Mihomo` | Mihomo (Clash Meta) | Merge the `proxies` entries into your config. The JSON is also valid YAML. Includes everything except Snell. |
| `# Surge` | Surge | Add the lines to `[Proxy]`. Includes everything except VLESS Reality. |
| `# Share links` | v2rayN and similar | Import the link for each protocol. Includes everything except Snell. |

<details>
<summary>What the export looks like (abbreviated)</summary>

```text
# Clash / Mihomo: JSON is also valid YAML
{
  "proxies": [
    { "name": "HK-hysteria-in", "type": "hysteria2", "server": "203.0.113.10", "port": 38183, ... },
    { "name": "HK-vless-in", "type": "vless", "server": "203.0.113.10", "port": 34359, ... },
    ...
  ]
}

# Surge
HK-hysteria-in = hysteria2, 203.0.113.10, 38183, password=..., skip-cert-verify=true, sni=www.bing.com
HK-snell-in = snell, 203.0.113.10, 40789, psk=..., version=6, mode=default, reuse=true
...

# Share links
hy2://...@203.0.113.10:38183?insecure=1&sni=www.bing.com#HK-hysteria-in
vless://...@203.0.113.10:34359?encryption=none&flow=xtls-rprx-vision&security=reality&...#HK-vless-in
...
```

</details>

Node names use the server's country or region code, or `Proxy` if it cannot be detected.

> [!NOTE]
> Hysteria2 and AnyTLS use a self-signed certificate, so their nodes set `skip-cert-verify` or `insecure=1`. VLESS Reality needs the public key, short ID, SNI and flow to match the server exactly; always import the exported node rather than typing it in.

## Management menu

The top of the menu shows install state, running state and core version. Before installation only **1**, **2** and **0** are offered.

| Option | Action | What it does |
| :---: | :--- | :--- |
| `1` | Install | Download the latest stable core, generate all five protocols, start the service and list the ports to open. |
| `2` | Uninstall | After you type `y`, remove the service, core, configuration and logs. Also cleans leftovers of a broken install. |
| `3` | Start / Stop | Toggle according to the current state. |
| `4` | Restart | Validate the configuration, restart, then confirm the core stays up. |
| `5` | Status | Show the service manager's status. |
| `6` | Logs | Follow the logs live; `Ctrl+C` returns to the menu. |
| `7` | Export nodes | Regenerate and print client nodes from the current configuration. |
| `8` | Update core | Install the latest stable core and keep the configuration byte for byte. |
| `0` | Exit | Close the menu. |

### Core updates

Menu **8** replaces the core and refreshes the service definition. Configuration, ports and credentials are kept, and protocols are never added or removed. A running service is restarted on the new core; a stopped one stays stopped.

- **Checked first.** The update stops if the release cannot be resolved, the package is missing, or your configuration fails the new core's check.
- **Rolled back on failure.** If replacing files, writing the service or restarting fails, the previous core, configuration, service definition and running state come back. If even that fails, the recovery files are kept and their path is printed.

The rollback covers the update itself; it does not replace backups and cannot survive a power loss.

### Files

| Path | Purpose |
| :--- | :--- |
| `/usr/local/bin/sing-box` | Core binary |
| `/etc/sing-box/config.json` | Server configuration |
| `/etc/sing-box/client.txt` | Last exported client nodes |
| `/etc/sing-box/client-meta.json` | Address (`address`) and name prefix (`name`) used in exports |
| `/etc/sing-box/cert.pem`, `key.pem` | Certificate and key for Hysteria2 and AnyTLS |

## FAQ

<details>
<summary>How do I change a port or password?</summary>

Edit `/etc/sing-box/config.json`, then choose **4** (the configuration is validated before the restart) and **7** to export the new nodes. Remember to open the new port in your firewall.

</details>

<details>
<summary>The server's public IP changed. How do I update the nodes?</summary>

Edit `address` in `/etc/sing-box/client-meta.json`, then choose **7**. The address is detected once at install time and not refreshed automatically. `name` sets the node name prefix the same way.

</details>

<details>
<summary>Can I use my own certificate?</summary>

Replace `/etc/sing-box/cert.pem` and `key.pem` (keep the paths), add your domain as `server_name` under the inbound's `tls`, then choose **4** and **7**. Exports always mark the certificate as unverified, so turn verification back on in your client.

</details>

<details>
<summary>Hysteria2 does not connect, but TCP protocols do.</summary>

Hysteria2 runs over UDP. Open its UDP port in both the cloud security group and the server firewall. Some networks throttle or block UDP; use a TCP protocol there.

</details>

<details>
<summary>How do I start over with new ports and credentials?</summary>

Choose **2** to uninstall, then **1** to install again.

</details>

## Troubleshooting

Check, in order: service status, open ports, client parameters, then logs.

```bash
/usr/local/bin/sing-box check -c /etc/sing-box/config.json
```

| System | Status | Logs |
| :--- | :--- | :--- |
| Debian / Ubuntu | `systemctl status sing-box --no-pager` | `journalctl -u sing-box -n 50 --no-pager` |
| Alpine | `rc-service sing-box status` | `tail -n 50 /var/log/sing-box.log` |

If the core keeps failing (for example, a port taken by another program), the service manager stops after 5 attempts in 60 seconds. Fix the cause, then start it again with **3** or **4**.

On Alpine, logs are checked hourly and rotated above 1 MiB, keeping 3 compressed archives.

When opening an [issue](https://github.com/passeway/sing-box/issues), include the OS and architecture, core and client versions, steps to reproduce and relevant logs. Hide passwords, PSKs, private keys and full node links.

## More guides

These standalone references are not used by the installer:

| Guide | Topic |
| :--- | :--- |
| [warp.md](warp.md) | Install and use Cloudflare WARP |
| [config.json](config.json) | Example server configuration with placeholder credentials |

## Testing

[CI](https://github.com/passeway/sing-box/actions/workflows/check.yml) runs on AMD64 and ARM64 in Debian 12/13, Ubuntu 24.04 and Alpine 3.22 containers, using the official core for each architecture:

- Script syntax, configuration generation, node export and update rollback
- Real local proxy traffic through all five protocols
- Real systemd and OpenRC: install, crash auto-restart, the restart limit, core update and uninstall

Boot-time autostart on a real VPS, Internet reachability and UDP relay still need checking in your own environment.

## License

An independent management script for the official [SagerNet/sing-box](https://github.com/SagerNet/sing-box) core. See [sing-box.sh](sing-box.sh) and [LICENSE](LICENSE).
