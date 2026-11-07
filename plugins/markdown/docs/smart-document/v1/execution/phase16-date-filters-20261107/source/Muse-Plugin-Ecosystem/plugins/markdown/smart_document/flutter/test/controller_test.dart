import 'dart:io';
import 'dart:typed_data';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'incompatible engine binding is rejected before reading storage or network',
    () async {
      final provider = _IncompatibleProvider();
      await expectLater(
        SmartDocumentController.open(
          core: NativeDocumentCore(),
          store: _UnreadableStore(),
          provider: provider,
          objectId: '041c01d0-831a-408a-b8fa-190d40dd9e74',
        ),
        throwsA(
          isA<SmartDocumentFailure>().having(
            (e) => e.code,
            'code',
            'INCOMPATIBLE_COLLABORATION_BINDING',
          ),
        ),
      );
      expect(provider.closed, isTrue);
    },
  );
  test(
    'AppFlowy transactions reach Rust and survive a real file reopen',
    () async {
      final dir = await Directory.systemTemp.createTemp('muse-smartdoc-');
      const id = '041c01d0-831a-408a-b8fa-190d40dd9e70';
      final file = File('${dir.path}/document.json');
      final core = NativeDocumentCore();
      var c = await SmartDocumentController.open(
        core: core,
        store: FileDocumentStore(file),
        objectId: id,
      );
      final firstId = c.blocks.first.id;
      final t = c.editor.transaction
        ..insertText(c.blocks.first, 0, '中文😀 collaboration');
      await c.editor.apply(t);
      await c.flush();
      expect(c.failure, isNull, reason: 'text transaction');
      final format = c.editor.transaction
        ..formatText(c.blocks.first, 0, 2, {'bold': true});
      await c.editor.apply(format);
      await c.flush();
      expect(c.failure, isNull, reason: 'format transaction');
      await c.insertParagraph('第二段');
      expect(c.localSave, LocalSaveState.durable);
      expect(c.blocks.first.delta!.toPlainText(), '中文😀 collaboration');
      expect(c.blocks.first.delta!.toJson().first['attributes'], {
        'bold': true,
      });
      await c.close();
      c = await SmartDocumentController.open(
        core: core,
        store: FileDocumentStore(file),
        objectId: id,
      );
      expect(c.blocks.first.id, firstId);
      expect(c.blocks.last.delta!.toPlainText(), '第二段');
      expect(c.blocks.first.delta!.toPlainText(), '中文😀 collaboration');
      await c.close();
      await dir.delete(recursive: true);
    },
  );
  test(
    'full block attribute updates preserve text in the CRDT and on reopen',
    () async {
      final dir = await Directory.systemTemp.createTemp('muse-smartdoc-align-');
      const id = '041c01d0-831a-408a-b8fa-190d40dd9e79';
      final store = FileDocumentStore(File('${dir.path}/doc.json'));
      final core = NativeDocumentCore();
      var c = await SmartDocumentController.open(
        core: core,
        store: store,
        objectId: id,
      );
      const text = '对齐不能复制正文😀';
      await c.editor.apply(
        c.editor.transaction..insertText(c.blocks.first, 0, text),
      );
      await c.editor.apply(
        c.editor.transaction..formatText(c.blocks.first, 0, 2, {'bold': true}),
      );
      c.editor.selection = Selection.single(
        path: [0],
        startOffset: 0,
        endOffset: 2,
      );
      // updateNode passes all attributes; its inverse omits the unchanged delta.
      await c.editor.updateNode(
        c.editor.selection,
        (node) =>
            node.copyWith(attributes: {...node.attributes, 'align': 'center'}),
      );
      await c.flush();
      expect(c.failure, isNull);
      await c.close();
      c = await SmartDocumentController.open(
        core: core,
        store: store,
        objectId: id,
      );
      expect(c.blocks.first.delta!.toPlainText(), text);
      expect(c.blocks.first.attributes['align'], 'center');
      expect(
        c.blocks.first.delta!.toJson().first['attributes'],
        containsPair('bold', true),
      );
      await c.close();
      await dir.delete(recursive: true);
    },
  );
  test(
    'stable type conversion keeps references, Y.Text and children across undo/reopen',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'muse-smartdoc-identity-',
      );
      const object = '041c01d0-831a-408a-b8fa-190d40dd9e80';
      final store = FileDocumentStore(File('${dir.path}/doc.json'));
      final core = NativeDocumentCore();
      var c = await SmartDocumentController.open(
        core: core,
        store: store,
        objectId: object,
      );
      await c.editor.apply(
        c.editor.transaction..insertText(c.blocks.first, 0, '稳定正文😀'),
      );
      await c.editor.apply(
        c.editor.transaction..formatText(c.blocks.first, 0, 2, {'bold': true}),
      );
      await c.editor.apply(
        c.editor.transaction
          ..insertNode([0, 0], paragraphNode(text: '子块'), deepCopy: false),
      );
      c.editor.selection = Selection.single(
        path: [0],
        startOffset: 0,
        endOffset: 2,
      );
      final ref = c.referencesForSelection().first;
      final child = c.blocks.first.children.first.id;
      final textId =
          (c.snapshot['data']['blocks'][ref.blockId] as Map)['external_id'];
      await c.convertSelection('heading', level: 6, attachTextService: false);
      expect(c.blocks.first.id, ref.blockId);
      expect(c.blocks.first.type, 'heading');
      expect(c.blocks.first.children.first.id, child);
      expect(
        c.editor.selection,
        Selection.single(path: [0], startOffset: 0, endOffset: 2),
      );
      expect(
        (c.snapshot['data']['blocks'][ref.blockId] as Map)['external_id'],
        textId,
      );
      await c.history();
      expect(c.resolveBlock(ref)!.type, 'paragraph');
      await c.history(redo: true);
      expect(c.resolveBlock(ref)!.type, 'heading');
      await c.close();
      c = await SmartDocumentController.open(
        core: core,
        store: store,
        objectId: object,
      );
      expect(c.resolveBlock(ref)!.delta!.toPlainText(), '稳定正文😀');
      expect(c.resolveBlock(ref)!.children.first.id, child);
      expect(
        c.resolveBlock(ref)!.delta!.toJson().first['attributes'],
        containsPair('bold', true),
      );
      await c.close();
      await dir.delete(recursive: true);
    },
  );
  test(
    'captured block references survive sibling insertions and reject stale/cross-object targets',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'muse-smartdoc-reference-',
      );
      final c = await SmartDocumentController.open(
        core: NativeDocumentCore(),
        store: FileDocumentStore(File('${dir.path}/doc.json')),
        objectId: '041c01d0-831a-408a-b8fa-190d40dd9e81',
      );
      c.editor.selection = Selection.collapsed(Position(path: [0]));
      final ref = c.referencesForSelection().first;
      await c.editor.apply(
        c.editor.transaction
          ..insertNode([0], paragraphNode(text: '新前置段落'), deepCopy: false),
      );
      await c.convertBlocks([ref], 'quote');
      expect(c.blocks.first.type, 'paragraph');
      expect(c.blocks.first.delta!.toPlainText(), '新前置段落');
      expect(c.resolveBlock(ref)!.path, [1]);
      expect(c.resolveBlock(ref)!.type, 'quote');
      await expectLater(
        c.convertBlocks([
          DocumentBlockReference(
            objectId: 'other-object',
            blockId: ref.blockId,
          ),
        ], 'heading'),
        throwsA(
          isA<SmartDocumentFailure>().having(
            (e) => e.code,
            'code',
            'REFERENCE_OBJECT_MISMATCH',
          ),
        ),
      );
      await c.editor.apply(
        c.editor.transaction..deleteNode(c.resolveBlock(ref)!),
      );
      await expectLater(
        c.convertBlocks([ref], 'heading'),
        throwsA(
          isA<SmartDocumentFailure>().having(
            (e) => e.code,
            'code',
            'TARGET_MISSING',
          ),
        ),
      );
      expect(c.canWrite, isTrue);
      expect(c.failure, isNull);
      expect(c.blocks.first.type, 'paragraph');
      await c.close();
      await dir.delete(recursive: true);
    },
  );
  test(
    'readonly refuses local mutation without changing stored state',
    () async {
      final dir = await Directory.systemTemp.createTemp('muse-smartdoc-view-');
      final c = await SmartDocumentController.open(
        core: NativeDocumentCore(),
        store: FileDocumentStore(File('${dir.path}/doc.json')),
        objectId: '041c01d0-831a-408a-b8fa-190d40dd9e71',
        editable: false,
      );
      await expectLater(
        c.insertParagraph('forbidden'),
        throwsA(isA<SmartDocumentFailure>()),
      );
      expect(c.blocks.length, 1);
      await c.close();
      await dir.delete(recursive: true);
    },
  );
  test(
    'failed durable write remains visible and recovers without discarding the edit',
    () async {
      final dir = await Directory.systemTemp.createTemp('muse-smartdoc-disk-');
      final store = _FailingStore(
        FileDocumentStore(File('${dir.path}/doc.json')),
      );
      final c = await SmartDocumentController.open(
        core: NativeDocumentCore(),
        store: store,
        objectId: '041c01d0-831a-408a-b8fa-190d40dd9e72',
      );
      store.fail = true;
      final t = c.editor.transaction..insertText(c.blocks.first, 0, '保留未持久修改');
      await c.editor.apply(t);
      await expectLater(c.flush(), throwsA(isA<FileSystemException>()));
      expect(c.localSave, LocalSaveState.failed);
      expect(c.blocks.first.delta!.toPlainText(), '保留未持久修改');
      store.fail = false;
      await c.flush();
      expect(c.localSave, LocalSaveState.durable);
      await c.close();
      await dir.delete(recursive: true);
    },
  );
  test(
    'rejected editor command blocks closing until explicitly discarded',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'muse-smartdoc-rejected-',
      );
      final c = await SmartDocumentController.open(
        core: NativeDocumentCore(),
        store: FileDocumentStore(File('${dir.path}/doc.json')),
        objectId: '041c01d0-831a-408a-b8fa-190d40dd9e73',
      );
      final transaction = c.editor.transaction
        ..insertNode([1], Node(type: 'unsupported-element'));
      await c.editor.apply(transaction);
      expect(c.contentFailure, isNotNull);
      await expectLater(c.flush(), throwsA(isA<SmartDocumentFailure>()));
      await expectLater(c.close(), throwsA(isA<SmartDocumentFailure>()));
      await c.discardRejectedOperation();
      expect(c.contentFailure, isNull);
      expect(c.blocks.length, 1);
      expect(c.editor.editable, isTrue);
      final recovery = c.editor.transaction
        ..insertText(c.blocks.first, 0, '关闭被阻止后仍可编辑');
      await c.editor.apply(recovery);
      await c.flush();
      expect(
        c.snapshot['data']['meta']['text_map'].values.join(),
        contains('关闭被阻止后仍可编辑'),
      );
      await c.close();
      await dir.delete(recursive: true);
    },
  );
  test(
    'tombstone and denied access remain read only across pause/resume and cached reopen',
    () async {
      for (final code in ['OBJECT_DELETED', 'FORBIDDEN']) {
        final dir = await Directory.systemTemp.createTemp('smartdoc-terminal-');
        final store = FileDocumentStore(File('${dir.path}/state.json'));
        const id = '041c01d0-831a-408a-b8fa-190d40dd9e75';
        final initial = await SmartDocumentController.open(
          core: NativeDocumentCore(),
          store: store,
          objectId: id,
        );
        await initial.close();
        final p = _TerminalProvider(code);
        final c = await SmartDocumentController.open(
          core: NativeDocumentCore(),
          store: store,
          objectId: id,
          provider: p,
          createRemote: true,
          syncInterval: null,
        );
        expect(c.canWrite, isFalse);
        expect(c.editor.editable, isFalse);
        expect(
          c.syncState,
          code == 'OBJECT_DELETED'
              ? DocumentSyncState.removed
              : DocumentSyncState.forbidden,
        );
        c.pauseCollaboration(true);
        c.pauseCollaboration(false);
        expect(c.canWrite, isFalse);
        await c.synchronize();
        await expectLater(c.history(), throwsA(isA<SmartDocumentFailure>()));
        expect(p.creates, 0);
        expect(p.exchanges, 0);
        await c.close();
        await dir.delete(recursive: true);
      }
    },
  );
}

