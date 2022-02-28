```本文基于 commit 9a7e140b42abb4bf6bcabada67e3568f73964278。```

## 概述

EventBus 是一个与 MQTT 服务器 (mosquitto) 交互的 MQTT 客户端，为其他组件提供订阅和发布功能；ServiceBus 是一个运行在边缘的 HTTP 客户端。

## EventBus

edge/pkg/eventbus/eventbus.go：
```
func (eb *eventbus) Start() {
	if eventconfig.Config.MqttMode >= v1alpha1.MqttModeBoth {
		hub := &mqttBus.Client{
			MQTTUrl:     eventconfig.Config.MqttServerExternal,
			SubClientID: eventconfig.Config.MqttSubClientID,
			PubClientID: eventconfig.Config.MqttPubClientID,
			Username:    eventconfig.Config.MqttUsername,
			Password:    eventconfig.Config.MqttPassword,
		}
		mqttBus.MQTTHub = hub
		hub.InitSubClient()
		hub.InitPubClient()
		klog.Infof("Init Sub And Pub Client for external mqtt broker %v successfully", eventconfig.Config.MqttServerExternal)
	}

	if eventconfig.Config.MqttMode <= v1alpha1.MqttModeBoth {
		// launch an internal mqtt server only
		mqttServer = mqttBus.NewMqttServer(
			int(eventconfig.Config.MqttSessionQueueSize),
			eventconfig.Config.MqttServerInternal,
			eventconfig.Config.MqttRetain,
			int(eventconfig.Config.MqttQOS))
		mqttServer.InitInternalTopics()
		err := mqttServer.Run()
		if err != nil {
			klog.Errorf("Launch internal mqtt broker failed, %s", err.Error())
			os.Exit(1)
		}
		klog.Infof("Launch internal mqtt broker %v successfully", eventconfig.Config.MqttServerInternal)
	}

	eb.pubCloudMsgToEdge()
}
```

MqttMode 分 MqttModeInternal、MqttModeBoth 和 MqttModeExternal 三种。当 eventconfig.Config.MqttMode >= v1alpha1.MqttModeBoth 将 MQTT 代理启动在 eventbus 之外，eventbus 作为独立启动的 MQTT 代理的客户端与其交互；当 eventconfig.Config.MqttMode <= v1alpha1.MqttModeBoth 时，在 eventbus 内启动一个 MQTT 代理，负责与终端设备交互。

### InitSubClient

InitSubClient 设置参数启动 subscribe 连接：
```
func (mq *Client) InitSubClient() {
	timeStr := strconv.FormatInt(time.Now().UnixNano()/1e6, 10)
	right := len(timeStr)
	if right > 10 {
		right = 10
	}
	// if SubClientID is NOT set, we need to generate it by ourselves.
	if mq.SubClientID == "" {
		mq.SubClientID = fmt.Sprintf("hub-client-sub-%s", timeStr[0:right])
	}
	subOpts := util.HubClientInit(mq.MQTTUrl, mq.SubClientID, mq.Username, mq.Password)
	subOpts.OnConnect = onSubConnect
	subOpts.AutoReconnect = false
	subOpts.OnConnectionLost = onSubConnectionLost
	mq.SubCli = MQTT.NewClient(subOpts)
	util.LoopConnect(mq.SubClientID, mq.SubCli)
	klog.Info("finish hub-client sub")
}
```

onSubConnect 和 onSubConnectionLost 定义了当连接和失联时的处理逻辑。eventbus 订阅以下 topic：
```
// SubTopics which edge-client should be sub
SubTopics = []string{
    "$hw/events/upload/#",
    "$hw/events/device/+/state/update",
    "$hw/events/device/+/twin/+",
    "$hw/events/node/+/membership/get",
    UploadTopic,
    "+/user/#",
}
```

当获得这些 topic 消息时，通过 mqtt 的 subscribe 方法回调 OnSubMessageReceived。该函数判断 topic，"hw/events/device" 和 "hw/events/node" 开头发送给 DeviceTwin 模块，其他信息发送给 EdgeHub 模块：
```
// OnSubMessageReceived msg received callback
func OnSubMessageReceived(client MQTT.Client, msg MQTT.Message) {
	klog.Infof("OnSubMessageReceived receive msg from topic: %s", msg.Topic())
	// for "$hw/events/device/+/twin/+", "$hw/events/node/+/membership/get", send to twin
	// for other, send to hub
	// for "SYS/dis/upload_records", no need to base64 topic
	var target string
	var message *beehiveModel.Message
	if strings.HasPrefix(msg.Topic(), "$hw/events/device") || strings.HasPrefix(msg.Topic(), "$hw/events/node") {
		target = modules.TwinGroup
		resource := base64.URLEncoding.EncodeToString([]byte(msg.Topic()))
		// routing key will be $hw.<project_id>.events.user.bus.response.cluster.<cluster_id>.node.<node_id>.<base64_topic>
		message = beehiveModel.NewMessage("").BuildRouter(modules.BusGroup, modules.UserGroup,
			resource, messagepkg.OperationResponse).FillBody(string(msg.Payload()))
	} else {
		target = modules.HubGroup
		message = beehiveModel.NewMessage("").BuildRouter(modules.BusGroup, modules.UserGroup,
			msg.Topic(), beehiveModel.UploadOperation).FillBody(string(msg.Payload()))
	}

	klog.Info(fmt.Sprintf("Received msg from mqttserver, deliver to %s with resource %s", target, message.GetResource()))
	beehiveContext.SendToGroup(target, *message)
}
```

