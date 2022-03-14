## 安装和启动

Ubuntu 系统使用 apt-get 工具从官方仓库安装

```bash
wget -qO - http://repos.taosdata.com/tdengine.key | sudo apt-key add -
echo "deb [arch=amd64] http://repos.taosdata.com/tdengine-stable stable main" | sudo tee /etc/apt/sources.list.d/tdengine-stable.list
sudo apt-get update
apt-cache policy tdengine
sudo apt-get install tdengine
```

启动

```bash
systemctl start taosd
```

执行 TDengine 客户端程序，只要在 Linux 终端执行 taos 即可。

```
taos
```
