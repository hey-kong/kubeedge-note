## 安装

前提条件需要安装 JDK 8 或更高版本。下载 Alluxio 二进制发行版：

```bash
wget https://downloads.alluxio.io/downloads/files/2.8.1/alluxio-2.8.1-bin.tar.gz
tar -zxvf alluxio-2.8.1-bin.tar.gz 
```

进入目录：

```bash
cp conf/alluxio-site.properties.template conf/alluxio-site.properties
vim conf/alluxio-site.properties
```

添加：

```
alluxio.master.mount.table.root.ufs=obs://pdsl-alluxio/knowledge-distillation/

fs.obs.accessKey=<OBS_ACCESS_KEY>
fs.obs.secretKey=<OBS_SECRET_KEY>
fs.obs.endpoint=<OBS_ENDPOINT>
```

执行：

```bash
# 格式化 Alluxio 文件系统
./bin/alluxio format

# 如果尚未挂载 ramdisk 或要重新挂载
./bin/alluxio-start.sh local SudoMount
# 如果已经挂载了 ramdisk
./bin/alluxio-start.sh local
```

运行测试：

```bash
./bin/alluxio runTests
```

停止 Alluxio：

```bash
./bin/alluxio-stop.sh local
```

开启和关闭代理服务器，端口为39999：

```
./bin/alluxio-start.sh proxy
./bin/alluxio-stop.sh proxy
```

## 错误排查

格式化时可能会报错：

```
java.lang.RuntimeException: java.net.UnknownHostException: [hostname]: [hostname] : Name or Service not known
```

需要在 `/etc/hosts` 文件添加：

```
127.0.0.1   [hostname] 
```
