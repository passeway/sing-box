## 预览

![preview](预览.png)

## 一键脚本
```bash
bash <(curl -Ls https://raw.githubusercontent.com/passeway/sing-box/main/sing-box.sh)

## 终端预览

![preview](预览.png)

## 一键脚本
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/passeway/sing-box/main/sing-box.sh)
```
## 安装 sing-box
下载sing-box
```
bash <(curl -fsSL https://sing-box.app/deb-install.sh)
```
修改/etc/sing-box/config.json
```
nano /etc/sing-box/config.json
```
```
{
  "log": {
    "level": "info",
    "timestamp": true,
    "output": "/var/log/singbox.log"
  },
  "inbounds": [
    {
      "type": "hysteria2",
      "listen": "::",
      "listen_port": 443,
      "users": [
          {
              "password": "your_password" 
          }
      ],
      "masquerade": "https://bing.com",
      "tls": {
          "enabled": true,
          "alpn": [
              "h3"
          ],
          "certificate_path": "/etc/sing-box/cert.pem",
          "key_path": "/etc/sing-box/private.key"
      }
    },
    {
      "type": "vless",
      "listen": "::",
      "listen_port": 443,
      "users": [
          {
              "uuid": "sing-box generate uuid",
              "flow": "xtls-rprx-vision"
          }
      ],
      "tls": {
          "enabled": true,
          "server_name": "www.tesla.com", 
          "reality": {
              "enabled": true,
              "handshake": {
                  "server": "www.tesla.com", 
                  "server_port": 443
              },
              "private_key": "sing-box generate reality-keypair", 
              "short_id": [
                  "123abc"
                ]
              }
          }
      }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct-out"
    }
  ]
}
```
查看config.json
```
cat /etc/sing-box/config.json
```
检查config.json
```
sing-box check -c /etc/sing-box/config.json
```
启动config.json
```
sing-box run -c /etc/sing-box/config.json
```
启动系统服务
```
systemctl enable sing-box
```
启动sing-box
```
systemctl start sing-box
```
停止sing-box
```
systemctl stop sing-box
```
重启sing-box
```
systemctl restart sing-box
```
查看sing-box
```
systemctl status sing-box
```
查看sing-box日志
```
cat /var/log/singbox.log
```


## 卸载 sing-box
禁用sing-box
```
systemctl stop sing-box.service
systemctl disable sing-box.service
```
卸载sing-box
```
dpkg --purge sing-box
```
删除sing-box
```
rm -rf /etc/sing-box
rm -f /var/log/singbox.log
```
重载systemd
```
systemctl daemon-reload
```

## 项目地址：https://github.com/SagerNet/sing-box
