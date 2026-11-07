/// Test-only transport control. No content model, protocol, auth or merge code.
library;

import 'dart:async';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

final class HttpRequestGate {
  Completer<void>? _held;
  int blockedRequests = 0;
  bool get held => _held != null;
  void hold() {
    if (held) throw StateError('HTTP already held');
    _held = Completer<void>();
  }

  void release() {
    final old = _held;
    _held = null;
    old?.complete();
  }

  http.Client client() => _GatedClient(this);
}

final class _GatedClient extends http.BaseClient {
  _GatedClient(this.gate);
  final HttpRequestGate gate;
  final http.Client inner = http.Client();
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final held = gate._held;
    if (held != null) {
      gate.blockedRequests++;
      await held.future;
    }
    if (closed) throw http.ClientException('test-client-closed');
    return inner.send(request);
  }

  @override
  void close() {
    closed = true;
    inner.close();
  }
}

/// Buffers copies of already encoded frames from the real channel, leaving
/// inbound packets live. The caller can commit BOTH local branches before
/// publishing either, without simulating a CRDT or relying on timing.
final class OutgoingFrameGate {
  OutgoingFrameGate({this.onHeld});
  final void Function(String actor, Uint8List bytes)? onHeld;
  final List<(_GatedSink, Uint8List)> _frames = [];
  int _bytes = 0;
  bool holding = false;
  int get bufferedFrames => _frames.length;
  void hold() {
    if (holding || _frames.isNotEmpty) throw StateError('Frames already held');
    holding = true;
  }

  WebSocketChannel open(String actor, Uri uri) =>
      _GatedChannel(WebSocketChannel.connect(uri), this, actor);
  void release() {
    holding = false;
    final pending = List.of(_frames);
    _frames.clear();
    _bytes = 0;
    for (final (sink, data) in pending) {
      if (!sink.closed) sink.inner.add(data);
    }
  }

  void _drop(_GatedSink sink) {
    _frames.removeWhere((e) => identical(e.$1, sink));
    _bytes = _frames.fold(0, (n, e) => n + e.$2.length);
  }

  void _add(_GatedSink sink, dynamic data) {
    if (sink.closed) throw StateError('test-socket-closed');
    if (!holding) {
      sink.inner.add(data);
      return;
    }
    if (data is! List<int>) throw StateError('Expected original binary frame');
    if (_frames.length >= 64 || _bytes + data.length > 16 * 1024 * 1024)
      throw StateError('Test frame gate quota');
    final copy = Uint8List.fromList(data);
    _frames.add((sink, copy));
    _bytes += copy.length;
    onHeld?.call(sink.actor, copy);
  }
}

final class _GatedChannel extends StreamChannelMixin
    implements WebSocketChannel {
  _GatedChannel(this.inner, OutgoingFrameGate gate, String actor)
    : sink = _GatedSink(inner.sink, gate, actor);
  final WebSocketChannel inner;
  @override
  final WebSocketSink sink;
  @override
  Stream get stream => inner.stream;
  @override
  String? get protocol => inner.protocol;
  @override
  int? get closeCode => inner.closeCode;
  @override
  String? get closeReason => inner.closeReason;
  @override
  Future<void> get ready => inner.ready;
}

final class _GatedSink implements WebSocketSink {
  _GatedSink(this.inner, this.gate, this.actor);
  final WebSocketSink inner;
  final OutgoingFrameGate gate;
  final String actor;
  bool closed = false;
  @override
  void add(dynamic data) => gate._add(this, data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      inner.addError(error, stackTrace);
  @override
  Future<void> addStream(Stream stream) async {
    await for (final data in stream) {
      add(data);
    }
  }

  @override
  Future close([int? closeCode, String? closeReason]) {
    closed = true;
    gate._drop(this);
    return inner.close(closeCode, closeReason);
  }

  @override
  Future get done => inner.done;
}
