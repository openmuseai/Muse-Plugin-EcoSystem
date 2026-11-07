import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';
import 'package:muse_smart_document_stage1/dataset_main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'public SDK independent dataset UI, actual Cloud collaboration and checkpoint',
    (t) async {
      final fatal = WidgetController.hitTestWarningShouldBeFatal;
      WidgetController.hitTestWarningShouldBeFatal = true;
      addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = fatal);
      expect(DatasetWorkbench.cloudEnabled, isTrue);
      final w = await DatasetWorkbench.open();
      await t.pumpWidget(DatasetApp(workbench: w));
      Future<void> until(bool Function() ready) async {
        for (var i = 0; i < 200; i++) {
          await t.pump(const Duration(milliseconds: 100));
          if (ready()) return;
        }
        fail('Dataset UI deadline exceeded');
      }

      await until(() => w.controller != null);
      final c = w.controller!;
      c.pauseCollaboration(true);
      final checks = <String>[];
      expect(
        w.session.record.mediaType,
        'application/vnd.openmuse.dataset+json',
      );
      expect(w.session.bytes.any((b) => b < 0), isFalse);
      expect(utf8.decode(w.session.bytes), isNot(contains('accessToken')));
      checks.add(
        'public-sdk-creator-resource-hub-bounded-editor-session-no-credentials-in-resource',
      );
      await t.tap(find.byKey(const ValueKey('dataset.add-row')));
      await until(() => c.views.single.rows.length == 1);
      final rowId = c.views.single.rows.single.id;
      DatasetRow row(DatasetController x) => x.views.single.rows.single;
      DatasetColumn col(DatasetController x, String id) =>
          x.views.single.columns.firstWhere((f) => f.id == id);
      Future<void> title(String value) async {
        await t.tap(find.byKey(ValueKey('dataset.cell.$rowId.title')));
        await t.pump(const Duration(milliseconds: 350));
        await t.enterText(
          find.byKey(const ValueKey('dataset.cell-input')),
          value,
        );
        await t.tap(find.byKey(const ValueKey('dataset.cell-apply')));
        await until(
          () => find
              .byKey(const ValueKey('dataset.cell-dialog'))
              .evaluate()
              .isEmpty,
        );
      }

      await title('项目任务😀');
      expect(row(c).cells['title']!.value, '项目任务😀');
      checks.add(
        'actual-add-record-and-unicode-cell-dialog-with-44-point-toolbar-hit-target',
      );
      c.pauseCollaboration(false);
      await c.synchronize();
      c.pauseCollaboration(true);
      expect(
        c.syncState,
        DatasetSyncState.accepted,
        reason: '${c.syncFailure}',
      );
      final bob = await DatasetController.open(
        core: NativeDatasetCore(),
        store: FileSnapshotStore(File('${w.directory.path}/bob.json')),
        objectId: c.objectId,
        providerFactory: DatasetWorkbench.providerFor('bob'),
        syncInterval: null,
      );
      expect(row(bob).id, rowId);
      bob.pauseCollaboration(true);
      await t.tap(find.byKey(ValueKey('dataset.cell.$rowId.title')));
      await t.pump(const Duration(milliseconds: 350));
      await t.enterText(
        find.byKey(const ValueKey('dataset.cell-input')),
        '旧弹窗草稿',
      );
      await bob.setCell(
        row(bob),
        col(bob, 'title'),
        '同事更新😀',
        expectedHash: row(bob).cells['title']!.hash,
      );
      bob.pauseCollaboration(false);
      await bob.synchronize();
      bob.pauseCollaboration(true);
      c.pauseCollaboration(false);
      await c.synchronize();
      c.pauseCollaboration(true);
      await t.tap(find.byKey(const ValueKey('dataset.cell-apply')));
      await t.pump(const Duration(milliseconds: 350));
      expect(find.text('内容已被修改，请取消后重新编辑'), findsOneWidget);
      expect(row(c).cells['title']!.value, '同事更新😀');
      expect(find.text('旧弹窗草稿'), findsOneWidget);
      await t.tap(find.text('取消'));
      await t.pump(const Duration(milliseconds: 350));
      checks.add(
        'actual-dialog-stale-draft-refused-after-real-peer-row-update-with-draft-retained',
      );
      await title('最终任务😀');
      await bob.setCell(
        row(bob),
        col(bob, 'done'),
        true,
        expectedHash: row(bob).cells['done']!.hash,
      );
      bob.pauseCollaboration(false);
      await bob.synchronize();
      c.pauseCollaboration(false);
      await c.synchronize();
      await bob.synchronize();
      expect(c.snapshot['views'], bob.snapshot['views']);
      expect(row(c).cells['done']!.value, true);
      checks.add(
        'actual-cloud-two-users-offline-independent-cells-converge-under-original-row-type-4',
      );
      await t.tap(find.byKey(const ValueKey('dataset.undo')));
      await t.pump(const Duration(milliseconds: 350));
      expect(row(c).cells['title']!.value, '同事更新😀');
      expect(row(c).cells['done']!.value, true);
      await t.tap(find.byKey(const ValueKey('dataset.redo')));
      await t.pump(const Duration(milliseconds: 350));
      expect(row(c).cells['title']!.value, '最终任务😀');
      checks.add('actual-origin-undo-redo-keeps-peer-checkbox');
      await t.tap(find.byKey(const ValueKey('dataset.field.title')));
      await t.pump(const Duration(milliseconds: 350));
      await t.enterText(
        find.byKey(const ValueKey('dataset.field-name')),
        '任务名称',
      );
      await t.tap(find.byKey(const ValueKey('dataset.field-apply')));
      await until(
        () => find
            .byKey(const ValueKey('dataset.field-dialog'))
            .evaluate()
            .isEmpty,
      );
      await t.tap(find.byKey(const ValueKey('dataset.add-field')));
      await t.pump(const Duration(milliseconds: 350));
      await t.tap(find.text('数字').last);
      await t.pump(const Duration(milliseconds: 350));
      await t.enterText(find.byKey(const ValueKey('dataset.field-name')), '预算');
      await t.tap(find.byKey(const ValueKey('dataset.field-apply')));
      await until(
        () => find
            .byKey(const ValueKey('dataset.field-dialog'))
            .evaluate()
            .isEmpty,
      );
      expect(col(c, 'title').name, '任务名称');
      expect(c.views.single.columns.last.semanticType, 'number');
      expect(row(c).cells['title']!.value, '最终任务😀');
      await c.synchronize();
      await bob.synchronize();
      expect(c.snapshot['views'], bob.snapshot['views']);
      expect(await w.session.prepareToClose(), isTrue);
      checks.add(
        'actual-field-rename-add-number-original-root-type-1-peer-sync-and-sdk-close-barrier',
      );
      await t.pump(const Duration(milliseconds: 400));
      final evidence = Directory('${w.directory.path}/evidence');
      await evidence.create(recursive: true);
      final boundary = t.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('dataset.surface')),
      );
      final capture = await boundary.toImage(pixelRatio: 1);
      final png = (await capture.toByteData(format: ui.ImageByteFormat.png))!;
      await File(
        '${evidence.path}/dataset-editor.png',
      ).writeAsBytes(png.buffer.asUint8List());
      capture.dispose();
      await File('${evidence.path}/dataset-e2e.json').writeAsString(
        jsonEncode({
          'status': 'passed',
          'platform': Platform.isIOS ? 'ios' : 'macos',
          'run': DatasetWorkbench.run,
          'objectId': c.objectId,
          'rowId': rowId,
          'views': c.snapshot['views'],
          'checks': checks,
          'limits': [
            'four field types and one grid layout only',
            'complete SiYuan database and collaboration acceptance remain open',
          ],
        }),
      );
      await bob.close();
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump();
      await w.close();
      debugPrint('SMARTDOC_DATASET_EVIDENCE=${evidence.path}');
    },
  );
}
