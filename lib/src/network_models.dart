import 'dart:typed_data';

const wearNetAbiVersion = 1;
const oronboxNetworkAbiVersion = wearNetAbiVersion;

class WearNetConfig {
  const WearNetConfig({
    this.mtu = 1500,
    this.ingressCapacity = 256,
    this.stackCapacity = 256,
    this.outboundCapacity = 128,
    this.meterWindowSeconds = 5,
    this.statsIntervalMilliseconds = 1000,
    this.capturePath,
  });

  final int mtu;
  final int ingressCapacity;
  final int stackCapacity;
  final int outboundCapacity;
  final int meterWindowSeconds;
  final int statsIntervalMilliseconds;
  final String? capturePath;
}

enum WearNetEventType { packet, state, statistics, warning, closed }

sealed class WearNetEvent {
  const WearNetEvent(this.type);
  final WearNetEventType type;
}

class WearNetPacket extends WearNetEvent {
  const WearNetPacket(this.bytes) : super(WearNetEventType.packet);
  final Uint8List bytes;
}

class WearNetStatus extends WearNetEvent {
  const WearNetStatus(this.message) : super(WearNetEventType.state);
  final String message;
}

class WearNetStatistics extends WearNetEvent {
  const WearNetStatistics({
    required this.bytesFromDevice,
    required this.bytesToDevice,
    required this.readBytesPerSecond,
    required this.writeBytesPerSecond,
    required this.activeSessions,
    required this.droppedPackets,
  }) : super(WearNetEventType.statistics);

  final int bytesFromDevice;
  final int bytesToDevice;
  final double readBytesPerSecond;
  final double writeBytesPerSecond;
  final int activeSessions;
  final int droppedPackets;
}

class WearNetWarning extends WearNetEvent {
  const WearNetWarning(this.message) : super(WearNetEventType.warning);
  final String message;
}

class WearNetClosed extends WearNetEvent {
  const WearNetClosed() : super(WearNetEventType.closed);
}

class WearNetSnapshot {
  const WearNetSnapshot({
    required this.bytesFromDevice,
    required this.bytesToDevice,
    required this.activeSessions,
    required this.droppedPackets,
  });

  final int bytesFromDevice;
  final int bytesToDevice;
  final int activeSessions;
  final int droppedPackets;
}