### InitPubClient

```
// InitPubClient init pub client
func (mq *Client) InitPubClient() {
	timeStr := strconv.FormatInt(time.Now().UnixNano()/1e6, 10)
	right := len(timeStr)
	if right > 10 {
		right = 10
	}
	// if PubClientID is NOT set, we need to generate it by ourselves.
	if mq.PubClientID == "" {
		mq.PubClientID = fmt.Sprintf("hub-client-pub-%s", timeStr[0:right])
	}
	pubOpts := util.HubClientInit(mq.MQTTUrl, mq.PubClientID, mq.Username, mq.Password)
	pubOpts.OnConnectionLost = onPubConnectionLost
	pubOpts.AutoReconnect = false
	mq.PubCli = MQTT.NewClient(pubOpts)
	util.LoopConnect(mq.PubClientID, mq.PubCli)
	klog.Info("finish hub-client pub")
}
```

InitPubClient 创建了一个 MQTT client，然后调用 LoopConnect 每 5 秒钟连接一次 MQTT server，直到连接成功。如果失去连接，则通过 onPubConnectionLost 继续调用 InitPubClient。

### pubCloudMsgToEdge

在启动/连接完 MQTT server 后，调用了 pubCloudMsgToEdge 方法：
```
func (eb *eventbus) pubCloudMsgToEdge() {
	for {
		select {
		case <-beehiveContext.Done():
			klog.Warning("EventBus PubCloudMsg To Edge stop")
			return
		default:
		}
		accessInfo, err := beehiveContext.Receive(eb.Name())
		if err != nil {
			klog.Errorf("Fail to get a message from channel: %v", err)
			continue
		}
		operation := accessInfo.GetOperation()
		resource := accessInfo.GetResource()
		switch operation {
		case messagepkg.OperationSubscribe:
			eb.subscribe(resource)
			klog.Infof("Edge-hub-cli subscribe topic to %s", resource)
		case messagepkg.OperationUnsubscribe:
			eb.unsubscribe(resource)
			klog.Infof("Edge-hub-cli unsubscribe topic to %s", resource)
		case messagepkg.OperationMessage:
			body, ok := accessInfo.GetContent().(map[string]interface{})
			if !ok {
				klog.Errorf("Message is not map type")
				continue
			}
			message := body["message"].(map[string]interface{})
			topic := message["topic"].(string)
			payload, _ := json.Marshal(&message)
			eb.publish(topic, payload)
		case messagepkg.OperationPublish:
			topic := resource
			// cloud and edge will send different type of content, need to check
			payload, ok := accessInfo.GetContent().([]byte)
			if !ok {
				content, ok := accessInfo.GetContent().(string)
				if !ok {
					klog.Errorf("Message is not []byte or string")
					continue
				}
				payload = []byte(content)
			}
			eb.publish(topic, payload)
		case messagepkg.OperationGetResult:
			if resource != "auth_info" {
				klog.Info("Skip none auth_info get_result message")
				continue
			}
			topic := fmt.Sprintf("$hw/events/node/%s/authInfo/get/result", eventconfig.Config.NodeName)
			payload, _ := json.Marshal(accessInfo.GetContent())
			eb.publish(topic, payload)
		default:
			klog.Warningf("Action not found")
		}
	}
}
```

pubCloudMsgToEdge 执行以下操作：

1. 从 beehive 获取消息
2. 获取消息的 operation 和 resource
3. 当动作为 subscribe 时从 MQTT 订阅 resource(topic) 消息；当动作为 unsubscribe 时从 MQTT 取消订阅 resource(topic) 消息
4. 当动作为 message 时，将消息的 message 根据消息的 topic 发送给 MQTT broker，消息类型是一个 map
5. 当动作为 publish 时，将消息发送给 MQTT broker，消息为一个字符串，topic 和 resource 一致
6. 当动作为 getResult 时，resource 必须为 auth_info，然后发送消息到 "hw/events/node/`eventconfig.Config.NodeName`/authInfo/get/result" 这一个 topic

## ServiceBus

edge/pkg/servicebus/servicebus.go：
```
func (sb *servicebus) Start() {
	// no need to call TopicInit now, we have fixed topic
	htc.Timeout = time.Second * 10
	uc.Client = htc
	if !dao.IsTableEmpty() {
		if atomic.CompareAndSwapInt32(&inited, 0, 1) {
			go server(c)
		}
	}
	//Get message from channel
	for {
		select {
		case <-beehiveContext.Done():
			klog.Warning("servicebus stop")
			return
		default:
		}
		msg, err := beehiveContext.Receive(modules.ServiceBusModuleName)
		if err != nil {
			klog.Warningf("servicebus receive msg error %v", err)
			continue
		}

		// build new message with required field & send message to servicebus
		klog.V(4).Info("servicebus receive msg")
		go processMessage(&msg)
	}
}
```

ServiceBus 接受来自 beehive 的消息，然后启动一个 processMessage 协程基于消息中带的参数，将消息通过 REST-API 发送到本地 127.0.0.1 上的目标 APP。相当于一个客户端，而 APP 是一个 http Rest-API server，所有的操作和设备状态都需要客户端调用接口来下发和获取。ServiceBus 执行过程图如下：

<div align=center>
<img src="eventbus & servicebus/servicebus.png" style="zoom:100%;" />
</div>
