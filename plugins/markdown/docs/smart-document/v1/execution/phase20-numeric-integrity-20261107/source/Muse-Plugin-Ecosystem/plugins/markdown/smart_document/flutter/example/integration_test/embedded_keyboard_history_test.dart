import 'dart:convert';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';

class _DocStore implements DocumentStore {
  Map<String, dynamic>? value;
  @override
  Future<Map<String, dynamic>?> read() async => value;
  @override
  Future<void> write(Map<String, dynamic> v) async => value = v;
}

class _DataStore implements SnapshotStore {
  Map<String, dynamic>? value;
  @override
  Future<Map<String, dynamic>?> read() async => value;
  @override
  Future<void> write(Map<String, dynamic> v) async => value = v;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final modifier in [LogicalKeyboardKey.metaLeft]) {
    testWidgets(
      'embedded keyboard history owns child, modal draft and readonly boundary: $modifier',
      (t) async {
        t.view.physicalSize = const Size(1200, 1000);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final doc = await SmartDocumentController.open(
          core: NativeDocumentCore(),
          store: _DocStore(),
          objectId: '5f552c71-93cc-41a5-8dda-691de75acb4f',
        );
        final data = await DatasetController.open(
          core: NativeDatasetCore(),
          store: _DataStore(),
          objectId: '46b82596-7aa4-4c62-957f-975c36baaf62',
          syncInterval: null,
        );
        final target = ResourceEmbedTarget(
          reference: ResourceReference(
            identity: ResourceIdentity(
              scope: 'test',
              source: 'local',
              workspace: 'test',
              mount: 'root',
              resource: 'dataset',
            ),
          ),
          surface: 'dataset.grid',
          selector: {'objectId': data.objectId, 'viewId': data.views.single.id},
        );
        debugPrint('KEYBOARD_STEP: locator');
        await doc.insertDatabaseView(target);
        var childEditable = true;
        Widget app() => MaterialApp(
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            AppFlowyEditorLocalizations.delegate,
          ],
          supportedLocales:
              AppFlowyEditorLocalizations.delegate.supportedLocales,
          home: Scaffold(
            body: SmartDocumentView(
              controller: doc,
              title: '嵌入编辑边界',
              embeds: ResourceEmbedHost(
                build: (_, target, policy) => DatasetSurface(
                  controller: data,
                  title: '独立数据库',
                  viewId: target.selector['viewId'],
                  embedded: true,
                  allowEditing: policy.allowEditing && childEditable,
                ),
              ),
            ),
          ),
        );
        Future<void> key({bool redo = false}) async {
          await t.sendKeyDownEvent(modifier);
          if (redo) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          await t.sendKeyEvent(LogicalKeyboardKey.keyZ);
          if (redo) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          await t.sendKeyUpEvent(modifier);
          await t.pumpAndSettle();
        }

        debugPrint('KEYBOARD_STEP: pump');
        await t.pumpWidget(app());
        await t.pumpAndSettle();
        final parentBefore = jsonEncode(doc.snapshot['data']);
        await t.tap(find.byKey(const ValueKey('dataset.add-row')));
        await t.pumpAndSettle();
        final rowId = data.views.single.rows.single.id;
        Finder cell() => find.byKey(ValueKey('dataset.cell.$rowId.title'));
        await t.tap(cell());
        await t.pumpAndSettle();
        await t.enterText(
          find.byKey(const ValueKey('dataset.cell-input')),
          '子资源原历史',
        );
        await t.tap(find.byKey(const ValueKey('dataset.cell-apply')));
        await t.pumpAndSettle();
        expect(data.views.single.rows.single.cells['title']!.value, '子资源原历史');
        debugPrint('KEYBOARD_STEP: key undo');
        await key();
        expect(data.views.single.rows.single.cells['title']!.value, isNull);
        expect(jsonEncode(doc.snapshot['data']), parentBefore);
        debugPrint('KEYBOARD_STEP: key redo');
        await key(redo: true);
        expect(data.views.single.rows.single.cells['title']!.value, '子资源原历史');
        expect(jsonEncode(doc.snapshot['data']), parentBefore);
        await t.tap(cell());
        await t.pumpAndSettle();
        await t.enterText(
          find.byKey(const ValueKey('dataset.cell-input')),
          '未提交草稿',
        );
        debugPrint('KEYBOARD_STEP: key undo');
        await key();
        expect(
          find.byKey(const ValueKey('dataset.cell-dialog')),
          findsOneWidget,
        );
        expect(data.views.single.rows.single.cells['title']!.value, '子资源原历史');
        expect(jsonEncode(doc.snapshot['data']), parentBefore);
        debugPrint('KEYBOARD_STEP: cancel');
        await t.tap(find.text('取消').last);
        await t.pumpAndSettle();
        childEditable = false;
        debugPrint('KEYBOARD_STEP: pump');
        await t.pumpWidget(app());
        await t.pumpAndSettle();
        debugPrint('KEYBOARD_STEP: readonly');
        await t.tap(find.text('独立数据库'));
        debugPrint('KEYBOARD_STEP: key undo');
        await key();
        expect(data.views.single.rows.single.cells['title']!.value, '子资源原历史');
        expect(jsonEncode(doc.snapshot['data']), parentBefore);
        // Returning to the original paragraph restores its own command handler.
        debugPrint('KEYBOARD_STEP: parent');
        await t.tap(find.byKey(doc.blocks.first.key));
        await t.pumpAndSettle();
        doc.editor.selection = Selection.collapsed(Position(path: [0]));
        await doc.editor.apply(
          doc.editor.transaction..insertText(doc.blocks.first, 0, '正文历史'),
        );
        await t.pumpAndSettle();
        debugPrint('KEYBOARD_STEP: key undo');
        await key();
        expect(doc.blocks.first.delta!.toPlainText(), '');
        expect(doc.blocks.last.type, 'grid');
        expect(data.views.single.rows.single.cells['title']!.value, '子资源原历史');
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
        debugPrint('KEYBOARD_STEP: close');
        await data.close();
        await doc.close();
        debugPrint('KEYBOARD_STEP: done');
      },
    );
  }
}
