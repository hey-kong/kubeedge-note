```本文基于 commit 9a7e140b42abb4bf6bcabada67e3568f73964278。```

## 概述

DeviceTwin 负责存储设备状态（传感器的值等）并将设备状态同步到云，它还为应用程序提供查询接口。它由四个子模块组成（membership 模块，communication 模块，device 模块和 device twin 模块）。

## DeviceTwin 注册

DeviceTwin 注册也调用了 InitDBTable，在 SQLite 数据库中初始化了三张表 Device，DeviceAttr 与 DeviceTwin：
```
//Device the struct of device
type Device struct {
	ID          string `orm:"column(id); size(64); pk"`
	Name        string `orm:"column(name); null; type(text)"`
	Description string `orm:"column(description); null; type(text)"`
	State       string `orm:"column(state); null; type(text)"`
	LastOnline  string `orm:"column(last_online); null; type(text)"`
}

//DeviceAttr the struct of device attributes
type DeviceAttr struct {
	ID          int64  `orm:"column(id);size(64);auto;pk"`
	DeviceID    string `orm:"column(deviceid); null; type(text)"`
	Name        string `orm:"column(name);null;type(text)"`
	Description string `orm:"column(description);null;type(text)"`
	Value       string `orm:"column(value);null;type(text)"`
	Optional    bool   `orm:"column(optional);null;type(integer)"`
	AttrType    string `orm:"column(attr_type);null;type(text)"`
	Metadata    string `orm:"column(metadata);null;type(text)"`
}

//DeviceTwin the struct of device twin
type DeviceTwin struct {
	ID              int64  `orm:"column(id);size(64);auto;pk"`
	DeviceID        string `orm:"column(deviceid); null; type(text)"`
	Name            string `orm:"column(name);null;type(text)"`
	Description     string `orm:"column(description);null;type(text)"`
	Expected        string `orm:"column(expected);null;type(text)"`
	Actual          string `orm:"column(actual);null;type(text)"`
	ExpectedMeta    string `orm:"column(expected_meta);null;type(text)"`
	ActualMeta      string `orm:"column(actual_meta);null;type(text)"`
	ExpectedVersion string `orm:"column(expected_version);null;type(text)"`
	ActualVersion   string `orm:"column(actual_version);null;type(text)"`
	Optional        bool   `orm:"column(optional);null;type(integer)"`
	AttrType        string `orm:"column(attr_type);null;type(text)"`
	Metadata        string `orm:"column(metadata);null;type(text)"`
}
```

## 模块入口

edge/pkg/devicetwin/devicetwin.go：
```
// Start run the module
func (dt *DeviceTwin) Start() {
	dtContexts, _ := dtcontext.InitDTContext()
	dt.DTContexts = dtContexts
	err := SyncSqlite(dt.DTContexts)
	if err != nil {
		klog.Errorf("Start DeviceTwin Failed, Sync Sqlite error:%v", err)
		return
	}
	dt.runDeviceTwin()
}
```

主要就是 SyncSqlite 和 runDeviceTwin

## SyncSqlite

SyncSqlite 最终会执行 SyncDeviceFromSqlite：
```
func SyncDeviceFromSqlite(context *dtcontext.DTContext, deviceID string) error {
	klog.Infof("Sync device detail info from DB of device %s", deviceID)
	_, exist := context.GetDevice(deviceID)
	if !exist {
		var deviceMutex sync.Mutex
		context.DeviceMutex.Store(deviceID, &deviceMutex)
	}

	defer context.Unlock(deviceID)
	context.Lock(deviceID)

	devices, err := dtclient.QueryDevice("id", deviceID)
	if err != nil {
		klog.Errorf("query device failed: %v", err)
		return err
	}
	if len(*devices) <= 0 {
		return errors.New("Not found device from db")
	}
	device := (*devices)[0]

	deviceAttr, err := dtclient.QueryDeviceAttr("deviceid", deviceID)
	if err != nil {
		klog.Errorf("query device attr failed: %v", err)
		return err
	}
	attributes := make([]dtclient.DeviceAttr, 0)
	attributes = append(attributes, *deviceAttr...)

	deviceTwin, err := dtclient.QueryDeviceTwin("deviceid", deviceID)
	if err != nil {
		klog.Errorf("query device twin failed: %v", err)
		return err
	}
	twins := make([]dtclient.DeviceTwin, 0)
	twins = append(twins, *deviceTwin...)

	context.DeviceList.Store(deviceID, &dttype.Device{
		ID:          deviceID,
		Name:        device.Name,
		Description: device.Description,
		State:       device.State,
		LastOnline:  device.LastOnline,
		Attributes:  dttype.DeviceAttrToMsgAttr(attributes),
		Twin:        dttype.DeviceTwinToMsgTwin(twins)})

	return nil
}
```

这段函数主要执行了以下操作：

1. 检查设备是否在上下文中（设备列表存储在上下文中），如果不在则添加一个 deviceMutex 至上下文中
2. 从数据库中查询设备
3. 从数据库中查询设备属性
4. 从数据库中查询 Device Twin
5. 将设备、设备属性和 Device Twin 数据合并为一个结构，并将其存储在上下文中

## runDeviceTwin

