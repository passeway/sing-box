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

[Highlights](#highlights) · [Quick start](#quick-start) · [Connect clients](#connect-clients) · [Management menu](#management-menu) · [Core updates](#core-updates) · [Troubleshooting](#troubleshooting)

</div>

---

## Highlights

| | |
| :--- | :--- |
| **Official core only** | Downloads the latest stable release straight from SagerNet/sing-box. Pre-releases are rejected, and the asset must match your architecture. |
| **Five protocols, one install** | Random free ports (TCP, UDP and IPv6 checked), independent credentials, a self-signed certificate and a Reality key pair. |
| **Ready-to-import nodes** | Mihomo (Clash Meta), Surge and share links for v2rayN and similar clients, named by region such as `HK-vless-in`. |
| **Firewall hint** | The install result lists exactly which TCP and UDP ports to open. |
| **Self-healing service** | systemd or OpenRC restarts a crashed core after 3 s, and stops after 5 failures in 60 s instead of looping forever. |
| **Safe core updates** | Your configuration is checked against the new core first. A failed update rolls back the core, configuration, service definition and running state. |

The management menu is in Simplified Chinese.

## Quick start

Run as **root** on AMD64 or ARM64. Debian and Ubuntu use systemd; Alpine uses OpenRC. The server must be able to reach GitHub to download the official release.

**Debian / Ubuntu** (needs `bash`, `curl` and `ca-certificates`)

```bash
bash <(curl -fsSL https://sing-box-sigma.vercel.app)
```

**Alpine**

```sh
apk add --no-cache bash curl ca-certificates
bash -c 'bash <(curl -fsSL https://sing-box-sigma.vercel.app)'
```

1. Choose **1** to install. Dependencies, the core, the configuration and the service are set up in one go.
2. Open the ports from the result in your cloud security group and the server firewall:

   ```text
   🎉sing-box 安装成功，请在云安全组和系统防火墙中放行 TCP 端口 34359/40789/42000/47903，UDP 端口 38183/42000，项目地址: https://github.com/passeway/sing-box
   ```

3. Import the nodes printed below that line into your client.

Run the same command again to open the menu. The listening address follows the system: `::` when IPv6 is available, otherwise `0.0.0.0`. System IPv6 settings are never changed.

<details>
<summary>Alternative: run directly from GitHub</summary>

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/passeway/sing-box/main/sing-box.sh)
```

</details>

## Connect clients

Nodes are printed after installation and can be exported again at any time with menu **7**. Names use the server's country or region code; `Proxy` is used if it cannot be detected.

| Protocol | Default setup | Port | Mihomo | Surge | Share link |
| :--- | :--- | :---: | :---: | :---: | :---: |
| Hysteria2 | QUIC, single port | UDP | ✓ | ✓ | ✓ |
| VLESS Reality | TCP, Vision flow | TCP | ✓ | — | ✓ |
| AnyTLS | TLS, independent random password | TCP | ✓ | ✓ | ✓ |
| Shadowsocks 2022 | `2022-blake3-aes-128-gcm` | TCP + UDP | ✓ | ✓ | ✓ |
| Snell v6 | Native inbound, `mode=default` | TCP | — | ✓ | — |

The output has three sections. Copy each one separately; they contain nodes only, not full rule sets or policy groups.

| Section | How to use it |
| :--- | :--- |
| `# Clash / Mihomo` | Merge the `proxies` entries into your config. The JSON is also valid YAML. |
| `# Surge` | Add the lines to the `[Proxy]` section. |
| `# Share links` | Import the link for each protocol into v2rayN or another compatible client. |

> [!NOTE]
> Hysteria2 and AnyTLS use a self-signed certificate, so exported nodes set `skip-cert-verify` or `insecure=1`. If you switch to a trusted certificate, turn certificate verification back on in your clients.

VLESS Reality needs the public key, short ID, SNI and flow to match the server. Hysteria2 has no port hopping by default. Snell v6 runs on sing-box's native inbound, so the client must support v6.

