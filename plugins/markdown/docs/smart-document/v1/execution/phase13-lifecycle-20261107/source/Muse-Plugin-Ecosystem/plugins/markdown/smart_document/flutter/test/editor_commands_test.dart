import 'dart:io';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/editor_component/service/ime/delta_input_on_insert_impl.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';
import 'package:openmuse_smart_document/src/editor_components.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Markdown block triggers keep identity and undo prefix/type atomically',
    () async {
      final dir = await Directory.systemTemp.createTemp('smartdoc-markdown-');
      for (final (prefix, type, trigger) in const [
        ('######', 'heading', ' '),
        ('-', 'bulleted_list', ' '),
        ('3.', 'numbered_list', ' '),
        ('[x]', 'todo_list', ' '),
        ('>', 'quote', ' '),
        ('```dart', 'code', '\n'),
      ]) {
        final c = await SmartDocumentController.open(
          core: NativeDocumentCore(),
          store: FileDocumentStore(File('${dir.path}/${type}.json')),
          objectId: '041c01d0-831a-408a-b8fa-190d40dd9e83',
        );
        final id = c.blocks.first.id;
        await c.editor.apply(
          c.editor.transaction..insertText(c.blocks.first, 0, prefix),
        );
        c.editor.selection = Selection.collapsed(
          Position(path: [0], offset: prefix.length),
        );
        await onInsert(
          TextEditingDeltaInsertion(
            oldText: prefix,
            textInserted: trigger,
            insertionOffset: prefix.length,
            selection: TextSelection.collapsed(offset: prefix.length + 1),
            composing: TextRange.empty,
          ),
          c.editor,
          smartDocumentCharacterShortcuts(c),
        );
        expect(c.blocks.first.id, id);
        expect(c.blocks.first.type, type);
        expect(c.blocks.first.delta!.toPlainText(), '');
        if (type == 'heading') expect(c.blocks.first.attributes['level'], 6);
        if (type == 'todo_list')
          expect(c.blocks.first.attributes['checked'], true);
        if (type == 'numbered_list')
          expect(c.blocks.first.attributes['number'], 3);
        if (type == 'code')
          expect(c.blocks.first.attributes['language'], 'dart');
        await c.history();
        expect(c.blocks.first.id, id);
        expect(c.blocks.first.type, 'paragraph');
        expect(c.blocks.first.delta!.toPlainText(), prefix);
        await c.history(redo: true);
        expect(c.blocks.first.type, type);
        expect(c.blocks.first.delta!.toPlainText(), '');
        await c.close();
      }
      await dir.delete(recursive: true);
    },
  );
  test(
    'code IME input keeps Markdown and newline literal through a file reopen',
    () async {
      final dir = await Directory.systemTemp.createTemp('smartdoc-code-');
      final store = FileDocumentStore(File('${dir.path}/code.json'));
      var c = await SmartDocumentController.open(
        core: NativeDocumentCore(),
        store: store,
        objectId: '041c01d0-831a-408a-b8fa-190d40dd9e84',
      );
      c.editor.selection = Selection.collapsed(Position(path: [0]));
      await c.convertSelection('code');
      final id = c.blocks.first.id;
      for (final value in ['#', ' ', '\n', 'print("智能😀")']) {
        final text = c.blocks.first.delta!.toPlainText();
        c.editor.selection = Selection.collapsed(
          Position(path: [0], offset: text.length),
        );
        await onInsert(
          TextEditingDeltaInsertion(
            oldText: text,
            textInserted: value,
            insertionOffset: text.length,
            selection: TextSelection.collapsed(
              offset: text.length + value.length,
            ),
            composing: TextRange.empty,
          ),
          c.editor,
          smartDocumentCharacterShortcuts(c),
        );
      }
      expect(c.blocks.length, 1);
      expect(c.blocks.first.type, 'code');
      expect(c.blocks.first.delta!.toPlainText(), '# \nprint("智能😀")');
      await c.close();
      c = await SmartDocumentController.open(
        core: NativeDocumentCore(),
        store: store,
        objectId: '041c01d0-831a-408a-b8fa-190d40dd9e84',
      );
      expect(c.blocks.first.id, id);
      expect(c.blocks.first.delta!.toPlainText(), '# \nprint("智能😀")');
      await c.close();
      await dir.delete(recursive: true);
    },
  );
}
