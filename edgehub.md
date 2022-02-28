```本文基于 commit 9a7e140b42abb4bf6bcabada67e3568f73964278。```

## 概述

EdgeHub 是一个 Web Socket 客户端，负责与边缘计算的云端交互，包括同步云端资源更新、报告边缘主机和设备状态变化到云端等功能。

## 模块入口

edge/pkg/edgehub/edgehub.go：
```
//Start sets context and starts the controller
func (eh *EdgeHub) Start() {
	eh.certManager = certificate.NewCertManager(config.Config.EdgeHub, config.Config.NodeName)
	eh.certManager.Start()

	HasTLSTunnelCerts <- true
	close(HasTLSTunnelCerts)

	go eh.ifRotationDone()

	for {
		select {
		case <-beehiveContext.Done():
			klog.Warning("EdgeHub stop")
			return
		default:
		}
		err := eh.initial()
		if err != nil {
			klog.Exitf("failed to init controller: %v", err)
			return
		}

		waitTime := time.Duration(config.Config.Heartbeat) * time.Second * 2

		err = eh.chClient.Init()
		if err != nil {
			klog.Errorf("connection failed: %v, will reconnect after %s", err, waitTime.String())
			time.Sleep(waitTime)
			continue
		}
		// execute hook func after connect
		eh.pubConnectInfo(true)
		go eh.routeToEdge()
		go eh.routeToCloud()
		go eh.keepalive()

		// wait the stop signal
		// stop authinfo manager/websocket connection
		<-eh.reconnectChan
		eh.chClient.UnInit()

		// execute hook fun after disconnect
		eh.pubConnectInfo(false)

		// sleep one period of heartbeat, then try to connect cloud hub again
		klog.Warningf("connection is broken, will reconnect after %s", waitTime.String())
		time.Sleep(waitTime)

		// clean channel
	clean:
		for {
			select {
			case <-eh.reconnectChan:
			default:
				break clean
			}
		}
	}
}
```

edgehub 启动主要有以下几步：
1. 设置证书，从 cloudcore 申请证书（若正确配置本地证书，则直接使用本地证书），然后进入循环
2. 调用 eh.initial() 创建 eh.chClient，接着调用 eh.chClient.Init()，初始化过程建立了 websocket/quic 的连接
3. 调用 eh.pubConnectInfo(true)，向 edgecore 各模块广播已经连接成功的消息
4. go eh.routeToEdge()，执行 eh.chClient.Receive() 接收消息，将从云上部分收到的消息转发给指定边缘部分的模块 (MetaManager/DeviceTwin/EventBus/ServiceBus)
5. go eh.routeToCloud()，执行 beehiveContext.Receive(modules.EdgeHubModuleName) 接收来自边缘 (MetaManager/DeviceTwin/EventBus/ServiceBus) 的信息，并执行 eh.sendToCloud(message) 发到 cloudhub
6. go eh.keepalive()，向 cloudhub 发送心跳信息

另外，当云边消息传送过程中出现错误时，边缘部分会重新 init 相应的 websocket/quic client，与云端重新建立连接。
