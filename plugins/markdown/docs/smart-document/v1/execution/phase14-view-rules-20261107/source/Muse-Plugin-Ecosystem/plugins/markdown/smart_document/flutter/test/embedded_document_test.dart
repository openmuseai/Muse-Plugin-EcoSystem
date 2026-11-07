import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
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

ResourceEmbedTarget _target() => ResourceEmbedTarget(
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
  selector: {
    'objectId': '143197bf-8e44-4c1c-a084-d28bd58087a7',
    'viewId': 'view-1',
  },
);
void main() {
  test(
    'original inline database reference resolves stable anchor and survives remove undo/reopen',
    () async {
      final store = _Memory();
      var c = await SmartDocumentController.open(
        core: NativeDocumentCore(),
        store: store,
        objectId: '769c5ff4-0f5a-45da-9644-3e5c549afabc',
      );
      c.editor.selection = Selection.collapsed(Position(path: [0]));
      final anchor = c.insertionAnchor;
      await c.editor.apply(
        c.editor.transaction
          ..insertNode([0], paragraphNode(text: '并发前置'), deepCopy: false),
      );
      final ref = await c.insertDatabaseView(_target(), after: anchor);
      expect(c.resolveBlock(ref)!.path, [2]);
      expect(c.resolveBlock(ref)!.attributes['view_id'], 'view-1');
      expect(c.resolveBlock(ref)!.delta, isNull);
      await c.removeDatabaseView(ref);
      expect(c.resolveBlock(ref), isNull);
      await c.history();
      expect(c.resolveBlock(ref)!.attributes['muse_embed'], _target().toJson());
      await c.close();
      c = await SmartDocumentController.open(
        core: NativeDocumentCore(),
        store: store,
        objectId: '769c5ff4-0f5a-45da-9644-3e5c549afabc',
      );
      expect(c.resolveBlock(ref)!.attributes['muse_embed'], _target().toJson());
      await c.close();
    },
  );
  for (final width in [390.0, 1100.0]) {
    testWidgets(
      'embedded surface respects reading policy and unknown reference at $width',
      (t) async {
        t.view.physicalSize = Size(width, 950);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final c = await SmartDocumentController.open(
          core: NativeDocumentCore(),
          store: _Memory(),
          objectId: '769c5ff4-0f5a-45da-9644-3e5c549afabc',
        );
        await c.insertDatabaseView(_target());
        ResourceEmbedPolicy? policy;
        Widget app(ResourceEmbedHost? host) => MaterialApp(
          localizationsDelegates: [AppFlowyEditorLocalizations.delegate],
          supportedLocales:
              AppFlowyEditorLocalizations.delegate.supportedLocales,
          home: Scaffold(
            body: SmartDocumentView(
              controller: c,
              title: '同屏数据库',
              embeds: host,
            ),
          ),
        );
        await t.pumpWidget(
          app(
            ResourceEmbedHost(
              build: (_, target, p) {
                policy = p;
                expect(target.key, _target().key);
                return const Text('独立插件表格');
              },
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('独立插件表格'), findsOneWidget);
        expect(policy!.allowEditing, width >= 700);
        await t.pumpWidget(app(null));
        await t.pumpAndSettle();
        expect(find.text('数据库引用暂不可用，原引用保留'), findsOneWidget);
        expect(c.blocks.last.attributes['muse_embed'], _target().toJson());
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await t.runAsync(c.close);
      },
    );
  }
}
