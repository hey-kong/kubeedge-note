# Ubuntu 20.04安装Kubeedge集群操作步骤

## 版本要求

系统最好选择能支持Glibc3.2以上的，升级Glibc是一件非常麻烦且一不小心就会导致系统崩溃的事，所以不如直接选择一个高版本的系统。Kubernetes选择v1.20.0。

## 事先准备（云端和边缘端）

需要准备一台电脑作为master（云端），另一台作为node（边缘端）节点。云端和边缘端都需要安装docker，云端还需要安装Kubernetes，边缘端不需要。

安装的时候，虽然很多命令都要用root权限，但建议在自己的用户身份下操作，**不要为了省事用`sudo su`切换到root用户去操作**！因为root用户和你自己的用户本质上是两个用户，很多东西都不一样。举个例子，你自己用户的环境变量和root用户的环境变量是不一样的，你切换到root以后，很多需要环境变量的操作很可能就会出错。另外，不要在边缘端安装**kubelet**和**kube-proxy**。

首先修改Ubuntu的软件源，添加国内的镜像源，下载docker

```bash
# 云端和边缘端
# 备份原来的源
sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
sudo vim /etc/apt/sources.list
# 将以下内容写到该文件末尾
deb http://mirrors.aliyun.com/ubuntu/ focal main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ focal main restricted universe multiverse

deb http://mirrors.aliyun.com/ubuntu/ focal-security main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ focal-security main restricted universe multiverse

deb http://mirrors.aliyun.com/ubuntu/ focal-updates main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ focal-updates main restricted universe multiverse

# deb http://mirrors.aliyun.com/ubuntu/ focal-proposed main restricted universe multiverse
# deb-src http://mirrors.aliyun.com/ubuntu/ focal-proposed main restricted universe multiverse

deb http://mirrors.aliyun.com/ubuntu/ focal-backports main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ focal-backports main restricted universe multiverse

# 然后进行以下操作
sudo apt-get update
sudo apt-get -y upgrade
sudo apt-get -y install build-essential
sudo apt -y install docker.io

# 如果是 ARM64 架构
# 参考 https://blog.csdn.net/qq_34253926/article/details/121629068
```

注意docker的cgroup driver必须和kubelet的cgroup driver一致。

关闭swap分区功能和防火墙，具体操作是

```bash
sudo sed -i '/ swap / s/^/#/' /etc/fstab
sudo swapoff -a
sudo ufw disable
```

添加新的 DNS

```bash
sudo vim /etc/systemd/resolved.conf
# 添加
DNS=8.8.8.8 114.114.114.114 169.254.96.16

# 执行
systemctl restart systemd-resolved
systemctl enable systemd-resolved
mv /etc/resolv.conf /etc/resolv.conf.bak
ln -s /run/systemd/resolve/resolv.conf /etc/

# 查看
cat /etc/resolv.conf
```

安装golang，运行以下命令

```bash
wget https://dl.google.com/go/go1.17.4.linux-amd64.tar.gz
tar -zxvf go1.17.4.linux-amd64.tar.gz -C /usr/local
#配置用户环境
vim ~/.bashrc
#文件末尾加上
export GOROOT=/usr/local/go
export PATH=$PATH:$GOROOT/bin
export GOPROXY=https://proxy.golang.com.cn,direct
#刷新
source ~/.bashrc
#检查go环境
go version
```

然后安装gcc，make

```bash
sudo apt install -y make
sudo apt install -y gcc
```

设置hostname

```bash
# 云侧
$ hostnamectl set-hostname cloud.kubeedge
# 端侧（可选）
$ hostnamectl set-hostname edge.kubeedge
```

添加 ip，`vim /etc/hosts`

```bash
# 云侧
8.130.22.97 cloud.kubeedge
# 端侧（可选）
8.130.23.131 edge.kubeedge
```

## 具体步骤

### 主节点开启Kubernetes集群

安装kubeadm、kubelet、kubectl

```bash
# 云端
# 支持https传送
sudo apt install -y apt-transport-https
# 添加访问公钥
curl https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg | apt-key add - 
# 添加kubernetes的软件源
cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb https://mirrors.aliyun.com/kubernetes/apt/ kubernetes-xenial main
EOF
# 更新缓存索引
sudo apt update
# 安装指定版本
sudo apt install -y kubelet=1.20.0-00 kubeadm=1.20.0-00 kubectl=1.20.0-00 --allow-downgrades
# 开机自启kubelet
systemctl enable kubelet
```

然后用kubeadm初始化Kubernetes集群

```bash
# 云端
sudo kubeadm init --image-repository=registry.aliyuncs.com/google_containers --kubernetes-version=v1.20.0 --pod-network-cidr=10.244.0.0/16
```

