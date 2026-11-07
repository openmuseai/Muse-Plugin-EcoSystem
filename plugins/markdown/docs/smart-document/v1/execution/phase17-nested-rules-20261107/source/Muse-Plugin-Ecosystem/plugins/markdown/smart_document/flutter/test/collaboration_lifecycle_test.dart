import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';

class _Memory implements DocumentStore {
  Map<String, dynamic>? value;
  int writes = 0;
  @override
  Future<Map<String, dynamic>?> read() async => value;
  @override
  Future<void> write(Map<String, dynamic> v) async {
    value = v;
    writes++;
  }
}

class _Gate implements CollaborationProvider {
  _Gate(this.seed);
  final Uint8List seed;
  bool opening = true, closed = false, consumed = false;
  Completer<Uint8List>? gate;
  Completer<void> entered = Completer<void>();
  @override
  CollaborationBinding get binding => smartDocumentCollaborationBinding;
  @override
  Future<Uint8List?> readState(String id) async {
    if (opening) {
      opening = false;
      throw const SmartDocumentFailure('OFFLINE');
    }
    return seed;
  }

  @override
  Future<void> initializeState(String id, Uint8List bytes) async =>
      throw StateError('must not create');
  @override
  Future<Uint8List> exchange(String id, Uint8List bytes) async {
    final wait = gate;
    if (wait != null && !consumed) {
      consumed = true;
      if (!entered.isCompleted) entered.complete();
      return wait.future;
    }
    return File(
      '../dataset/flutter/test/fixtures/empty-update.zst',
    ).readAsBytesSync();
  }

  @override
  void close() {
    closed = true;
  }
}

Future<({SmartDocumentController c, _Gate provider, _Memory store})>
open() async {
  final seed = await SmartDocumentController.open(
    core: NativeDocumentCore(),
    store: _Memory(),
    objectId: 'e765718a-b596-46c9-9fa9-bc4ed91a3c49',
  );
  final raw = seed.snapshot['docState'] as String;
  await seed.close();
  final provider = _Gate(base64Decode(raw)), store = _Memory();
  final c = await SmartDocumentController.open(
    core: NativeDocumentCore(),
    store: store,
    objectId: seed.objectId,
    initialDocState: raw,
    provider: provider,
    syncInterval: null,
  );
  return (c: c, provider: provider, store: store);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('paused document refuses incoming content until resumed', () async {
    final w = await open(), c = w.c;
    final peer = await SmartDocumentController.open(
      core: NativeDocumentCore(),
      store: _Memory(),
      objectId: c.objectId,
      initialDocState: c.snapshot['docState'] as String,
    );
    await peer.insertParagraph('暂停期间的远端内容');
    c.pauseCollaboration(true);
    final before = jsonEncode(c.snapshot['data']);
    await c.applyRealtimeUpdate(
      base64Decode(peer.snapshot['docState'] as String),
    );
    expect(jsonEncode(c.snapshot['data']), before);
    await c.close();
    await peer.close();
  });
  for (final code in ['FORBIDDEN', 'OBJECT_DELETED', 'OFFLINE']) {
    test(
      'closed document ignores late $code from a previously authorized HTTP request',
      () async {
        final w = await open(), c = w.c, p = w.provider;
        p.gate = Completer<Uint8List>();
        final sync = c.synchronize();
        await p.entered.future;
        await c.close();
        expect(p.closed, true);
        final before = (
          state: c.syncState,
          failure: c.collaborationFailure,
          writes: w.store.writes,
        );
        p.gate!.completeError(SmartDocumentFailure(code));
        await sync;
        expect(c.syncState, before.state);
        expect(c.collaborationFailure, before.failure);
        expect(w.store.writes, before.writes);
      },
    );
  }
  test(
    'fresh authenticated writer grant is not overwritten by an older HTTP denial',
    () async {
      final w = await open(), c = w.c, p = w.provider;
      p.gate = Completer<Uint8List>();
      final sync = c.synchronize();
      await p.entered.future;
      c.acceptRealtimeAccess(canRead: false, canWrite: false, reason: 'denied');
      c.acceptRealtimeAccess(canRead: true, canWrite: true, reason: 'granted');
      expect(c.canWrite, true);
      p.gate!.completeError(const SmartDocumentFailure('FORBIDDEN'));
      await sync;
      expect(c.canWrite, true);
      expect(c.editor.editable, true);
      expect(c.syncState, isNot(DocumentSyncState.forbidden));
      await c.close();
    },
  );
  test(
    'pause and resume invalidate an earlier failure without clearing current authority',
    () async {
      final w = await open(), c = w.c, p = w.provider;
      p.gate = Completer<Uint8List>();
      final sync = c.synchronize();
      await p.entered.future;
      c.pauseCollaboration(true);
      c.pauseCollaboration(false);
      p.gate!.completeError(const SmartDocumentFailure('FORBIDDEN'));
      await sync;
      expect(c.canWrite, true);
      await c.close();
    },
  );
}
