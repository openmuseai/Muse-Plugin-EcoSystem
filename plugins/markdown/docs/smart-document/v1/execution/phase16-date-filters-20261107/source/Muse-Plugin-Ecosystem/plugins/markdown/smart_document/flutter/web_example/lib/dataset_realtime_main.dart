import 'dart:async';
import 'dart:convert';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:muse_content_store/browser.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';
import 'package:openmuse_smart_document/browser.dart';

const objectId = String.fromEnvironment('DATASET_REALTIME_OBJECT'),
    datasetId = String.fromEnvironment('DATASET_REALTIME_DATASET'),
    rowId = String.fromEnvironment('DATASET_REALTIME_ROW'),
    targetJson = String.fromEnvironment('DATASET_REALTIME_TARGET'),
    run = String.fromEnvironment('SMARTDOC_RUN'),
    workspace = String.fromEnvironment('SMARTDOC_WORKSPACE'),
    origin = String.fromEnvironment('SMARTDOC_ORIGIN'),
    nonce = String.fromEnvironment('DATASET_REALTIME_NONCE');
String token(String who) => who == 'bob'
    ? const String.fromEnvironment('SMARTDOC_BOB_TOKEN')
    : const String.fromEnvironment('SMARTDOC_ALICE_TOKEN');

class _HttpGate extends http.BaseClient {
  final http.Client inner = http.Client();
  bool blocked = false;
  int networkRequests = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest r) {
    if (blocked) throw http.ClientException('test-http-route-offline');
    networkRequests++;
    return inner.send(r);
  }

  @override
  void close() => inner.close();
}

