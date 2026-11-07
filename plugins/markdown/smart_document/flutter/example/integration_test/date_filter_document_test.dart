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
    'original date view filter, shared peer rules, prefill and hidden row editor',
    (t) async {
      final old = WidgetController.hitTestWarningShouldBeFatal;
      WidgetController.hitTestWarningShouldBeFatal = true;
      addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = old);
      final w = await EmbeddedWorkbench.open(realtime: true);
      await t.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('date_filter.capture'),
          child: StageOneApp(workbench: w.document),
        ),
      );
      Future<void> until(bool Function() ready, String why) async {
        for (var i = 0; i < 250; i++) {
          await t.pump(const Duration(milliseconds: 100));
          if (ready()) return;
        }
        fail('Dates UI deadline: $why');
      }

      await until(
        () => w.document.controller != null,
        'public parent resource',
      );
      final doc = w.document.controller!;
      doc.pauseCollaboration(true);
      final mobile = t.view.physicalSize.width / t.view.devicePixelRatio < 700;
      if (mobile) {
        await t.tap(find.text('编辑').last);
        await t.pump(const Duration(milliseconds: 300));
      }
      await doc.editor.apply(
        doc.editor.transaction
          ..insertText(doc.blocks.first, 0, '项目计划｜日期筛选与记录编辑'),
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
        'independent child resource',
      );
      final c = w.dataset.controller!,
          rt = w.dataset.plugin.realtimeFor(w.dataset.session.record.identity)!;
      await until(() => rt.connected, 'original WS2');
      final checks = <String>[
        'actual-desktop-mobile-insert-and-public-sdk-independent-date-resource',
      ];
      Future<void> tapVisible(Finder f) async {
        await t.ensureVisible(f);
        await t.pump(const Duration(milliseconds: 250));
        await t.tap(f);
        await t.pump(const Duration(milliseconds: 300));
      }

      await tapVisible(find.byKey(const ValueKey('dataset.add-field')));
      await t.tap(find.text('日期').last);
      await t.pump(const Duration(milliseconds: 300));
      await t.enterText(
        find.byKey(const ValueKey('dataset.field-name')),
        '交付日期',
      );
      await t.enterText(
        find.byKey(const ValueKey('dataset.field-timezone')),
        'Asia/Shanghai',
      );
      await t.tap(find.byKey(const ValueKey('dataset.field-apply')));
      await until(
        () => c.views.single.columns.any((f) => f.semanticType == 'date'),
        'original date field2',
      );
      final fieldId = c.views.single.columns.last.id;
      await tapVisible(find.byKey(const ValueKey('dataset.add-row')));
      await until(() => c.views.single.rows.length == 1, 'new row4');
      final rowId = c.views.single.rows.single.id;
      final parentBefore = jsonEncode(doc.snapshot['data']);
      Map value() => c.views.single.rows.single.cells[fieldId]!.value as Map;
      Future<void> openDate() =>
          tapVisible(find.byKey(ValueKey('dataset.cell.$rowId.$fieldId')));
      await openDate();
      await t.enterText(
        find.byKey(const ValueKey('dataset.date-start')),
        '2026-11-06',
      );
      await t.tap(find.byKey(const ValueKey('dataset.date-range')));
      await t.pump(const Duration(milliseconds: 200));
      await t.enterText(
        find.byKey(const ValueKey('dataset.date-end')),
        '2026-11-07',
      );
      await t.tap(find.byKey(const ValueKey('dataset.date-apply')));
      await until(() => value()['start'] == '2026-11-06', 'civil range commit');
      expect(value()['end'], '2026-11-07');
      expect(value()['includeTime'], false);
      checks.add(
        'original-DateCellData-civil-range-explicit-IANA-timezone-and-field2-row4',
      );
      await c.synchronize();
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
          deviceId: 'date-peer-${DatasetWorkbench.run}',
          clientId: (DateTime.now().microsecondsSinceEpoch + 1).toString(),
          accessToken: () async => DatasetWorkbench.bobToken,
          codec: AppFlowyRealtimeCodec(wire),
        ),
      );
      await peer.start();
      await until(() => rt.collaborators.isNotEmpty, 'authenticated peer');
      final evidence = Directory('${w.document.directory.path}/evidence');
      await evidence.create(recursive: true);
      Future<void> screenshot(String name) async {
        await t.pump(const Duration(milliseconds: 200));
        final boundary = t.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('date_filter.capture')),
        );
        final image = await boundary.toImage(pixelRatio: 1);
        final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        await File(
          '${evidence.path}/$name',
        ).writeAsBytes(png.buffer.asUint8List());
        image.dispose();
      }

      await tapVisible(find.byKey(const ValueKey('dataset.filters')));
      await tapVisible(find.byKey(const ValueKey('dataset.rules-add-filter')));
      await tapVisible(find.byType(DropdownButtonFormField<String>).first);
      await tapVisible(find.text('交付日期').last);
      await tapVisible(find.byType(DropdownButtonFormField<int>).first);
      await tapVisible(find.text('结束日期为').last);
      await t.enterText(find.byType(TextFormField), '2026-11-07');
      await tapVisible(find.byTooltip('选择筛选日期'));
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await screenshot('date_filter-calendar.png');
      final cancel = MaterialLocalizations.of(
        t.element(find.byType(DatePickerDialog)),
      ).cancelButtonLabel;
      await tapVisible(find.text(cancel).last);
      await screenshot('date_filter-dialog.png');
      await tapVisible(find.byKey(const ValueKey('dataset.rules-apply')));
      await until(
        () => bob.views.single.filters.isNotEmpty,
        'shared original date condition',
      );
      expect(c.views.single.rows.length, 1);
      expect(
        bob.views.single.dateFilterInputs.values.single['timestamp'],
        '2026-11-07',
      );
      checks.add(
        'actual-date-filter-field-condition-calendar-explicit-zone-and-original-storage',
      );
      await tapVisible(find.byKey(const ValueKey('dataset.filters')));
      await t.enterText(find.byType(TextFormField), '2026-11-08');
      final beforeUpdates = rt.remoteUpdatesApplied;
      final changed = Map<String, dynamic>.from(bob.views.single.filters.single)
        ..['content'] = {'timestamp': '2026-11-09'};
      await bob.configureViewRules(
        bob.views.single,
        filters: [changed],
        sorts: [],
      );
      await until(
        () =>
            c.views.single.rows.isEmpty &&
            rt.remoteUpdatesApplied > beforeUpdates,
        'actual WS2 shared Root1 date filter',
      );
      await tapVisible(find.byKey(const ValueKey('dataset.rules-apply')));
      expect(find.byKey(const ValueKey('dataset.rules-error')), findsOneWidget);
      expect(
        t.widget<EditableText>(find.byType(EditableText).first).controller.text,
        '2026-11-08',
      );
      await screenshot('date_filter-conflict.png');
      await tapVisible(find.text('取消').last);
      expect(find.text('没有符合筛选的记录'), findsOneWidget);
      expect(c.rowObjectIds.contains(rowId), true);
      checks.add(
        'actual-peer-Root1-date-rule-update-retains-hidden-Row4-and-rejects-stale-draft',
      );
      await tapVisible(find.byKey(const ValueKey('dataset.filters')));
      await tapVisible(find.byType(DropdownButtonFormField<int>).first);
      await tapVisible(find.text('开始日期不为空').last);
      await tapVisible(find.byKey(const ValueKey('dataset.rules-apply')));
      await until(
        () => c.views.single.rows.length == 1,
        'existing row matches not-empty',
      );
      final beforeRows = c.rowObjectIds;
      await tapVisible(find.byKey(const ValueKey('dataset.add-row')));
      final hidden = c.rowObjectIds.difference(beforeRows).single;
      expect(c.views.single.rows.length, 1);
      expect(
        c.readRow(c.views.single.id, hidden).cells[fieldId]!.value,
        isNull,
      );
      expect(find.text('记录已创建，当前筛选下不可见'), findsOneWidget);
      await tapVisible(find.text('编辑新记录').last);
      expect(
        find.byKey(const ValueKey('dataset.record-dialog')),
        findsOneWidget,
      );
      await screenshot('date_filter-record.png');
      await tapVisible(find.byKey(ValueKey('dataset.record-field.$fieldId')));
      await t.enterText(
        find.byKey(const ValueKey('dataset.date-start')),
        '2026-11-08',
      );
      await tapVisible(find.byKey(const ValueKey('dataset.date-apply')));
      await until(
        () => c.views.single.rows.length == 2,
        'hidden row becomes visible through same original DateCellData writer',
      );
      await tapVisible(find.text('完成').last);
      checks.add(
        'actual-filtered-create-hidden-row-action-reuses-date-cell-editor-no-rule-reset',
      );
      await until(
        () => bob.views.single.rows.length == 2,
        'peer discovers new Row4 and edited date',
      );
      expect(
        bob.readRow(bob.views.single.id, hidden).cells[fieldId]!.value is Map,
        true,
      );
      checks.add(
        'actual-peer-new-row-reference-then-Row4-date-synchronization',
      );
      await tapVisible(find.byKey(const ValueKey('dataset.undo')));
      await until(
        () => c.views.single.rows.length == 1,
        'date original undo hides row',
      );
      await tapVisible(find.byKey(const ValueKey('dataset.redo')));
      await until(
        () => c.views.single.rows.length == 2,
        'date original redo restores row',
      );
      expect(jsonEncode(doc.snapshot['data']), parentBefore);
      checks.add(
        'actual-child-origin-date-undo-redo-keeps-shared-filter-and-parent',
      );
      // Equality permits original date seed and keeps a newly created row visible.
      final original = Map<String, dynamic>.from(c.views.single.filters.single)
        ..['condition'] = 0
        ..['content'] = {'timestamp': '2026-11-08'};
      await c.configureViewRules(
        c.views.single,
        filters: [original],
        sorts: [],
      );
      await tapVisible(find.byKey(const ValueKey('dataset.add-row')));
      expect(c.views.single.rows.length, 2);
      for (final row in c.views.single.rows) {
        expect((row.cells[fieldId]!.value as Map)['start'], '2026-11-08');
      }
      checks.add(
        'actual-add-row-uses-original-date-filter-seed-without-changing-shared-rules',
      );
      await peer.close();
      await bob.close();
      await c.synchronize();
      doc.pauseCollaboration(false);
      await doc.synchronize();
      doc.pauseCollaboration(true);
      expect(await w.document.session.prepareToClose(), true);
      expect(await w.dataset.session.prepareToClose(), true);
      await screenshot('date_filter-editor.png');
      expect(t.takeException(), isNull);
      await File('${evidence.path}/date_filter-e2e.json').writeAsString(
        jsonEncode({
          'status': 'passed',
          'platform': Platform.isIOS ? 'ios' : 'macos',
          'run': StageOneWorkbench.run,
          'objectId': doc.objectId,
          'datasetObjectId': c.objectId,
          'rowId': rowId,
          'fieldId': fieldId,
          'target': w.target.toJson(),
          'views': c.snapshot['views'],
          'checks': checks,
          'fullProductAcceptance': 'not-complete',
        }),
      );
      await t.pumpWidget(const SizedBox());
      await t.pump();
      await w.close();
      debugPrint('SMARTDOC_DATE_FILTER_EVIDENCE=${evidence.path}');
    },
  );
}
