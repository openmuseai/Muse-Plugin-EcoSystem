import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
    'embedded original date field UI, live peer conflicts, contextual history and reopen checkpoint',
    (t) async {
      final old = WidgetController.hitTestWarningShouldBeFatal;
      WidgetController.hitTestWarningShouldBeFatal = true;
      addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = old);
      final w = await EmbeddedWorkbench.open(realtime: true);
      await t.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('dates.capture'),
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
        doc.editor.transaction..insertText(doc.blocks.first, 0, '项目计划｜跨端日期与协作'),
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
      await openDate();
      await t.enterText(
        find.byKey(const ValueKey('dataset.date-start')),
        '2026-11-08',
      );
      await t.enterText(
        find.byKey(const ValueKey('dataset.date-end')),
        '2026-11-09',
      );
      final row = bob.views.single.rows.single,
          field = bob.views.single.columns.last;
      await bob.setCell(row, field, {
        'start': '2026-11-10',
        'end': '2026-11-11',
        'includeTime': false,
        'isRange': true,
      }, expectedHash: row.cells[fieldId]!.hash);
      await until(
        () => value()['start'] == '2026-11-10',
        'actual WS peer date',
      );
      await t.tap(find.byKey(const ValueKey('dataset.date-apply')));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('内容已被修改，草稿保留'), findsOneWidget);
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('dataset.date-start')))
            .controller!
            .text,
        '2026-11-08',
      );
      final evidence = Directory('${w.document.directory.path}/evidence');
      await evidence.create(recursive: true);
      Future<void> screenshot(String name) async {
        await t.pump(const Duration(milliseconds: 250));
        final boundary = t.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('dates.capture')),
        );
        final image = await boundary.toImage(pixelRatio: 1);
        final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        await File(
          '${evidence.path}/$name',
        ).writeAsBytes(png.buffer.asUint8List());
        image.dispose();
      }

      await screenshot('dates-conflict.png');
      await t.tap(find.text('取消').last);
      await t.pump(const Duration(milliseconds: 300));
      checks.add(
        'real-peer-live-date-update-preserves-open-modal-draft-and-rejects-stale-cell',
      );
      await openDate();
      await t.tap(find.byTooltip('选择开始日期'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await screenshot('dates-calendar.png');
      final calendarCancel = MaterialLocalizations.of(
        t.element(find.byType(DatePickerDialog)),
      ).cancelButtonLabel;
      await t.tap(find.text(calendarCancel).last);
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.byKey(const ValueKey('dataset.date-time')));
      await t.pump(const Duration(milliseconds: 200));
      await t.enterText(
        find.byKey(const ValueKey('dataset.date-start')),
        '2026-11-12T09:30:45+08:00',
      );
      await t.enterText(
        find.byKey(const ValueKey('dataset.date-end')),
        '2026-11-13T10:45:12+08:00',
      );
      await t.tap(find.byTooltip('选择开始时间'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(TimePickerDialog), findsOneWidget);
      final clockCancel = MaterialLocalizations.of(
        t.element(find.byType(TimePickerDialog)),
      ).cancelButtonLabel;
      await t.tap(find.text(clockCancel).last);
      await t.pump(const Duration(milliseconds: 300));
      checks.add(
        'actual-reused-calendar-and-time-picker-cancel-keeps-date-draft',
      );
      await screenshot('dates-dialog.png');
      await t.tap(find.byKey(const ValueKey('dataset.date-apply')));
      await until(
        () => value()['includeTime'] == true,
        'seconds precision commit',
      );
      Future<void> history(bool redo) async {
        if (!mobile) {
          await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
          if (redo) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          await t.sendKeyEvent(LogicalKeyboardKey.keyZ);
          if (redo) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        } else {
          await tapVisible(
            find.byKey(ValueKey(redo ? 'dataset.redo' : 'dataset.undo')),
          );
        }
      }

      await history(false);
      await until(
        () => value()['start'] == '2026-11-10',
        'child original undo',
      );
      expect(jsonEncode(doc.snapshot['data']), parentBefore);
      await history(true);
      await until(
        () => value()['start'] == '2026-11-12T09:30:45+08:00',
        'child original redo',
      );
      expect(jsonEncode(doc.snapshot['data']), parentBefore);
      checks.add(
        mobile
            ? 'actual-child-toolbar-date-undo-redo-preserves-parent-document'
            : 'actual-CmdZ-CmdShiftZ-owns-child-date-history-and-preserves-parent',
      );
      await c.synchronize();
      await bob.synchronize();
      await openDate();
      await bob.configureDateField(
        bob.views.single.columns.last,
        '交付日期',
        'America/New_York',
      );
      await until(
        () => c.views.single.columns.last.timezone == 'America/New_York',
        'Root1 live schema',
      );
      await t.tap(find.byKey(const ValueKey('dataset.date-apply')));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('字段或时区已变化，草稿保留'), findsOneWidget);
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('dataset.date-start')))
            .controller!
            .text,
        '2026-11-12T09:30:45+08:00',
      );
      await t.tap(find.text('取消').last);
      await t.pump(const Duration(milliseconds: 300));
      expect(value()['start'], '2026-11-11T20:30:45-05:00');
      checks.add(
        'real-peer-Root1-timezone-schema-keeps-instant-and-rejects-old-draft',
      );
      await peer.close();
      await bob.close();
      await c.synchronize();
      doc.pauseCollaboration(false);
      await doc.synchronize();
      doc.pauseCollaboration(true);
      expect(await w.document.session.prepareToClose(), true);
      expect(await w.dataset.session.prepareToClose(), true);
      await screenshot('dates-editor.png');
      expect(t.takeException(), isNull);
      checks.add(
        'two-independent-resource-checkpoints-no-flattened-dataset-in-parent',
      );
      await File('${evidence.path}/dates-e2e.json').writeAsString(
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
      debugPrint('SMARTDOC_DATES_EVIDENCE=${evidence.path}');
    },
  );
}