final class _FailingStore implements DocumentStore {
  _FailingStore(this.inner);
  final DocumentStore inner;
  bool fail = false;
  @override
  Future<Map<String, dynamic>?> read() => inner.read();
  @override
  Future<void> write(Map<String, dynamic> snapshot) async {
    if (fail) throw const FileSystemException('injected durable write failure');
    await inner.write(snapshot);
  }
}

final class _UnreadableStore implements DocumentStore {
  @override
  Future<Map<String, dynamic>?> read() =>
      throw StateError('Binding must be checked first');
  @override
  Future<void> write(Map<String, dynamic> snapshot) =>
      throw StateError('Unexpected write');
}

final class _IncompatibleProvider implements CollaborationProvider {
  bool closed = false;
  @override
  CollaborationBinding get binding => const CollaborationBinding(
    protocol: 'appflowy.full-sync/1',
    engine: 'other/2',
    encoding: 'yrs.update-v1',
    schema: 'appflowy.document/0.2',
    epoch: 0,
  );
  @override
  void close() {
    closed = true;
  }

  @override
  Future<Uint8List?> readState(String objectId) =>
      throw StateError('Unexpected network');
  @override
  Future<void> initializeState(String objectId, Uint8List state) =>
      throw StateError('Unexpected network');
  @override
  Future<Uint8List> exchange(String objectId, Uint8List request) =>
      throw StateError('Unexpected network');
}

final class _TerminalProvider implements CollaborationProvider {
  _TerminalProvider(this.code);
  final String code;
  int creates = 0, exchanges = 0;
  @override
  CollaborationBinding get binding => smartDocumentCollaborationBinding;
  @override
  void close() {}
  @override
  Future<Uint8List?> readState(String objectId) async =>
      throw SmartDocumentFailure(code);
  @override
  Future<void> initializeState(String objectId, Uint8List state) async {
    creates++;
  }

  @override
  Future<Uint8List> exchange(String objectId, Uint8List request) async {
    exchanges++;
    throw StateError('unexpected');
  }
}