```
func (dt *DeviceTwin) runDeviceTwin() {
	moduleNames := []string{dtcommon.MemModule, dtcommon.TwinModule, dtcommon.DeviceModule, dtcommon.CommModule}
	for _, v := range moduleNames {
		dt.RegisterDTModule(v)
		go dt.DTModules[v].Start()
	}
	go func() {
		for {
			select {
			case <-beehiveContext.Done():
				klog.Warning("Stop DeviceTwin ModulesContext Receive loop")
				return
			default:
			}
			if msg, ok := beehiveContext.Receive("twin"); ok == nil {
				klog.Info("DeviceTwin receive msg")
				err := dt.distributeMsg(msg)
				if err != nil {
					klog.Warningf("distributeMsg failed: %v", err)
				}
			}
		}
	}()

	for {
		select {
		case <-time.After((time.Duration)(60) * time.Second):
			//range to check whether has bug
			for dtmName := range dt.DTModules {
				health, ok := dt.DTContexts.ModulesHealth.Load(dtmName)
				if ok {
					now := time.Now().Unix()
					if now-health.(int64) > 60*2 {
						klog.Infof("%s health %v is old, and begin restart", dtmName, health)
						go dt.DTModules[dtmName].Start()
					}
				}
			}
			for _, v := range dt.HeartBeatToModule {
				v <- "ping"
			}
		case <-beehiveContext.Done():
			for _, v := range dt.HeartBeatToModule {
				v <- "stop"
			}
			klog.Warning("Stop DeviceTwin ModulesHealth load loop")
			return
		}
	}
}
```

runDeviceTwin 主要执行了以下操作：
1. 启动 devicetwin 中四个的子模块，子模块代码在 edge/pkg/devicetwin/dtmanager 下
2. 轮询接收消息，执行 distributeMsg。将收到的消息发送给 communication 模块，对消息进行分类，即消息是来自 EventBus、EdgeManager 还是 EdgeHub，并填充 ActionModuleMap，再将消息发送至对应的子模块
3. 定期（默认60s）向子模块发送 "ping" 信息。每个子模块一旦收到 "ping" 信息，就会更新自己的时间戳。控制器检查每个模块的时间戳是否超过 2 分钟，如果超过则重新启动该子模块。

## Membership 模块

Membership 模块的主要作用是为新设备添加提供资格，该模块将新设备与边缘节点绑定，并在边缘节点和边缘设备之间建立相应关系。它主要执行以下操作：
1. 初始化 memActionCallBack，它的类型是 map[string]Callback，包含可执行的动作函数
2. 接收消息
3. 对于每条消息，都会调用相应动作函数
4. 接收心跳信息，并向控制器发送心跳信号

以下是可由 Membership 模块执行的动作函数：
* dealMembershipGet：从缓存中获取与特定边缘节点相关的设备信息
* dealMembershipUpdated：更新节点的成员信息
* dealMembershipDetail：提供了边缘节点的成员详细信息

## Twin 模块

Twin 模块的主要作用是处理所有与 device twin 相关的操作。它可以执行诸如更新 device twin、获取 device twin 和同步 device twin 到云的操作。它执行的操作与 Membership 模块类似。

以下是可由 Twin 模块执行的动作函数：
* dealTwinUpdate：更新一个特定设备的 device twin 信息
* dealTwinGet：提供一个特定设备的 device twin 信息
* dealTwinSync：将 device twin 信息同步到云端

## Communication 模块

Communication 模块的主要作用是确保设备双胞胎和其他组件之间的通信功能。它主要执行以下操作：
1. 初始化 memActionCallBack，它的类型是 map[string]Callback，包含可执行的动作函数
2. 接收消息
3. 对于每条消息，都会调用相应动作函数
4. 确认消息中指定的动作是否完成，如果动作没有完成则重做该动作
5. 接收心跳信息，并向控制器发送心跳信号

以下是可由 Communication 模块执行的动作函数：
* dealSendToCloud：用于发送数据到 cloudhub。这个函数首先确保云边是连接的，然后将消息发送到 edgehub 模块，edgehub 将消息转发给云
* dealSendToEdge：用于发送数据给边缘的其他模块。这个函数将收到的消息发送到 edgehub 模块，edgehub 将消息转发给其他模块
* dealLifeCycle：检查是否连接到云并且 twin 的状态是否为断开，将状态改为连接并将节点的详细信息发送给 edgehub；如果未连接到云，就把 twin 的状态设置为断开
* dealConfirm：检查消息的类型是否正确，然后从 ConfirmMap 中删除 msgID

## Device 模块

Device 模块的主要作用是执行与设备有关的操作，如设备状态更新和设备属性更新。它执行的操作与 Membership 模块类似。

以下是可由 Device 模块执行的动作函数：
* dealDeviceUpdated：处理的是当遇到设备属性更新时要执行的操作。更新设备属性，比如在数据库中增加属性、更新属性和删除属性
* dealDeviceStateUpdate：处理的是当遇到设备状态更新时要执行的操作。更新设备的状态以及数据库中设备的最后在线时间

## More

关于执行动作函数的流程以及 Device，DeviceAttr 与 DeviceTwin 这三张表中字段的描述请见 [DeviceTwin](https://kubeedge.io/zh/docs/architecture/edge/devicetwin/)。
