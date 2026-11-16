# wear_net C ABI

接口定义见 [`include/wear_net.h`](../include/wear_net.h)

## 所有权

- `wear_net_open` 创建会话并返回非零句柄，调用方负责调用一次 `wear_net_close`
- `wear_net_push` 在返回前复制传入的数据
- 事件数据由原生会话持有，`wear_net_event_read` 将其复制到调用方缓冲区并移出队列
- `wear_net_last_error` 返回的指针属于当前线程，有效期持续到该线程的下一次 ABI 调用

## 事件通知

唤醒回调可能在原生运行时线程执行，回调内须避免阻塞与重入会话，函数指针需保持有效，直到 `wear_net_close` 返回

Dart 使用 isolate 级的 `NativeCallable.listener` 接收通知，按句柄分发并读取事件队列，会话关闭时注销句柄，已排队的通知会被忽略

自行提供事件读取机制的宿主可传入空回调

| 事件 | 数据 |
|---|---|
| Packet | 发送回设备协议网络通道的原始 IPv4 包 |
| Statistics | UTF-8 JSON |
| State、Warning | UTF-8 文本 |

## 动态库加载

Flutter 应用通过 `DynamicLibrary.codeAsset` 加载构建 hook 打包的原生库

测试可通过 `WEAR_NET_LIBRARY` 指定动态库绝对路径，源码开发的 hook 配置见 [README](../README.md#本地开发)

## 兼容性

当前 `wear_net_abi_version()` 和结构体中的 `abi_version` 均为 `1`，调用方需拒绝不匹配的 ABI 版本

兼容更新仅可在结构体末尾追加字段，现有字段的顺序、宽度、符号与函数签名保持稳定
