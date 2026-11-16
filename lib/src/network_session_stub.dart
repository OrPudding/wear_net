import 'dart:typed_data';

import 'network_models.dart';

class WearNetSession {
  WearNetSession._();

  static Future<WearNetSession> open({
    WearNetConfig config = const WearNetConfig(),
  }) => throw UnsupportedError('WearNet is unavailable on this platform');

  Stream<WearNetEvent> get events => const Stream.empty();
  Stream<Uint8List> get outboundPackets => const Stream.empty();
  void pushInbound(Uint8List packet) => throw StateError('Session is closed');
  WearNetSnapshot get snapshot => throw StateError('Session is closed');
  Future<void> close() async {}
}
