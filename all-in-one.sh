#!/usr/bin/env bash
set -e # Exit the script if an error happens

# set hostname
hostname=$1
if [[ $# != 1 ]]; then
  printf "please input hostname \n example like: ./join.sh yourhost "
  exit 1
fi
hostnamectl set-hostname $hostname

if [ ! -d "join_node" ]; then 
  mkdir join_node
fi
cd join_node

# choose edge architecture
hw_arch=$(uname -m)

arch="arm64"
case $hw_arch in
"x86_64")
    arch="amd64"
    ;;
"aarch64")
    arch="arm64"
    ;;
esac

# install and run docker
case $arch in
"amd64")
     apt-get -y update
     apt-get -y install build-essential
     apt -y install docker.io
    ;;
"arm64")
    apt-get -y install wget
    wget -O /etc/apt/sources.list https://repo.huaweicloud.com/repository/conf/Ubuntu-Ports-bionic.list
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 7EA0A9C3F273FCD8
    apt-get -y update
    apt-get -y install build-essential
    apt-get -y install wget apt-transport-https ca-certificates software-properties-common ufw
    apt-get -y purge libcurl4
    apt-get -y install curl gnupg
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository \
        "deb [arch=arm64] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) \
        stable"
    apt-get -y install docker-ce
    # modify nvidia docker.daemon
    wget -nc https://metaedge.oss-cn-hangzhou.aliyuncs.com/arm64/modify-nvidia-docker.py
    python3 modify-nvidia-docker.py
    ;;
esac

# start docker
systemctl enable docker
systemctl start docker

# close firewall 
sed -i '/ swap / s/^/#/' /etc/fstab
swapoff -a
ufw disable

# add DNS
echo "[Resolve]" > /etc/systemd/resolved.conf
echo DNS=8.8.8.8 114.114.114.114 169.254.96.16 >> /etc/systemd/resolved.conf
systemctl restart systemd-resolved
systemctl enable systemd-resolved
mv /etc/resolv.conf /etc/resolv.conf.bak
ln -s /run/systemd/resolve/resolv.conf /etc/

# install golang and set go env
wget -nc https://metaedge.oss-cn-hangzhou.aliyuncs.com/$arch/go1.17.4.linux-$arch.tar.gz
tar -zxvf go1.17.4.linux-$arch.tar.gz -C /usr/local

cat >> ~/.bashrc << EOF
export GOROOT=/usr/local/go
export PATH=\$PATH:\$GOROOT/bin
export GOPROXY=https://proxy.golang.com.cn,direct
EOF
source ~/.bashrc

# install gcc
apt -y install make
apt -y install gcc

# download and install mosquitto
add-apt-repository ppa:mosquitto-dev/mosquitto-ppa
apt -y install mosquitto
mosquitto -d -p 1883

# download resoures to join
wget -nc https://metaedge.oss-cn-hangzhou.aliyuncs.com/$arch/edgecore.service
wget -nc https://metaedge.oss-cn-hangzhou.aliyuncs.com/$arch/keadm-v1.9.2-linux-$arch.tar.gz
wget -nc https://metaedge.oss-cn-hangzhou.aliyuncs.com/$arch/kubeedge-v1.9.2-linux-$arch.tar.gz
wget -nc https://metaedge.oss-cn-hangzhou.aliyuncs.com/modify-yaml.py

# copy files to /etc/kubeedge
if [ ! -d "/etc/kubeedge" ]; then
  mkdir /etc/kubeedge
fi
cp edgecore.service /etc/kubeedge
cp kubeedge-v1.9.2-linux-$arch.tar.gz /etc/kubeedge

# join to master
tar -zxvf keadm-v1.9.2-linux-$arch.tar.gz
cp keadm-v1.9.2-linux-$arch/keadm/keadm /usr/local/bin
echo y | keadm reset
# get token from master , run apiservice on cloud first
cloud_token=$(curl http://39.108.15.57:6442/gettoken)
printf "token = %s \n" $cloud_token
printf "\n edge join to master will take a few minutes, please wait..."
keadm join --cloudcore-ipport=39.108.15.57:10000 --edgenode-name=$hostname --kubeedge-version=1.9.2 --token=$cloud_token

# script to modify /etc/kubeedge/config/edgecore.yaml
python3 modify-yaml.py

# restart edgecore
systemctl daemon-reload
systemctl restart edgecore
