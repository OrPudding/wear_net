# 宿主集成

wear_net 处理用户态 IPv4 网络代理，宿主管理小米设备认证、协议传输与设备生命周期

## 启动

1. 完成设备认证并建立协议连接
2. 为设备创建一个 `WearNetSession`
3. 发送网络能力值为 `2` 的小米 `SyncNetworkStatus`
4. 将 `L2Channel.Network` 收到的数据传入 `pushInbound`
5. 将 `outboundPackets` 返回的数据通过 `L2Channel.Network` 的写入操作发送给设备

原生会话在本地响应 DHCP，其余 IPv4 流量通过宿主网络转发

## 停止

设备断开时先取消数据转发订阅，再关闭网络会话，最后释放协议连接

关闭会话会取消 IP 栈及活动的 TCP、UDP 转发任务

## 队列与丢包

入站队列与事件队列有容量上限，入站队列满时 `pushInbound` 抛出异常，事件被丢弃时原生层递增 `droppedPackets`

宿主需处理异常并记录丢包，过期数据包直接丢弃

## 示例

以下示例中的 `xiaomi` 表示宿主协议适配器

```dart
final network = await WearNetSession.open(
  config: WearNetConfig(
    capturePath: diagnosticsEnabled ? pcapPath : null,
  ),
);

final outbound = network.outboundPackets.listen((packet) {
  xiaomi.sendNetworkPacket(packet);
});
final inbound = xiaomi.networkPackets.listen(network.pushInbound);

// 设备断开时取消转发并关闭会话
await inbound.cancel();
await outbound.cancel();
await network.close();
```
