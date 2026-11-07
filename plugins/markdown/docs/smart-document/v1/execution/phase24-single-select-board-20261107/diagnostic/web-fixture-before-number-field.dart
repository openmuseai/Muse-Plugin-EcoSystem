import 'dart:async';
import 'dart:convert';
import 'package:muse_collab_test_support/muse_collab_test_support.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:muse_content_store/browser.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';
import 'package:openmuse_smart_document/browser.dart';

const objectId = String.fromEnvironment('BOARD_OBJECT'),
    datasetId = String.fromEnvironment('BOARD_DATASET'),
    firstId = String.fromEnvironment('BOARD_FIRST'),
    nativeBoardId = String.fromEnvironment('BOARD_NATIVE'),
    nativeRowId = String.fromEnvironment('BOARD_ROW'),
    fieldId = String.fromEnvironment('BOARD_FIELD'),
    todoId = String.fromEnvironment('BOARD_TODO'),
    doingId = String.fromEnvironment('BOARD_DOING'),
    doneId = String.fromEnvironment('BOARD_DONE'),
    targetJson = String.fromEnvironment('BOARD_TARGET'),
    parentJson = String.fromEnvironment('BOARD_PARENT_DATA'),
    nonce = String.fromEnvironment('BOARD_NONCE'),
    run = String.fromEnvironment('SMARTDOC_RUN'),
    workspace = String.fromEnvironment('SMARTDOC_WORKSPACE'),
    origin = String.fromEnvironment('SMARTDOC_ORIGIN');

class _HistoryCore implements DatasetCore {
  _HistoryCore(this.inner, this.observe);
  final DatasetCore inner;
  final void Function(String, Map<String, dynamic>) observe;
  @override
  Map<String, dynamic> call(Map<String, dynamic> request) {
    final result = inner.call(request);
    if ({'undo', 'redo'}.contains(request['action'])) {
      observe(request['action'] as String, result);
    }
    return result;
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        AppFlowyEditorLocalizations.delegate,
      ],
      supportedLocales: AppFlowyEditorLocalizations.delegate.supportedLocales,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xff4c63d9),
        useMaterial3: true,
      ),
      home: const _Workbench(),
    ),
  );
}

class _Workbench extends StatefulWidget {
  const _Workbench();
  @override
  State<_Workbench> createState() => _State();
}

class _State extends State<_Workbench> {
  final actor = Uri.base.queryParameters['actor'] == 'bob' ? 'bob' : 'alice';
  final reopening = Uri.base.queryParameters['reopen'] == '1';
  final checks = <String>[],
      historyEvents = <Map<String, dynamic>>[],
      branch = <String, int>{};
  SmartDocumentController? doc;
  DatasetController? data;
  DatasetRealtimeSession? realtime;
  DatasetEmbedRegistry? registry;
  ResourceEmbedHost? host;
  String? failure;
  bool busy = false, passed = false, left = false;
  int phase = 0, heldFrames = 0;
  final httpGate = HttpRequestGate();
  late final frames = OutgoingFrameGate(
    onHeld: (_, bytes) {
      heldFrames++;
      if (mounted) setState(() {});
    },
  );
  String get token => actor == 'bob'
      ? const String.fromEnvironment('SMARTDOC_BOB_TOKEN')
      : const String.fromEnvironment('SMARTDOC_ALICE_TOKEN');
  IndexedDbSnapshotStore store(String id) => IndexedDbSnapshotStore(
    namespace: 'board:$workspace:$run:$actor',
    objectId: id,
  );
  @override
  void initState() {
    super.initState();
    unawaited(open());
  }