如果看到以下语句，说明初始化成功

```bash
kubeadm join 192.168.179.30:6443 --token fkxju7.d39l2sct5bc4w5yo \
    --discovery-token-ca-cert-hash sha256:28b467ec8f97537069724028c5d51650983b8bbc2ac29a6e52b210bb2d1896ff 
```

其中的token，如果你需要后面其他节点以Kubernetes node的角色加入这个集群，那么你要记下来。这里我们其他节点是以Kubeedge的角色加入，所以记不记无所谓。

接着执行

```bash
# 云端
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

如果这一步初始化失败了，可能是你之前初始化过，再去初始化就会失败。这个时候需要先`sudo kubeadm reset`，再`rm -rf $HOME/.kube`，然后再初始化即可。如果还是不行，那么就是你之前初始化的到现在的期间你的电脑ip变了，这个时候只能把原来的配置文件都删掉再继续初始化，具体是执行以下操作

```bash
# 云端
sudo kubeadm reset
sudo systemctl stop kubelet
sudo systemctl stop docker
sudo rm -rf /var/lib/cni/
sudo rm -rf /var/lib/kubelet/*
sudo rm -rf /etc/cni/
sudo rm -rf /etc/kubernetes/*
sudo systemctl restart kubelet
sudo systemctl restart docker
```

这个时候可以执行`kubectl get pods -A`查看所有pod是否变成ready，正常情况下应该有几个pod还没有ready，这是因为还没有配置网络插件。执行以下操作安装flannel网络插件

```bash
# 云端
wget https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml

# 准备云侧网络配置
cp kube-flannel.yml kube-flannel-cloud.yml
# 修改云侧网络配置
diff --git a/kube-flannel-cloud.yml b/kube-flannel-cloud.yml
index c7edaef..f3846b9 100644
--- a/kube-flannel-cloud.yml
+++ b/kube-flannel-cloud.yml
@@ -134,7 +134,7 @@ data:
 apiVersion: apps/v1
 kind: DaemonSet
 metadata:
-  name: kube-flannel-ds
+  name: kube-flannel-cloud-ds
   namespace: kube-system
   labels:
     tier: node
@@ -158,6 +158,8 @@ spec:
                 operator: In
                 values:
                 - linux
+              - key: node-role.kubernetes.io/agent
+                operator: DoesNotExist
       hostNetwork: true
       priorityClassName: system-node-critical
       tolerations:

# 准备端侧网络配置
cp kube-flannel.yml kube-flannel-edge.yml
# 修改端侧网络配置
diff --git a/kube-flannel-edge.yml b/kube-flannel-edge.yml
index c7edaef..66a5b5b 100644
--- a/kube-flannel-edge.yml
+++ b/kube-flannel-edge.yml
@@ -134,7 +134,7 @@ data:
 apiVersion: apps/v1
 kind: DaemonSet
 metadata:
-  name: kube-flannel-ds
+  name: kube-flannel-edge-ds
   namespace: kube-system
   labels:
     tier: node
@@ -158,6 +158,8 @@ spec:
                 operator: In
                 values:
                 - linux
+              - key: node-role.kubernetes.io/agent
+                operator: Exists
       hostNetwork: true
       priorityClassName: system-node-critical
       tolerations:
@@ -186,6 +188,7 @@ spec:
         args:
         - --ip-masq
         - --kube-subnet-mgr
+        - --kube-api-url=http://127.0.0.1:10550
         resources:
           requests:
             cpu: "100m"
# 这里的--kube-api-url为端侧edgecore监听地址

# 执行
kubectl apply -f kube-flannel-cloud.yml
kubectl apply -f kube-flannel-edge.yml
```

再等待一段时间，再执行`kubectl get pods -A`，这时所有pod都变成ready了，那么就成功建立起Kubernetes集群了，后面就是其他节点加入这个集群了。可以执行`kubectl get nodes`查看节点情况，这个时候应该只有一个master节点，并且是ready状态。


### 主节点开启Kubeedge cloud服务

这里部署Kubeedge v1.9.2。下载keadm

```bash
#可自行前往官网下载
wget https://github.com/kubeedge/kubeedge/releases/download/v1.9.2/keadm-v1.9.2-linux-amd64.tar.gz
#解压压缩包
tar -zxvf keadm-v1.9.2-linux-amd64.tar.gz
#master部署kubeedge
cp keadm-v1.9.2-linux-amd64/keadm/keadm /usr/local/bin/
#在keadm目录下，执行init操作(ip为master节点公网ip)：
keadm init --advertise-address="39.108.15.57" --kubeedge-version=1.9.2
#【注】在这里会出现错误，原因为github无法访问，解决方案：通过 http://ping.chinaz.com/github.com 查看ip，修改/etc/hosts：
52.78.231.108    github.com
185.199.111.133  raw.githubusercontent.com
```

生成stream证书

```bash
export CLOUDCOREIPS="39.108.15.57"
#复制kubeedge生成证书的certgen.sh文件，放入/etc/kubeedge
mv certgen.sh /etc/kubeedge/
chmod +x /etc/kubeedge/certgen.sh
/etc/kubeedge/certgen.sh stream
```

在keadm-v1.9.2-linux-amd64/keadm目录下执行`keadm gettoken`获取token。

修改配置，`vim /etc/kubeedge/config/cloudcore.yaml`，重启cloudcore后才生效

```
modules:
  ..
  cloudStream:
    enable: true
    streamPort: 10003
  ..
  dynamicController:
    enable: true
..
```

```bash
# 运行查看ipTunnelPort
kubectl get cm tunnelport -nkubeedge -oyaml

apiVersion: v1
kind: ConfigMap
metadata:
  annotations:
    tunnelportrecord.kubeedge.io: '{"ipTunnelPort":{"172.22.57.109":10351},"port":{"10351":true}}'
  creationTimestamp: "2022-03-10T06:01:15Z"
...

# 根据ConfigMap设置iptables
# iptables -t nat -A OUTPUT -p tcp --dport $YOUR-TUNNEL-PORT -j DNAT --to $YOUR-CLOUDCORE-IP:10003
iptables -t nat -A OUTPUT -p tcp --dport 10351 -j DNAT --to 172.22.57.109:10003
```

cloudcore通过systemd管理

```bash
cp /etc/kubeedge/cloudcore.service /etc/systemd/system/cloudcore.service
# 杀掉当前cloudcore进程
pkill cloudcore
# 重启cloudcore
systemctl daemon-reload
systemctl restart cloudcore
# 查看cloudcore是否运行
systemctl status cloudcore
```

edgemesh安装（需要安装helm）

```bash
#安装helm
curl https://baltocdn.com/helm/signing.asc | sudo apt-key add -
sudo apt-get install apt-transport-https --yes
echo "deb https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm

#卸载老的edgemesh
helm uninstall edgemesh

#安装edgemesh
helm install edgemesh \
--set agent.image=kubeedge/edgemesh-agent:v1.12.0 \
--set server.image=kubeedge/edgemesh-server:v1.12.0 \
--set server.nodeName=cloud.kubeedge \
--set server.advertiseAddress="{39.108.15.57}" \
https://raw.githubusercontent.com/kubeedge/edgemesh/main/build/helm/edgemesh.tgz

#检验部署结果
helm ls
kubectl get all -n kubeedge -o wide
```

如果 edgemesh 未启动成功，需要查看 pod 日志检查端口是否被占用

使用kubeadm部署的k8s集群，那么kube-proxy会下发到端侧节点，但是edgecore无法与kube-proxy并存，所以要修改kube-proxy的daemonset节点亲和性，禁止在端侧部署kube-proxy
```bash
kubectl edit ds kube-proxy -n kube-system
# 添加以下配置
    ..
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: node-role.kubernetes.io/edge
                operator: DoesNotExist
      containers:
      ..
```

后续如果关闭 cloudcore 需要执行

```bash
pkill cloudcore
rm /usr/lib/systemd/system/cloudcore.service
```


### 边缘端开启edge服务

下载mosquitto（只有边缘端需要mosquitto），执行以下操作

```bash
# 边缘端
sudo add-apt-repository ppa:mosquitto-dev/mosquitto-ppa 
sudo apt update
sudo apt -y install mosquitto
mosquitto -d -p 1883

# 为了方便测试，还需要下载mosquitto-clients
apt install mosquitto-clients
# 并修改配置
vim /etc/mosquitto/conf.d/mosquitto.conf
# 添加
allow_anonymous true
listener 1883
# 重启
sudo service mosquitto restart
```

下载keadm

```bash
#可自行前往官网下载
wget https://github.com/kubeedge/kubeedge/releases/download/v1.9.2/keadm-v1.9.2-linux-amd64.tar.gz
#解压压缩包
tar -zxvf keadm-v1.9.2-linux-amd64.tar.gz
#在keadm目录下，执行join操作(注意修改ip与edgenode-name，并在token后添加在cloud中获取到的token)：
cp keadm-v1.9.2-linux-amd64/keadm/keadm /usr/local/bin/
keadm join --cloudcore-ipport=39.108.15.57:10000 --edgenode-name=edge.kubeedge --kubeedge-version=1.9.2 --token=XXX
#【注】在这里会出现错误，原因为github无法访问，解决方案：通过 http://ping.chinaz.com/github.com 查看ip，修改/etc/hosts：
52.78.231.108    github.com
185.199.111.133  raw.githubusercontent.com
```
#【注】 在边缘节点 join 无报错，但是仍未加入节点，docker ps 显示为空，可查看 /etc/kubeedge/config/edgecore.yaml 配置文件中，确认文件中服务器的端口在云服务器上已开放

修改配置，`vim /etc/kubeedge/config/edgecore.yaml`，重启edgecore后才生效

```
modules:
  ..
  edgeStream:
    enable: true
    handshakeTimeout: 30
  ..
  edged:
    clusterDNS: 169.254.96.16,8.8.8.8
    clusterDomain: cluster.local
  ..
  metaManager:
    metaServer:
      enable: true
..
```

edgecore通过systemd管理

```bash
# 杀掉当前edgecore进程
pkill edgecore
# 重启edgecore
systemctl daemon-reload
systemctl restart edgecore
# 查看edgecore状态
systemctl status edgecore
```

如果边缘节点加入后会出现kube-flannel-edge-ds一直处于pending状态中，需要在云端删掉对应的pod后重新生成pod才能成功部署到边缘端。

```bash
# 查看pod状态
kubectl get nodes -o wide && kubectl get pods -o wide -A
# 删除对应pod
kubectl delete pod kube-flannel-edge-ds-775x5 -n kube-system
kubectl delete pod edgemesh-agent-98kmp -n kubeedge
```

后续如果关闭 edgecore 需要执行

```bash
pkill edgecore
```


### 测试

deployment.yaml

```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  labels:
    app: nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx
        ports:
        - containerPort: 80
          hostPort: 80
```

部署deployment.yaml

```bash
kubectl apply -f deployment.yaml

# 查看是否部署到了端侧
kubectl get pod -A -owide | grep nginx
```

进入端侧节点，测试功能是否正常

```bash
curl nginx的IP:80
```

查看日志

```bash
kubectl logs nginx-deployment-77f96fbb65-j58lk -n default
```

删除deployment

```bash
kubectl get deployment -n default
kubectl delete deployment nginx-deployment -n default
```


### 删除kubeedge

删除kubeedge边缘节点

```
#k8s的master节点上执行 
#查看节点
kubectl get node 

#删除节点名为:edge.kubeedge
kubectl delete node edge.kubeedge
```

卸载kubeedge边缘节点

```
#删除相关文件
rm /usr/local/bin/edgecore
rm /etc/systemd/system/edgecore.service
rm /usr/lib/systemd/system/edgecore.service
rm -rf /etc/kubeedge/*

#停止服务
pkill edgecore
systemctl daemon-reload
ps aux|grep edgecore

#在边缘节点上执行
keadm reset 
```

卸载kubeedge云端节点

```
#在云端节点上执行
keadm reset 
```


### 注意

日志查看

```bash
# 云端日志
tail -f /var/log/kubeedge/cloudcore.log

# 边缘端日志
journalctl -u edgecore.service -b -f
```

## 用证书或者 token 访问集群 api 接口

使用 k8s 的过程中需要访问集群的 api 接口，但是通常 k8s 的 apiserver 都是用 https 认证，当我们想直接访问 api 接口的时候都是需要进行认证的

当我们需要在其他机器上通过代码或者用 curl 请求去访问集群的 api 接口时，我们需要通过客户端证书或者集群 token 来访问 api 接口

### 客户端证书访问集群 api 接口

进入到 k8s 的配置目录下

```
cd /etc/kubernetes
```

获取 cert 和 key 信息，拿到 client-cert.pem 和 client-key.pem

```
cat ./admin.conf | grep client-certificate-data | awk -F ' ' '{print $2}' | base64 -d > client-cert.pem
cat ./admin.conf | grep client-key-data | awk -F ' ' '{print $2}' | base64 -d > client-key.pem
```

客户端获取集群中所有 namespace

```
curl --cert client-cert.pem --key client-key.pem -k $APISERVER/api/v1/namespaces
```

### token 访问 api

```
kubectl create serviceaccount admin -n kube-system
kubectl create clusterrolebinding metaedge-cluster-admin --clusterrole=cluster-admin --serviceaccount=kube-system:admin
```

拿到 token

```
kubectl get secret -n kube-system

kubectl describe secret admin-token-b29dl -n kube-system
```

客户端获取集群中所有 namespace

```
curl curl -k -H "Authorization: Bearer $token" -k $APISERVER/api/v1/namespaces
```

## 参考
https://kubeedge.io/en/docs/setup/keadm/
