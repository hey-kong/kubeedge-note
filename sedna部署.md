## 安装

KubeEdge 版本需要 v1.8 以上，并且需要保证 EdgeMesh 处于运行状态。

在 cloudcore 上运行：

```bash
# SEDNA_ROOT is the sedna directory
export SEDNA_ROOT=/root/sedna
curl https://raw.githubusercontent.com/kubeedge/sedna/main/scripts/installation/install.sh | SEDNA_ACTION=create bash -
```

输出：

```
Installing Sedna v0.4.3...
namespace/sedna created
customresourcedefinition.apiextensions.k8s.io/datasets.sedna.io created
customresourcedefinition.apiextensions.k8s.io/federatedlearningjobs.sedna.io created
customresourcedefinition.apiextensions.k8s.io/incrementallearningjobs.sedna.io created
customresourcedefinition.apiextensions.k8s.io/jointinferenceservices.sedna.io created
customresourcedefinition.apiextensions.k8s.io/lifelonglearningjobs.sedna.io created
customresourcedefinition.apiextensions.k8s.io/models.sedna.io created
customresourcedefinition.apiextensions.k8s.io/objectsearchservices.sedna.io created
customresourcedefinition.apiextensions.k8s.io/objecttrackingservices.sedna.io created
service/kb created
deployment.apps/kb created
clusterrole.rbac.authorization.k8s.io/sedna created
clusterrolebinding.rbac.authorization.k8s.io/sedna created
serviceaccount/sedna created
configmap/gm-config created
service/gm created
deployment.apps/gm created
daemonset.apps/lc created
Waiting control components to be ready...
deployment.apps/gm condition met
pod/gm-5bb9c898d6-zc9xc condition met
pod/kb-6b7897c89-dsmns condition met
pod/lc-9l9jz condition met
pod/lc-t922x condition met
NAME                  READY   STATUS    RESTARTS   AGE
gm-5bb9c898d6-zc9xc   1/1     Running   0          4s
kb-6b7897c89-dsmns    1/1     Running   0          4s
lc-9l9jz              1/1     Running   0          4s
lc-t922x              1/1     Running   0          4s
Sedna is running:
See GM status: kubectl -n sedna get deploy
See LC status: kubectl -n sedna get ds lc
See Pod status: kubectl -n sedna get pod
```

## 卸载

在 cloudcore 上运行：

```bash
curl https://raw.githubusercontent.com/kubeedge/sedna/main/scripts/installation/install.sh | SEDNA_ACTION=delete bash -
```

## 注意

### pod 一直处于 pending 状态

安装 sedna 时可能会出现 gm and kb 一直处于 pending 状态，这是因为 gm 和 kb 不能容忍主节点上的 taint：

```
# 查看污点，找到 Taints 字段
kubectl describe nodes cloud.kubeedge

# 去除污点 NoSchedule
kubectl taint nodes cloud.kubeedge node-role.kubernetes.io/master:NoSchedule-
```

### no such host

部署完 sedna 之后，查看 lc pod 的 log 可能会发现如下报错：

```
client tries to connect global manager(address: gm.sedna:9000) failed, error: dial tcp: lookup gm.sedna on 169.254.96.16:53: no such host
```

这是因为 edgemesh 未在正常运行，可能某个节点的网络出问题了，需要进行检查。

## 调试

修改代码后调试需要重新构建镜像，这里使用阿里云容器镜像服务，公网为 `pdsl-registry.cn-shenzhen.cr.aliyuncs.com`，命名空间为 `sedna`。

在服务器上登录阿里云 Docker Registry，用于登录的用户名为阿里云账号全名，密码为开通服务时设置的密码：

```
docker login --username=aliyun5782043170 pdsl-registry.cn-shenzhen.cr.aliyuncs.com
```

在镜像中编译 gm、lc 或 kb，其 DockerFile 分别为 sedna/build/{gm,lc,kb}/Dockerfile。以 kb 为例，进入 sedna 目录后，执行 `docker build`：

```
docker build -f build/kb/Dockerfile -t pdsl-registry.cn-shenzhen.cr.aliyuncs.com/sedna/sedna-kb:[镜像版本号] .
```

使用 `docker push` 命令将该镜像推送至远程：

```
docker push pdsl-registry.cn-shenzhen.cr.aliyuncs.com/sedna/sedna-kb:[镜像版本号]
```

从 Registry 中拉取镜像：

```
docker pull pdsl-registry.cn-shenzhen.cr.aliyuncs.com/sedna/sedna-kb:[镜像版本号]
```
