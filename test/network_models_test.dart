import 'package:flutter_test/flutter_test.dart';
import 'package:wear_net/wear_net.dart';

void main() {
  test('uses the stable ABI and wearable-safe defaults', () {
    const config = WearNetConfig();

    expect(wearNetAbiVersion, 1);
    expect(config.mtu, 1500);
    expect(config.ingressCapacity, greaterThan(0));
    expect(config.stackCapacity, greaterThan(0));
    expect(config.outboundCapacity, greaterThan(0));
    expect(config.capturePath, isNull);
  });

  test('statistics preserve native counters', () {
    const event = WearNetStatistics(
      bytesFromDevice: 10,
      bytesToDevice: 20,
      readBytesPerSecond: 1.5,
      writeBytesPerSecond: 2.5,
      activeSessions: 3,
      droppedPackets: 4,
    );

    expect(event.type, WearNetEventType.statistics);
    expect(event.bytesFromDevice, 10);
    expect(event.bytesToDevice, 20);
    expect(event.activeSessions, 3);
    expect(event.droppedPackets, 4);
  });
}
