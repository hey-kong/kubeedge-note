## 安装

KubeEdge 版本需要 v1.8 以上，并且需要保证 EdgeMesh 处于运行状态。

在 cloudcore 上运行

```bash
# SEDNA_ROOT is the sedna directory
export SEDNA_ROOT=/root/sedna
curl https://raw.githubusercontent.com/kubeedge/sedna/main/scripts/installation/install.sh | SEDNA_ACTION=create bash -
```

输出

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

在 cloudcore 上运行

```bash
curl https://raw.githubusercontent.com/kubeedge/sedna/main/scripts/installation/install.sh | SEDNA_ACTION=delete bash -
```