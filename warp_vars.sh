#!/bin/bash

# 获取 JSON 输出
output=$(bash -c "$(curl -L warp-reg.vercel.app)")

# 打印输出检查
echo "Raw output:"
echo "$output"

# 解析 JSON
v4=$(echo "$output" | jq -r '.endpoint.v4')
reserved=$(echo "$output" | jq -r '.reserved_dec | @csv')
private_key=$(echo "$output" | jq -r '.private_key')
v6=$(echo "$output" | jq -r '.v6')

# 输出解析后的结果
echo "v4: $v4"
echo "reserved: $reserved"
echo "private_key: $private_key"
echo "v6: $v6"
