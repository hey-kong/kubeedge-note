## 下载和安装

通过 https://github.com/lf-edge/ekuiper/releases 获取安装包

```bash
wget https://github.com/lf-edge/ekuiper/releases/download/1.4.3/kuiper-1.4.3-linux-amd64.deb
sudo dpkg -i kuiper-1.4.3-linux-amd64.deb
```

启动 eKuiper 服务器

```bash
sudo systemctl start kuiper
```

## 运行第一个规则流

### 定义输入流

创建一个名为 demo 的流，该流使用 DATASOURCE 属性中指定的 MQTT test 主题。

```bash
kuiper create stream demo '(temperature float, humidity bigint) WITH (FORMAT="JSON", DATASOURCE="test")'
```

MQTT 源将通过 tcp://localhost:1883 连接到 MQTT 消息服务器，如果 MQTT 消息服务器位于别的位置，请在etc/mqtt_source.yaml中进行修改。

```yaml
default:
  qos: 1
  sharedsubscription: true
  servers: [tcp://127.0.0.1:1883]
```

使用 kuiper show streams 命令来查看是否创建了 demo 流。

```bash
kuiper show streams
```

### 通过查询工具测试流

通过 kuiper query 命令对其进行测试

```bash
kuiper query

kuiper > select count(*), avg(humidity) as avg_hum, max(humidity) as max_hum from demo where temperature > 30 group by TUMBLINGWINDOW(ss, 5);
```

### 编写规则

rule 由三部分组成：
* 规则名称：它必须是唯一的
* sql：针对规则运行的查询
* 动作：规则的输出动作

`myRule` 文件的内容。对于在1分钟内滚动时间窗口中的平均温度大于30的事件，它将打印到日志中。

```json
{
    "sql": "SELECT temperature from demo where temperature > 30",
    "actions": [{
        "log":  {}
    }]
}
```

运行 kuiper rule 命令来创建 ruleDemo 规则

```bash
kuiper create rule ruleDemo -f myRule
```

### 测试规则

使用 MQTT 客户端将消息发布到 test 主题即可。消息应为 json 格式

```bash
mosquitto_pub -h 192.168.181.97 -t "test" -m "{\"temperature\":31.2, \"humidity\": 77}"
mosquitto_pub -h 192.168.181.97 -t "test" -m "{\"temperature\":29, \"humidity\": 80}"
```

查看日志

```bash
tail -f /var/log/kuiper/stream.log
```

### 管理规则

开启规则

```bash
kuiper start rule ruleDemo
```

暂停规则

```bash
kuiper stop rule ruleDemo
```

删除规则

```bash
kuiper drop rule ruleDemo
```