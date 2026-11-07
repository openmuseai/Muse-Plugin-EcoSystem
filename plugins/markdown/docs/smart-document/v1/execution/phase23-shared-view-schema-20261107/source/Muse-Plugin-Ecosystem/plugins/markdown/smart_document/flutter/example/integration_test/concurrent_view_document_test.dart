import 'dart:convert';
import 'package:muse_collab_test_support/muse_collab_test_support.dart';
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
    'actual original concurrent view commands and one-item history preserve collaboration',
    (t) async {
      final httpGate = HttpRequestGate();
      final wire = await loadRealtimeWireCore();
      final codec = AppFlowyRealtimeCodec(wire);
      final captured = <String, int>{};
      final frames = OutgoingFrameGate(
        onHeld: (actor, bytes) {
          // Client frames are not server packets (their RID is assigned by
          // the real server). Keep the original bytes opaque in this gate.
          captured[actor] = (captured[actor] ?? 0) + 1;
        },
      );
      final w = await EmbeddedWorkbench.open(
        realtime: true,
        transportClientFactory: (_) => httpGate.client(),
        realtimeSocketFactory: (uri) => frames.open('alice', uri),
      );
      await t.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('concurrent.capture'),
          child: StageOneApp(workbench: w.document),
        ),
      );
      Future<void> until(bool Function() ready, String why) async {
        for (var i = 0; i < 250; i++) {
          await t.pump(const Duration(milliseconds: 100));
          if (ready()) return;
        }
        fail('View rules UI deadline: $why');
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
          ..insertText(doc.blocks.first, 0, '项目计划｜并发视图与命令撤销'),
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

      final evidence = Directory('${w.document.directory.path}/evidence');
      await evidence.create(recursive: true);
      final checks = <String>[
        'actual-public-sdk-embedded-grid-and-independent-original-root-row-resources',
      ];
      Future<void> shot(String name) async {
        await t.pump(const Duration(milliseconds: 200));
        final boundary = t.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('concurrent.capture')),
        );
        final image = await boundary.toImage(pixelRatio: 1);
        final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        await File(
          '${evidence.path}/$name',
        ).writeAsBytes(png.buffer.asUint8List());
        image.dispose();
      }

      Future<void> tap(Finder f) async {
        await t.ensureVisible(f);
        await t.pump(const Duration(milliseconds: 180));
        await t.tap(f);
        await t.pump(const Duration(milliseconds: 250));
      }

      Future<String> add(String title) async {
        final before = c.rowObjectIds.toSet();
        await tap(find.byKey(const ValueKey('dataset.add-row')));
        await until(
          () => c.rowObjectIds.length == before.length + 1,
          'new original row',
        );
        final row = c.rowObjectIds.difference(before).single;
        await tap(find.byKey(ValueKey('dataset.cell.$row.title')));
        await t.enterText(
          find.byKey(const ValueKey('dataset.cell-input')),
          title,
        );
        await tap(find.byKey(const ValueKey('dataset.cell-apply')));
        return row;
      }

      final rowA = await add('Muse A'), rowB = await add('Muse B');
      final parentBefore = jsonEncode(doc.snapshot['data']);
      await tap(find.byKey(const ValueKey('dataset.filters')));
      await tap(find.byKey(const ValueKey('dataset.rules-add-filter')));
      await tap(find.byType(DropdownButtonFormField<int>).last);
      await tap(find.text('包含').last);
      await t.enterText(find.byType(TextFormField), 'Muse');
      await tap(find.byKey(const ValueKey('dataset.rules-apply')));
      await c.synchronize();
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
      final peer = DatasetRealtimeSession(
        controller: bob,
        presenceCore: wire,
        connection: AppFlowyRealtimeConnection(
          origin: Uri.parse(DatasetWorkbench.origin),
          workspaceId: DatasetWorkbench.workspace,
          deviceId: 'concurrent-peer-${DatasetWorkbench.run}',
          clientId: (DateTime.now().microsecondsSinceEpoch + 1).toString(),
          accessToken: () async => DatasetWorkbench.bobToken,
          codec: codec,
          socketFactory: (uri) => frames.open('bob', uri),
        ),
      );
      await peer.start();
      await until(() => rt.collaborators.isNotEmpty, 'authenticated peer');
      String content(DatasetController d) =>
          d.views.single.filters.single['content'] as String;
      final ruleId = c.views.single.filters.single['id'] as String;
      Map<String, dynamic> rule(String content) => {
        'id': ruleId,
        'filter_type': 2,
        'field_id': 'title',
        'ty': 0,
        'condition': 2,
        'content': content,
      };
      Future<void> edit(String text) async {
        await tap(find.byKey(const ValueKey('dataset.filters')));
        await t.enterText(find.byType(TextFormField), text);
        await tap(find.byKey(const ValueKey('dataset.rules-apply')));
      }

      Future<void> repair() async {
        await c.synchronize();
        await bob.synchronize();
        await t.pump(const Duration(milliseconds: 200));
      }

      await repair();
      httpGate.hold();
      frames.hold();
      captured.clear();
      final updatesBefore = rt.remoteUpdatesApplied;
      await edit('Muse A');
      await bob.configureViewRules(
        bob.views.single,
        filters: [rule('Muse B')],
        sorts: [],
      );
      await until(
        () => (captured['alice'] ?? 0) > 0 && (captured['bob'] ?? 0) > 0,
        'both original encoded outgoing frames held',
      );
      expect(content(c), 'Muse A');
      expect(content(bob), 'Muse B');
      expect(httpGate.held, true);
      final split = {
        'alice': content(c),
        'bob': content(bob),
        'heldOriginalFrames': Map.of(captured),
      };
      await shot('concurrent-local-branch.png');
      checks.add(
        'two-real-core-branches-commit-different-shared-rule-values-before-either-original-frame-is-published',
      );
      frames.release();
      await until(
        () =>
            c.views.single.rulesReady &&
            bob.views.single.rulesReady &&
            content(c) == content(bob),
        'concurrent original WS2 leaf merge',
      );
      expect(c.views.single.filters, hasLength(1));
      expect(rt.remoteUpdatesApplied, greaterThan(updatesBefore));
      expect(httpGate.held, true);
      httpGate.release();
      await repair();
      checks.add(
        'original-WS2-concurrent-leaf-updates-converge-without-duplicate-rule-nodes-while-HTTP-held',
      );
      await edit('Muse');
      await repair();
      httpGate.hold();
      frames.hold();
      captured.clear();
      await edit('Muse A');
      await bob.configureViewRules(
        bob.views.single,
        filters: bob.views.single.filters,
        sorts: [
          {'id': 'peer-sort', 'field_id': 'title', 'condition': 1},
        ],
      );
      await until(
        () => (captured['alice'] ?? 0) > 0 && (captured['bob'] ?? 0) > 0,
        'independent original frames held',
      );
      expect(content(c), 'Muse A');
      expect(content(bob), 'Muse');
      frames.release();
      await until(
        () =>
            content(c) == 'Muse A' &&
            content(bob) == 'Muse A' &&
            c.views.single.sorts.length == 1 &&
            bob.views.single.sorts.length == 1,
        'independent filter and sort intents',
      );
      expect(c.views.single.sorts.single['condition'], 1);
      expect(c.views.single.rows.single.id, rowA);
      expect(httpGate.held, true);
      httpGate.release();
      await repair();
      checks.add(
        'true-concurrent-filter-and-sort-intents-both-survive-original-map-merge',
      );
      await edit('Muse');
      await repair();
      await bob.configureViewRules(
        bob.views.single,
        filters: [rule('peer')],
        sorts: bob.views.single.sorts,
      );
      await until(() => content(c) == 'peer', 'causally later peer rule');
      await tap(find.byKey(const ValueKey('dataset.undo')));
      expect(content(c), 'peer');
      expect(c.lastHistoryApplied, false);
      expect(c.rowObjectIds, containsAll([rowA, rowB]));
      expect(find.text('这条修改已被协作者覆盖，当前内容已保留'), findsOneWidget);
      expect(jsonEncode(doc.snapshot['data']), parentBefore);
      await shot('concurrent-obsolete-undo.png');
      checks.add(
        'actual-child-undo-consumes-only-obsolete-command-and-explains-preserved-peer-rule-without-crossing-root-history',
      );
      await edit('Muse');
      await tap(find.byKey(ValueKey('dataset.cell.$rowB.title')));
      await t.enterText(
        find.byKey(const ValueKey('dataset.cell-input')),
        'Muse Z',
      );
      await tap(find.byKey(const ValueKey('dataset.cell-apply')));
      await until(
        () => bob.views.single.rows.any(
          (r) => r.id == rowB && r.cells['title']!.value == 'Muse Z',
        ),
        'post-conflict cell still editable',
      );
      await tap(find.byKey(const ValueKey('dataset.undo')));
      await until(
        () => c.views.single.rows.any(
          (r) => r.id == rowB && r.cells['title']!.value == 'Muse B',
        ),
        'bounded original row undo',
      );
      await tap(find.byKey(const ValueKey('dataset.redo')));
      await until(
        () => c.views.single.rows.any(
          (r) => r.id == rowB && r.cells['title']!.value == 'Muse Z',
        ),
        'bounded original row redo',
      );
      expect(jsonEncode(doc.snapshot['data']), parentBefore);
      checks.add(
        'actual-cell-edit-and-bounded-row-undo-redo-retain-both-original-identities-and-parent',
      );
      await peer.close();
      await bob.close();
      await c.synchronize();
      doc.pauseCollaboration(false);
      await doc.synchronize();
      await c.flush();
      await doc.flush();
      expect(await w.dataset.session.prepareToClose(), true);
      expect(await w.document.session.prepareToClose(), true);
      await shot('concurrent-editor.png');
      expect(t.takeException(), isNull);
      checks.add(
        'independent-public-resource-checkpoints-preserve-parent-locator-and-shared-view',
      );
      await File('${evidence.path}/concurrent-e2e.json').writeAsString(
        jsonEncode({
          'status': 'passed',
          'platform': Platform.isIOS ? 'ios' : 'macos',
          'run': StageOneWorkbench.run,
          'objectId': doc.objectId,
          'datasetObjectId': c.objectId,
          'rowA': rowA,
          'rowB': rowB,
          'ruleId': ruleId,
          'target': w.target.toJson(),
          'views': c.snapshot['views'],
          'splitBeforePublish': split,
          'checks': checks,
          'fullProductAcceptance': 'not-complete',
        }),
      );
      await t.pumpWidget(const SizedBox());
      await t.pump();
      await w.close();
      debugPrint('SMARTDOC_CONCURRENT_EVIDENCE=${evidence.path}');
    },
  );
}
