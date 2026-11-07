import 'dart:io';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';
import 'package:openmuse_smart_document/src/editor_components.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'table insertion uses a stable anchor and preserves rich cell identities on reopen/delete/undo',
    () async {
      final dir = await Directory.systemTemp.createTemp('smart-table-');
      final store = FileDocumentStore(File('${dir.path}/document.json'));
      const object = '041c01d0-831a-408a-b8fa-190d40dd9e92';
      var c = await SmartDocumentController.open(
        core: NativeDocumentCore(),
        store: store,
        objectId: object,
      );
      c.editor.selection = Selection.collapsed(Position(path: [0]));
      final anchor = c.insertionAnchor!;
      await c.editor.apply(
        c.editor.transaction
          ..insertNode([0], paragraphNode(text: '前置段落'), deepCopy: false),
      );
      final ref = await c.insertTable(rows: 3, columns: 2, after: anchor);
      final table = c.resolveBlock(ref)!;
      expect(table.path, [2]);
      expect(table.children, hasLength(6));
      final cell = table.children.first.children.first;
      final id = cell.id;
      await c.editor.apply(
        c.editor.transaction
          ..insertText(cell, 0, '单元格😀\n第二行', attributes: {'bold': true}),
      );
      await c.flush();
      await expectLater(
        c.insertTable(rows: 0),
        throwsA(isA<SmartDocumentFailure>()),
      );
      await c.close();
      c = await SmartDocumentController.open(
        core: NativeDocumentCore(),
        store: store,
        objectId: object,
      );
      expect(c.resolveBlock(ref)!.children.first.children.first.id, id);
      expect(
        c.resolveBlock(ref)!.children.first.children.first.delta!.toPlainText(),
        '单元格😀\n第二行',
      );
      expect(
        c
            .resolveBlock(ref)!
            .children
            .first
            .children
            .first
            .delta!
            .toJson()
            .first['attributes'],
        containsPair('bold', true),
      );
      await c.deleteTable(ref);
      expect(c.resolveBlock(ref), isNull);
      await c.history();
      expect(c.resolveBlock(ref)!.children.first.children.first.id, id);
      await c.close();
      await dir.delete(recursive: true);
    },
  );

  test(
    'table command guards preserve boundaries and hardware Enter inserts a literal line break',
    () async {
      final dir = await Directory.systemTemp.createTemp('smart-table-keys-');
      final c = await SmartDocumentController.open(
        core: NativeDocumentCore(),
        store: FileDocumentStore(File('${dir.path}/doc.json')),
        objectId: '041c01d0-831a-408a-b8fa-190d40dd9e93',
      );
      final ref = await c.insertTable();
      final cell = c.resolveBlock(ref)!.children.first.children.first;
      final events = smartDocumentCommandShortcuts();
      c.editor.selection = Selection.collapsed(Position(path: cell.path));
      expect(
        events
            .firstWhere((e) => e.key == 'muse-table-boundary-backspace')
            .handler(c.editor),
        KeyEventResult.handled,
      );
      expect(
        events
            .firstWhere((e) => e.key == 'muse-table-boundary-delete')
            .handler(c.editor),
        KeyEventResult.handled,
      );
      expect(events.first.handler(c.editor), KeyEventResult.handled);
      await Future<void>.delayed(Duration.zero);
      await c.flush();
      expect(cell.delta!.toPlainText(), '\n');
      expect(c.resolveBlock(ref)!.children, hasLength(4));
      expect(c.failure, isNull);
      await c.close();
      await dir.delete(recursive: true);
    },
  );

  testWidgets(
    'table renderer is read-only during layout at mobile and desktop widths',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('smart-table-ui-'),
      ))!;
      final c = (await tester.runAsync(
        () => SmartDocumentController.open(
          core: NativeDocumentCore(),
          store: FileDocumentStore(File('${dir.path}/doc.json')),
          objectId: '041c01d0-831a-408a-b8fa-190d40dd9e94',
        ),
      ))!;
      final ref = (await tester.runAsync(
        () => c.insertTable(rows: 2, columns: 3),
      ))!;
      final cell = c.resolveBlock(ref)!.children.first.children.first;
      await tester.runAsync(
        () => c.editor.apply(
          c.editor.transaction..insertText(cell, 0, '真实单元格😀\n第二行'),
        ),
      );
      final revision = c.revision;
      for (final width in [320.0, 390.0, 1100.0]) {
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: [AppFlowyEditorLocalizations.delegate],
            supportedLocales:
                AppFlowyEditorLocalizations.delegate.supportedLocales,
            home: Scaffold(
              body: SmartDocumentView(controller: c, title: '表格文档'),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(AppFlowyRichText), findsNWidgets(7));
        expect(
          c.revision,
          revision,
          reason: 'Layout must not persist cell height',
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(c.close);
      await tester.runAsync(() => dir.delete(recursive: true));
    },
  );
}
