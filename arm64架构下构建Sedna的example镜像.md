## 安装 docker

Ubuntu 20.04 arm64 安装 Docker

```
# 更新 apt
sudo apt-get update

# 安装基本软件
sudo apt-get install curl wget apt-transport-https ca-certificates software-properties-common

# 添加 docker 密钥
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo apt-key fingerprint 0EBFCD88

# 添加源
sudo add-apt-repository "deb [arch=arm64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

# 更新 apt，安装 docker
sudo apt-get update
sudo apt-get install docker-ce
```

卸载 Docker

```
apt-get autoremove docker docker-ce docker-engine docker.io containerd runc

# 查看 docker 是否卸载干净
dpkg -l | grep docker

# 删除无用的相关的配置文件
dpkg -l |grep ^rc|awk '{print $2}' |sudo xargs dpkg -P

# 删除没有删除的相关插件
apt-get autoremove docker-ce-*

# 删除 docker 的相关配置&目录
rm -rf /etc/systemd/system/docker.service.d
rm -rf /var/lib/docker

docker --version
```


## 安装 buildx

```
wget https://github.com/docker/buildx/releases/download/v0.8.1/buildx-v0.8.1.linux-arm64
chmod a+x buildx-v0.8.1.linux-arm64
mkdir -p ~/.docker/cli-plugins
mv buildx-v0.8.1.linux-arm64 ~/.docker/cli-plugins/docker-buildx
```

`vim /etc/docker/daemon.json`，添加配置
```
{
    "registry-mirrors": ["https://docker.mirrors.ustc.edu.cn"],
    "experimental": true
}
```

重启，`sudo systemctl restart docker`


## 下载基础镜像

```
docker pull --platform=linux/arm64/v8 python:3.6-slim
docker pull kumatea/tensorflow:2.4
docker pull kumatea/tensorflow:1.15.5
```


## 编译镜像

下载此分支的[sedna](https://github.com/hey-kong/sedna/tree/arm64)，执行 `examples/build_image.sh`，即可编译 arm64 架构下的镜像
