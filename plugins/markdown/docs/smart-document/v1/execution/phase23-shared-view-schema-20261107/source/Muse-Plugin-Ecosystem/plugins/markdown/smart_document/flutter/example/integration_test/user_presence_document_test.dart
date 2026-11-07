import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';
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

class _Peer {
  _Peer(
    this.document,
    this.dataset,
    this.documentRealtime,
    this.datasetRealtime,
  );
  final SmartDocumentController document;
  final DatasetController dataset;
  final DocumentRealtimeSession documentRealtime;
  final DatasetRealtimeSession datasetRealtime;
  Future<void> close() async {
    await documentRealtime.close();
    await datasetRealtime.close();
    await document.close();
    await dataset.close();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'original authenticated same-user positions aggregate in document and dataset UI',
    (t) async {
      final fatal = WidgetController.hitTestWarningShouldBeFatal;
      WidgetController.hitTestWarningShouldBeFatal = true;
      addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = fatal);
      final w = await EmbeddedWorkbench.open(
        realtime: true,
        documentRealtime: true,
      );
      await t.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('users.capture'),
          child: StageOneApp(workbench: w.document),
        ),
      );
      Future<void> until(bool Function() ready, String why) async {
        for (var i = 0; i < 300; i++) {
          await t.pump(const Duration(milliseconds: 100));
          if (ready()) return;
        }
        fail('User presence deadline: $why');
      }

      Future<void> tap(Finder f) async {
        await t.ensureVisible(f);
        await t.pump(const Duration(milliseconds: 200));
        await t.tap(f);
        await t.pump(const Duration(milliseconds: 300));
      }

      await until(() => w.document.controller != null, 'public document');
      final doc = w.document.controller!;
      final mobile = t.view.physicalSize.width / t.view.devicePixelRatio < 700;
      if (mobile) await tap(find.text('编辑').last);
      await doc.editor.apply(
        doc.editor.transaction..insertText(doc.blocks.first, 0, '多端协作计划与在线位置'),
      );
      await tap(
        find.byKey(
          ValueKey(
            mobile ? 'smart-document.mobile.insert' : 'smart-document.insert',
          ),
        ),
      );
      await tap(find.text('数据库').last);
      await tap(find.byKey(const ValueKey('embed.pick-dataset')));
      await until(
        () => w.dataset.controller != null,
        'public embedded dataset',
      );
      final data = w.dataset.controller!;
      await tap(find.byKey(const ValueKey('dataset.add-row')));
      await until(() => data.views.single.rows.length == 1, 'original Row4');
      await doc.synchronize();
      await data.synchronize();
      final dr = w.document.plugin.realtimeFor(
            w.document.session.record.identity,
          )!,
          tr = w.dataset.plugin.realtimeFor(w.dataset.session.record.identity)!;
      await until(
        () => dr.connection.actorUid != null && tr.connection.actorUid != null,
        'authenticated original profile UID',
      );
      final uid = dr.connection.actorUid!;
      expect(tr.connection.actorUid, uid);
      final wire = await loadRealtimeWireCore();
      var sequence = 10;
      Future<_Peer> peer(String who, String label, int position) async {
        final token = who == 'bob'
            ? StageOneWorkbench.bobToken
            : StageOneWorkbench.aliceToken;
        final d = await SmartDocumentController.open(
          core: NativeDocumentCore(),
          store: _Memory(),
          objectId: doc.objectId,
          provider: AppFlowyCollaborationProvider(
            origin: Uri.parse(StageOneWorkbench.origin),
            workspaceId: StageOneWorkbench.workspace,
            deviceId: 'user-doc-$label-${StageOneWorkbench.run}',
            accessToken: () async => token,
          ),
          syncInterval: null,
        );
        final s = await DatasetController.open(
          core: NativeDatasetCore(),
          store: _Memory(),
          objectId: data.objectId,
          providerFactory: DatasetWorkbench.providerFor(who),
          syncInterval: null,
        );
        AppFlowyRealtimeConnection connection(String suffix) =>
            AppFlowyRealtimeConnection(
              origin: Uri.parse(StageOneWorkbench.origin),
              workspaceId: StageOneWorkbench.workspace,
              deviceId: 'user-$label-$suffix-${StageOneWorkbench.run}',
              clientId: (DateTime.now().microsecondsSinceEpoch + sequence++)
                  .toString(),
              accessToken: () async => token,
              codec: AppFlowyRealtimeCodec(wire),
            );
        final rd = DocumentRealtimeSession(
              controller: d,
              connection: connection('doc'),
              presenceCore: wire,
            ),
            rs = DatasetRealtimeSession(
              controller: s,
              connection: connection('data'),
              presenceCore: wire,
            );
        await rd.start();
        await rs.start();
        d.editor.selection = Selection.collapsed(
          Position(path: [0], offset: position),
        );
        rs.selectCell(
          viewId: s.views.single.id,
          rowId: s.views.single.rows.single.id,
          fieldId: position == 3 ? 'done' : 'title',
          editing: true,
        );
        return _Peer(d, s, rd, rs);
      }

      final bobOne = await peer('bob', 'bob-one', 1),
          bobTwo = await peer('bob', 'bob-two', 3),
          aliceOther = await peer('alice', 'alice-other', 5);
      await until(
        () =>
            dr.collaborators.length == 3 &&
            tr.collaborators.length == 3 &&
            doc.editor.remoteSelections.value.length == 3 &&
            bobOne.documentRealtime.connection.actorUid != null &&
            bobTwo.datasetRealtime.connection.actorUid != null &&
            aliceOther.documentRealtime.connection.actorUid != null,
        'three independent original remote positions',
      );
      final bobUid = dr.collaborators.firstWhere((p) => p.uid != uid).uid;
      expect(dr.collaborators.where((p) => p.uid == bobUid), hasLength(2));
      expect(dr.collaborators.where((p) => p.uid == uid), hasLength(1));
      expect(bobOne.documentRealtime.connection.actorUid, bobUid);
      expect(bobTwo.datasetRealtime.connection.actorUid, bobUid);
      final checks = <String>[
        'public-document-and-dataset-original-Cloud-profile-UID-agree',
        'same-authenticated-UID-retains-three-independent-remote-selections-and-cells',
      ];
      final evidence = Directory('${w.document.directory.path}/evidence');
      await evidence.create(recursive: true);
      Future<void> shot(String name) async {
        await t.pump(const Duration(milliseconds: 200));
        final b = t.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('users.capture')),
        );
        final image = await b.toImage(pixelRatio: 1);
        final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        await File(
          '${evidence.path}/$name',
        ).writeAsBytes(png.buffer.asUint8List());
        image.dispose();
      }

      final datasetButton = find.byKey(const ValueKey('dataset.collaborators'));
      expect(
        find.descendant(of: datasetButton, matching: find.text('2 人')),
        findsOneWidget,
      );
      await tap(datasetButton);
      expect(find.text('我'), findsOneWidget);
      expect(find.text('2 处在线'), findsNWidgets(2));
      await tap(find.byKey(ValueKey('collaboration.member.$bobUid')));
      expect(find.textContaining('正在编辑'), findsNWidgets(2));
      await shot('users-dataset-roster.png');
      checks.add(
        'actual-embedded-member-entry-counts-two-users-not-four-positions-and-expands-both-peer-locations',
      );
      await bobOne.close();
      await until(
        () => tr.collaborators.length == 2 && dr.collaborators.length == 2,
        'one Bob position leaves',
      );
      expect(
        find.byKey(ValueKey('collaboration.member.$bobUid')),
        findsOneWidget,
      );
      expect(find.text('2 处在线'), findsOneWidget);
      checks.add(
        'closing-one-peer-position-keeps-user-and-other-position-live',
      );
      await bobTwo.close();
      await until(
        () => tr.collaborators.length == 1 && dr.collaborators.length == 1,
        'last Bob position leaves',
      );
      expect(
        find.byKey(ValueKey('collaboration.member.$bobUid')),
        findsNothing,
      );
      expect(find.text('我'), findsOneWidget);
      Navigator.of(t.element(find.text('在线协作者'))).pop();
      await t.pump(const Duration(milliseconds: 300));
      expect(
        find.descendant(of: datasetButton, matching: find.text('1 人')),
        findsOneWidget,
      );
      checks.add(
        'last-peer-position-leave-removes-user-while-own-other-window-counts-once',
      );
      await aliceOther.close();
      await until(
        () =>
            dr.collaborators.isEmpty &&
            tr.collaborators.isEmpty &&
            doc.editor.remoteSelections.value.isEmpty,
        'all explicit original leaves',
      );
      final rejoined = await peer('bob', 'bob-return', 1);
      await until(
        () => dr.collaborators.length == 1 && tr.collaborators.length == 1,
        'peer reconnect',
      );
      await dr.connection.disconnect();
      expect(dr.connection.actorUid, isNull);
      await dr.start();
      await until(
        () => dr.connection.actorUid == uid && dr.collaborators.length == 1,
        'authenticated leader reconnect restores roster',
      );
      checks.add(
        'connection-bound-profile-identity-clears-on-disconnect-and-restores-after-original-reconnect',
      );
      if (mobile) await tap(find.text('完成').first);
      final documentButton = find.byKey(
        const ValueKey('smart-document.collaborators'),
      );
      expect(
        find.descendant(of: documentButton, matching: find.text('2 人')),
        findsOneWidget,
      );
      await tap(documentButton);
      expect(find.text('在线协作者'), findsOneWidget);
      expect(find.text('我'), findsOneWidget);
      await shot('users-document-roster.png');
      Navigator.of(t.element(find.text('在线协作者'))).pop();
      await t.pump(const Duration(milliseconds: 300));
      checks.add(
        'actual-desktop-mobile-document-member-entry-shares-same-user-roster',
      );
      await rejoined.close();
      await until(
        () => dr.collaborators.isEmpty && tr.collaborators.isEmpty,
        'final leave',
      );
      await doc.synchronize();
      await data.synchronize();
      expect(await w.document.session.prepareToClose(), true);
      expect(await w.dataset.session.prepareToClose(), true);
      final contents = jsonEncode([
        doc.snapshot['data'],
        data.snapshot['views'],
        await doc.store.read(),
        data.bundle,
      ]);
      expect(contents, isNot(contains('accessToken')));
      expect(contents, isNot(contains('muse.document.presence')));
      expect(contents, isNot(contains('muse.dataset.presence')));
      expect(contents, isNot(contains('user-bob')));
      checks.add(
        'profile-and-original-awareness-remain-transient-and-independent-content-checkpoints-save',
      );
      await shot('users-editor.png');
      expect(t.takeException(), isNull);
      await File('${evidence.path}/users-e2e.json').writeAsString(
        jsonEncode({
          'status': 'passed',
          'platform': Platform.isIOS ? 'ios' : 'macos',
          'run': StageOneWorkbench.run,
          'objectId': doc.objectId,
          'datasetObjectId': data.objectId,
          'target': w.target.toJson(),
          'views': data.snapshot['views'],
          'uids': {'alice': uid, 'bob': bobUid},
          'checks': checks,
          'fullProductAcceptance': 'not-complete',
        }),
      );
      await t.pumpWidget(const SizedBox());
      await t.pump();
      await w.close();
      debugPrint('SMARTDOC_USERS_EVIDENCE=${evidence.path}');
    },
  );
}
