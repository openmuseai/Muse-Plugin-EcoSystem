import 'dart:typed_data';
import 'dart:convert';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';

class _Memory implements DocumentStore {
  Map<String, dynamic>? value;
  bool fail = false;
  @override
  Future<Map<String, dynamic>?> read() async => value;
  @override
  Future<void> write(Map<String, dynamic> next) async {
    if (fail) throw StateError('Injected storage failure');
    value = Map.of(next);
  }
}

class _Denied implements CollaborationProvider {
  @override
  CollaborationBinding get binding => smartDocumentCollaborationBinding;
  @override
  Future<Uint8List?> readState(String id) async =>
      throw const SmartDocumentFailure('FORBIDDEN');
  @override
  Future<Uint8List> exchange(String id, Uint8List request) async =>
      throw const SmartDocumentFailure('FORBIDDEN');
  @override
  Future<void> initializeState(String id, Uint8List state) async =>
      throw const SmartDocumentFailure('FORBIDDEN');
  @override
  void close() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'fresh authenticated viewer capabilities recover HTTP denial without enabling writes',
    () async {
      final core = NativeDocumentCore();
      final peer = await SmartDocumentController.open(
        core: core,
        store: _Memory(),
        objectId: '9ac3ad58-105c-4cb8-80da-5912b95f34a4',
      );
      final c = await SmartDocumentController.open(
        core: core,
        store: _Memory(),
        objectId: peer.objectId,
        initialDocState: peer.snapshot['docState'] as String,
        provider: _Denied(),
        syncInterval: null,
      );
      expect(c.syncState, DocumentSyncState.forbidden);
      c.pauseCollaboration(true);
      c.pauseCollaboration(false);
      expect(c.canWrite, isFalse);
      c.acceptRealtimeAccess(canRead: true, canWrite: false, reason: 'denied');
      await peer.insertParagraph('只读订阅内容');
      await c.applyRealtimeUpdate(
        base64Decode(peer.snapshot['docState'] as String),
      );
      expect(c.blocks.last.delta!.toPlainText(), '只读订阅内容');
      expect(c.canWrite, isFalse);
      expect(c.editor.editable, isFalse);
      await c.close();
      await peer.close();
    },
  );

  test(
    'read-only remote projection retains local guard and original undo ownership',
    () async {
      final core = NativeDocumentCore();
      final store = _Memory();
      final a = await SmartDocumentController.open(
        core: core,
        store: store,
        objectId: '9ac3ad58-105c-4cb8-80da-5912b95f34a1',
      );
      await a.editor.apply(
        a.editor.transaction..insertText(a.blocks.first, 0, '本地😀'),
      );
      final b = await SmartDocumentController.open(
        core: core,
        store: _Memory(),
        objectId: a.objectId,
        initialDocState: a.snapshot['docState'] as String,
      );
      a.editor.selection = Selection.collapsed(Position(path: [0], offset: 2));
      a.acceptRealtimeAccess(canRead: true, canWrite: false, reason: 'denied');
      expect(a.canWrite, isFalse);
      await b.editor.apply(
        b.editor.transaction..insertText(b.blocks.first, 0, '远端'),
      );
      final epoch = a.localMutationEpoch;
      await a.applyRealtimeUpdate(
        base64Decode(b.snapshot['docState'] as String),
      );
      expect(a.blocks.first.delta!.toPlainText(), '远端本地😀');
      expect(
        a.editor.selection!.start.offset,
        4,
        reason: 'Local caret follows the same Y.Text identity',
      );
      expect(a.editor.editable, isFalse);
      expect(
        a.localMutationEpoch,
        epoch,
        reason: 'Remote updates are not local edits',
      );
      await a.editor.apply(
        a.editor.transaction..insertText(a.blocks.first, 0, '禁止'),
      );
      expect(a.blocks.first.delta!.toPlainText(), '远端本地😀');
      a.acceptRealtimeAccess(canRead: true, canWrite: true, reason: 'denied');
      await a.history();
      expect(
        a.blocks.first.delta!.toPlainText(),
        '远端',
        reason: 'Undo only removes own origin',
      );
      await a.close();
      await b.close();
    },
  );
  test(
    'pending local changes persist across reopen; access denial cannot be cleared by pause',
    () async {
      final core = NativeDocumentCore(), store = _Memory();
      var c = await SmartDocumentController.open(
        core: core,
        store: store,
        objectId: '9ac3ad58-105c-4cb8-80da-5912b95f34a2',
      );
      await c.insertParagraph('离线修改');
      expect(c.hasPendingLocalChanges, isTrue);
      await c.close();
      c = await SmartDocumentController.open(
        core: core,
        store: store,
        objectId: c.objectId,
      );
      expect(c.hasPendingLocalChanges, isTrue);
      c.acceptRealtimeAccess(canRead: false, canWrite: false, reason: 'denied');
      c.pauseCollaboration(true);
      c.pauseCollaboration(false);
      expect(c.canRead, isFalse);
      expect(c.canWrite, isFalse);
      expect(c.blocks.last.delta!.toPlainText(), '离线修改');
      c.acceptRealtimeAccess(
        canRead: false,
        canWrite: false,
        reason: 'deleted',
      );
      c.acceptRealtimeAccess(canRead: true, canWrite: true, reason: 'denied');
      expect(
        c.canWrite,
        isFalse,
        reason: 'Tombstone is terminal for this session',
      );
      await c.close();
    },
  );
  test(
    'failed close keeps a usable session; concurrent retries close only once',
    () async {
      final core = NativeDocumentCore(), store = _Memory();
      final c = await SmartDocumentController.open(
        core: core,
        store: store,
        objectId: '9ac3ad58-105c-4cb8-80da-5912b95f34a3',
      );
      store.fail = true;
      await c.editor.apply(
        c.editor.transaction..insertText(c.blocks.first, 0, '未丢失'),
      );
      await expectLater(c.close(), throwsStateError);
      expect(c.canWrite, isTrue);
      store.fail = false;
      await c.editor.apply(
        c.editor.transaction..insertText(c.blocks.first, 3, '😀'),
      );
      await Future.wait([c.close(), c.close()]);
      expect(c.canWrite, isFalse);
      expect(store.value!['pendingLocalChanges'], isTrue);
    },
  );
}
