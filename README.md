# wear_net

简体中文 | [English](README.en.md)

为 Flutter 应用提供小米 VelaOS / MiWear 设备的用户态 IPv4 网络代理，支持 DHCP、TCP、UDP、ICMP、流量统计和 PCAP 捕获

## 接入

在 `pubspec.yaml` 中添加本仓库的 Git 依赖，并将 `ref` 固定到所需提交

Flutter 构建 hook 根据 `native_release.json` 下载对应平台的预编译库，校验压缩包与库文件的 SHA-256 后随应用打包，使用预编译库无需安装 Rust 工具链

Dart 入口为 `package:wear_net/wear_net.dart`，宿主为每台已连接设备创建一个 `WearNetSession`，通过 `pushInbound` 输入设备 IPv4 数据包，通过 `outboundPackets` 接收返回设备的数据包

设备认证、协议通道和会话关闭由宿主管理，接入流程见 [宿主集成](docs/INTEGRATION.md)，C ABI 与资源所有权约定见 [ABI](docs/ABI.md)

## 平台与产物

| 平台 | 架构 | 原生产物 |
|---|---|---|
| Android | arm64-v8a、armeabi-v7a、x86_64 | `libwear_net.so` |
| Linux | arm64、x86_64 | `libwear_net.so` |
| macOS | arm64、x86_64 | `libwear_net.dylib` |
| Windows | x86_64 | `wear_net.dll` |
| iOS 真机 | arm64 | `libwear_net.a` |
| iOS 模拟器 | arm64、x86_64 | `libwear_net.a` |

Flutter 自动打包覆盖 Android、Linux、macOS 和 Windows，iOS 产物供宿主原生静态链接

每个目标平台提供 ZIP 与配套 SHA-256 文件

ZIP 包含原生库、C 头文件、构建清单、依赖清单、锁文件和许可证，构建清单记录源码提交、工作区状态、目标平台、ABI 版本及库文件哈希

## 本地开发

Flutter 与 Rust 版本分别由 `.fvmrc` 和 `rust-toolchain.toml` 指定

构建当前平台的原生库

```sh
python3 tool/build.py --output dist/local --archive
```

交叉编译通过 `--target` 指定 Rust target，Android 构建还需设置 `ANDROID_NDK_HOME` 或 `ANDROID_NDK_ROOT`

```sh
ANDROID_NDK_HOME=/path/to/ndk python3 tool/build.py --target aarch64-linux-android --archive
```

在消费项目的 `pubspec.yaml` 中指定本地库后，Flutter 构建与测试使用该库

```yaml
hooks:
  user_defines:
    wear_net:
      native_library: /absolute/path/to/library
```

运行包内检查与原生集成测试时，同样在本仓库的 `pubspec.yaml` 中配置本地库

```sh
fvm flutter pub get
fvm flutter analyze
WEAR_NET_NATIVE_TEST=1 fvm flutter test
cargo test --locked --workspace
```

## 许可证

本项目采用 AGPL-3.0，第三方组件的来源、署名与许可证见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
