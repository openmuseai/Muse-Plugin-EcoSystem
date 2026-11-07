import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:openmuse_dataset/openmuse_dataset.dart';

class MemoryStore implements SnapshotStore {
  Map<String, dynamic>? value;
  int writes = 0, active = 0, maxActive = 0;
  Completer<void>? gate, entered;
  @override
  Future<Map<String, dynamic>?> read() async => value == null
      ? null
      : (jsonDecode(jsonEncode(value)) as Map).cast<String, dynamic>();
  @override
  Future<void> write(Map<String, dynamic> data) async {
    final captured = (jsonDecode(jsonEncode(data)) as Map)
        .cast<String, dynamic>();
    writes++;
    active++;
    if (active > maxActive) maxActive = active;
    final wait = gate;
    if (wait != null) {
      gate = null;
      entered?.complete();
      await wait.future;
    }
    value = captured;
    active--;
  }
}

class TracedCore implements DatasetCore {
  final DatasetCore inner = NativeDatasetCore();
  final Map<String, Uint8List> byBody = {}, byEncoded = {};
  String? lastRootBody;
  @override
  Map<String, dynamic> call(Map<String, dynamic> request) {
    final state = inner.call(request);
    if (request['action'] == 'syncObject') {
      final bytes = base64Decode(state['docState'] as String);
      byBody[state['body'] as String] = bytes;
      byEncoded[state['encodedCollab'] as String] = bytes;
      if (state['collabType'] == 1) lastRootBody = state['body'] as String;
    }
    return state;
  }
}

class FakeCloud {
  FakeCloud(this.core);
  final TracedCore core;
  final Uint8List emptyUpdate = File(
    'test/fixtures/empty-update.zst',
  ).readAsBytesSync();
  final Map<String, Uint8List> states = {};
  final List<String> initialized = [], rootRequests = [];
  Future<void> Function(String, int)? beforeRead;
  CollaborationProvider provider(int type) => _Provider(this, type);
}

class _Provider implements CollaborationProvider {
  _Provider(this.cloud, this.type);
  final FakeCloud cloud;
  final int type;
  @override
  CollaborationBinding get binding => datasetBinding(type);
  @override
  Future<Uint8List?> readState(String id) async {
    await cloud.beforeRead?.call(id, type);
    return cloud.states[id];
  }

  @override
  Future<void> initializeState(String id, Uint8List encoded) async {
    cloud.initialized.add(id);
    cloud.states[id] = cloud.core.byEncoded[base64Encode(encoded)]!;
  }

  @override
  Future<Uint8List> exchange(String id, Uint8List request) async {
    final body = base64Encode(request);
    cloud.states[id] = cloud.core.byBody[body]!;
    if (type == 1) cloud.rootRequests.add(body);
    return cloud.emptyUpdate;
  }

  @override
  void close() {}
}
