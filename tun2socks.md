# 手动安装和配置 Tun2Socks

本指南详细介绍如何手动安装 **Tun2Socks** 并配置为 `systemd` 服务。

---

## **1. 以 root 身份运行**

所有操作需要 **root 权限**，请先切换到 root 用户，或在命令前加 `sudo`。

```sh
sudo -i
```

---

## **2. 获取最新版本的 Linux x86_64 二进制文件**

### **2.1 获取最新版本下载链接**

```sh
curl -s https://api.github.com/repos/heiher/hev-socks5-tunnel/releases/latest | grep "browser_download_url" | grep "linux-x86_64" | cut -d '"' -f 4
```

手动访问以下链接获取最新版本：

🔗 [GitHub Releases](https://github.com/heiher/hev-socks5-tunnel/releases)

---

## **3. 下载并安装二进制文件**

### **3.1 下载二进制文件**

```sh
curl -L -o "/usr/local/bin/tun2socks" "<实际下载链接>"
```

### **3.2 赋予执行权限**

```sh
chmod +x "/usr/local/bin/tun2socks"
```

---

## **4. 创建配置文件**

### **4.1 创建配置目录**

```sh
mkdir -p "/etc/tun2socks"
```

### **4.2 编写 `config.yaml`**

```sh
cat > "/etc/tun2socks/config.yaml" <<'EOF'
tunnel:
  name: tun0
  mtu: 8500
  multi-queue: true
  ipv4: 198.18.0.1

socks5:
  port: 20000
  address: '2a14:67c0:116::1'
  udp: 'udp'
  username: 'alice'
  password: 'alicefofo123..OVO'
EOF
```

---

## **5. 创建 `systemd` 服务**

### **5.1 生成 `tun2socks.service`**

```sh
cat > "/etc/systemd/system/tun2socks.service" <<EOF
[Unit]
Description=Tun2Socks Tunnel Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/tun2socks /etc/tun2socks/config.yaml
ExecStartPost=/sbin/ip route add default dev tun0
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
```

### **5.2 重新加载 `systemd` 配置**

```sh
systemctl daemon-reload
```

### **5.3 设置开机自启**

```sh
systemctl enable tun2socks.service
```

---

## **6. 启动并检查服务**

### **6.1 启动服务**

```sh
systemctl start tun2socks.service
```

### **6.2 查看服务状态**

```sh
systemctl status tun2socks.service
```

如果 `Active: failed`，请运行以下命令查看详细错误信息：

```sh
journalctl -xeu tun2socks.service
```

---

## **7. 手动调试（可选）**

如果 `systemd` 启动失败，可手动运行 Tun2Socks 进行调试：

```sh
/usr/local/bin/tun2socks /etc/tun2socks/config.yaml
```

如果遇到 **`tun0` 设备未创建**，可尝试：

```sh
modprobe tun
ip link add tun0 type tun
ip link set tun0 up
```

---

## **8. 卸载 Tun2Socks（可选）**

### **8.1 停止并禁用服务**

```sh
systemctl stop tun2socks.service
systemctl disable tun2socks.service
```

### **8.2 删除文件**

```sh
rm -f "/usr/local/bin/tun2socks"
rm -rf "/etc/tun2socks"
rm -f "/etc/systemd/system/tun2socks.service"
```

### **8.3 重新加载 `systemd`**

```sh
systemctl daemon-reload
```

---

## **9. 结论**

现在你已经成功手动安装、配置并启动了 **Tun2Socks**，如果遇到问题，可以使用以下命令进行排查：

- **检查运行状态**：
  ```sh
  systemctl status tun2socks.service
  ```
- **查看日志**：
  ```sh
  journalctl -xeu tun2socks.service
  ```
- **手动运行测试**：
  ```sh
  /usr/local/bin/tun2socks /etc/tun2socks/config.yaml
  ```

如果有更多问题，请提供 `systemctl status` 和 `journalctl` 日志，以便进一步分析。

