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
    'original linked views share concurrent row membership and retain explicit UI identity',
    (t) async {
      final fatal = WidgetController.hitTestWarningShouldBeFatal;
      WidgetController.hitTestWarningShouldBeFatal = true;
      addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = fatal);
      final httpGate = HttpRequestGate(), captured = <String, int>{};
      final frames = OutgoingFrameGate(
        onHeld: (actor, bytes) => captured[actor] = (captured[actor] ?? 0) + 1,
      );
      final w = await EmbeddedWorkbench.open(
        realtime: true,
        transportClientFactory: (_) => httpGate.client(),
        realtimeSocketFactory: (uri) => frames.open('alice', uri),
      );
      await t.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('linked-view.capture'),
          child: StageOneApp(workbench: w.document),
        ),
      );
      Future<void> until(bool Function() ready, String why) async {
        for (var i = 0; i < 300; i++) {
          await t.pump(const Duration(milliseconds: 100));
          if (ready()) return;
        }
        fail('Linked view deadline: $why');
      }

      Future<void> tap(Finder f) async {
        await t.ensureVisible(f);
        await t.pump(const Duration(milliseconds: 150));
        await t.tap(f);
        await t.pump(const Duration(milliseconds: 300));
      }

      await until(
        () => w.document.controller != null,
        'parent public resource',
      );
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
      await until(() => w.dataset.controller != null, 'independent database');
      final c = w.dataset.controller!,
          rt = w.dataset.plugin.realtimeFor(w.dataset.session.record.identity)!;
      await until(() => rt.connected, 'original WS2');
      final first = c.views.single.id, checks = <String>[];
      await tap(find.byKey(const ValueKey('dataset.add-row')));
      final firstRow = c.views.single.rows.single;
      await tap(find.byKey(ValueKey('dataset.cell.${firstRow.id}.title')));
      await t.enterText(
        find.byKey(const ValueKey('dataset.cell-input')),
        '已有记录',
      );
      await tap(find.byKey(const ValueKey('dataset.cell-apply')));
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
      final wire = await loadRealtimeWireCore();
      final peer = DatasetRealtimeSession(
        controller: bob,
        presenceCore: wire,
        connection: AppFlowyRealtimeConnection(
          origin: Uri.parse(DatasetWorkbench.origin),
          workspaceId: DatasetWorkbench.workspace,
          deviceId: 'linked-view-bob-${DatasetWorkbench.run}',
          clientId: DateTime.now().microsecondsSinceEpoch.toString(),
          accessToken: () async => DatasetWorkbench.bobToken,
          codec: AppFlowyRealtimeCodec(wire),
          socketFactory: (uri) => frames.open('bob', uri),
        ),
      );
      await peer.start();
      await until(() => rt.collaborators.isNotEmpty, 'authenticated peer');
      final evidence = Directory('${w.document.directory.path}/evidence');
      await evidence.create(recursive: true);
      Future<void> shot(String name) async {
        await t.pump(const Duration(milliseconds: 200));
        final b = t.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('linked-view.capture')),
        );
        final image = await b.toImage(pixelRatio: 1),
            bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '${evidence.path}/$name',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }

      Future<void> createView(String name) async {
        await tap(find.byKey(const ValueKey('dataset.add-view')));
        await t.enterText(
          find.byKey(const ValueKey('dataset.view-name')),
          name,
        );
        await tap(find.byKey(const ValueKey('dataset.view-apply')));
      }

      DatasetViewProjection view(DatasetController d, String id) =>
          d.views.singleWhere((v) => v.id == id);
      String? selected() => t
          .widget<DropdownButton<String>>(
            find.byKey(const ValueKey('dataset.view-picker')),
          )
          .value;
      final parentBefore = jsonEncode(doc.snapshot['data']);
      checks.add(
        'actual-public-resource-host-reuses-one-database-root-and-independent-row-session',
      );
      httpGate.hold();
      frames.hold();
      captured.clear();
      await createView('协作视图');
      final linked = c.views.singleWhere((v) => v.name == '协作视图').id;
      final added = await bob.addRow(cells: {'title': '并发新增'});
      unawaited(bob.synchronize());
      await until(
        () => (captured['alice'] ?? 0) > 0 && httpGate.blockedRequests > 0,
        'held original root frame and dependent-row registration',
      );
      expect(c.views.length, 2);
      expect(bob.views.length, 1);
      expect(view(c, linked).rows.length, 1);
      expect(bob.views.single.rows.length, 2);
      final split = {
        'aliceViews': c.views.length,
        'bobViews': bob.views.length,
        'aliceRows': view(c, linked).rows.length,
        'bobRows': bob.views.single.rows.length,
        'heldOriginalFrames': Map.of(captured),
        'blockedHttpRequests': httpGate.blockedRequests,
      };
      await shot('linked-view-concurrent.png');
      checks.add(
        'view-and-row-branches-commit-independently-before-any-branch-publication',
      );
      // Registration must precede the new Row4's WS exposure. HTTP and WS both
      // resume here; this test does not pretend the registration is WS-only.
      httpGate.release();
      frames.release();
      await until(
        () =>
            c.views.length == 2 &&
            bob.views.length == 2 &&
            view(c, linked).rows.length == 2 &&
            view(bob, linked).rows.length == 2 &&
            view(c, linked).rows.every((r) => r.loaded),
        'concurrent original Cloud membership convergence',
      );
      expect(
        view(c, first).rows.map((r) => r.id).toSet(),
        view(c, linked).rows.map((r) => r.id).toSet(),
      );
      expect(c.readRow(linked, added).cells['title']!.value, '并发新增');
      checks.add(
        'original-Root1-Row4-registration-and-concurrent-merge-keep-every-primary-member-in-linked-view',
      );
      expect(selected(), linked);
      await tap(find.byKey(const ValueKey('dataset.filters')));
      await tap(find.byKey(const ValueKey('dataset.rules-add-filter')));
      await tap(find.byType(DropdownButtonFormField<int>).last);
      await tap(find.text('包含').last);
      await t.enterText(find.byType(TextFormField), '并发');
      await tap(find.byKey(const ValueKey('dataset.rules-apply')));
      await until(
        () =>
            view(c, linked).rows.length == 1 &&
            view(bob, linked).rows.length == 1,
        'independent shared view rule',
      );
      expect(view(c, first).rows.length, 2);
      rt.selectCell(viewId: linked, rowId: added, fieldId: 'title');
      await until(
        () => peer.collaborators.any(
          (u) => u.uid == rt.connection.actorUid && u.cell?['viewId'] == linked,
        ),
        'peer receives current-view position',
      );
      final epoch = c.localMutationEpoch;
      await tap(find.byKey(const ValueKey('dataset.view-picker')));
      await tap(find.text('表格').last);
      expect(selected(), first);
      expect(c.localMutationEpoch, epoch);
      await until(
        () => peer.collaborators.any(
          (u) => u.uid == rt.connection.actorUid && u.cell == null,
        ),
        'view switch clears previous-view presence',
      );
      checks.add(
        'actual-local-view-switch-clears-obsolete-cell-presence-without-writing-content',
      );
      await tap(find.byKey(const ValueKey('dataset.view-picker')));
      await tap(find.text('协作视图').last);
      expect(selected(), linked);
      expect(c.localMutationEpoch, epoch);
      checks.add(
        'embedded-view-switch-is-local-and-independent-filters-retain-the-same-original-row-identities',
      );
      await tap(find.byKey(const ValueKey('dataset.view-settings')));
      await t.enterText(
        find.byKey(const ValueKey('dataset.view-name')),
        '本地旧名称',
      );
      await bob.renameView(view(bob, linked), '远端视图');
      await until(() => view(c, linked).name == '远端视图', 'peer view rename');
      await tap(find.byKey(const ValueKey('dataset.view-apply')));
      expect(find.text('视图已变化或名称无效，请重新检查'), findsOneWidget);
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('dataset.view-name')))
            .controller!
            .text,
        '本地旧名称',
      );
      await shot('linked-view-stale-name.png');
      await tap(find.text('取消').last);
      checks.add(
        'actual-stale-view-settings-draft-is-preserved-with-peer-name-and-stable-view-id',
      );
      await tap(find.byKey(const ValueKey('dataset.view-settings')));
      await t.enterText(
        find.byKey(const ValueKey('dataset.view-name')),
        '团队视图',
      );
      await tap(find.byKey(const ValueKey('dataset.view-apply')));
      await until(
        () => view(bob, linked).name == '团队视图',
        'actual rename reaches peer',
      );
      await tap(find.byKey(const ValueKey('dataset.undo')));
      await until(
        () =>
            view(c, linked).name == '远端视图' && view(bob, linked).name == '远端视图',
        'author rename undo',
      );
      expect(c.readRow(linked, added).cells['title']!.value, '并发新增');
      checks.add(
        'actual-original-author-undo-restores-previous-view-name-with-peer-row-and-filter-intact',
      );
      await createView('临时视图');
      final temporary = c.views.singleWhere((v) => v.name == '临时视图').id;
      expect(selected(), temporary);
      await tap(find.byKey(const ValueKey('dataset.undo')));
      await until(
        () => !c.views.any((v) => v.id == temporary),
        'undo created view',
      );
      expect(selected(), isNull);
      expect(find.text('指定视图不可用，原引用保留'), findsOneWidget);
      await shot('linked-view-missing.png');
      await tap(find.byKey(const ValueKey('dataset.redo')));
      await until(
        () =>
            c.views.any((v) => v.id == temporary) &&
            view(c, temporary).rows.length == 2,
        'redo same view identity',
      );
      expect(selected(), temporary);
      checks.add(
        'view-creation-undo-never-falls-back-and-redo-restores-the-same-view-identity',
      );
      expect(jsonEncode(doc.snapshot['data']), parentBefore);
      doc.pauseCollaboration(false);
      await doc.flush();
      await doc.synchronize();
      await c.flush();
      await c.synchronize();
      await bob.synchronize();
      expect(await w.document.session.prepareToClose(), isTrue);
      expect(await w.dataset.session.prepareToClose(), isTrue);
      checks.add(
        'original-parent-reference-and-independent-resource-checkpoints-retain-three-views-without-row-copies',
      );
      await shot('linked-view-editor.png');
      expect(t.takeException(), isNull);
      await File('${evidence.path}/linked-view-e2e.json').writeAsString(
        jsonEncode({
          'status': 'passed',
          'platform': Platform.isIOS ? 'ios' : 'macos',
          'run': StageOneWorkbench.run,
          'objectId': doc.objectId,
          'datasetObjectId': c.objectId,
          'firstViewId': first,
          'linkedViewId': linked,
          'temporaryViewId': temporary,
          'rowId': added,
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
      debugPrint('SMARTDOC_LINKED_VIEW_EVIDENCE=${evidence.path}');
    },
  );
}
