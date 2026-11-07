import 'dart:convert';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';

class _Memory implements DocumentStore {
  Map<String, dynamic>? value;
  @override
  Future<Map<String, dynamic>?> read() async => value;
  @override
  Future<void> write(Map<String, dynamic> v) async {
    value = v;
  }
}

Widget _app(SmartDocumentController c) => MaterialApp(
  localizationsDelegates: [AppFlowyEditorLocalizations.delegate],
  supportedLocales: AppFlowyEditorLocalizations.delegate.supportedLocales,
  home: Scaffold(
    body: SmartDocumentView(controller: c, title: '智能文档'),
  ),
);

void main() {
  test(
    'outline rejects forged hierarchy, duplicate identity and unsupported query version',
    () {
      Map<String, dynamic> entry(
        String id,
        int level,
        int depth,
        String? parent,
      ) => {
        'blockId': id,
        'level': level,
        'depth': depth,
        'parentId': parent,
        'text': '标题',
        'truncated': false,
      };
      Map<String, dynamic> query(List<Map<String, dynamic>> rows) => {
        'profile': 'muse.document.outline/1',
        'ready': true,
        'entries': rows,
      };
      expect(
        DocumentOutline.decode(
          'doc',
          query([entry('a', 1, 0, null), entry('b', 3, 1, 'a')]),
        ).ready,
        isTrue,
      );
      expect(
        DocumentOutline.decode(
          'doc',
          query([entry('a', 1, 0, null), entry('b', 3, 0, null)]),
        ).ready,
        isFalse,
      );
      expect(
        DocumentOutline.decode(
          'doc',
          query([entry('a', 1, 0, null), entry('a', 2, 1, 'a')]),
        ).ready,
        isFalse,
      );
      expect(
        DocumentOutline.decode('doc', {
          'profile': 'future',
          'ready': true,
          'entries': [],
        }).ready,
        isFalse,
      );
    },
  );
  testWidgets(
    'outline survives peer prefix insertion, navigates virtualized stable heading and leaves history untouched',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1100, 900);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetPhysicalSize);
      final store = _Memory();
      final c = (await t.runAsync(
        () => SmartDocumentController.open(
          core: NativeDocumentCore(),
          store: store,
          objectId: '041c01d0-831a-408a-b8fa-190d40dd9e19',
        ),
      ))!;
      final tx = c.editor.transaction;
      final head = headingNode(level: 1, text: '起点');
      final child = headingNode(level: 3, text: '远处😀');
      tx.insertNodes(
        [1],
        [
          head,
          ...List.generate(40, (i) => paragraphNode(text: '第 $i 段，正文保持原文档模型。')),
          child,
          ...List.generate(30, (i) => paragraphNode(text: '后续 $i 段正文')),
        ],
        deepCopy: false,
      );
      await t.runAsync(() async {
        await c.editor.apply(tx);
        await c.flush();
      });
      final ref = c.outline.entries.last.reference;
      final peer = (await t.runAsync(
        () => SmartDocumentController.open(
          core: NativeDocumentCore(),
          store: _Memory(),
          objectId: c.objectId,
          initialDocState: c.snapshot['docState'] as String,
        ),
      ))!;
      await t.runAsync(() async {
        await peer.editor.apply(
          peer.editor.transaction
            ..insertNode([0], paragraphNode(text: '协作者插入前缀'), deepCopy: false),
        );
        await peer.flush();
        await c.applyRealtimeUpdate(
          base64Decode(peer.snapshot['docState'] as String),
        );
      });
      expect(c.outline.entries.last.reference, ref);
      final before = c.snapshot['docState'],
          epoch = c.localMutationEpoch,
          undo = c.canUndo;
      await t.pumpWidget(_app(c));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('smart-document.outline.toggle')));
      await t.pumpAndSettle();
      final fold = find.byKey(
        ValueKey('smart-document.outline.fold.${head.id}'),
      );
      await t.tap(fold);
      await t.pumpAndSettle();
      expect(
        find.byKey(ValueKey('smart-document.outline.entry.${child.id}')),
        findsNothing,
      );
      await t.tap(fold);
      await t.pumpAndSettle();
      await t.tap(
        find.byKey(ValueKey('smart-document.outline.entry.${child.id}')),
      );
      await t.pumpAndSettle();
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await t.pumpAndSettle();
      expect(c.resolveBlock(ref)!.key.currentContext, isNotNull);
      final box =
          c.resolveBlock(ref)!.key.currentContext!.findRenderObject()!
              as RenderBox;
      expect(box.attached, isTrue);
      final target = box.localToGlobal(Offset.zero) & box.size;
      expect(target.top, greaterThanOrEqualTo(90));
      expect(target.top, lessThan(600));
      expect(c.editor.selection, isNull);
      expect(c.snapshot['docState'], before);
      expect(c.localMutationEpoch, epoch);
      expect(c.canUndo, undo);
      expect(t.takeException(), isNull);
      // The same local collapsed IDs survive desktop/mobile/desktop layout swaps.
      await t.tap(fold);
      await t.pumpAndSettle();
      t.view.physicalSize = const Size(390, 844);
      await t.pumpAndSettle();
      await t.tap(find.text('目录').last);
      await t.pumpAndSettle();
      expect(
        find.byKey(ValueKey('smart-document.outline.entry.${child.id}')),
        findsNothing,
      );
      expect(c.editor.editable, isFalse);
      expect(t.testTextInput.isVisible, isFalse);
      t.view.physicalSize = const Size(900, 800);
      await t.pumpAndSettle();
      expect(
        find.byKey(ValueKey('smart-document.outline.entry.${child.id}')),
        findsNothing,
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump();
      await t.runAsync(() async {
        await peer.close();
        await c.close();
      });
    },
  );
  testWidgets(
    'readonly nested heading navigation uses original list offset and never starts IME',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1100, 900);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetPhysicalSize);
      final core = NativeDocumentCore();
      const id = '041c01d0-831a-408a-b8fa-190d40dd9e20';
      final seed = (await t.runAsync(
        () => SmartDocumentController.open(
          core: core,
          store: _Memory(),
          objectId: id,
        ),
      ))!;
      final heading = headingNode(level: 2, text: '列表中的标题');
      await t.runAsync(() async {
        await seed.editor.apply(
          seed.editor.transaction..insertNodes(
            [1],
            [
              bulletedListNode(
                text: '列表',
                children: [
                  ...List.generate(40, (i) => paragraphNode(text: '列表子段落 $i')),
                  heading,
                  ...List.generate(30, (i) => paragraphNode(text: '尾部子段落 $i')),
                ],
              ),
            ],
            deepCopy: false,
          ),
        );
        await seed.flush();
      });
      final c = (await t.runAsync(
        () => SmartDocumentController.open(
          core: core,
          store: _Memory(),
          objectId: id,
          initialDocState: seed.snapshot['docState'] as String,
          editable: false,
        ),
      ))!;
      await t.pumpWidget(_app(c));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('smart-document.outline.toggle')));
      await t.pumpAndSettle();
      final coordinator = t
          .widget<DocumentOutlineView>(find.byType(DocumentOutlineView))
          .coordinator;
      final ref = c.outline.entries.single.reference;
      final before = c.snapshot['docState'];
      await t.tap(
        find.byKey(ValueKey('smart-document.outline.entry.${heading.id}')),
      );
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await t.pumpAndSettle();
      final box =
          c.resolveBlock(ref)!.key.currentContext!.findRenderObject()!
              as RenderBox;
      final y = box.localToGlobal(Offset.zero).dy;
      expect(y, greaterThanOrEqualTo(90));
      expect(y, lessThan(600));
      expect(coordinator.activeId, heading.id);
      expect(c.editor.selection, isNull);
      expect(t.testTextInput.isVisible, isFalse);
      expect(c.canWrite, isFalse);
      expect(c.snapshot['docState'], before);
      expect(
        await coordinator.navigate(
          DocumentBlockReference(objectId: 'foreign', blockId: heading.id),
        ),
        isFalse,
      );
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump();
      expect(await coordinator.navigate(ref), isFalse);
      expect(t.takeException(), isNull);
      await t.runAsync(() async {
        await c.close();
        await seed.close();
      });
    },
  );
}
