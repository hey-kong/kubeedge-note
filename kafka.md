### 服务端与客户端

下载 Kafka：
```
wget https://dlcdn.apache.org/kafka/3.2.0/kafka_2.12-3.2.0.tgz
tar -zxvf kafka_2.12-3.2.0.tgz
```

安装 Java：
```
sudo apt install openjdk-11-jdk
```

### 服务端

修改 server.properties 配置：
```bash
# config/server.properties
listeners=PLAINTEXT://kafka:9092
```

配置 hosts：
```bash
# /etc/hosts
内网ip kafka
```

启动 zookeeper：
```bash
bin/zookeeper-server-start.sh config/zookeeper.properties
```

启动 Kafka：
```bash
bin/kafka-server-start.sh config/server.properties
```

服务端收消息，命令行演示如下：
```
bin/kafka-console-consumer.sh --bootstrap-server kafka:9092 --topic test --from-beginning
```

### 客户端

配置 hosts：
```bash
# /etc/hosts
服务端公网ip kafka
```

客户端发消息，命令行演示如下：
```
bin/kafka-console-producer.sh --broker-list kafka:9092 --topic test
```
