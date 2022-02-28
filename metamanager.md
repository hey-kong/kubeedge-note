```本文基于 commit 9a7e140b42abb4bf6bcabada67e3568f73964278。```

## 概述

MetaManager 是消息处理器，位于 Edged 和 Edgehub 之间，它负责向轻量级数据库 (SQLite) 持久化/检索元数据。

## MetaManager 注册

和其他模块注册相比，metamanager 注册最大的不同就是它还调用了 initDBTable 在 SQLite 数据库中初始化了两张表 Meta 与 MetaV2：
```
// Meta metadata object
type Meta struct {
	Key   string `orm:"column(key); size(256); pk"`
	Type  string `orm:"column(type); size(32)"`
	Value string `orm:"column(value); null; type(text)"`
}

// MetaV2 record k8s api object
type MetaV2 struct {
	// Key is the primary key of a line record, format like k8s obj key in etcd:
	// /Group/Version/Resources/Namespace/Name
	//0/1   /2 /3   /4           /5
	// /core/v1/pods/{namespaces}/{name}									normal obj
	// /core/v1/pods/{namespaces} 											List obj
	// /extensions/v1beta1/ingresses/{namespaces}/{name}				 	normal obj
	// /storage.k8s.io/v1beta1/csidrivers/null/{name} 					 	cluster scope obj
	Key string `orm:"column(key); size(256); pk"`
	// GroupVersionResource are set buy gvr.String() like "/v1, Resource=endpoints"
	GroupVersionResource string `orm:"column(groupversionresource); size(256);"`
	// Namespace is the namespace of an api object, and set as metadata.namespace
	Namespace string `orm:"column(namespace); size(256)"`
	// Name is the name of api object, and set as metadata.name
	Name string `orm:"column(name); size(256)"`
	// ResourceVersion is the resource version of the obj, and set as metadata.resourceVersion
	ResourceVersion uint64 `orm:"column(resourceversion); size(256)"`
	// Value is the api object in json format
	// TODO: change to []byte
	Value string `orm:"column(value); null; type(text)"`
}
```

## 模块入口

edge/pkg/metamanager/metamanager.go：
```
func (m *metaManager) Start() {
	if metaserverconfig.Config.Enable {
		imitator.StorageInit()
		go metaserver.NewMetaServer().Start(beehiveContext.Done())
	}
	go func() {
		period := getSyncInterval()
		timer := time.NewTimer(period)
		for {
			select {
			case <-beehiveContext.Done():
				klog.Warning("MetaManager stop")
				return
			case <-timer.C:
				timer.Reset(period)
				msg := model.NewMessage("").BuildRouter(MetaManagerModuleName, GroupResource, model.ResourceTypePodStatus, OperationMetaSync)
				beehiveContext.Send(MetaManagerModuleName, *msg)
			}
		}
	}()

	m.runMetaManager()
}
```

启动时，开启两个协程，一个用于定时（默认60s）给自己发送消息通知进行边到云的 podstatus 数据同步（KubeEdge 实现了边缘自治，需要将数据同步到云端，网络断开后如果网络恢复，就能立刻将边端的状态进行反馈）；另一个 runMetaManager 用于 edgehub 与 edged 的消息，然后调用 m.process(msg) 进行处理。

process 函数获取消息的操作的类型，然后根据信息操作类型对信息进行相应处理：
```
func (m *metaManager) process(message model.Message) {
	operation := message.GetOperation()
	switch operation {
	case model.InsertOperation:
		m.processInsert(message)
	case model.UpdateOperation:
		m.processUpdate(message)
	case model.DeleteOperation:
		m.processDelete(message)
	case model.QueryOperation:
		m.processQuery(message)
	case model.ResponseOperation:
		m.processResponse(message)
	case messagepkg.OperationNodeConnection:
		m.processNodeConnection(message)
	case OperationMetaSync:
		m.processSync()
	case OperationFunctionAction:
		m.processFunctionAction(message)
	case OperationFunctionActionResult:
		m.processFunctionActionResult(message)
	case constants.CSIOperationTypeCreateVolume,
		constants.CSIOperationTypeDeleteVolume,
		constants.CSIOperationTypeControllerPublishVolume,
		constants.CSIOperationTypeControllerUnpublishVolume:
		m.processVolume(message)
	default:
		klog.Errorf("metamanager not supported operation: %v", operation)
	}
}
```

具体的处理函数 processInsert、processUpdate 等的具体过程不再分析，大致都是对数据库进行操作，然后再通知 edgehub 或 edged。
