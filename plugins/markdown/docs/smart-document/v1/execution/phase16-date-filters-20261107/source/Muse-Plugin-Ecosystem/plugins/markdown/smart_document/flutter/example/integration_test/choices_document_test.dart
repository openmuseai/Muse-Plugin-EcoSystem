import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';
import 'package:muse_smart_document_stage1/dataset_main.dart';

class _Memory implements SnapshotStore {
  Map<String, dynamic>? value;
  @override
  Future<Map<String, dynamic>?> read() async => value;
  @override
  Future<void> write(Map<String, dynamic> data) async {
    value = Map.of(data);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'public Dataset choice fields UI, real Cloud peer, schema guard and checkpoint',
    (t) async {
      final oldFatal = WidgetController.hitTestWarningShouldBeFatal;
      WidgetController.hitTestWarningShouldBeFatal = true;
      addTearDown(
        () => WidgetController.hitTestWarningShouldBeFatal = oldFatal,
      );
      expect(DatasetWorkbench.cloudEnabled, isTrue);
      final w = await DatasetWorkbench.open();
      await t.pumpWidget(DatasetApp(workbench: w));
      Future<void> until(bool Function() ready, String reason) async {
        for (var i = 0; i < 200; i++) {
          await t.pump(const Duration(milliseconds: 100));
          if (ready()) return;
        }
        fail('Choice UI deadline: $reason');
      }

      await until(() => w.controller != null, 'public resource session');
      final c = w.controller!;
      c.pauseCollaboration(true);
      final checks = <String>[
        'public-sdk-independent-dataset-resource-and-original-root-row-core',
      ];
      Future<void> create(String label, String name, String options) async {
        await t.tap(find.byKey(const ValueKey('dataset.add-field')));
        await t.pump(const Duration(milliseconds: 300));
        await t.tap(find.text(label).last);
        await t.pump(const Duration(milliseconds: 300));
        await t.enterText(
          find.byKey(const ValueKey('dataset.field-name')),
          name,
        );
        await t.enterText(
          find.byKey(const ValueKey('dataset.field-options')),
          options,
        );
        await t.tap(find.byKey(const ValueKey('dataset.field-apply')));
        await until(
          () =>
              c.views.single.columns.any((f) => f.name == name) &&
              find
                  .byKey(const ValueKey('dataset.field-dialog'))
                  .evaluate()
                  .isEmpty,
          'field creation',
        );
      }

      await create('单选', '流程', '待办,A😀\n进行中\n已完成');
      await create('多选', '标签', '研发\n设计\n质量');
      checks.add(
        'actual-field-menu-creates-original-single-multi-options-with-stable-ids',
      );
      await t.tap(find.byKey(const ValueKey('dataset.add-row')));
      await until(() => c.views.single.rows.length == 1, 'row creation');
      final rowId = c.views.single.rows.single.id;
      DatasetColumn col(DatasetController x, String name) =>
          x.views.single.columns.firstWhere((f) => f.name == name);
      DatasetRow row(DatasetController x) => x.views.single.rows.single;
      final stateId = col(c, '流程').id, tagsId = col(c, '标签').id;
      Future<void> open(String fieldId) async {
        final target = find.byKey(ValueKey('dataset.cell.$rowId.$fieldId'));
        await t.ensureVisible(target);
        await t.pump(const Duration(milliseconds: 300));
        await t.tap(target);
        await t.pump(const Duration(milliseconds: 300));
      }

      await open('title');
      await t.enterText(
        find.byKey(const ValueKey('dataset.cell-input')),
        '选择字段端到端😀',
      );
      await t.tap(find.byKey(const ValueKey('dataset.cell-apply')));
      await until(
        () => row(c).cells['title']!.value == '选择字段端到端😀',
        'title commit',
      );
      Future<void> select(String fieldId, List<DatasetChoice> options) async {
        await open(fieldId);
        for (final option in options) {
          final target = find.byKey(
            ValueKey('dataset.choice-option.${option.id}'),
          );
          expect(t.getSize(target).height, greaterThanOrEqualTo(44));
          await t.tap(target);
        }
        await t.tap(find.byKey(const ValueKey('dataset.choice-apply')));
        await until(
          () => find
              .byKey(const ValueKey('dataset.choice-dialog'))
              .evaluate()
              .isEmpty,
          'choice commit',
        );
      }

      await select(stateId, [col(c, '流程').options.first]);
      await select(tagsId, col(c, '标签').options.take(2).toList());
      expect(row(c).cells[stateId]!.value, '待办,A😀');
      expect(row(c).cells[tagsId]!.value, ['研发', '设计']);
      checks.add(
        'actual-choice-route-selects-comma-unicode-single-and-ordered-multi-values',
      );
      c.pauseCollaboration(false);
      await c.synchronize();
      expect(c.syncState, DatasetSyncState.accepted);
      final bob = await DatasetController.open(
        core: NativeDatasetCore(),
        store: _Memory(),
        objectId: c.objectId,
        providerFactory: (type) => AppFlowyObjectTransport(
          origin: Uri.parse(DatasetWorkbench.origin),
          workspaceId: DatasetWorkbench.workspace,
          accessToken: () async => DatasetWorkbench.bobToken,
          deviceId: 'choices-native-bob',
          collabType: type,
          binding: datasetBinding(type),
        ),
        syncInterval: null,
      );
      expect(
        col(bob, '流程').options.map((v) => v.id).toList(),
        col(c, '流程').options.map((v) => v.id).toList(),
      );
      await bob.setCell(
        row(bob),
        col(bob, '标签'),
        col(bob, '标签').options.map((v) => v.id).toList(),
        expectedHash: row(bob).cells[tagsId]!.hash,
      );
      await select(stateId, [col(c, '流程').options.last]);
      for (var i = 0; i < 3; i++) {
        await bob.synchronize();
        await c.synchronize();
      }
      expect(c.snapshot['views'], bob.snapshot['views']);
      checks.add(
        'actual-two-user-cloud-metadata-and-independent-choice-cell-convergence',
      );
      await t.tap(find.byKey(const ValueKey('dataset.undo')));
      await t.pump(const Duration(milliseconds: 300));
      expect(row(c).cells[stateId]!.value, '待办,A😀');
      expect(row(c).cells[tagsId]!.value, ['研发', '设计', '质量']);
      await c.synchronize();
      await bob.synchronize();
      checks.add('actual-toolbar-origin-undo-keeps-peer-choice-cell');
      await open(stateId);
      final captured = col(c, '流程');
      await t.tap(
        find.byKey(ValueKey('dataset.choice-option.${captured.options[1].id}')),
      );
      await bob.renameField(col(bob, '流程'), '流程状态');
      await bob.synchronize();
      await c.synchronize();
      await t.tap(find.byKey(const ValueKey('dataset.choice-apply')));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('内容或选项已变化，请取消后重新打开'), findsOneWidget);
      expect(row(c).cells[stateId]!.value, '待办,A😀');
      await t.tap(find.text('取消'));
      await t.pump(const Duration(milliseconds: 300));
      checks.add(
        'live-peer-schema-change-rejects-old-dialog-without-overwrite',
      );
      await open(stateId);
      await t.tap(find.byKey(const ValueKey('dataset.choice-clear')));
      await t.tap(find.byKey(const ValueKey('dataset.choice-apply')));
      await until(
        () => row(c).cells[stateId]!.selectedOptionIds.isEmpty,
        'explicit clear',
      );
      await t.tap(find.byKey(const ValueKey('dataset.undo')));
      await t.pump(const Duration(milliseconds: 300));
      expect(row(c).cells[stateId]!.value, '待办,A😀');
      await c.synchronize();
      await bob.synchronize();
      checks.add(
        'explicit-clear-and-original-undo-restore-selected-option-identity',
      );
      expect(await w.session.prepareToClose(), isTrue);
      expect(t.takeException(), isNull);
      final target = find.byKey(ValueKey('dataset.cell.$rowId.$tagsId'));
      await t.ensureVisible(target);
      await t.pump(const Duration(milliseconds: 400));
      final evidence = Directory('${w.directory.path}/evidence');
      await evidence.create(recursive: true);
      final boundary = t.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('dataset.surface')),
      );
      final image = await boundary.toImage(pixelRatio: 1);
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await File(
        '${evidence.path}/choices-editor.png',
      ).writeAsBytes(png.buffer.asUint8List());
      image.dispose();
      checks.add(
        'shared-grid-badges-visible-no-hit-miss-overflow-and-sdk-checkpoint',
      );
      await File('${evidence.path}/choices-e2e.json').writeAsString(
        jsonEncode({
          'status': 'passed',
          'platform': Platform.isIOS ? 'ios' : 'macos',
          'run': DatasetWorkbench.run,
          'objectId': c.objectId,
          'rowId': rowId,
          'stateFieldId': stateId,
          'tagsFieldId': tagsId,
          'views': c.snapshot['views'],
          'checks': checks,
          'fullProductAcceptance': 'not-complete',
        }),
      );
      await bob.close();
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump();
      await w.close();
      debugPrint('SMARTDOC_CHOICES_EVIDENCE=${evidence.path}');
    },
  );
}
