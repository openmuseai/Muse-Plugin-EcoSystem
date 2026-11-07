@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';
import 'package:openmuse_smart_document/browser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('actual browser WASM core and IndexedDB survive close/reopen', () async {
    final core = await WasmDocumentCore.load(
      assetBase: Uri.parse(
        'http://127.0.0.1:18080/assets/packages/openmuse_smart_document/assets/wasm/',
      ),
    );
    const id = 'a18704b8-7290-4002-b31c-67f1b4cad1ae';
    final namespace = 'web-core-${DateTime.now().microsecondsSinceEpoch}';
    final store = IndexedDbDocumentStore(namespace: namespace, objectId: id);
    var c = await SmartDocumentController.open(
      core: core,
      store: store,
      objectId: id,
    );
    expect(
      c.snapshot['collabRevision'],
      'e59260e524f33104b0ddcd6bb8f6218cad0f7e18',
    );
    final stable = c.blocks.first.id;
    final transaction = c.editor.transaction
      ..insertText(c.blocks.first, 0, '浏览器同一核心😀');
    await c.editor.apply(transaction);
    c.editor.selection = Selection.single(
      path: [0],
      startOffset: 0,
      endOffset: 2,
    );
    await c.convertSelection('heading', level: 6);
    expect(c.blocks.first.id, stable);
    expect(c.blocks.first.type, 'heading');
    await c.flush();
    expect(c.localSave, LocalSaveState.durable);
    await c.close();
    c = await SmartDocumentController.open(
      core: core,
      store: IndexedDbDocumentStore(namespace: namespace, objectId: id),
      objectId: id,
    );
    expect(c.blocks.first.id, stable);
    expect(c.blocks.first.type, 'heading');
    expect(c.blocks.first.attributes['level'], 6);
    expect(c.blocks.first.delta!.toPlainText(), '浏览器同一核心😀');
    await c.history(); // Reopen deliberately starts a fresh local undo stack.
    expect(c.blocks.first.delta!.toPlainText(), '浏览器同一核心😀');
    await c.close();
    final other = IndexedDbDocumentStore(
      namespace: '$namespace-other-account',
      objectId: id,
    );
    expect(await other.read(), isNull);
  });
}
