## 终端预览

![preview](image.png)

## 一键脚本
```
bash <(curl -fsSL sing-box-sigma.vercel.app)
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

实时sing-box日志
```
sudo journalctl -u sing-box --output cat -f
```
解码openai.srs
```
sing-box rule-set decompile geosite-openai.srs
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
```
重载systemd
```
systemctl daemon-reload
```

## 项目地址：https://github.com/SagerNet/sing-box
