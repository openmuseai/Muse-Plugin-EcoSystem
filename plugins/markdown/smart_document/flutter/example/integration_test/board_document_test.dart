import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:muse_collab_test_support/muse_collab_test_support.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';
import 'package:muse_smart_document_stage1/main.dart';
import 'package:muse_smart_document_stage1/dataset_main.dart';
import 'package:muse_smart_document_stage1/embedded_main.dart';

class _Memory implements SnapshotStore {
  @override
  Future<Map<String, dynamic>?> read() async => null;
  @override
  Future<void> write(Map<String, dynamic> value) async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'original single-select board shares rows, concurrent moves and peer edits through Cloud',
    (t) async {
      final fatal = WidgetController.hitTestWarningShouldBeFatal;
      WidgetController.hitTestWarningShouldBeFatal = true;
      addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = fatal);
      final httpGate = HttpRequestGate(), frames = OutgoingFrameGate();
      final w = await EmbeddedWorkbench.open(
        realtime: true,
        transportClientFactory: (_) => httpGate.client(),
        realtimeSocketFactory: (uri) => frames.open('alice', uri),
      );
      await t.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('board.capture'),
          child: StageOneApp(workbench: w.document),
        ),
      );
      Future<void> until(bool Function() predicate, String why) async {
        for (var i = 0; i < 300; i++) {
          await t.pump(const Duration(milliseconds: 100));
          if (predicate()) return;
        }
        fail('Board deadline: $why');
      }

      Future<void> tap(Finder f) async {
        await t.ensureVisible(f);
        await t.pump(const Duration(milliseconds: 150));
        await t.tap(f);
        await t.pump(const Duration(milliseconds: 300));
      }

      await until(() => w.document.controller != null, 'document resource');
      final doc = w.document.controller!;
      doc.pauseCollaboration(true);
      final mobile = t.view.physicalSize.width / t.view.devicePixelRatio < 700;
      if (mobile) await tap(find.text('编辑').last);
      await tap(
        find.byKey(
          ValueKey(
            mobile ? 'smart-document.mobile.insert' : 'smart-document.insert',
          ),
        ),
      );
      await tap(find.text('数据库').last);
      await tap(find.byKey(const ValueKey('embed.pick-dataset')));
      await until(() => w.dataset.controller != null, 'database resource');
      final c = w.dataset.controller!;
      final rt = w.dataset.plugin.realtimeFor(
        w.dataset.session.record.identity,
      )!;
      await until(() => rt.connected, 'original realtime');
      await c.createField(
        '状态',
        'singleSelect',
        options: const [
          DatasetOptionDraft(name: '待处理', color: 1),
          DatasetOptionDraft(name: '进行中', color: 2),
          DatasetOptionDraft(name: '已完成', color: 3),
        ],
      );
      final field = c.views.single.columns.last,
          todo = field.options[0].id,
          doing = field.options[1].id,
          done = field.options[2].id;
      final row = await c.addRow(
        cells: {
          'title': '原始任务',
          field.id: [todo],
        },
      );
      await c.synchronize();
      final first = c.views.single.id,
          parentBefore = jsonEncode(doc.snapshot['data']);
      final bob = await DatasetController.open(
        core: NativeDatasetCore(),
        store: _Memory(),
        objectId: c.objectId,
        providerFactory: DatasetWorkbench.providerFor(
          'bob',
          clientFactory: (_) => httpGate.client(),
        ),
        syncInterval: null,
      );
      final wire = await loadRealtimeWireCore();
      final peer = DatasetRealtimeSession(
        controller: bob,
        presenceCore: wire,
        connection: AppFlowyRealtimeConnection(
          origin: Uri.parse(DatasetWorkbench.origin),
          workspaceId: DatasetWorkbench.workspace,
          deviceId: 'board-bob-${DatasetWorkbench.run}',
          clientId: DateTime.now().microsecondsSinceEpoch.toString(),
          accessToken: () async => DatasetWorkbench.bobToken,
          codec: AppFlowyRealtimeCodec(wire),
          socketFactory: (uri) => frames.open('bob', uri),
        ),
      );
      await peer.start();
      await until(() => rt.collaborators.isNotEmpty, 'authenticated peer');
      final checks = <String>[],
          evidence = Directory('${w.document.directory.path}/evidence');
      await evidence.create(recursive: true);
      Future<void> shot(String name) async {
        await t.pump(const Duration(milliseconds: 200));
        final boundary = t.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('board.capture')),
        );
        final image = await boundary.toImage(pixelRatio: 1),
            bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '${evidence.path}/$name',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }

      httpGate.hold();
      frames.hold();
      await tap(find.byKey(const ValueKey('dataset.add-view')));
      await t.enterText(
        find.byKey(const ValueKey('dataset.view-name')),
        '协作看板',
      );
      await tap(find.byKey(const ValueKey('dataset.view-layout')));
      await tap(find.text('看板').last);
      await tap(find.byKey(const ValueKey('dataset.view-apply')));
      final boardId = c.views.singleWhere((v) => v.layout == 1).id;
      final added = await bob.addRow(
        cells: {
          'title': '并发新增任务',
          field.id: [done],
        },
      );
      unawaited(bob.synchronize());
      await until(
        () => httpGate.blockedRequests > 0,
        'dependent row registration held',
      );
      expect(c.views.length, 2);
      expect(bob.views.length, 1);
      expect(c.views.last.rows.length, 1);
      expect(bob.views.single.rows.length, 2);
      final split = {
        'aliceViews': c.views.length,
        'bobViews': bob.views.length,
        'aliceRows': c.views.last.rows.length,
        'bobRows': bob.views.single.rows.length,
      };
      checks.add(
        'actual-board-creation-and-peer-row-insertion-exist-on-independent-unpublished-branches',
      );
      frames.release();
      httpGate.release();
      await c.synchronize();
      await bob.synchronize();
      DatasetViewProjection board(DatasetController d) =>
          d.views.singleWhere((v) => v.id == boardId);
      await until(
        () => c.views.every((v) => v.rows.length == 2) && bob.views.length == 2,
        'board row convergence',
      );
      expect(board(c).board!.groups.singleWhere((g) => g.id == done).rowIds, [
        added,
      ]);
      checks.add(
        'original-grid-and-board-share-one-database-root-and-the-same-two-independent-row-identities',
      );
      httpGate.hold();
      frames.hold();
      await tap(find.byKey(ValueKey('dataset.card-move.$row')));
      await tap(find.byKey(ValueKey('dataset.move-group.$doing')));
      var peerRow = bob.readRow(first, row),
          peerTitle = bob.views.first.columns.singleWhere(
            (f) => f.id == 'title',
          );
      await bob.setCell(
        peerRow,
        peerTitle,
        '协作者修改的任务标题',
        expectedHash: peerRow.cells['title']!.hash,
      );
      unawaited(bob.synchronize());
      expect(c.readRow(boardId, row).cells[field.id]!.selectedOptionIds, [
        doing,
      ]);
      expect(bob.readRow(first, row).cells[field.id]!.selectedOptionIds, [
        todo,
      ]);
      expect(c.readRow(boardId, row).cells['title']!.value, '原始任务');
      expect(bob.readRow(first, row).cells['title']!.value, '协作者修改的任务标题');
      checks.add(
        'actual-card-move-and-peer-title-edit-are-concurrent-before-either-update-is-published',
      );
      frames.release();
      httpGate.release();
      await c.synchronize();
      await bob.synchronize();
      await until(
        () =>
            c.readRow(boardId, row).cells['title']!.value == '协作者修改的任务标题' &&
            bob
                .readRow(boardId, row)
                .cells[field.id]!
                .selectedOptionIds
                .contains(doing),
        'move and title convergence',
      );
      checks.add(
        'original-row-cell-merge-retains-both-the-card-move-and-independent-peer-title',
      );
      await tap(find.byKey(const ValueKey('dataset.undo')));
      await until(
        () => bob
            .readRow(boardId, row)
            .cells[field.id]!
            .selectedOptionIds
            .contains(todo),
        'row undo',
      );
      expect(c.readRow(boardId, row).cells['title']!.value, '协作者修改的任务标题');
      await tap(find.byKey(const ValueKey('dataset.redo')));
      await until(
        () => bob
            .readRow(boardId, row)
            .cells[field.id]!
            .selectedOptionIds
            .contains(doing),
        'row redo',
      );
      checks.add(
        'actual-original-row-undo-redo-preserve-peer-title-and-card-identity',
      );
      await tap(find.byKey(ValueKey('dataset.card-move.$row')));
      peerRow = bob.readRow(boardId, row);
      await bob.setCell(
        peerRow,
        board(bob).columns.singleWhere((f) => f.id == field.id),
        [done],
        expectedHash: peerRow.cells[field.id]!.hash,
      );
      await until(
        () => c
            .readRow(boardId, row)
            .cells[field.id]!
            .selectedOptionIds
            .contains(done),
        'peer move with old menu open',
      );
      await tap(find.byKey(ValueKey('dataset.move-group.$todo')));
      expect(c.readRow(boardId, row).cells[field.id]!.selectedOptionIds, [
        done,
      ]);
      expect(find.text('操作未完成，请检查内容或保存状态'), findsOneWidget);
      checks.add(
        'actual-stale-card-move-menu-rejects-overwriting-a-causally-newer-peer-move',
      );
      await shot('board-stale.png');
      final card = find.byKey(ValueKey('dataset.card.$row'));
      // Lazy horizontal groups may require a real swipe to materialize the final
      // column before ensureVisible can resolve the actual card.
      for (var i = 0; i < 8 && card.evaluate().isEmpty; i++) {
        final rect = t.getRect(find.byKey(const ValueKey('dataset.board')));
        await t.dragFrom(rect.center, const Offset(-180, 0));
        await t.pump(const Duration(milliseconds: 200));
      }
      await tap(card);
      await tap(find.byKey(const ValueKey('dataset.record-field.title')));
      await t.enterText(
        find.byKey(const ValueKey('dataset.cell-input')),
        '卡片详情中编辑',
      );
      await tap(find.byKey(const ValueKey('dataset.cell-apply')));
      await tap(find.text('完成').last);
      await until(
        () => bob.readRow(boardId, row).cells['title']!.value == '卡片详情中编辑',
        'record editor reaches peer',
      );
      checks.add(
        'actual-card-detail-reuses-existing-typed-cell-editor-and-original-row-transport',
      );
      await shot('board-cards.png');
      final epoch = c.localMutationEpoch;
      await tap(find.byKey(const ValueKey('dataset.view-picker')));
      await tap(find.text('表格').last);
      expect(c.localMutationEpoch, epoch);
      expect(
        c.views.first.rows
            .singleWhere((r) => r.id == row)
            .cells['title']!
            .value,
        '卡片详情中编辑',
      );
      checks.add(
        'local-switch-back-to-grid-keeps-the-same-edited-row-without-a-new-domain-mutation',
      );
      expect(jsonEncode(doc.snapshot['data']), parentBefore);
      doc.pauseCollaboration(false);
      await doc.flush();
      await doc.synchronize();
      await c.flush();
      await c.synchronize();
      await bob.synchronize();
      expect(await w.document.session.prepareToClose(), true);
      expect(await w.dataset.session.prepareToClose(), true);
      checks.add(
        'parent-reference-remains-unchanged-and-public-resource-checkpoints-flush-separately',
      );
      await shot('board-editor.png');
      expect(t.takeException(), isNull);
      await File('${evidence.path}/board-e2e.json').writeAsString(
        jsonEncode({
          'status': 'passed',
          'platform': Platform.isIOS ? 'ios' : 'macos',
          'run': StageOneWorkbench.run,
          'objectId': doc.objectId,
          'datasetObjectId': c.objectId,
          'boardViewId': boardId,
          'firstViewId': first,
          'rowId': row,
          'peerRowId': added,
          'fieldId': field.id,
          'todoId': todo,
          'doingId': doing,
          'doneId': done,
          'target': w.target.toJson(),
          'views': c.snapshot['views'],
          'split': split,
          'checks': checks,
          'fullProductAcceptance': 'not-complete',
        }),
      );
      await peer.close();
      await bob.close();
      await t.pumpWidget(const SizedBox());
      await t.pump();
      await w.close();
      debugPrint('SMARTDOC_BOARD_EVIDENCE=${evidence.path}');
    },
  );
}
