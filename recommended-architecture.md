# DolphinDB 云平台推荐架构

## 整体架构

```
┌─────────────────────────────────────────────────────────────┐
│                        用户浏览器                              │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│              Ingress (Nginx/APISIX/OpenResty)               │
│                /user001 → codeserver-user001                │
│                /user002 → codeserver-user002                │
└────────────────────┬────────────────────────────────────────┘
                     │
        ┌────────────┴────────────┐
        ▼                         ▼
┌──────────────────┐      ┌──────────────────┐
│  CodeServer      │      │  CodeServer      │
│  user001         │      │  user002         │
│  (只能访问自己的)  │      │  (只能访问自己的) │
└────────┬─────────┘      └────────┬─────────┘
         │                         │
         ▼                         ▼
┌──────────────────┐      ┌──────────────────┐
│  DolphinDB       │      │  DolphinDB       │
│  user001         │      │  user002         │
│  (网络隔离)       │      │  (网络隔离)       │
└──────────────────┘      └──────────────────┘
```

## 推荐方案对比

| 方案 | 优点 | 缺点 | 适用场景 |
|------|------|------|----------|
| **Helm Chart** | 简单易用，社区标准 | 需手动管理生命周期 | 中小规模，100用户以内 |
| **Operator + CRD** | 全自动化，声明式管理 | 开发复杂度高 | 大规模，需要复杂编排 |
| **Ingress** | K8s原生，自动同步 | 依赖Ingress Controller | 推荐用于路由管理 |
| **etcd + 脚本** | 灵活可控 | 需要额外维护 | 特殊需求场景 |
| **NetworkPolicy** | K8s原生，安全可靠 | 需要CNI支持 | 推荐用于网络隔离 |

## 推荐实施步骤

### Phase 1: 基础版（立即可用）
1. 创建 Helm Chart 模板
2. 在 Chart 中包含 Ingress
3. 使用 NetworkPolicy 做基本隔离
4. 提供简单的管理脚本

### Phase 2: 增强版（1-2周）
1. 开发 REST API 管理平台
2. 添加用户配额和资源限制
3. 实现自动备份和恢复
4. 添加监控和日志

### Phase 3: 生产版（1-2月）
1. 开发 Operator
2. 实现自动扩缩容
3. 多租户计费系统
4. Web 管理控制台

## 快速开始

```bash
# 1. 创建 Helm Chart
mkdir -p dolphindb-user-chart/{templates,charts}
# (复制上面提供的 values.yaml 和 templates/all.yaml)

# 2. 测试创建用户环境
helm install dolphindb-user001 ./dolphindb-user-chart \
  --set userId=user001 \
  --dry-run --debug

# 3. 实际部署
helm install dolphindb-user001 ./dolphindb-user-chart \
  --set userId=user001

# 4. 验证
kubectl get pods,svc,ingress -l userId=user001

# 5. 访问
# http://your-domain.com/user001
```

## 关键配置说明

### 1. 资源配额
```yaml
# 在 values.yaml 中设置
resources:
  dolphindb:
    limits:
      memory: "4Gi"
      cpu: "2"
```

### 2. 网络隔离
- 使用 NetworkPolicy 确保 pod 之间不能互访
- 只允许 CodeServer 访问配对的 DolphinDB
- 使用 label selector 精确匹配

### 3. 路由管理
- Ingress 自动创建/删除（随 Helm release）
- URL 格式: `/user001`, `/user002`, ...
- 路径重写: `/user001/abc` → `/abc`

### 4. 存储管理
- StatefulSet 自动管理 PVC
- 删除 release 时可选保留数据
- 支持快照和备份

## 安全建议

1. **认证**: 在 Ingress 层添加 OAuth2/OIDC
2. **授权**: 使用 RBAC 限制 API 访问
3. **加密**: 启用 TLS/HTTPS
4. **审计**: 记录所有操作日志
5. **隔离**: NetworkPolicy + 可选的 namespace 隔离

## 监控和告警

```yaml
# 在 Chart 中添加 ServiceMonitor (Prometheus)
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: dolphindb-{{ .Values.userId }}
spec:
  selector:
    matchLabels:
      app: dolphindb-{{ .Values.userId }}
```

## 常见问题

**Q: 如何限制每个用户的资源？**
A: 在 values.yaml 中设置 resources limits，或使用 ResourceQuota

**Q: 如何实现用户数据备份？**
A: 使用 Velero 或定期 snapshot PVC

**Q: 如何处理用户闲置资源？**
A: 使用 CronJob 检测并自动缩容或删除长期未使用的环境

**Q: 支持多少用户？**
A: 取决于集群资源，单节点约50-100用户，集群可扩展到上千