#!/bin/bash
# DolphinDB 云平台使用示例

# 1. 创建用户工作空间
curl -X POST http://platform-api:8080/api/v1/workspaces \
  -H "Content-Type: application/json" \
  -d '{
    "userId": "user001",
    "config": {
      "dolphindb": {
        "storage": "20Gi",
        "password": "secure_password"
      }
    }
  }'

# 2. 列出所有工作空间
curl http://platform-api:8080/api/v1/workspaces

# 3. 查看特定用户工作空间状态
curl http://platform-api:8080/api/v1/workspaces/user001

# 4. 删除用户工作空间
curl -X DELETE http://platform-api:8080/api/v1/workspaces/user001

# ===================================
# 或者直接使用 Helm 命令
# ===================================

# 创建 user002 环境
helm install dolphindb-user002 ./dolphindb-user-chart \
  --set userId=user002 \
  --set dolphindb.storage=15Gi

# 创建 user003 环境
helm install dolphindb-user003 ./dolphindb-user-chart \
  --set userId=user003

# 列出所有环境
helm list | grep dolphindb

# 删除环境
helm uninstall dolphindb-user002

# 批量创建
for i in {001..010}; do
  helm install dolphindb-user$i ./dolphindb-user-chart \
    --set userId=user$i \
    --wait &
done
wait
echo "All workspaces created!"