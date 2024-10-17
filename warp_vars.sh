#!/bin/bash

# 获取 JSON 输出并解析
output=$(bash -c "$(curl -L warp-reg.vercel.app)")

# 提取所需的参数
v4=$(echo "$output" | jq -r '.endpoint.v4')
reserved=$(echo "$output" | jq -r '.reserved_dec | @csv')
private_key=$(echo "$output" | jq -r '.private_key')
v6=$(echo "$output" | jq -r '.v6')

# 将参数设置为环境变量
export V4="$v4"
export RESERVED="$reserved"
export PRIVATE_KEY="$private_key"
export V6="$v6"

# 输出结果以确认
echo "v4: $V4"
echo "reserved: $RESERVED"
echo "private_key: $PRIVATE_KEY"
echo "v6: $V6"
