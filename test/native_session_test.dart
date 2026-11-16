import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wear_net/wear_net.dart';

void main() {
  test('opens the native library through Dart FFI', () async {
    final session = await WearNetSession.open();
    addTearDown(session.close);
    expect(session.snapshot.bytesFromDevice, 0);
    expect(session.snapshot.bytesToDevice, 0);
  }, skip: Platform.environment['WEAR_NET_NATIVE_TEST'] != '1');

  test('closing a session preserves callbacks for other sessions', () async {
    const config = WearNetConfig(statsIntervalMilliseconds: 100);
    final first = await WearNetSession.open(config: config);
    addTearDown(first.close);
    final second = await WearNetSession.open(config: config);
    addTearDown(second.close);
    final firstEvents = <WearNetEvent>[];
    final firstStatistics = Completer<void>();
    final firstClosed = Completer<void>();
    final firstSubscription = first.events.listen((event) {
      firstEvents.add(event);
      if (event is WearNetStatistics && !firstStatistics.isCompleted) {
        firstStatistics.complete();
      }
    }, onDone: firstClosed.complete);
    addTearDown(firstSubscription.cancel);

    await firstStatistics.future.timeout(const Duration(seconds: 5));
    await first.close();
    await firstClosed.future.timeout(const Duration(seconds: 5));
    final eventsAtClose = firstEvents.length;
    expect(firstEvents.last, isA<WearNetClosed>());

    final statistics = await second.events
        .where((event) => event is WearNetStatistics)
        .cast<WearNetStatistics>()
        .first
        .timeout(const Duration(seconds: 5));
    expect(statistics.bytesFromDevice, 0);
    expect(statistics.bytesToDevice, 0);
    expect(firstEvents, hasLength(eventsAtClose));
  }, skip: Platform.environment['WEAR_NET_NATIVE_TEST'] != '1');
}
