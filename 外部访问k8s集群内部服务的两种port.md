## hostPort

出现在 Deployment、Pod 等资源对象描述文件中的容器部分，类似于 `docker run -p <containerPort>:<hostPort>`。containerPort 为容器暴露的端口；hostPort 为容器暴露的端口直接映射到的主机端口。例如：

```
apiVersion: apps/v1
kind: Deployment
...
spec:
  ...
  template:
    ...
    spec:
      nodeName: node1
      containers:
      - name: nginx
        image: nginx
        ports:
        - containerPort: 80
          hostPort: 30080
```

集群外访问方式：`node1的IP:30080`

## nodePort

出现在 Service 描述文件中，Service 为 NodePort 类型时。port 为在k8s集群内服务访问端口；targetPort 为关联 pod 对外开放端口，与上述 containerPort 保持一致；nodePort 为集群外访问端口，端口范围为 30000-32767。例如：

```
apiVersion: v1
kind: Service
metadata:
  name: nginx-pod-service
  labels:
    app: nginx
spec:
  type: NodePort
  ports:
  - port: 8080
    targetPort: 80
    nodePort: 30080
  selector:
    app: nginx
```

集群外访问方式：`集群任意IP:30080`
