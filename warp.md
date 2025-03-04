## Cloudflare WARP 安装与使用指南

添加Cloudflare GPG密钥
```
curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | sudo gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
```
添加Cloudflare软件源到系统
```
echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/cloudflare-client.list
```
更新 apt 软件源并安装 Cloudflare WARP 客户端
```
sudo apt-get update && sudo apt-get install -y cloudflare-warp
```
更新 apt 软件源并升级 Cloudflare WARP 客户端
```
sudo apt-get update && sudo apt-get upgrade -y cloudflare-warp
```
升级 warp+ 账号
```
warp-cli registration license 8t1KD74k-02Gu9zj5-j8390Qgl
```
测试 proxy 模式是否启动
```
curl ifconfig.me --proxy socks5://127.0.0.1:40000
```
测试 proxy 模式 ip 质量
```
bash <(curl -Ls IP.Check.Place) -x socks5://127.0.0.1:40000
```
查看 warp 账户类型 warp=plus
```
curl --proxy http://127.0.0.1:40000 https://chatgpt.com/cdn-cgi/trace
```
```
curl --proxy http://127.0.0.1:40000 https://www.cloudflare.com/cdn-cgi/trace
```

## WARP CLI常用命令
```
warp-cli --help                # 完整帮助指令
```
```
warp-cli mode --help           # 查看帮助指令
```
```
warp-cli registration new      # 注册新客户端
```
```
warp-cli registration show     # 查看注册信息
```
```
warp-cli mode proxy            # 设置为代理模式
```
```
warp-cli connect               # 连接到 WARP
```
```
warp-cli --version             # 查看安装版本
```
```
warp-cli disconnect            # 断开 WARP 连接
```
```
warp-cli status                # 当前连接状态
```
```
warp-cli registration delete   # 删除当前注册
```

## 卸载Cloudflare WARP客户端
```
sudo systemctl stop warp-svc                                        # 停止 WARP 服务
```
```
sudo systemctl disable warp-svc                                     # 禁用 WARP 自启
```
```
sudo apt-get purge -y cloudflare-warp                               # 卸载客户端及依赖
```
```
sudo rm -f /etc/apt/sources.list.d/cloudflare-client.list           # 删除 apt 源列表
```
```
sudo rm -f /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg  # 删除 GPG 密钥
```
```
sudo apt-get update                                                 # 更新 apt 缓存
```
```
sudo systemctl status warp-svc                                      # 查看服务是否已被禁用
```
## 项目地址：https://pkg.cloudflareclient.com/
