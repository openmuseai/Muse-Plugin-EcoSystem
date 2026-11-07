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
    'nested original view commands preserve independent child and group intents',
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
          key: const ValueKey('nested.capture'),
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
          find.byKey(const ValueKey('nested.capture')),
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
      await tap(find.byKey(const ValueKey('dataset.rules-add-group')));
      await tap(find.text('添加条件').first);
      await tap(find.byType(DropdownButtonFormField<int>).at(1));
      await tap(find.text('包含').last);
      await t.enterText(find.byType(TextFormField).first, 'Muse');
      await tap(find.text('添加条件').first);
      await tap(find.byType(DropdownButtonFormField<int>).at(2));
      await tap(find.text('包含').last);
      await tap(find.byKey(const ValueKey('dataset.rules-apply')));
      await c.synchronize();
      expect(c.views.single.rows.length, 2);
      checks.add(
        'actual-reused-filter-dialog-creates-original-AND-group-and-stable-child-nodes',
      );
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
          deviceId: 'nested-peer-${DatasetWorkbench.run}',
          clientId: (DateTime.now().microsecondsSinceEpoch + 1).toString(),
          accessToken: () async => DatasetWorkbench.bobToken,
          codec: codec,
          socketFactory: (uri) => frames.open('bob', uri),
        ),
      );
      await peer.start();
      await until(() => rt.collaborators.isNotEmpty, 'authenticated peer');
      Map<String, dynamic> copyGroup(DatasetController d) =>
          Map<String, dynamic>.from(
            (jsonDecode(jsonEncode(d.views.single.filters.single)) as Map),
          );
      String child(DatasetController d, int index) =>
          (d.views.single.filters.single['children'] as List)[index]['content']
              as String;
      Future<void> editChild(int index, String text) async {
        await tap(find.byKey(const ValueKey('dataset.filters')));
        final input = find.byType(TextFormField).at(index);
        await t.ensureVisible(input);
        await t.enterText(input, text);
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
      await editChild(0, 'Muse A');
      final peerGroup = copyGroup(bob);
      (peerGroup['children'] as List)[1]['content'] = 'A';
      await bob.configureViewRules(
        bob.views.single,
        filters: [peerGroup],
        sorts: [],
      );
      await until(
        () => (captured['alice'] ?? 0) > 0 && (captured['bob'] ?? 0) > 0,
        'both encoded branches held',
      );
      expect(child(c, 0), 'Muse A');
      expect(child(c, 1), '');
      expect(child(bob, 0), 'Muse');
      expect(child(bob, 1), 'A');
      final split = {
        'alice': [child(c, 0), child(c, 1)],
        'bob': [child(bob, 0), child(bob, 1)],
        'heldOriginalFrames': Map.of(captured),
      };
      await shot('nested-local-branch.png');
      checks.add(
        'two-independent-branches-commit-different-child-intents-before-publishing-original-bytes',
      );
      frames.release();
      await until(
        () =>
            child(c, 0) == 'Muse A' &&
            child(c, 1) == 'A' &&
            child(bob, 0) == 'Muse A' &&
            child(bob, 1) == 'A',
        'both nested intents merged',
      );
      expect(c.views.single.rows.single.id, rowA);
      expect(rt.remoteUpdatesApplied, greaterThan(updatesBefore));
      expect(httpGate.held, true);
      await shot('nested-merged.png');
      checks.add(
        'actual-original-WS2-preserves-both-child-edits-in-one-shared-group-while-HTTP-held',
      );
      httpGate.release();
      await repair();
      await editChild(0, 'Muse');
      await repair();
      httpGate.hold();
      frames.hold();
      captured.clear();
      await tap(find.byKey(const ValueKey('dataset.filters')));
      await tap(find.byType(DropdownButtonFormField<int>).first);
      await tap(find.text('满足任一条件 · OR').last);
      await tap(find.byKey(const ValueKey('dataset.rules-apply')));
      final modePeer = copyGroup(bob);
      (modePeer['children'] as List)[1]['content'] = 'B';
      await bob.configureViewRules(
        bob.views.single,
        filters: [modePeer],
        sorts: [],
      );
      await until(
        () => (captured['alice'] ?? 0) > 0 && (captured['bob'] ?? 0) > 0,
        'group mode and child original frames held',
      );
      expect(c.views.single.filters.single['filter_type'], 1);
      expect(bob.views.single.filters.single['filter_type'], 0);
      frames.release();
      await until(
        () =>
            c.views.single.filters.single['filter_type'] == 1 &&
            bob.views.single.filters.single['filter_type'] == 1 &&
            child(c, 1) == 'B' &&
            child(bob, 1) == 'B',
        'parent mode and child both preserved',
      );
      expect(c.views.single.rows.length, 2);
      httpGate.release();
      await repair();
      checks.add(
        'concurrent-parent-OR-mode-and-peer-child-content-both-survive',
      );
      await tap(find.byKey(const ValueKey('dataset.undo')));
      await until(
        () => c.views.single.filters.single['filter_type'] == 0,
        'author-only undo parent mode',
      );
      expect(child(c, 1), 'B');
      expect(c.views.single.rows.single.id, rowB);
      await tap(find.byKey(const ValueKey('dataset.redo')));
      await until(
        () => c.views.single.filters.single['filter_type'] == 1,
        'author-only redo parent mode',
      );
      expect(child(c, 1), 'B');
      expect(c.views.single.rows.length, 2);
      expect(jsonEncode(doc.snapshot['data']), parentBefore);
      checks.add(
        'actual-child-undo-redo-changes-only-authored-group-mode-keeps-peer-leaf-and-parent-document',
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
      await shot('nested-editor.png');
      expect(t.takeException(), isNull);
      checks.add(
        'original-filter-JSON-and-independent-resource-checkpoints-preserved',
      );
      await File('${evidence.path}/nested-e2e.json').writeAsString(
        jsonEncode({
          'status': 'passed',
          'platform': Platform.isIOS ? 'ios' : 'macos',
          'run': StageOneWorkbench.run,
          'objectId': doc.objectId,
          'datasetObjectId': c.objectId,
          'rowA': rowA,
          'rowB': rowB,
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
      debugPrint('SMARTDOC_NESTED_EVIDENCE=${evidence.path}');
    },
  );
}