## Management menu

The top of the menu shows install state, running state and core version. Before installation only **1**, **2** and **0** are offered; other numbers are rejected.

| Option | Action | Details |
| :---: | :--- | :--- |
| `1` | Install | Download the latest stable core, generate all five protocols, start the service and list the ports to open. |
| `2` | Uninstall | After you type `y`, remove the service, core, configuration and logs. Leftover files are cleaned even when nothing is installed. |
| `3` | Start / Stop | Toggle according to the current state. |
| `4` | Restart | Validate the configuration, restart, then confirm the core process stays up. |
| `5` | Status | Show the service manager's status. |
| `6` | Logs | Follow the logs live; press `Ctrl+C` to return to the menu. |
| `7` | Export nodes | Regenerate and print client nodes from the current configuration. |
| `8` | Update core | Install the latest stable core and keep the configuration byte for byte. |
| `0` | Exit | Close the menu. |

If the core keeps failing (for example, a port taken by another program), the service manager gives up after 5 attempts in 60 seconds. Fix the cause, then start it again with **3** or **4**.

### Files

| Path | Purpose |
| :--- | :--- |
| `/usr/local/bin/sing-box` | Core binary |
| `/etc/sing-box/config.json` | Server configuration |
| `/etc/sing-box/client.txt` | Last exported client nodes |
| `/etc/sing-box/client-meta.json` | Export address (`address`) and name prefix (`name`) |
| `/etc/sing-box/cert.pem`, `key.pem` | Certificate and key for Hysteria2 and AnyTLS |

After editing the server configuration, restart with **4** and export with **7**. If the public IP or name prefix changes, edit `client-meta.json` and export again; it is not refreshed automatically.

## Core updates

Menu **8** replaces the core and refreshes the service definition. Configuration, ports and credentials are kept; protocols are never added, removed or migrated.

- **Checked before replacing**: the update stops if the release cannot be resolved, the package is missing, or your configuration fails the new core's check.
- **Rolled back on failure**: if replacing files, writing the service or restarting fails, the previous core, configuration, service definition and running state are restored. If restoring also fails, the recovery files are kept and their path is printed.
- **Nodes exported after success**: if only the export fails, the new core keeps running and you can retry with **7**.

This short-term rollback does not replace backups and cannot survive a power loss or `SIGKILL`.

## Troubleshooting

Check, in order: service status, open ports, client parameters, then logs.

```bash
/usr/local/bin/sing-box check -c /etc/sing-box/config.json
```

<details>
<summary>Debian / Ubuntu: status and logs</summary>

```bash
systemctl status sing-box --no-pager
journalctl -u sing-box -n 50 --no-pager
```

</details>

<details>
<summary>Alpine: status and logs</summary>

```sh
rc-service sing-box status
tail -n 50 /var/log/sing-box.log
```

Logs are checked hourly and rotated above 1 MiB, keeping 3 compressed archives. The file can grow between checks, and `copytruncate` may drop a few lines during rotation.

</details>

When opening an [issue](https://github.com/passeway/sing-box/issues), include the OS and architecture, core and client versions, steps to reproduce and relevant logs. Hide passwords, PSKs, private keys and full node links.

## Testing

[CI](https://github.com/passeway/sing-box/actions/workflows/check.yml) runs on AMD64 and ARM64 in Debian 12/13, Ubuntu 24.04 and Alpine 3.22 containers, using the official core for each architecture:

- Script syntax, configuration generation, node export and update rollback
- Real local proxy traffic through all five protocols
- Real systemd and OpenRC: install, crash auto-restart, the restart limit, core update and uninstall

Boot-time autostart on a real VPS, Internet reachability and UDP relay still need checking in your own environment.

## License

An independent management script for the official [SagerNet/sing-box](https://github.com/SagerNet/sing-box) core. See [sing-box.sh](sing-box.sh) and [LICENSE](LICENSE).
