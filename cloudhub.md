```本文基于 commit 9a7e140b42abb4bf6bcabada67e3568f73964278。```

## 概述

CloudHub 是一个 Web Socket 服务端，负责监听云端的变化，缓存并发送消息到 EdgeHub。

## 模块入口

cloud/pkg/cloudhub/cloudhub.go：
```
func (a *cloudHub) Start() {
	if !cache.WaitForCacheSync(beehiveContext.Done(), a.informersSyncedFuncs...) {
		klog.Errorf("unable to sync caches for objectSyncController")
		os.Exit(1)
	}

	// start dispatch message from the cloud to edge node
	go a.messageq.DispatchMessage()

	// check whether the certificates exist in the local directory,
	// and then check whether certificates exist in the secret, generate if they don't exist
	if err := httpserver.PrepareAllCerts(); err != nil {
		klog.Exit(err)
	}
	// TODO: Will improve in the future
	DoneTLSTunnelCerts <- true
	close(DoneTLSTunnelCerts)

	// generate Token
	if err := httpserver.GenerateToken(); err != nil {
		klog.Exit(err)
	}

	// HttpServer mainly used to issue certificates for the edge
	go httpserver.StartHTTPServer()

	servers.StartCloudHub(a.messageq)

	if hubconfig.Config.UnixSocket.Enable {
		// The uds server is only used to communicate with csi driver from kubeedge on cloud.
		// It is not used to communicate between cloud and edge.
		go udsserver.StartServer(hubconfig.Config.UnixSocket.Address)
	}
}
```

cloudhub 启动主要有以下 3 步：
1. 调用 DispatchMessage，开始从云端向边缘节点派送消息
2. 启动 HttpServer，主要用于为边端发放证书
3. 调用 StartCloudHub

接下来对 DispatchMessage 和 StartCloudHub 进行具体分析。

## DispatchMessage

DispatchMessage 从云中获取消息，提取节点 ID，获取与节点相关的消息，将其放入消息队列中：
```
func (q *ChannelMessageQueue) DispatchMessage() {
	for {
		select {
		case <-beehiveContext.Done():
			klog.Warning("Cloudhub channel eventqueue dispatch message loop stopped")
			return
		default:
		}
		msg, err := beehiveContext.Receive(model.SrcCloudHub)
		klog.V(4).Infof("[cloudhub] dispatchMessage to edge: %+v", msg)
		if err != nil {
			klog.Info("receive not Message format message")
			continue
		}
		nodeID, err := GetNodeID(&msg)
		if nodeID == "" || err != nil {
			klog.Warning("node id is not found in the message")
			continue
		}
		if isListResource(&msg) {
			q.addListMessageToQueue(nodeID, &msg)
		} else {
			q.addMessageToQueue(nodeID, &msg)
		}
	}
}
```

## StartCloudHub

StartCloudHub 的代码如下：
```
func StartCloudHub(messageq *channelq.ChannelMessageQueue) {
	handler.InitHandler(messageq)
	// start websocket server
	if hubconfig.Config.WebSocket.Enable {
		go startWebsocketServer()
	}
	// start quic server
	if hubconfig.Config.Quic.Enable {
		go startQuicServer()
	}
}
```

如果设置了 WebSocket 启动，就启动 WebSocket 服务器协程；如果设置了 Quic 启动，就启动 Quic 服务器协程。

WebSocket 是性能最好的，默认使用 WebSocket。Quic 作为备选项，在网络频繁断开等很不稳定场景下有优势。KubeEdge 云边消息传递是通过 cloudhub 跟 edgehub 间的 Websocket 或 Quic 协议的长连接传输的。
