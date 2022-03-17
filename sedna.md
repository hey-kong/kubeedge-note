## 安装

KubeEdge 版本需要 v1.8 以上，并且需要保证 EdgeMesh 处于运行状态。

在 cloudcore 上运行

```bash
# SEDNA_ROOT is the sedna directory
export SEDNA_ROOT=/root/sedna
curl https://raw.githubusercontent.com/kubeedge/sedna/main/scripts/installation/install.sh | SEDNA_ACTION=create bash -
```


## 卸载

在 cloudcore 上运行

```bash
curl https://raw.githubusercontent.com/kubeedge/sedna/main/scripts/installation/install.sh | SEDNA_ACTION=delete bash -
```