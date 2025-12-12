
# CodeServer 嵌入与统一鉴权集成方案

## 1. 方案概述

我们需要在 `chat.dolphindb.cloud` 前端通过 `<iframe>` 嵌入用户的 CodeServer 环境（运行在 Kubernetes 中）。

为了实现 **单点登录 (SSO)** 并确保安全性，我们将采用 **Nginx (OpenResty) `auth_request`** 机制。即：Nginx 在转发请求给 CodeServer 之前，先向后端 API 发起一次“鉴权子请求”，验证当前访问者是否有权限操作目标 CodeServer。

**流量路径：**
`用户浏览器` -> `Nginx /code/userXXX` -> `后端 API 验证 token` -> `(验证通过)` -> `K8s Pod (CodeServer)`

---

## 2. 前端开发说明 (Frontend)

**目标**：在 Chat 界面中嵌入 CodeServer，并将当前用户的 JWT Token 传递给服务端。

由于 `<iframe>` 加载时无法自定义 HTTP Header（无法在 Header 中带 Authorization），我们需要通过 **URL Query 参数** 传递 Token。

### 实现要求

1.  **拼接 URL**：在嵌入 iframe 时，将当前用户的 access token 作为 `token` 参数拼接到 URL 后面。
2.  **目标 URL 格式**：`https://chat.dolphindb.cloud/code/<target_user_id>/?token=<jwt_token>`

### 代码示例 (React/Vue)

```javascript
// 假设当前登录用户的 Token 存储在状态管理或 localStorage 中
const currentUserToken = localStorage.getItem('access_token'); 
// 目标 CodeServer 的归属用户 ID (通常就是当前登录用户的 ID)
const targetUserId = 'user006'; 

// 拼接 iframe 地址
// 注意：务必带上最后的斜杠 /，否则可能导致重定向丢失参数
const codeServerUrl = `https://chat.dolphindb.cloud/code/${targetUserId}/?token=${currentUserToken}`;

// 渲染 iframe
return (
  <div className="code-server-container">
    <iframe 
      src={codeServerUrl}
      title="DolphinDB Workbench"
      style={{ width: '100%', height: '800px', border: 'none' }}
      allow="clipboard-read; clipboard-write;" // 允许剪贴板
    />
  </div>
);
```

---

## 3. 后端开发说明 (Backend)

**目标**：提供一个轻量级鉴权接口，供 Nginx 内部调用，判断请求是否合法。

### 新增接口定义

*   **路径**: `/api/auth/verify_codeserver`
*   **方法**: `GET`
*   **参数**:
    *   `target_user` (String): URL 中试图访问的目标用户 ID（例如 `user006`）。
    *   `token` (String): 前端传来的 JWT Token。
*   **响应状态码**:
    *   `200 OK`: 鉴权通过，允许访问。
    *   `401 Unauthorized`: Token 无效或过期。
    *   `403 Forbidden`: Token 有效，但这名用户无权访问目标 CodeServer。

### 逻辑伪代码 (Python/Go/Java)

```python
def verify_codeserver(request):
    # 1. 获取 Token
    # 优先从 URL 参数获取 (适配 iframe 场景)
    token = request.args.get('token')
    
    # (可选兼容) 如果 URL 没传，尝试从 Header 获取
    if not token:
        auth_header = request.headers.get("Authorization")
        if auth_header and auth_header.startswith("Bearer "):
            token = auth_header.split(" ")[1]

    if not token:
        return HttpResponse(status=401) # 未登录

    # 2. 验证 Token 有效性并解析
    try:
        user_info = verify_and_decode_jwt(token)
    except TokenError:
        return HttpResponse(status=401) # Token 无效/过期

    # 3. 权限校验
    # 核心逻辑：只有“当前登录用户”等于“目标资源归属用户”时才放行
    # (或者当前用户是管理员)
    current_user_id = user_info['user_id']
    target_user_id = request.args.get('target_user')

    if current_user_id == target_user_id:
        return HttpResponse(status=200) # ✅ 放行
    else:
        # 记录日志：用户 A 试图访问用户 B 的资源
        return HttpResponse(status=403) # ❌ 拒绝
