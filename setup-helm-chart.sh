#!/bin/bash
# 自动创建 DolphinDB Helm Chart 的脚本

set -e

CHART_NAME="dolphindb-user-chart"

echo "🚀 Creating Helm Chart structure..."

# 创建目录
mkdir -p ${CHART_NAME}/templates
cd ${CHART_NAME}

# 创建 Chart.yaml
cat > Chart.yaml <<'EOF'
apiVersion: v2
name: dolphindb-user-chart
description: A Helm chart for DolphinDB user workspace
type: application
version: 1.0.0
appVersion: "3.00.3"
keywords:
  - dolphindb
  - codeserver
  - workspace
maintainers:
  - name: Platform Team
EOF

# 创建 values.yaml
cat > values.yaml <<'EOF'
userId: "user001"

dolphindb:
  image: registry.cn-hangzhou.aliyuncs.com/dolphindbit/dolphindb:v3.00.3
  port: 8848
  username: admin
  password: "123456"
  storage: 10Gi
  storageClass: local-path

codeserver:
  image: codeserver-ddb:latest
  port: 3000
  password: "userpassword"

# 资源限制
resources:
  dolphindb:
    requests:
      memory: "2Gi"
      cpu: "1000m"
    limits:
      memory: "4Gi"
      cpu: "2000m"
  codeserver:
    requests:
      memory: "512Mi"
      cpu: "500m"
    limits:
      memory: "1Gi"
      cpu: "1000m"
EOF

# 创建 templates/all.yaml
cat > templates/all.yaml <<'EOF'
---
apiVersion: v1
kind: Service
metadata:
  name: dolphindb-{{ .Values.userId }}
  labels:
    app: dolphindb-{{ .Values.userId }}
    userId: {{ .Values.userId }}
spec:
  type: ClusterIP
  selector:
    app: dolphindb-{{ .Values.userId }}
  ports:
    - name: api
      port: {{ .Values.dolphindb.port }}
      targetPort: {{ .Values.dolphindb.port }}
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: dolphindb-{{ .Values.userId }}
  labels:
    app: dolphindb-{{ .Values.userId }}
    userId: {{ .Values.userId }}
spec:
  serviceName: dolphindb-{{ .Values.userId }}
  replicas: 1
  selector:
    matchLabels:
      app: dolphindb-{{ .Values.userId }}
  template:
    metadata:
      labels:
        app: dolphindb-{{ .Values.userId }}
        userId: {{ .Values.userId }}
    spec:
      containers:
      - name: dolphindb
        image: {{ .Values.dolphindb.image }}
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: {{ .Values.dolphindb.port }}
        env:
        - name: DDB_USER
          value: {{ .Values.dolphindb.username | quote }}
        - name: DDB_PASS
          value: {{ .Values.dolphindb.password | quote }}
        volumeMounts:
        - name: dolphindb-data
          mountPath: /opt/dolphindb/data
        resources:
          {{- toYaml .Values.resources.dolphindb | nindent 10 }}
  volumeClaimTemplates:
  - metadata:
      name: dolphindb-data
    spec:
      storageClassName: {{ .Values.dolphindb.storageClass }}
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: {{ .Values.dolphindb.storage }}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: codeserver-{{ .Values.userId }}
  labels:
    app: codeserver-{{ .Values.userId }}
    userId: {{ .Values.userId }}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: codeserver-{{ .Values.userId }}
  template:
    metadata:
      labels:
        app: codeserver-{{ .Values.userId }}
        userId: {{ .Values.userId }}
    spec:
      securityContext:
        fsGroup: 1000
      initContainers:
        - name: init-settings
          image: busybox
          command: ["sh", "-c"]
          args:
            - |
              mkdir -p /config
              cat > /config/settings.json <<SETTINGSEOF
              {
                "dolphindb.connections": [
                  {
                    "name": "localDDB",
                    "url": "ws://dolphindb-{{ .Values.userId }}:{{ .Values.dolphindb.port }}",
                    "autologin": true,
                    "username": "{{ .Values.dolphindb.username }}",
                    "password": "{{ .Values.dolphindb.password }}"
                  }
                ],
                "extensions.autoUpdate": false,
                "extensions.autoCheckUpdates": false,
                "telemetry.telemetryLevel": "off",
                "workbench.enableExperiments": false
              }
              SETTINGSEOF
          volumeMounts:
            - name: config-volume
              mountPath: /config
        - name: fix-perms
          image: {{ .Values.codeserver.image }}
          command: ["sh", "-c"]
          args:
            - |
              uid=$(awk -F: '/^coder:/{print $3; exit}' /etc/passwd 2>/dev/null || echo 0)
              gid=$(awk -F: '/^coder:/{print $4; exit}' /etc/passwd 2>/dev/null || echo 0)
              if [ -f /config/settings.json ]; then
                chown ${uid}:${gid} /config/settings.json 2>/dev/null || true
                chmod 0644 /config/settings.json 2>/dev/null || true
              fi
          volumeMounts:
            - name: config-volume
              mountPath: /config
      containers:
      - name: code-server
        image: {{ .Values.codeserver.image }}
        imagePullPolicy: IfNotPresent
        env:
          - name: PASSWORD
            value: {{ .Values.codeserver.password | quote }}
        ports:
          - containerPort: {{ .Values.codeserver.port }}
        volumeMounts:
          - name: config-volume
            mountPath: /home/coder/.local/share/code-server/Machine/settings.json
            subPath: settings.json
        resources:
          {{- toYaml .Values.resources.codeserver | nindent 10 }}
      volumes:
      - name: config-volume
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: codeserver-{{ .Values.userId }}
  labels:
    app: codeserver-{{ .Values.userId }}
    userId: {{ .Values.userId }}
