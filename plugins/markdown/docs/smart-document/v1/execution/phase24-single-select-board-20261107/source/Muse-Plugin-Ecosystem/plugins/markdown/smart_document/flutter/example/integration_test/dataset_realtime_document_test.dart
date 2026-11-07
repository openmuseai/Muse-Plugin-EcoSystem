import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
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
    'public SDK embedded realtime database, live cell presence, stale draft and scoped undo',
    (t) async {
      final old = WidgetController.hitTestWarningShouldBeFatal;
      WidgetController.hitTestWarningShouldBeFatal = true;
      addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = old);
      final w = await EmbeddedWorkbench.open(realtime: true);
      await t.pumpWidget(StageOneApp(workbench: w.document));
      Future<void> until(bool Function() ready, String reason) async {
        for (var i = 0; i < 250; i++) {
          await t.pump(const Duration(milliseconds: 100));
          if (ready()) return;
        }
        fail('Dataset realtime UI deadline: $reason');
      }

      await until(() => w.document.controller != null, 'document session');
      final doc = w.document.controller!;
      doc.pauseCollaboration(true);
      final mobile = t.view.physicalSize.width / t.view.devicePixelRatio < 700;
      if (mobile) {
        await t.tap(find.text('编辑').last);
        await t.pump(const Duration(milliseconds: 300));
      }
      await doc.editor.apply(
        doc.editor.transaction..insertText(doc.blocks.first, 0, '项目计划｜数据库实时协作'),
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
        () => w.dataset.controller != null,
        'child public resource session',
      );
      final c = w.dataset.controller!,
          rt = w.dataset.plugin.realtimeFor(w.dataset.session.record.identity)!;
      await until(() => rt.connected, 'plugin owned original WS2');
      final checks = <String>[
        'public-sdk-resource-child-session-injects-independent-realtime-adapter',
      ];
      await t.ensureVisible(find.byKey(const ValueKey('dataset.add-row')));
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.byKey(const ValueKey('dataset.add-row')));
      await until(() => c.views.single.rows.length == 1, 'actual row control');
      final rowId = c.views.single.rows.single.id;
      Future<void> openCell() async {
        final cell = find.byKey(ValueKey('dataset.cell.$rowId.title'));
        await t.ensureVisible(cell);
        await t.pump(const Duration(milliseconds: 300));
        await t.tap(cell);
        await t.pump(const Duration(milliseconds: 300));
      }

      Future<void> apply(String text) async {
        await t.enterText(
          find.byKey(const ValueKey('dataset.cell-input')),
          text,
        );
        await t.tap(find.byKey(const ValueKey('dataset.cell-apply')));
        await until(
          () => find
              .byKey(const ValueKey('dataset.cell-dialog'))
              .evaluate()
              .isEmpty,
          'dialog applied',
        );
      }

      await openCell();
      await apply('本机初值');
      await c.synchronize();
      final parentBefore = jsonEncode(doc.snapshot['data']);
      final bob = await DatasetController.open(
        core: NativeDatasetCore(),
        store: _Memory(),
        objectId: c.objectId,
        providerFactory: DatasetWorkbench.providerFor('bob'),
        syncInterval: null,
      );
      final wire = await loadRealtimeWireCore();
      final peer = DatasetRealtimeSession(
        controller: bob,
        presenceCore: wire,
        connection: AppFlowyRealtimeConnection(
          origin: Uri.parse(DatasetWorkbench.origin),
          workspaceId: DatasetWorkbench.workspace,
          deviceId: 'dataset-ui-peer-${DatasetWorkbench.run}',
          clientId: (DateTime.now().microsecondsSinceEpoch + 1).toString(),
          accessToken: () async => DatasetWorkbench.bobToken,
          codec: AppFlowyRealtimeCodec(wire),
        ),
      );
      await peer.start();
      await until(
        () => rt.collaborators.isNotEmpty,
        'server-normalized peer presence',
      );
      checks.add(
        'actual-embedded-grid-cell-editor-and-second-authenticated-original-root-row-peer',
      );
      peer.selectCell(
        viewId: bob.views.single.id,
        rowId: rowId,
        fieldId: 'title',
        editing: true,
      );
      final marker = find.byKey(ValueKey('dataset.remote-cell.$rowId.title'));
      await until(() => marker.evaluate().isNotEmpty, 'remote cell border');
      expect(t.getSize(marker).height, 52);
      checks.add(
        'actual-grid-remote-cell-painter-uses-stable-view-row-field-awareness',
      );
      await openCell();
      await t.enterText(
        find.byKey(const ValueKey('dataset.cell-input')),
        '未提交本机草稿',
      );
      final beforeUpdates = rt.remoteUpdatesApplied;
      var row = bob.views.single.rows.firstWhere((r) => r.id == rowId),
          field = bob.views.single.columns.first;
      await bob.setCell(
        row,
        field,
        '远端实时更新😀',
        expectedHash: row.cells[field.id]!.hash,
      );
      await until(
        () =>
            rt.remoteUpdatesApplied > beforeUpdates &&
            c.views.single.rows.first.cells['title']!.value == '远端实时更新😀',
        'live row update while dialog open',
      );
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('dataset.cell-input')))
            .controller!
            .text,
        '未提交本机草稿',
      );
      await t.tap(find.byKey(const ValueKey('dataset.cell-apply')));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('内容已被修改，请取消后重新编辑'), findsOneWidget);
      expect(c.views.single.rows.first.cells['title']!.value, '远端实时更新😀');
      await t.tap(find.text('取消'));
      await t.pump(const Duration(milliseconds: 300));
      checks.add(
        'live-ws-update-keeps-modal-draft-and-rejects-stale-cell-commit',
      );
      await openCell();
      await apply('界面继续编辑');
      final undo = find.byKey(const ValueKey('dataset.undo'));
      await t.ensureVisible(undo);
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(undo);
      await until(
        () => c.views.single.rows.first.cells['title']!.value == '远端实时更新😀',
        'child origin undo',
      );
      expect(jsonEncode(doc.snapshot['data']), parentBefore);
      checks.add(
        'actual-child-toolbar-origin-undo-restores-peer-value-without-parent-history-mutation',
      );
      await bob.synchronize();
      final newRow = await bob.addRow(cells: {'title': '协作者新增行'});
      await bob.synchronize();
      await until(
        () => c.views.single.rows.any(
          (r) =>
              r.id == newRow && r.loaded && r.cells['title']!.value == '协作者新增行',
        ),
        'dynamic row projection',
      );
      expect(c.unavailableRows, isEmpty);
      checks.add(
        'new-root-reference-and-independent-row-load-in-the-shared-embedded-grid',
      );
      final evidence = Directory('${w.document.directory.path}/evidence');
      await evidence.create(recursive: true);
      Future<void> screenshot(String name) async {
        final boundary = t.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('stage1.surface')),
        );
        final image = await boundary.toImage(pixelRatio: 1);
        final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        await File(
          '${evidence.path}/$name',
        ).writeAsBytes(png.buffer.asUint8List());
        image.dispose();
      }

      peer.selectCell(
        viewId: bob.views.single.id,
        rowId: rowId,
        fieldId: 'title',
        editing: true,
      );
      await until(
        () => marker.evaluate().isNotEmpty,
        'selection survives peer row append',
      );
      await t.ensureVisible(marker);
      await t.pump(const Duration(milliseconds: 400));
      await screenshot('dataset_realtime-editor.png');
      final people = find.byKey(const ValueKey('dataset.collaborators'));
      await t.ensureVisible(people);
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(people);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('在线协作者'), findsOneWidget);
      expect(find.text('协作者'), findsOneWidget);
      await screenshot('dataset_realtime-members.png');
      await t.tapAt(const Offset(15, 150));
      await t.pump(const Duration(milliseconds: 300));
      await peer.close();
      await until(
        () => rt.collaborators.isEmpty && marker.evaluate().isEmpty,
        'transient leave clears avatar and cell border',
      );
      checks.add('live-member-sheet-and-leave-clear-transient-grid-markers');
      await c.synchronize();
      doc.pauseCollaboration(false);
      await doc.synchronize();
      doc.pauseCollaboration(true);
      expect(await w.dataset.session.prepareToClose(), isTrue);
      expect(await w.document.session.prepareToClose(), isTrue);
      expect(t.takeException(), isNull);
      checks.add(
        'two-domain-sdk-checkpoints-no-hit-miss-or-overflow-and-clean-close-barrier',
      );
      await File('${evidence.path}/dataset_realtime-e2e.json').writeAsString(
        jsonEncode({
          'status': 'passed',
          'platform': Platform.isIOS ? 'ios' : 'macos',
          'run': StageOneWorkbench.run,
          'objectId': doc.objectId,
          'datasetObjectId': c.objectId,
          'target': w.target.toJson(),
          'rowId': rowId,
          'newRowId': newRow,
          'views': c.snapshot['views'],
          'checks': checks,
          'fullProductAcceptance': 'not-complete',
        }),
      );
      await bob.close();
      await t.pumpWidget(const SizedBox());
      await t.pump();
      await w.close();
      debugPrint('SMARTDOC_DATASET_REALTIME_EVIDENCE=${evidence.path}');
    },
  );
}
