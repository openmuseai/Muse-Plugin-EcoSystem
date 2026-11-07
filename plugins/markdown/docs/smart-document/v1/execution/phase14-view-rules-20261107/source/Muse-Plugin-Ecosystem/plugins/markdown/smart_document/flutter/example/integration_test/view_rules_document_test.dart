import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
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

class _HttpGate {
  Completer<void>? held;
  void hold() {
    held = Completer<void>();
  }

  void release() {
    held?.complete();
    held = null;
  }
}

class _GateClient extends http.BaseClient {
  _GateClient(this.gate);
  final _HttpGate gate;
  final http.Client inner = http.Client();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final held = gate.held;
    if (held != null) await held.future;
    return inner.send(request);
  }

  @override
  void close() => inner.close();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'shared embedded view rules and hidden-row updates use original root and row collaboration',
    (t) async {
      final gate = _HttpGate();
      final w = await EmbeddedWorkbench.open(
        realtime: true,
        transportClientFactory: (_) => _GateClient(gate),
      );
      await t.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('rules.capture'),
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
          ..insertText(doc.blocks.first, 0, '项目计划｜共享视图与实时协作'),
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
        'actual-public-sdk-embedded-grid-shares-independent-dataset-resource',
      ];
      final evidence = Directory('${w.document.directory.path}/evidence');
      await evidence.create(recursive: true);
      Future<void> shot(String name) async {
        await t.pump(const Duration(milliseconds: 200));
        final boundary = t.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('rules.capture')),
        );
        final image = await boundary.toImage(pixelRatio: 1);
        final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        await File(
          '${evidence.path}/$name',
        ).writeAsBytes(png.buffer.asUint8List());
        image.dispose();
      }

      Future<void> tapVisible(Finder f) async {
        await t.ensureVisible(f);
        await t.pump(const Duration(milliseconds: 200));
        await t.tap(f);
        await t.pump(const Duration(milliseconds: 300));
      }

      Future<String> add(String title) async {
        final before = c.rowObjectIds.toSet();
        await tapVisible(find.byKey(const ValueKey('dataset.add-row')));
        await until(
          () => c.rowObjectIds.length == before.length + 1,
          'add original row',
        );
        final row = c.rowObjectIds.difference(before).single;
        await tapVisible(find.byKey(ValueKey('dataset.cell.$row.title')));
        await t.enterText(
          find.byKey(const ValueKey('dataset.cell-input')),
          title,
        );
        await tapVisible(find.byKey(const ValueKey('dataset.cell-apply')));
        return row;
      }

      final rowA = await add('Muse A'), rowB = await add('Other B');
      final parentBefore = jsonEncode(doc.snapshot['data']);
      await c.synchronize();
      final bob = await DatasetController.open(
        core: NativeDatasetCore(),
        store: _Memory(),
        objectId: c.objectId,
        providerFactory: DatasetWorkbench.providerFor('bob'),
        syncInterval: null,
      );
      final field = bob.views.single.columns.firstWhere((f) => f.id == 'title');
      final hidden = bob.views.single.rows.firstWhere((r) => r.id == rowB);
      final wire = await loadRealtimeWireCore();
      final peer = DatasetRealtimeSession(
        controller: bob,
        presenceCore: wire,
        connection: AppFlowyRealtimeConnection(
          origin: Uri.parse(DatasetWorkbench.origin),
          workspaceId: DatasetWorkbench.workspace,
          deviceId: 'view-peer-${DatasetWorkbench.run}',
          clientId: (DateTime.now().microsecondsSinceEpoch + 1).toString(),
          accessToken: () async => DatasetWorkbench.bobToken,
          codec: AppFlowyRealtimeCodec(wire),
        ),
      );
      await peer.start();
      await until(() => rt.collaborators.isNotEmpty, 'authenticated WS2 peer');
      await tapVisible(find.byKey(const ValueKey('dataset.filters')));
      await tapVisible(find.byKey(const ValueKey('dataset.rules-add-filter')));
      await t.enterText(find.byType(TextFormField), 'Muse A');
      await shot('rules-filter-dialog.png');
      await tapVisible(find.byKey(const ValueKey('dataset.rules-apply')));
      await until(() => c.views.single.rows.length == 1, 'filter applied');
      expect(c.views.single.rows.single.id, rowA);
      expect(c.rowObjectIds, containsAll([rowA, rowB]));
      await until(
        () => bob.views.single.rows.length == 1,
        'shared Root1 filter',
      );
      checks.add(
        'actual-filter-dialog-shares-original-Root1-config-and-keeps-hidden-Row4-dependency',
      );
      await c.synchronize();
      gate.hold();
      await bob.setCell(
        hidden,
        field,
        'Muse A',
        expectedHash: hidden.cells['title']!.hash,
      );
      await until(
        () => c.views.single.rows.length == 2,
        'hidden row update returns to filtered view',
      );
      expect(gate.held!.isCompleted, false);
      gate.release();
      checks.add(
        'actual-HTTP-gated-original-WS2-hidden-row-edit-re-enters-filter',
      );
      await tapVisible(find.byKey(const ValueKey('dataset.undo')));
      await until(() => c.views.single.filters.isEmpty, 'original root undo');
      expect(
        c.views.single.rows
            .firstWhere((r) => r.id == rowB)
            .cells['title']!
            .value,
        'Muse A',
      );
      expect(jsonEncode(doc.snapshot['data']), parentBefore);
      await tapVisible(find.byKey(const ValueKey('dataset.redo')));
      await until(
        () => c.views.single.filters.isNotEmpty,
        'original root redo',
      );
      checks.add(
        'actual-child-origin-undo-redo-keeps-peer-row-and-parent-document',
      );
      await c.synchronize();
      await bob.synchronize();
      await tapVisible(find.byKey(const ValueKey('dataset.filters')));
      final old = bob.views.single;
      await bob.configureViewRules(
        old,
        filters: [
          {
            'id': 'peer-title',
            'filter_type': 2,
            'field_id': 'title',
            'ty': 0,
            'condition': 2,
            'content': 'Muse',
          },
        ],
        sorts: [],
      );
      await until(
        () => c.views.single.filters.first['id'] == 'peer-title',
        'peer Root1 rules',
      );
      await tapVisible(find.byKey(const ValueKey('dataset.rules-apply')));
      expect(find.byKey(const ValueKey('dataset.rules-error')), findsOneWidget);
      await shot('rules-peer-conflict.png');
      await tapVisible(find.text('取消').last);
      checks.add(
        'actual-peer-view-config-rejects-open-stale-draft-without-overwrite',
      );
      await tapVisible(find.byKey(const ValueKey('dataset.sorts')));
      await tapVisible(find.byKey(const ValueKey('dataset.rules-add-sort')));
      await tapVisible(find.byType(DropdownButtonFormField<int>).last);
      await tapVisible(find.text('降序').last);
      await shot('rules-sort-dialog.png');
      await tapVisible(find.byKey(const ValueKey('dataset.rules-apply')));
      await until(() => bob.views.single.sorts.isNotEmpty, 'shared sort');
      final peerRow = bob.views.single.rows.firstWhere((r) => r.id == rowB);
      await bob.setCell(
        peerRow,
        field,
        'Muse Z',
        expectedHash: peerRow.cells['title']!.hash,
      );
      await until(
        () => c.views.single.rows.first.id == rowB,
        'live sorted row move',
      );
      checks.add(
        'actual-sort-dialog-and-live-peer-value-reorder-use-shared-view-with-stable-identities',
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
      await shot('rules-editor.png');
      expect(t.takeException(), isNull);
      checks.add(
        'independent-parent-and-dataset-durable-local-checkpoints-preserve-original-content',
      );
      await File('${evidence.path}/rules-e2e.json').writeAsString(
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
          'checks': checks,
          'fullProductAcceptance': 'not-complete',
        }),
      );
      await t.pumpWidget(const SizedBox());
      await t.pump();
      await w.close();
      debugPrint('SMARTDOC_RULES_EVIDENCE=${evidence.path}');
    },
  );
}
