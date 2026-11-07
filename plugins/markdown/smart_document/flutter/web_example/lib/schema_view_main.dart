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

const nativeFieldId = String.fromEnvironment('SCHEMA_VIEW_NATIVE_FIELD'),
    nativeRowId = String.fromEnvironment('SCHEMA_VIEW_NATIVE_ROW');
const objectId = String.fromEnvironment('SCHEMA_VIEW_OBJECT'),
    datasetId = String.fromEnvironment('SCHEMA_VIEW_DATASET'),
    firstId = String.fromEnvironment('SCHEMA_VIEW_FIRST'),
    nativeLinkedId = String.fromEnvironment('SCHEMA_VIEW_NATIVE_LINKED'),
    nativeTemporaryId = String.fromEnvironment('SCHEMA_VIEW_NATIVE_TEMPORARY'),
    targetJson = String.fromEnvironment('SCHEMA_VIEW_TARGET'),
    parentJson = String.fromEnvironment('SCHEMA_VIEW_PARENT_DATA'),
    nonce = String.fromEnvironment('SCHEMA_VIEW_NONCE'),
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
  final checks = <String>[];
  SmartDocumentController? doc;
  DatasetController? data;
  DatasetRealtimeSession? realtime;
  DatasetEmbedRegistry? registry;
  ResourceEmbedHost? host;
  String? failure, webViewId, temporaryId;
  final historyEvents = <Map<String, dynamic>>[];
  final branch = <String, int>{};
  final httpGate = HttpRequestGate();
  int heldFrames = 0;
  late final frames = OutgoingFrameGate(
    onHeld: (_, bytes) {
      heldFrames++;
      if (mounted) setState(() {});
    },
  );
  bool busy = false, passed = false, left = false;
  int phase = 0;
  String get token => actor == 'bob'
      ? const String.fromEnvironment('SMARTDOC_BOB_TOKEN')
      : const String.fromEnvironment('SMARTDOC_ALICE_TOKEN');
  IndexedDbSnapshotStore store(String id) => IndexedDbSnapshotStore(
    namespace: 'schema-view:$workspace:$run:$actor',
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
                    deviceId: 'number-http-$actor-$type-$run',
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
                deviceId: 'number-web-$actor-$run',
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
            title: '项目金额',
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
                deviceId: 'number-doc-$actor-$run',
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
    for (final view in data?.views ?? <DatasetViewProjection>[]) {
      if (view.name == 'Web协作视图') webViewId ??= view.id;
      if (view.name == 'Web临时视图') temporaryId ??= view.id;
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> action(Future<void> Function() task) async {
    setState(() {
      busy = true;
      failure = null;
    });
    try {
      await task();
    } on Object catch (e) {
      if (mounted) {
        setState(() => failure = '$e');
      }
    }
    if (mounted) {
      setState(() => busy = false);
    }
  }

  void require(bool ok, String label) {
    if (!ok) {
      throw StateError(label);
    }
    if (!checks.contains(label)) {
      checks.add(label);
    }
  }

  DatasetViewProjection? byId(String? id) =>
      data?.views.where((v) => v.id == id).firstOrNull;
  DatasetViewProjection? named(String name) =>
      data?.views.where((v) => v.name == name).firstOrNull;
  DatasetViewProjection? get webView =>
      byId(webViewId) ??
      named('Web远端视图') ??
      named('Web团队视图') ??
      named('Web协作视图');
  DatasetViewProjection? get temporary => byId(temporaryId) ?? named('Web临时视图');
  String? get peerFieldId => data?.views.first.columns
      .where((f) => f.name == 'Web字段' || f.name == 'Web共享字段')
      .firstOrNull
      ?.id;
  String? get peerRowId => byId(
    firstId,
  )?.rows.where((r) => r.cells['title']?.value == 'Web新记录').firstOrNull?.id;
  bool get loaded => data != null && doc != null;
  bool get ready =>
      loaded &&
      (reopening ||
          switch (phase) {
            0 => realtime?.connection.actorUid != null,
            1 => actor == 'bob' || (webView != null && data!.views.length == 4),
            2 => true,
            3 =>
              actor == 'bob'
                  ? webView?.name == 'Web团队视图'
                  : webView?.name == 'Web团队视图' &&
                        webView?.rows.length == 1 &&
                        byId(firstId)?.rows.length == 3,
            4 =>
              actor == 'bob'
                  ? temporary != null && data!.views.length == 5
                  : webView?.name == 'Web远端视图',
            _ => temporary != null && data!.views.length == 5,
          });
  void common() {
    require(
      data!.objectId == datasetId &&
          doc!.objectId == objectId &&
          byId(firstId) != null &&
          byId(nativeLinkedId) != null &&
          byId(nativeTemporaryId) != null &&
          data!.views.every(
            (v) => v.columns.any((f) => f.id == nativeFieldId),
          ) &&
          data!
                  .readRow(nativeLinkedId, nativeRowId)
                  .cells[nativeFieldId]
                  ?.value ==
              '字段并发值',
      'same-original-native-document-dataset-and-three-view-identities',
    );
    require(
      jsonEncode(doc!.snapshot['data']) == parentJson,
      'parent-document-retains-only-its-original-resource-reference',
    );
    if (!reopening) {
      require(
        realtime!.connection.actorUid != null,
        'original-authenticated-actor-owns-independent-root-and-row-session',
      );
    }
  }

  void hold() {
    common();
    httpGate.hold();
    frames.hold();
    heldFrames = 0;
    phase = 1;
  }

  void recordBranch() {
    common();
    require(
      httpGate.held &&
          frames.holding &&
          data!.views.length == 4 &&
          byId(firstId)!.rows.length == 2 &&
          webView!.rows.length == 2 &&
          byId(firstId)!.columns.length == 4,
      'actual-new-view-commits-before-peer-row-and-before-any-network-publication',
    );
    branch.addAll({
      'viewCount': data!.views.length,
      'rowCount': byId(firstId)!.rows.length,
      'heldFrames': heldFrames,
      'httpHeld': 1,
      'fieldCount': byId(firstId)!.columns.length,
    });
    webViewId = webView!.id;
    phase = 2;
  }

  Future<void> peerAdd() async {
    common();
    await data!.addRow(cells: {'title': 'Web新记录'});
    await data!.createField('Web字段', 'text');
    require(
      httpGate.held &&
          frames.holding &&
          data!.views.length == 3 &&
          byId(firstId)!.rows.length == 3 &&
          webView == null &&
          byId(firstId)!.columns.length == 5,
      'actual-peer-row-commits-before-new-view-and-before-any-network-publication',
    );
    branch.addAll({
      'viewCount': data!.views.length,
      'rowCount': byId(firstId)!.rows.length,
      'heldFrames': heldFrames,
      'httpHeld': 1,
      'fieldCount': byId(firstId)!.columns.length,
    });
    unawaited(data!.synchronize());
    phase = 2;
  }

  void release() {
    httpGate.release();
    frames.release();
    phase = 3;
  }

  void merged() {
    common();
    require(
      data!.views.length == 4 &&
          webView!.rows.length == 1 &&
          webView!.rows.single.id == peerRowId &&
          byId(firstId)!.rows.length == 3,
      'concurrent-original-root-row-membership-converges-and-new-view-filter-is-independent',
    );
    require(
      webView!.name == 'Web团队视图' &&
          webView!.filters.length == 1 &&
          byId(nativeLinkedId)!.rows.length == 1 &&
          byId(nativeTemporaryId)!.rows.length == 3,
      'actual-web-view-settings-and-filter-preserve-original-native-view-identities',
    );
    require(
      peerFieldId != null &&
          data!.views.every(
            (v) =>
                v.columns.length == 5 &&
                v.columns.any((f) => f.id == peerFieldId),
          ),
      'concurrent-global-field-id-is-projected-in-every-original-view',
    );
    require(
      webView!.rows.single.cells[peerFieldId]?.value == 'Web字段值',
      'actual-new-column-editor-keeps-original-field-id-and-independent-row-value',
    );
    webViewId = webView!.id;
    phase = 4;
  }

  Future<void> peerRename() async {
    common();
    require(
      realtime!.collaborators.isNotEmpty &&
          realtime!.collaborators.every((p) => p.cell == null),
      'peer-observes-obsolete-cell-position-cleared-after-actual-view-switch',
    );
    final view = webView!;
    webViewId = view.id;
    await data!.renameView(view, 'Web远端视图');
    require(
      webView!.name == 'Web远端视图' && byId(firstId)!.rows.length == 3,
      'peer-view-rename-preserves-original-record-membership-and-filter',
    );
    phase = 4;
  }

  void conflict() {
    require(
      webView!.name == 'Web远端视图' && webView!.id == webViewId,
      'peer-view-name-survives-actual-stale-settings-draft',
    );
    phase = 5;
  }

  Future<void> finish(String kind) async {
    common();
    require(
      data!.views.length == 5 &&
          temporary!.rows.length == 3 &&
          webView!.rows.single.id == peerRowId &&
          peerFieldId != null &&
          data!.readRow(firstId, peerRowId!).cells[peerFieldId]?.value ==
              'Web字段值',
      'five-original-views-share-three-independent-rows-without-copying-document-content',
    );
    require(
      peerFieldId != null &&
          data!.views.every((v) => v.columns.any((f) => f.id == peerFieldId)) &&
          data!.readRow(firstId, peerRowId!).cells[peerFieldId]?.value ==
              'Web字段值',
      'original-peer-field-id-and-value-survive-in-every-view-checkpoint',
    );
    if (actor == 'alice') {
      require(
        temporaryId != null &&
            historyEvents.any(
              (e) =>
                  e['action'] == 'undo' &&
                  e['applied'] == true &&
                  !(e['viewIds'] as List).contains(temporaryId),
            ) &&
            historyEvents.any(
              (e) =>
                  e['action'] == 'redo' &&
                  e['applied'] == true &&
                  (e['viewIds'] as List).contains(temporaryId),
            ),
        'actual-original-undo-removes-view-and-redo-restores-the-same-view-id',
      );
    }
    require(
      !jsonEncode(data!.bundle).contains('accessToken'),
      'independent-checkpoint-contains-no-authentication-credentials',
    );
    await data!.flush();
    await data!.synchronize();
    await doc!.flush();
    await receipt(kind);
    passed = true;
  }

  Future<void> offline() async {
    common();
    require(
      data!.views.length == 5 &&
          byId(firstId)!.rows.length == 3 &&
          webView!.rows.single.id == peerRowId &&
          peerFieldId != null &&
          data!.readRow(firstId, peerRowId!).cells[peerFieldId]?.value ==
              'Web字段值',
      'offline-original-five-views-and-three-row-identities-retain-independent-rules',
    );
    require(
      realtime == null && !data!.canWrite && !doc!.canWrite,
      'offline-has-no-network-provider-presence-or-edit-grant',
    );
    require(
      !jsonEncode(data!.bundle).contains('accessToken'),
      'independent-checkpoint-contains-no-authentication-credentials',
    );
    await receipt('reload');
    passed = true;
  }

  Future<void> receipt(String kind) async {
    final result = await http.post(
      Uri.base.resolve('/__schema_view/$kind/$nonce'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'status': 'passed',
        'actor': actor,
        'objectId': objectId,
        'datasetObjectId': datasetId,
        'checks': checks,
        'platform': reopening ? 'web-reload' : 'web',
        'phase': phase,
        'webViewId': webView!.id,
        'temporaryViewId': temporary!.id,
        'peerRowId': peerRowId,
        'peerFieldId': peerFieldId,
        'branch': branch,
        'history': historyEvents,
        'views': data!.views
            .map(
              (v) => {
                'id': v.id,
                'name': v.name,
                'rowIds': v.rows.map((r) => r.id).toList(),
                'filterCount': v.filters.length,
                'fieldIds': v.columns.map((f) => f.id).toList(),
              },
            )
            .toList(),
      }),
    );
    if (result.statusCode != 204) throw StateError('receipt-not-saved');
  }

  Future<void> leave() async {
    httpGate.release();
    frames.release();
    data!.pauseCollaboration(true);
    await realtime?.close();
    await data!.flush();
    await doc!.flush();
    left = true;
  }

  String get label => reopening
      ? '验证离线视图'
      : switch (phase) {
          0 => '暂停并发发布',
          1 => actor == 'alice' ? '记录本地分支' : '协作端新增记录',
          2 => '恢复并发发布',
          3 => actor == 'alice' ? '验证合并与切换' : '协作端改视图名称',
          4 => actor == 'alice' ? '验证名称冲突' : '验证最终同步',
          _ => '验证最终视图并保存',
        };
  Future<void> advance() async {
    if (reopening) {
      await offline();
      return;
    }
    switch (phase) {
      case 0:
        hold();
      case 1:
        if (actor == 'alice') {
          recordBranch();
        } else {
          await peerAdd();
        }
      case 2:
        release();
      case 3:
        if (actor == 'alice') {
          merged();
        } else {
          await peerRename();
        }
      case 4:
        if (actor == 'alice') {
          conflict();
        } else {
          await finish('peer');
        }
      default:
        await finish('result');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: doc == null
        ? Center(child: Text(failure ?? '加载原协作文档…'))
        : Row(
            children: [
              Expanded(
                child: SmartDocumentView(
                  controller: doc!,
                  title: '智能文档 · 多视图协作',
                  embeds: host,
                ),
              ),
              const VerticalDivider(width: 1),
              SizedBox(
                width: 290,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('视图验收 · $actor${reopening ? ' / offline' : ''}'),
                    if (failure != null) Text('FAIL: $failure'),
                    ElevatedButton(
                      onPressed: busy || passed || !ready
                          ? null
                          : () => action(advance),
                      child: Text(label),
                    ),
                    Text('阶段 $phase · ${data?.views.length ?? 0} 个视图'),
                    Text('原主成员 ${byId(firstId)?.rows.length ?? 0}'),
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