spec:
  type: ClusterIP
  selector:
    app: codeserver-{{ .Values.userId }}
  ports:
    - port: {{ .Values.codeserver.port }}
      targetPort: {{ .Values.codeserver.port }}
EOF

# 创建 templates/networkpolicy.yaml (网络隔离)
cat > templates/networkpolicy.yaml <<'EOF'
---
# DolphinDB 只允许同用户的 CodeServer 访问
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: dolphindb-{{ .Values.userId }}-isolation
spec:
  podSelector:
    matchLabels:
      app: dolphindb-{{ .Values.userId }}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: codeserver-{{ .Values.userId }}
    ports:
    - protocol: TCP
      port: {{ .Values.dolphindb.port }}
---
# CodeServer 出站流量控制
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: codeserver-{{ .Values.userId }}-egress
spec:
  podSelector:
    matchLabels:
      app: codeserver-{{ .Values.userId }}
  policyTypes:
  - Egress
  egress:
  # 允许访问自己的 DolphinDB
  - to:
    - podSelector:
        matchLabels:
          app: dolphindb-{{ .Values.userId }}
    ports:
    - protocol: TCP
      port: {{ .Values.dolphindb.port }}
  # 允许 DNS 查询
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53
EOF

# 创建 templates/ingress.yaml (可选)
cat > templates/ingress.yaml <<'EOF'
{{- if .Values.ingress.enabled }}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: codeserver-{{ .Values.userId }}
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  ingressClassName: {{ .Values.ingress.className }}
  rules:
  - host: {{ .Values.ingress.host }}
    http:
      paths:
      - path: /{{ .Values.userId }}(/|$)(.*)
        pathType: Prefix
        backend:
          service:
            name: codeserver-{{ .Values.userId }}
            port:
              number: {{ .Values.codeserver.port }}
{{- end }}
EOF

# 在 values.yaml 中添加 ingress 配置
cat >> values.yaml <<'EOF'

# Ingress 配置 (可选)
ingress:
  enabled: false
  className: nginx
  host: your-domain.com
EOF

cd ..

echo "✅ Helm Chart created successfully!"
echo ""
echo "📁 Chart structure:"
tree ${CHART_NAME} 2>/dev/null || find ${CHART_NAME} -type f

echo ""
echo "🎯 Quick start:"
echo "  # 验证 Chart"
echo "  helm lint ${CHART_NAME}"
echo ""
echo "  # 测试渲染"
echo "  helm template test-user ${CHART_NAME} --set userId=user001"
echo ""
echo "  # 安装"
echo "  helm install dolphindb-user002 ${CHART_NAME} --set userId=user002"
echo ""
echo "  # 查看"
echo "  kubectl get pods,svc -l userId=user002"
echo ""
echo "  # 删除"
echo "  helm uninstall dolphindb-user002"