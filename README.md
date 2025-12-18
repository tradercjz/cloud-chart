# DolphinDB Cloud Platform Manager

这是一个基于 Kubernetes 和 Helm 的 DolphinDB 多租户云平台管理系统。它允许通过 REST API 快速创建、管理和销毁隔离的 DolphinDB 用户工作空间。每个工作空间包含 DolphinDB 数据库实例和一个集成的 Code-Server 开发环境。

## 🌟 功能特性

*   **自动化部署**: 通过 REST API 自动创建和销毁用户环境
*   **资源隔离**: 基于 Kubernetes Namespace 和 Resource Quota 的资源隔离
*   **集成环境**: 每个用户拥有独立的 DolphinDB 实例和 Web IDE (Code-Server)
*   **持久化存储**: 支持配置持久卷 (PVC) 以保存用户数据
*   **网络访问**: 自动配置 Ingress 规则，提供基于用户 ID 的访问 URL

## 🏗 架构概览

*   **Platform Manager (`dolphindb-platform-manager.py`)**: 基于 Flask 的控制平面，接收 API 请求并调用 Helm 执行操作。
*   **Helm Chart (`dolphindb-user-chart`)**: 定义了用户环境的 Kubernetes 资源模板 (StatefulSet, Service, Ingress, NetworkPolicy 等)。

## 📋 前置要求

*   Kubernetes Cluster (1.19+)
*   Helm 3
*   Python 3.8+
*   已配置好的 StorageClass (默认为 `local-path`)
*   DolphinDB 和 Code-Server 的 Docker 镜像

## 🚀 快速开始

### 1. 安装依赖

```bash
pip install flask
# 确保 helm 命令在系统 PATH 中可用
```

### 2. 启动管理服务

```bash
python3 dolphindb-platform-manager.py
```
服务默认在 `0.0.0.0:8080` 启动。

## 🔌 API 文档

### 创建工作空间

**POST** `/api/v1/workspaces`

请求体示例:
```json
{
    "userId": "user001",
    "config": {
        "dolphindb": {
            "password": "secure_password",
            "storage": "20Gi"
        }
    }
}
```

### 列出所有工作空间

**GET** `/api/v1/workspaces`

### 获取工作空间状态

**GET** `/api/v1/workspaces/<user_id>`

### 删除工作空间

**DELETE** `/api/v1/workspaces/<user_id>`

## ⚙️ 配置说明

Helm Chart 的默认配置位于 `dolphindb-user-chart/values.yaml`。

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `userId` | 用户标识 | `user001` |
| `dolphindb.image` | DolphinDB 镜像地址 | `registry.cn-hangzhou.aliyuncs.com/dolphindbit/dolphindb:v3.00.3` |
| `dolphindb.storage` | 存储大小 | `10Gi` |
| `codeserver.image` | Code-Server 镜像地址 | `codeserver-ddb:latest` |
| `resources` | CPU/内存资源限制 | 见 values.yaml |

## 🛠 开发与维护

*   **Helm Chart 开发**: 修改 `dolphindb-user-chart/templates/` 下的 yaml 文件以调整 Kubernetes 资源定义。
*   **API 开发**: 修改 `dolphindb-platform-manager.py` 扩展管理功能。

## 📝 License

[License Name]