/// Observe the real shared core boundary without replacing its history engine.
final class _HistoryTraceCore implements DatasetCore {
  _HistoryTraceCore(this.inner, this.events);
  final DatasetCore inner;
  final List<String> events;
  @override
  Map<String, dynamic> call(Map<String, dynamic> request) {
    final result = inner.call(request);
    if ({'undo', 'redo'}.contains(request['action'])) {
      events.add(request['action'] as String);
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
  final gates = <_HttpGate>[], checks = <String>[];
  final historyEvents = <String>[];
  final nativeRows =
      (jsonDecode(const String.fromEnvironment('DATASET_REALTIME_ROWS'))
              as List)
          .cast<String>()
          .toSet();
  SmartDocumentController? doc;
  DatasetController? data;
  DatasetRealtimeSession? realtime;
  DatasetEmbedRegistry? registry;
  ResourceEmbedHost? host;
  String? failure, parentBefore;
  bool gated = false, busy = false, passed = false;
  int phase = 0, networkBefore = 0, updatesBefore = 0;
  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  IndexedDbSnapshotStore store(String id) => IndexedDbSnapshotStore(
    namespace: 'dataset-realtime:$workspace:$run:$actor',
    objectId: id,
  );
  DatasetProviderFactory get provider => (type) {
    final gate = _HttpGate();
    gates.add(gate);
    return AppFlowyObjectTransport(
      origin: Uri.parse(origin),
      workspaceId: workspace,
      deviceId: 'dataset-rt-web-$run-$actor-$type',
      accessToken: () async => token(actor),
      binding: datasetBinding(type),
      collabType: type,
      client: gate,
    );
  };
  Future<void> _open() async {
    try {
      final target = ResourceEmbedTarget.fromJson(jsonDecode(targetJson));
      final engine = _HistoryTraceCore(await loadDatasetCore(), historyEvents);
      final wire = reopening ? null : await loadRealtimeWireCore();
      registry = DatasetEmbedRegistry(
        open: (request) async {
          if (request.key != target.key) {
            throw const ResourceFailure('RESOURCE_NOT_AUTHORIZED');
          }
          final c = await DatasetController.open(
            core: engine,
            store: store(datasetId),
            objectId: datasetId,
            providerFactory: reopening ? null : provider,
            syncInterval: null,
          );
          DatasetRealtimeSession? rt;
          if (wire != null) {
            rt = DatasetRealtimeSession(
              controller: c,
              presenceCore: wire,
              connection: AppFlowyRealtimeConnection(
                origin: Uri.parse(origin),
                workspaceId: workspace,
                deviceId: 'dataset-rt-web-$run-$actor',
                clientId: DateTime.now().microsecondsSinceEpoch.toString(),
                accessToken: () async => token(actor),
                codec: AppFlowyRealtimeCodec(wire),
              ),
            );
            await rt.start();
          }
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
        provider: reopening
            ? null
            : AppFlowyCollaborationProvider(
                origin: Uri.parse(origin),
                workspaceId: workspace,
                deviceId: 'dataset-rt-document-web-$run-$actor',
                accessToken: () async => token(actor),
              ),
        createRemote: false,
        syncInterval: null,
      );
      if (mounted) {
        setState(() {
          doc = c;
          parentBefore = jsonEncode(c.snapshot['data']);
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => failure = '$e');
    }
  }

  void toggleGate() {
    gated = !gated;
    for (final gate in gates) {
      gate.blocked = gated;
    }
    if (gated) {
      networkBefore = gates.fold<int>(0, (s, g) => s + g.networkRequests);
      updatesBefore = realtime!.remoteUpdatesApplied;
    } else {
      unawaited(data!.synchronize());
    }
    setState(() {});
  }

  void require(bool ok, String check) {
    if (!ok) throw StateError(check);
    if (!checks.contains(check)) checks.add(check);
  }

  String? newRow() => data!.views.single.rows
      .where(
        (r) =>
            !nativeRows.contains(r.id) && r.cells['title']?.value == '网页新增记录',
      )
      .firstOrNull
      ?.id;
  Future<void> receipt(String kind) async {
    final response = await http.post(
      Uri.base.resolve('/__dataset_realtime/$kind/$nonce'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'status': 'passed',
        'actor': actor,
        'objectId': objectId,
        'datasetObjectId': datasetId,
        'rowId': rowId,
        'newRowId': newRow(),
        'checks': checks,
        'platform': reopening ? 'web-reload' : 'web',
        'date': DateTime.now().toUtc().toIso8601String(),
      }),
    );
    if (response.statusCode != 204) throw StateError('receipt-not-saved');
  }

  Future<void> verify() async {
    setState(() {
      busy = true;
      failure = null;
    });
    try {
      final d = doc!, c = data!;
      final row = c.views.single.rows.singleWhere((r) => r.id == rowId);
      require(
        d.blocks.any(
          (b) =>
              b.type == 'grid' &&
              ResourceEmbedTarget.fromJson(b.attributes['muse_embed']).key ==
                  ResourceEmbedTarget.fromJson(jsonDecode(targetJson)).key,
        ),
        'same-native-document-grid-locator-and-independent-database-row-identities',
      );
      require(
        row.cells['title']!.value == '网页协作者更新😀',
        'actual-peer-browser-cell-form-value-visible-in-current-wasm-session',
      );
      require(
        jsonEncode(d.snapshot['data']) == parentBefore,
        'child-realtime-edits-do-not-mutate-parent-document-data',
      );
      if (reopening) {
        require(
          newRow() != null,
          'new-independent-row-and-original-origin-history-result-restored-from-indexeddb',
        );
        require(
          realtime == null,
          'offline-reopen-does-not-connect-a-socket-or-persist-presence',
        );
        await receipt('reload');
        setState(() => passed = true);
        return;
      }
      require(
        realtime!.connected && realtime!.collaborators.isNotEmpty,
        'original-root-awareness-shows-independent-authenticated-browser-peer',
      );
      if (actor == 'bob' || phase == 0) {
        require(
          gated &&
              gates.fold<int>(0, (s, g) => s + g.networkRequests) ==
                  networkBefore,
          'http-gated-reader-makes-zero-additional-content-network-requests',
        );
        require(
          realtime!.remoteUpdatesApplied > updatesBefore,
          'actual-original-ws2-row-or-root-update-applied-after-http-gate',
        );
      }
      if (actor == 'bob') {
        require(
          newRow() != null,
          'dynamically-referenced-row-bootstraps-over-ws-while-http-remains-gated',
        );
        await receipt('peer');
        setState(() => passed = true);
        return;
      }
      if (phase == 0) {
        setState(() => phase = 1);
        return;
      }
      require(
        !gated && newRow() != null,
        'actual-browser-add-row-and-cell-editor-create-new-independent-record',
      );
      require(
        c.canRedo == false &&
            historyEvents.length >= 2 &&
            historyEvents[historyEvents.length - 2] == 'undo' &&
            historyEvents.last == 'redo',
        'actual-child-toolbar-redo-completed-with-peer-title-preserved',
      );
      await c.synchronize();
      await c.flush();
      await d.flush();
      require(
        c.syncState == DatasetSyncState.accepted,
        'separate-original-root-row-http-repair-accepted-before-checkpoint',
      );
      await receipt('result');
      setState(() => passed = true);
    } on Object catch (e) {
      setState(() => failure = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Row(
        children: [
          Expanded(
            child: doc == null
                ? const Center(child: CircularProgressIndicator())
                : SmartDocumentView(
                    controller: doc!,
                    title: '智能文档 · 数据库实时协作',
                    embeds: host,
                  ),
          ),
          SizedBox(
            width: 285,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                children: [
                  const Text('双浏览器验收辅助'),
                  Text('当前测试会话：$actor'),
                  const SizedBox(height: 10),
                  Text(
                    reopening
                        ? '仅恢复两个本机副本，不访问协作服务'
                        : actor == 'bob'
                        ? '暂停此端 HTTP；在真实单元格中修改第一行标题，随后核对另一个浏览器新增的记录。'
                        : phase == 0
                        ? '暂停此端 HTTP；打开第一行标题并输入草稿。让 Bob 修改同格后提交，确认冲突提示并取消，再验收。'
                        : '恢复此端 HTTP，新增记录并填写“网页新增记录”；点击子表格撤销、重做后完成验收。',
                  ),
                  if (!reopening)
                    OutlinedButton(
                      onPressed: data == null ? null : toggleGate,
                      child: Text(gated ? '恢复此端 HTTP' : '暂停此端 HTTP'),
                    ),
                  FilledButton(
                    onPressed: data == null || busy || passed ? null : verify,
                    child: Text(
                      reopening
                          ? '验收本机恢复'
                          : actor == 'bob'
                          ? '核对远端新增记录'
                          : phase == 0
                          ? '验收实时编辑'
                          : '完成实时验收',
                    ),
                  ),
                  if (failure != null) Text('失败：$failure'),
                  if (passed) Text('通过 ${checks.length} 项'),
                  for (final c in checks) Text('✓ $c'),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
