import 'dart:convert';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';

class _Memory implements DocumentStore {
  @override
  Future<Map<String, dynamic>?> read() async => null;
  @override
  Future<void> write(Map<String, dynamic> v) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'backward cross-block anchors survive queued peer updates and clear a deleted target',
    () async {
      final core = NativeDocumentCore();
      final a = await SmartDocumentController.open(
        core: core,
        store: _Memory(),
        objectId: '9ac3ad58-105c-4cb8-80da-5912b95f34a5',
      );
      await a.editor.apply(
        a.editor.transaction..insertText(a.blocks.first, 0, '段落A😀'),
      );
      await a.insertParagraph('段落B');
      final b = await SmartDocumentController.open(
        core: core,
        store: _Memory(),
        objectId: a.objectId,
        initialDocState: a.snapshot['docState'] as String,
      );
      try {
        a.editor.selection = Selection(
          start: Position(path: [1], offset: 2),
          end: Position(path: [0], offset: 1),
        );
        await b.editor.apply(
          b.editor.transaction
            ..insertNode([0], paragraphNode(text: '前方新块'), deepCopy: false),
        );
        final first = base64Decode(b.snapshot['docState'] as String);
        await b.editor.apply(
          b.editor.transaction..insertText(b.blocks[1], 0, '前缀'),
        );
        final second = base64Decode(b.snapshot['docState'] as String);
        await Future.wait([
          a.applyRealtimeUpdate(first),
          a.applyRealtimeUpdate(second),
        ]);
        expect(
          a.editor.selection,
          Selection(
            start: Position(path: [2], offset: 2),
            end: Position(path: [1], offset: 3),
          ),
        );
        expect(
          a.localMutationEpoch,
          2,
          reason: 'Queued remote changes are not new local edits',
        );
        final deleted = b.blocks[1];
        await b.editor.apply(b.editor.transaction..deleteNode(deleted));
        await a.applyRealtimeUpdate(
          base64Decode(b.snapshot['docState'] as String),
        );
        expect(
          a.editor.selection,
          isNull,
          reason:
              'Deleted text identity cannot redirect selection into another block',
        );
        expect(a.blocks.map((n) => n.delta!.toPlainText()), ['前方新块', '段落B']);
      } finally {
        await b.close();
        await a.close();
      }
    },
  );
}
