#!/bin/bash

# 运行 warp-reg 并提取输出
output=$(curl -sLo warp-reg https://github.com/badafans/warp-reg/releases/download/v1.0/main-linux-arm64 && chmod +x warp-reg && ./warp-reg && rm warp-reg)

# 使用 jq 提取需要的字段
device_id=$(echo "$output" | grep -oP '(?<=device_id: ).*')
token=$(echo "$output" | grep -oP '(?<=token: ).*')
account_id=$(echo "$output" | grep -oP '(?<=account_id: ).*')
license=$(echo "$output" | grep -oP '(?<=license: ).*')
private_key=$(echo "$output" | grep -oP '(?<=private_key: ).*')
public_key=$(echo "$output" | grep -oP '(?<=public_key: ).*')
v4=$(echo "$output" | grep -oP '(?<=v4: ).*')
v6=$(echo "$output" | grep -oP '(?<=v6: ).*')

# 输出提取的变量
echo "Device ID: $device_id"
echo "Token: $token"
echo "Account ID: $account_id"
echo "License: $license"
echo "Private Key: $private_key"
echo "Public Key: $public_key"
echo "IPv6: $v6"
