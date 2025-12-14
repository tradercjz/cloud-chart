一、最推荐：docker → tar → containerd（ctr）
1️⃣ 从 Docker 导出镜像
docker save -o myimage.tar myimage:latest


也可以导出多个镜像：

docker save -o images.tar img1:tag img2:tag

2️⃣ 导入到 containerd

⚠️ 一定要指定 k8s 使用的 namespace：k8s.io

sudo ctr -n k8s.io images import myimage.tar


验证：

sudo ctr -n k8s.io images ls


看到 myimage:latest 即成功。