```

---

## 4. 运维/基础设施配置说明 (DevOps)

**目标**：配置 Nginx 拦截逻辑，并调整 CodeServer 启动参数为无密码模式。

### 4.1 Nginx (OpenResty) 配置

在 `chat.dolphindb.cloud` 的配置文件中添加以下块：

```nginx
    # === [鉴权子请求] ===
    # 仅供 Nginx 内部调用，不对外暴露
    location = /_auth_check {
        internal;
        
        # 将 Nginx 变量作为参数传给后端接口
        proxy_pass http://183.134.101.139:8008/api/auth/verify_codeserver?target_user=$auth_target_user&token=$arg_token;
        
        # 优化传输，不发送 Body
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
    }

    # === [CodeServer 业务入口] ===
    location /code/ {
        # 1. 从 URL 提取目标用户 ID (用于鉴权)
        set $auth_target_user "";
        if ($uri ~ "^/code/([^/]+)") {
            set $auth_target_user $1;
        }

        # 2. 发起鉴权
        # Nginx 会暂停当前请求，先去访问 /_auth_check
        # 如果后端返回 2xx -> 继续执行
        # 如果后端返回 4xx/5xx -> 直接拒绝请求
        auth_request /_auth_check;

        # 3. 鉴权通过后，转发给 K8s Ingress
        # 剥离 /code 前缀，变成 /user006 发送给后端
        rewrite ^/code/(.*) /$1 break;
        
        proxy_pass http://127.0.0.1:31986; # 指向 K8s Ingress Controller
        
        # 保持 Host 为 chat.dolphindb.cloud，K8s Ingress 需匹配此域名
        proxy_set_header Host $host;
        
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # 4. WebSocket 支持 (必须配置)
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # 5. 关闭缓冲，防止终端卡顿
        proxy_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
```

### 4.2 Helm Chart 修改 (all.yaml)

既然 Nginx 已经做了严格的鉴权，CodeServer 自身需要设置为**无密码模式**，以实现无缝进入。

**Deployment 修改点：**

1.  **启动参数 (`args`)**: 将 `--auth password` 改为 `--auth none`。
2.  **环境变量 (`VSCODE_PROXY_URI`)**: 必须指向统一后的外网地址，防止跳转错误。

```yaml
    spec:
      containers:
      - name: code-server
        # ...
        args:
          - |
            set -e
            chown -R coder:coder /home/coder /workspace || true
            exec gosu coder code-server \
              --bind-addr 0.0.0.0:8080 \
              --auth none \              # <--- 关键：改为 none
              --disable-telemetry \
              --disable-update-check \
              --proxy-domain codeserver.dolphindb.cloud \
              /workspace
        env:
          # 告诉 CodeServer 它的完整公共 URL
          - name: VSCODE_PROXY_URI
            value: "https://chat.dolphindb.cloud/code/{{ .Values.userId }}"
```

### 4.3 K8s Ingress 修改

确保 Ingress 规则匹配 `chat.dolphindb.cloud` 域名。

```yaml
spec:
  rules:
  - host: chat.dolphindb.cloud  # <--- 匹配主域名
    http:
      paths:
      - path: /{{ .Values.userId }}(/|$)(.*)
        # ...
```

---

## 5. 安全性总结

虽然 CodeServer 设置为 `auth: none`，但安全性并未降低，反而得到了提升和统一：

1.  **网络隔离**：外部流量必须经过 Nginx 入口，无法直接访问 Pod IP（配合 NetworkPolicy 效果更佳）。
2.  **严格鉴权**：Nginx 的 `auth_request` 保证了每一个 HTTP 请求（包括 WebSocket 握手）都必须经过后端 API 的校验。
3.  **资源隔离**：后端 API 强制校验了 `current_user_id == target_user_id`，防止用户 A 通过修改 URL 访问用户 B 的环境。