  Future<void> open() async {
    try {
      final target = ResourceEmbedTarget.fromJson(jsonDecode(targetJson)),
          engine = _HistoryCore(await loadDatasetCore(), (action, result) {
            if (historyEvents.length < 32) {
              historyEvents.add({
                'action': action,
                'applied': result['historyApplied'] == true,
                'viewIds': (result['views'] as List)
                    .map((v) => v['id'])
                    .toList(),
              });
            }
          });
      registry = DatasetEmbedRegistry(
        open: (request) async {
          if (request.key != target.key) {
            throw const ResourceFailure('RESOURCE_NOT_AUTHORIZED');
          }
          final c = await DatasetController.open(
            core: engine,
            store: store(datasetId),
            objectId: datasetId,
            editable: !reopening,
            syncInterval: null,
            providerFactory: reopening
                ? null
                : (type) => AppFlowyObjectTransport(
                    origin: Uri.parse(origin),
                    workspaceId: workspace,
                    deviceId: 'board-http-$actor-$type-$run',
                    accessToken: () async => token,
                    binding: datasetBinding(type),
                    collabType: type,
                    client: httpGate.client(),
                  ),
          );
          DatasetRealtimeSession? rt;
          if (!reopening) {
            final wire = await loadRealtimeWireCore();
            rt = DatasetRealtimeSession(
              controller: c,
              presenceCore: wire,
              connection: AppFlowyRealtimeConnection(
                origin: Uri.parse(origin),
                workspaceId: workspace,
                deviceId: 'board-web-$actor-$run',
                clientId: DateTime.now().microsecondsSinceEpoch.toString(),
                accessToken: () async => token,
                codec: AppFlowyRealtimeCodec(wire),
                socketFactory: (uri) => frames.open(actor, uri),
              ),
            );
            await rt.start();
          }
          c.addListener(changed);
          if (mounted) {
            setState(() {
              data = c;
              realtime = rt;
            });
          }
          return DatasetEmbedSession(
            controller: c,
            title: '项目数据库',
            realtime: rt,
            close: () async {
              await rt?.close();
              await c.close();
            },
          );
        },
      );
      host = ResourceEmbedHost(build: registry!.build);
      final c = await SmartDocumentController.open(
        core: await WasmDocumentCore.load(),
        store: store(objectId),
        objectId: objectId,
        editable: !reopening,
        syncInterval: null,
        provider: reopening
            ? null
            : AppFlowyCollaborationProvider(
                origin: Uri.parse(origin),
                workspaceId: workspace,
                deviceId: 'board-doc-$actor-$run',
                accessToken: () async => token,
              ),
      );
      if (mounted) {
        setState(() => doc = c);
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() => failure = '$e');
      }
    }
  }

  void changed() {
    if (mounted) setState(() {});
  }

  Future<void> action(Future<void> Function() task) async {
    setState(() {
      busy = true;
      failure = null;
    });
    try {
      await task();
    } on Object catch (e) {
      if (mounted) setState(() => failure = '$e');
    }
    if (mounted) setState(() => busy = false);
  }

  void require(bool ok, String label) {
    if (!ok) throw StateError(label);
    if (!checks.contains(label)) checks.add(label);
  }

  DatasetViewProjection? byId(String id) =>
      data?.views.where((v) => v.id == id).firstOrNull;
  DatasetViewProjection? get web =>
      data?.views.where((v) => v.name == 'Web看板').firstOrNull;
  DatasetRow? get webRow => byId(firstId)?.rows
      .where((r) => {'Web任务', 'Web卡片详情'}.contains(r.cells['title']?.value))
      .firstOrNull;
  bool get loaded => data != null && doc != null;
  bool get ready =>
      loaded &&
      (reopening ||
          switch (phase) {
            0 => realtime?.connected == true,
            1 => actor == 'bob' || web != null,
            2 => true,
            3 =>
              data!.views.length == 3 &&
                  byId(firstId)?.rows.length == 3 &&
                  (actor == 'alice' ||
                      webRow?.cells['title']?.value == 'Web卡片详情'),
            _ =>
              webRow?.cells[fieldId]?.selectedOptionIds.contains(doneId) ==
                  true,
          });
  void common() {
    require(
      data!.objectId == datasetId &&
          doc!.objectId == objectId &&
          objectId != datasetId,
      'same-native-document-and-independent-original-database',
    );
    require(
      byId(nativeBoardId)?.layout == 1 &&
          byId(nativeBoardId)?.board?.ready == true,
      'original-native-board-group-setting-loads-in-wasm',
    );
    require(
      data!.views.every((v) => v.columns.any((f) => f.id == fieldId)) &&
          data!.readRow(firstId, nativeRowId).cells['title']?.value ==
              '卡片详情中编辑',
      'native-fields-and-original-row-values-survive-cross-platform-open',
    );
    require(
      jsonEncode(doc!.snapshot['data']) == parentJson,
      'parent-reference-remains-unchanged',
    );
  }

  void hold() {
    common();
    httpGate.hold();
    frames.hold();
    phase = 1;
  }

  Future<void> localBranch() async {
    if (actor == 'bob') {
      await data!.addRow(
        cells: {
          'title': 'Web任务',
          fieldId: [todoId],
        },
      );
      unawaited(data!.synchronize());
    }
    require(
      data!.views.length == (actor == 'alice' ? 3 : 2) &&
          byId(firstId)!.rows.length == (actor == 'alice' ? 2 : 3),
      'independent-unpublished-board-and-row-branches',
    );
    require(
      heldFrames > 0,
      'original-protobuf-websocket-frames-are-held-before-publish',
    );
    branch.addAll({
      'viewCount': data!.views.length,
      'rowCount': byId(firstId)!.rows.length,
      'heldFrames': heldFrames,
      'httpHeld': httpGate.blockedRequests,
    });
    phase = 2;
  }

  void release() {
    frames.release();
    httpGate.release();
    phase = 3;
  }

  Future<void> edited() async {
    require(
      web != null && data!.views.length == 3 && byId(firstId)!.rows.length == 3,
      'shared-native-and-web-views-converge-on-three-original-row-identities',
    );
    require(
      webRow?.cells['title']?.value == 'Web卡片详情' &&
          webRow?.cells[fieldId]?.selectedOptionIds.contains(doingId) == true,
      'actual-web-card-move-and-record-detail-reach-the-peer',
    );
    if (actor == 'bob') {
      final row = webRow!,
          amount = web!.columns.singleWhere((f) => f.id == 'amount');
      await data!.setCell(
        row,
        amount,
        '12.5',
        expectedHash: row.cells['amount']!.hash,
      );
      await data!.moveBoardCard(web!, data!.readRow(web!.id, row.id), doneId);
    }
    phase = 4;
  }

  Future<void> finish(String kind) async {
    common();
    require(
      webRow?.cells[fieldId]?.selectedOptionIds.contains(doneId) == true &&
          webRow?.cells['amount']?.numberInput == '12.5',
      'peer-original-card-move-and-independent-number-cell-are-preserved',
    );
    require(
      data!.views.every((v) => v.rows.map((r) => r.id).toSet().length == 3) &&
          data!.views.length == 3,
      'all-views-render-the-same-three-row-identities-without-card-copies',
    );
    if (actor == 'alice' && !reopening) {
      require(
        historyEvents
                .where((e) => e['action'] == 'undo' && e['applied'] == true)
                .isNotEmpty &&
            historyEvents
                .where((e) => e['action'] == 'redo' && e['applied'] == true)
                .isNotEmpty &&
            webRow?.cells['title']?.value == 'Web卡片详情',
        'actual-original-undo-redo-retain-the-peer-card-location-and-number-value',
      );
    }
    await data!.flush();
    if (!reopening) await data!.synchronize();
    await doc!.flush();
    await receipt(kind);
    passed = true;
  }

  Future<void> receipt(String kind) async {
    final body = {
      'status': 'passed',
      'actor': actor,
      'objectId': objectId,
      'datasetObjectId': datasetId,
      'platform': reopening ? 'web-reload' : 'web',
      'checks': checks,
      'webViewId': web!.id,
      'webRowId': webRow!.id,
      'fieldId': fieldId,
      'branch': branch,
      'history': historyEvents,
      'views': [
        for (final view in data!.views)
          {
            'id': view.id,
            'layout': view.layout,
            'rowIds': view.rows.map((r) => r.id).toList(),
            'groups': view.board?.groups
                .map((g) => {'id': g.id, 'rowIds': g.rowIds})
                .toList(),
          },
      ],
    };
    final response = await http.post(
      Uri.base.resolve('/__board/$kind/$nonce'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode != 204) {
      throw StateError('receipt ${response.statusCode}');
    }
  }

  Future<void> leave() async {
    httpGate.release();
    frames.release();
    await data!.flush();
    await realtime?.close();
    left = true;
  }

  Future<void> advance() async {
    if (reopening) {
      await finish('reload');
      return;
    }
    switch (phase) {
      case 0:
        hold();
      case 1:
        await localBranch();
      case 2:
        release();
      case 3:
        await edited();
      default:
        await finish(actor == 'alice' ? 'result' : 'peer');
    }
  }

  String get label => reopening
      ? '验证离线看板'
      : switch (phase) {
          0 => '锁定并发分支',
          1 => actor == 'alice' ? '确认本地看板分支' : '创建并发记录',
          2 => '发布并发修改',
          3 => actor == 'alice' ? '验证卡片编辑' : '协作端移动卡片',
          _ => '验证最终看板并保存',
        };
  @override
  Widget build(BuildContext context) => Scaffold(
    body: doc == null
        ? Center(child: Text(failure ?? '加载原协作文档…'))
        : Row(
            children: [
              Expanded(
                child: SmartDocumentView(
                  controller: doc!,
                  title: '智能文档 · 看板协作',
                  embeds: host,
                ),
              ),
              const VerticalDivider(width: 1),
              SizedBox(
                width: 290,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('看板验收 · $actor${reopening ? ' / offline' : ''}'),
                    if (failure != null) Text('FAIL: $failure'),
                    ElevatedButton(
                      onPressed: busy || passed || !ready
                          ? null
                          : () => action(advance),
                      child: Text(label),
                    ),
                    Text(
                      '阶段 $phase · ${data?.views.length ?? 0} 个视图 · ${byId(firstId)?.rows.length ?? 0} 条记录',
                    ),
                    ...checks.map((c) => Text('✓ $c')),
                    if (passed) Text('PASS · ${checks.length} 项'),
                    if (!reopening && !left)
                      TextButton(
                        onPressed: busy || !loaded ? null : () => action(leave),
                        child: const Text('保存并离开'),
                      ),
                  ],
                ),
              ),
            ],
          ),
  );
}
