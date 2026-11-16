import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'network_bindings.dart';
import 'network_models.dart';

const _noEvent = 1;

/// 回调与 isolate 同寿命，避免关闭单个会话时释放仍可能被原生线程调用的函数指针
final class _WakeDispatcher {
  _WakeDispatcher._() {
    _callback = NativeCallable<WearNetWakeNative>.listener(_onWake);
  }

  static final instance = _WakeDispatcher._();

  late final NativeCallable<WearNetWakeNative> _callback;
  final Map<int, WearNetSession> _sessions = {};

  Pointer<NativeFunction<WearNetWakeNative>> get nativeFunction =>
      _callback.nativeFunction;

  void register(WearNetSession session) {
    _sessions[session._handle] = session;
  }

  void unregister(WearNetSession session) {
    if (identical(_sessions[session._handle], session)) {
      _sessions.remove(session._handle);
    }
  }

  void _onWake(int handle) {
    _sessions[handle]?._scheduleDrain();
  }
}

class WearNetSession {
  WearNetSession._(this._bindings, this._handle);

  static Future<WearNetSession> open({
    WearNetConfig config = const WearNetConfig(),
  }) async {
    final bindings = WearNetBindings.load();
    final nativeAbi = bindings.abiVersion();
    if (nativeAbi != wearNetAbiVersion) {
      throw StateError(
        'WearNet ABI mismatch: Dart $wearNetAbiVersion, native $nativeAbi',
      );
    }

    final dispatcher = _WakeDispatcher.instance;
    final nativeConfig = calloc<WearNetConfigNative>();
    final outHandle = calloc<Uint64>();
    final capturePath = config.capturePath?.toNativeUtf8();
    try {
      nativeConfig.ref
        ..abiVersion = wearNetAbiVersion
        ..mtu = config.mtu
        ..reserved = 0
        ..ingressCapacity = config.ingressCapacity
        ..stackCapacity = config.stackCapacity
        ..outboundCapacity = config.outboundCapacity
        ..meterWindowMilliseconds = config.meterWindowSeconds * 1000
        ..statisticsIntervalMilliseconds = config.statsIntervalMilliseconds
        ..capturePath = capturePath ?? nullptr;

      final status = bindings.open(
        nativeConfig,
        dispatcher.nativeFunction,
        outHandle,
      );
      if (status != 0) {
        throw StateError(bindings.errorMessage());
      }

      final session = WearNetSession._(bindings, outHandle.value);
      dispatcher.register(session);
      return session;
    } finally {
      calloc.free(nativeConfig);
      calloc.free(outHandle);
      if (capturePath != null) {
        calloc.free(capturePath);
      }
    }
  }

  final WearNetBindings _bindings;
  final int _handle;
  final _events = StreamController<WearNetEvent>.broadcast(sync: true);
  final _outbound = StreamController<Uint8List>.broadcast(sync: true);
  final _inboundBuffer = calloc<Uint8>(65536);
  final _eventKind = calloc<Uint32>();
  final _eventLength = calloc<Size>();
  bool _isDraining = false;
  bool _hasPendingDrain = false;
  bool _closed = false;

  Stream<WearNetEvent> get events => _events.stream;
  Stream<Uint8List> get outboundPackets => _outbound.stream;

  void pushInbound(Uint8List packet) {
    if (_closed) {
      throw StateError('Cannot push inbound packet into closed session');
    }
    if (packet.isEmpty) return;

    final length = packet.length;
    final buffer = _inboundBuffer.asTypedList(65536);
    if (length > buffer.length) {
      throw ArgumentError.value(
        length,
        'packet.length',
        'Packet exceeds maximum size of 65535 bytes',
      );
    }
    buffer.setRange(0, length, packet);

    final status = _bindings.push(_handle, _inboundBuffer, length);
    if (status != 0) {
      throw StateError(_bindings.errorMessage());
    }
  }

  WearNetSnapshot get snapshot {
    if (_closed) {
      throw StateError('Cannot query snapshot of closed session');
    }
    final snapshot = calloc<WearNetSnapshotNative>();
    try {
      final status = _bindings.snapshot(_handle, snapshot);
      if (status != 0) {
        throw StateError(_bindings.errorMessage());
      }
      return WearNetSnapshot(
        bytesFromDevice: snapshot.ref.bytesFromDevice,
        bytesToDevice: snapshot.ref.bytesToDevice,
        activeSessions: snapshot.ref.activeSessions,
        droppedPackets: snapshot.ref.droppedPackets,
      );
    } finally {
      calloc.free(snapshot);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _WakeDispatcher.instance.unregister(this);
    try {
      final status = _bindings.close(_handle);
      if (status != 0) {
        throw StateError(_bindings.errorMessage());
      }
    } finally {
      calloc.free(_inboundBuffer);
      calloc.free(_eventKind);
      calloc.free(_eventLength);
      _events.add(const WearNetClosed());
      await _events.close();
      await _outbound.close();
    }
  }

  void _scheduleDrain() {
    if (_closed) return;
    if (_isDraining) {
      _hasPendingDrain = true;
      return;
    }
    _isDraining = true;
    scheduleMicrotask(_drainEvents);
  }

  void _drainEvents() {
    if (_closed) {
      _isDraining = false;
      return;
    }
    try {
      while (!_closed) {
        final peek = _bindings.eventPeek(_handle, _eventKind, _eventLength);
        if (peek == _noEvent) {
          break;
        }
        if (peek != 0) {
          _events.add(
            WearNetWarning('eventPeek failed: ${_bindings.errorMessage()}'),
          );
          break;
        }

        final size = _eventLength.value;
        final buffer = calloc<Uint8>(size);
        try {
          final read = _bindings.eventRead(
            _handle,
            buffer,
            size,
            _eventKind,
            _eventLength,
          );
          if (read != 0) {
            _events.add(
              WearNetWarning('eventRead failed: ${_bindings.errorMessage()}'),
            );
            break;
          }
          final payload = Uint8List.fromList(buffer.asTypedList(size));
          final event = _decodeEvent(_eventKind.value, payload);
          _emit(event);
        } finally {
          calloc.free(buffer);
        }
      }
    } finally {
      _isDraining = false;
      if (_hasPendingDrain) {
        _hasPendingDrain = false;
        _scheduleDrain();
      }
    }
  }

  WearNetEvent _decodeEvent(int kind, Uint8List payload) {
    switch (kind) {
      case 1:
        return WearNetPacket(payload);
      case 2:
        return WearNetStatus(utf8.decode(payload));
      case 3:
        final json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
        return WearNetStatistics(
          bytesFromDevice: json['bytes_from_device'] as int,
          bytesToDevice: json['bytes_to_device'] as int,
          readBytesPerSecond: (json['read_bytes_per_second'] as num).toDouble(),
          writeBytesPerSecond: (json['write_bytes_per_second'] as num)
              .toDouble(),
          activeSessions: json['active_sessions'] as int,
          droppedPackets: json['dropped_packets'] as int,
        );
      case 4:
        return WearNetWarning(utf8.decode(payload));
      default:
        return WearNetWarning('Unknown native event kind $kind');
    }
  }

  void _emit(WearNetEvent event) {
    if (_closed) return;
    _events.add(event);
    if (event case WearNetPacket(:final bytes)) {
      _outbound.add(bytes);
    }
  }
}
