#!/bin/bash
set -e

IMAGES=(
  docker.io/kubernetesui/dashboard-api:1.14.0
  docker.io/kubernetesui/dashboard-auth:1.4.0
  docker.io/kubernetesui/dashboard-metrics-scraper:1.2.2
  docker.io/kubernetesui/dashboard-web:1.7.0
  docker.io/kong:3.9
)

for IMG in "${IMAGES[@]}"; do
  echo "=== Pulling $IMG with docker ==="
  docker pull $IMG

  TAR_NAME=$(echo $IMG | tr '/:' '_')".tar"

  echo "=== Saving $IMG to $TAR_NAME ==="
  docker save $IMG -o $TAR_NAME

  echo "=== Importing $IMG into containerd ==="
  sudo ctr -n k8s.io images import $TAR_NAME

  echo "=== Done $IMG ==="
done

echo "=== All images imported to containerd ==="

echo "Restarting Dashboard Pods..."
kubectl delete pod -n kubernetes-dashboard --all

