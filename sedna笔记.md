## Dataset

<div align=center>
<img src="sedna/image2020-11-11_12-4-27.png" style="zoom:100%;" />
</div>

dataset crd 中需要设置的字段有 nodeName、url 和 format。nodeName 指定此 dataset crd 由哪个边缘节点管理；url 为 dataset 所在路径，可以是边缘节点本地路径，也可以是共享存储；format 目前只支持 txt 和 csv。

dataset crd 创建后，主要就看 Dataset Manager，它会定时（MonitorDataSourceIntervalSeconds，默认 60s）重复两件事情，一是从 url 中读取数据集，二是通过 websocket 向云端推送状态，状态中包含数据集的行数(numberOfSamples)以及数据集更新的时间(updateTime)。

## Model

model 与 dataset 类似，且创建时不用指定 nodeName，也没有 controller 监控。

model 的信息将在使用该 model 的联邦学习等任务时被同步；当相应的训练/推理工作完成后，model 的状态将被更新。
