# wear_net

[简体中文](README.md) | English

A userspace IPv4 gateway for Xiaomi VelaOS / MiWear devices in Flutter applications, supporting DHCP, TCP, UDP, ICMP, traffic statistics, and PCAP capture

## Integration

Add this repository as a Git dependency in `pubspec.yaml` and pin `ref` to the required commit

The Flutter build hook downloads the platform library specified in `native_release.json`, verifies the archive and library SHA-256 hashes, and bundles the library with the application. Using prebuilt libraries requires no Rust toolchain

Import `package:wear_net/wear_net.dart`. Create one `WearNetSession` per connected device, pass device IPv4 packets to `pushInbound`, and send packets from `outboundPackets` back to the device

The host manages authentication, protocol transport, and session shutdown. See [host integration](docs/INTEGRATION.md) and the [C ABI and ownership contract](docs/ABI.md)

## Platforms and artifacts

| Platform | Architectures | Native library |
|---|---|---|
| Android | arm64-v8a, armeabi-v7a, x86_64 | `libwear_net.so` |
| Linux | arm64, x86_64 | `libwear_net.so` |
| macOS | arm64, x86_64 | `libwear_net.dylib` |
| Windows | x86_64 | `wear_net.dll` |
| iOS devices | arm64 | `libwear_net.a` |
| iOS Simulator | arm64, x86_64 | `libwear_net.a` |

Flutter bundles libraries automatically on Android, Linux, macOS, and Windows. The iOS artifacts are static libraries for native linking by the host application

Each target ZIP includes the native library, C header, build manifest, dependency inventory, lockfile, and licenses, with an adjacent SHA-256 file. The manifest records the source commit, workspace state, target, ABI version, and library hash

## Local development

Flutter and Rust versions are specified in `.fvmrc` and `rust-toolchain.toml`

Build the native library for the current platform

~~~sh
python3 tool/build.py --output dist/local --archive
~~~

Use `--target` for cross-compilation. Android builds also require `ANDROID_NDK_HOME` or `ANDROID_NDK_ROOT`

~~~sh
ANDROID_NDK_HOME=/path/to/ndk python3 tool/build.py --target aarch64-linux-android --archive
~~~

Select a local library in the consuming application’s `pubspec.yaml`

~~~yaml
hooks:
  user_defines:
    wear_net:
      native_library: /absolute/path/to/library
~~~

Apply the same configuration to this package’s `pubspec.yaml` when running its checks and native integration tests

~~~sh
fvm flutter pub get
fvm flutter analyze
WEAR_NET_NATIVE_TEST=1 fvm flutter test
cargo test --locked --workspace
~~~

## License

AGPL-3.0. Third-party sources, attribution, and licenses are listed in [THIRD_PARTY_NOTICES.en.md](THIRD_PARTY_NOTICES.en.md)
