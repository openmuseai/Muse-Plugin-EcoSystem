import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';
import 'package:muse_smart_document_stage1/main.dart';
import 'package:muse_smart_document_stage1/dataset_main.dart';
import 'package:muse_smart_document_stage1/embedded_main.dart';

class _Memory implements SnapshotStore {
  Map<String, dynamic>? value;
  @override
  Future<Map<String, dynamic>?> read() async => value;
  @override
  Future<void> write(Map<String, dynamic> v) async {
    value = v;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'public SDK document embeds independent original database with real Cloud peer and scoped undo',
    (t) async {
      final old = WidgetController.hitTestWarningShouldBeFatal;
      WidgetController.hitTestWarningShouldBeFatal = true;
      addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = old);
      final w = await EmbeddedWorkbench.open();
      await t.pumpWidget(StageOneApp(workbench: w.document));
      Future<void> until(bool Function() ready, String reason) async {
        for (var i = 0; i < 250; i++) {
          await t.pump(const Duration(milliseconds: 100));
          if (ready()) return;
        }
        fail('Embedded UI deadline: $reason');
      }

      await until(
        () => w.document.controller != null,
        'document public resource',
      );
      final doc = w.document.controller!;
      doc.pauseCollaboration(true);
      final mobile = t.view.physicalSize.width / t.view.devicePixelRatio < 700;
      if (mobile) {
        await t.tap(find.text('编辑').last);
        await t.pump(const Duration(milliseconds: 300));
      }
      // Product fixture has visible prose above the independently owned grid.
      await doc.editor.apply(
        doc.editor.transaction
          ..insertText(doc.blocks.first, 0, '项目计划｜正文与数据库同屏协作'),
      );
      await t.tap(
        find.byKey(
          ValueKey(
            mobile ? 'smart-document.mobile.insert' : 'smart-document.insert',
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.text('数据库').last);
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.byKey(const ValueKey('embed.pick-dataset')));
      await until(
        () =>
            w.dataset.controller != null &&
            doc.blocks.any((b) => b.type == 'grid'),
        'actual insertion and independent resource resolution',
      );
      final data = w.dataset.controller!;
      data.pauseCollaboration(true);
      final checks = <String>[
        'actual-desktop-or-mobile-insert-menu-and-authorized-public-sdk-resource-picker',
      ];
      final ref = doc.blocks.firstWhere((b) => b.type == 'grid');
      expect(ref.attributes['view_id'], w.target.selector['viewId']);
      expect(ref.delta, isNull);
      final before = jsonEncode(doc.snapshot['data']);
      final add = find.byKey(const ValueKey('dataset.add-row'));
      await t.ensureVisible(add);
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(add);
      await until(
        () => data.views.single.rows.length == 1,
        'embedded row creation',
      );
      final rowId = data.views.single.rows.single.id;
      final cell = find.byKey(ValueKey('dataset.cell.$rowId.title'));
      await t.ensureVisible(cell);
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(cell);
      await t.pump(const Duration(milliseconds: 300));
      await t.enterText(
        find.byKey(const ValueKey('dataset.cell-input')),
        '文档内数据库😀',
      );
      await t.tap(find.byKey(const ValueKey('dataset.cell-apply')));
      await until(
        () => data.views.single.rows.single.cells['title']!.value == '文档内数据库😀',
        'embedded field commit',
      );
      expect(jsonEncode(doc.snapshot['data']), before);
      checks.add(
        'same-screen-original-grid-cell-editor-writes-independent-row-not-parent-document',
      );
      data.pauseCollaboration(false);
      await data.synchronize();
      data.pauseCollaboration(true);
      final bob = await DatasetController.open(
        core: NativeDatasetCore(),
        store: _Memory(),
        objectId: data.objectId,
        providerFactory: DatasetWorkbench.providerFor('bob'),
        syncInterval: null,
      );
      final r = bob.views.single.rows.single,
          f = bob.views.single.columns.first;
      await bob.setCell(r, f, '协作者更新', expectedHash: r.cells[f.id]!.hash);
      await bob.synchronize();
      data.pauseCollaboration(false);
      await data.synchronize();
      data.pauseCollaboration(true);
      await until(
        () => find.text('协作者更新').evaluate().isNotEmpty,
        'peer projection in embedded grid',
      );
      checks.add(
        'real-cloud-original-database-root1-row4-peer-update-in-parent-editor',
      );
      final undo = find.byKey(const ValueKey('dataset.undo'));
      await t.ensureVisible(undo);
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(undo);
      await t.pump(const Duration(milliseconds: 300));
      expect(data.views.single.rows.single.cells['title']!.value, '协作者更新');
      expect(doc.blocks.any((b) => b.id == ref.id), isTrue);
      expect(jsonEncode(doc.snapshot['data']), before);
      checks.add(
        'child-origin-undo-preserves-peer-value-and-document-reference',
      );
      final menu = find.byKey(ValueKey('smart-document.embed-menu.${ref.id}'));
      await t.ensureVisible(menu);
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(menu);
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.text('移除引用'));
      await until(
        () => !doc.blocks.any((b) => b.id == ref.id),
        'remove locator',
      );
      await doc.history();
      await until(
        () =>
            doc.blocks.any((b) => b.id == ref.id) &&
            w.dataset.controller != null,
        'document undo restores locator',
      );
      final restored = w.dataset.controller!;
      restored.pauseCollaboration(true);
      expect(restored.views.single.rows.single.cells['title']!.value, '协作者更新');
      checks.add(
        'remove-reference-and-document-undo-preserve-independent-dataset-and-row',
      );
      doc.pauseCollaboration(false);
      await doc.synchronize();
      doc.pauseCollaboration(true);
      expect(await w.document.session.prepareToClose(), isTrue);
      expect(await w.dataset.session.prepareToClose(), isTrue);
      await until(
        () => find.text('协作者更新').evaluate().isNotEmpty,
        'restored shared surface',
      );
      await t.ensureVisible(find.byKey(doc.blocks.first.key));
      await t.pump(const Duration(milliseconds: 400));
      expect(t.takeException(), isNull);
      final evidence = Directory('${w.document.directory.path}/evidence');
      await evidence.create(recursive: true);
      final boundary = t.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('stage1.surface')),
      );
      final image = await boundary.toImage(pixelRatio: 1);
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await File(
        '${evidence.path}/embedded-editor.png',
      ).writeAsBytes(png.buffer.asUint8List());
      image.dispose();
      checks.add(
        'bounded-mobile-desktop-grid-no-overflow-hit-miss-and-two-public-resource-checkpoints',
      );
      await File('${evidence.path}/embedded-e2e.json').writeAsString(
        jsonEncode({
          'status': 'passed',
          'platform': Platform.isIOS ? 'ios' : 'macos',
          'run': StageOneWorkbench.run,
          'objectId': doc.objectId,
          'datasetObjectId': restored.objectId,
          'rowId': rowId,
          'blockId': ref.id,
          'target': w.target.toJson(),
          'checks': checks,
          'fullProductAcceptance': 'not-complete',
        }),
      );
      await bob.close();
      await t.pumpWidget(const SizedBox());
      await t.pump();
      await w.close();
      debugPrint('SMARTDOC_EMBEDDED_EVIDENCE=${evidence.path}');
    },
  );
}
