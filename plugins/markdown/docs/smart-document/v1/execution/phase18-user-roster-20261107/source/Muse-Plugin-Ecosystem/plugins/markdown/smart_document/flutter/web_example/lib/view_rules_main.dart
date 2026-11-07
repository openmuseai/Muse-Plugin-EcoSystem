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

const objectId = String.fromEnvironment('RULES_OBJECT'),
    datasetId = String.fromEnvironment('RULES_DATASET'),
    rowId = String.fromEnvironment('RULES_ROW_A'),
    rowB = String.fromEnvironment('RULES_ROW_B'),
    targetJson = String.fromEnvironment('RULES_TARGET'),
    run = String.fromEnvironment('SMARTDOC_RUN'),
    workspace = String.fromEnvironment('SMARTDOC_WORKSPACE'),
    origin = String.fromEnvironment('SMARTDOC_ORIGIN'),
    nonce = String.fromEnvironment('RULES_NONCE'),
    fieldId = 'title';
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
    namespace: 'rules:$workspace:$run:$actor',
    objectId: id,
  );
  DatasetProviderFactory get provider => (type) {
    final gate = _HttpGate();
    gates.add(gate);
    return AppFlowyObjectTransport(
      origin: Uri.parse(origin),
      workspaceId: workspace,
      deviceId: 'rules-web-$run-$actor-$type',
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
            editable: !reopening,
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
                deviceId: 'rules-web-$run-$actor',
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
                deviceId: 'rules-document-web-$run-$actor',
                accessToken: () async => token(actor),
              ),
        editable: !reopening,
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
    for (final g in gates) {
      g.blocked = gated;
    }
    if (gated) {
      networkBefore = gates.fold<int>(0, (s, g) => s + g.networkRequests);
      updatesBefore = realtime!.remoteUpdatesApplied;
    } else {
      unawaited(data!.synchronize());
    }
    setState(() {});
  }

  void require(bool ok, String name) {
    if (!ok) throw StateError(name);
    if (!checks.contains(name)) checks.add(name);
  }

  Future<void> receipt(String kind) async {
    final r = await http.post(
      Uri.base.resolve('/__rules/$kind/$nonce'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'status': 'passed',
        'actor': actor,
        'objectId': objectId,
        'datasetObjectId': datasetId,
        'checks': checks,
        'platform': reopening ? 'web-reload' : 'web',
        'rowA': rowId,
        'rowB': rowB,
      }),
    );
    if (r.statusCode != 204) throw StateError('receipt-not-saved');
  }

  String title(String id) =>
      data!.views.single.rows
              .firstWhere((r) => r.id == id)
              .cells[fieldId]!
              .value
          as String;
  Future<void> verify() async {
    setState(() {
      busy = true;
      failure = null;
    });
    try {
      final c = data!, d = doc!, v = c.views.single;
      require(
        c.objectId == datasetId && d.objectId == objectId,
        'original-native-objects-and-parent-child-resource-identities',
      );
      require(
        jsonEncode(d.snapshot['data']) == parentBefore,
        'view-config-and-child-edit-preserve-parent-reference',
      );
      if (reopening) {
        require(
          realtime == null && !c.canWrite && !d.canWrite,
          'fresh-IndexedDB-reopen-without-provider-or-transient-presence-and-readonly-floor',
        );
        require(
          v.filters.single['content'] == 'Muse' &&
              v.sorts.single['condition'] == 0 &&
              v.rows.first.id == rowId &&
              title(rowB) == 'Muse B',
          'shared-filters-sorts-and-peer-row-retained-in-original-local-checkpoint',
        );
        await receipt('reload');
        setState(() => passed = true);
        return;
      }
      require(
        v.rulesReady &&
            v.rows.length == 2 &&
            c.rowObjectIds.containsAll([rowId, rowB]),
        'visible-projection-is-independent-of-original-row-dependencies',
      );
      if (actor == 'bob') {
        require(
          v.filters.single['content'] == 'Muse' &&
              v.sorts.single['condition'] == 0 &&
              title(rowId) == 'Muse A' &&
              title(rowB) == 'Muse B',
          'peer-observes-shared-root-config-and-both-stable-row-identities',
        );
        await c.synchronize();
        await receipt('peer');
        setState(() => passed = true);
        return;
      }
      if (phase == 0) {
        require(
          gated &&
              gates.fold<int>(0, (s, g) => s + g.networkRequests) ==
                  networkBefore,
          'zero-HTTP-content-requests-during-hidden-row-reentry',
        );
        require(
          realtime!.remoteUpdatesApplied > updatesBefore &&
              v.filters.single['content'] == 'Muse A' &&
              title(rowB) == 'Muse A',
          'actual-peer-UI-edit-of-hidden-row-reenters-filter-over-original-WS2',
        );
        setState(() => phase = 1);
        return;
      }
      if (phase == 1) {
        require(
          v.filters.single['content'] == 'Muse',
          'peer-view-config-replaces-committed-rule-while-local-draft-is-open',
        );
        setState(() => phase = 2);
        return;
      }
      require(
        !gated &&
            v.filters.single['content'] == 'Muse' &&
            v.sorts.single['condition'] == 0 &&
            v.rows.first.id == rowId &&
            title(rowB) == 'Muse B',
        'shared-multi-key-sort-reprojects-live-peer-value-with-stable-row-identity',
      );
      require(
        historyEvents.length >= 2 &&
            historyEvents[historyEvents.length - 2] == 'undo' &&
            historyEvents.last == 'redo',
        'actual-child-original-undo-redo-keeps-peer-cell-and-parent-reference',
      );
      await c.synchronize();
      await c.flush();
      await d.flush();
      require(
        c.syncState == DatasetSyncState.accepted,
        'original-Root1-and-Row4-HTTP-repair-accepted-and-local-checkpoint-flushed',
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
                    title: '智能文档 · 共享数据库视图',
                    embeds: host,
                  ),
          ),
          SizedBox(
            width: 280,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                children: [
                  const Text('双浏览器验收辅助'),
                  Text('当前测试会话：$actor'),
                  const SizedBox(height: 12),
                  Text(
                    reopening
                        ? '只读恢复原文档与数据库本机副本'
                        : actor == 'bob'
                        ? '先打开 Muse Z 的文本草稿；Alice 隐藏该行后，将其改为 Muse A。之后更改筛选内容为 Muse；最终把第二行改为 Muse B。'
                        : phase == 0
                        ? '先让 Bob 打开第二行草稿；将筛选内容改为 Muse A，暂停此端 HTTP。等 Bob 提交同样的标题后验收。'
                        : phase == 1
                        ? '恢复 HTTP 并打开筛选草稿；让 Bob 将筛选内容改为 Muse。提交旧草稿确认冲突后取消，再核对共享设置。'
                        : '将排序设为升序；让 Bob 将第二行改为 Muse B。使用子表撤销、重做，然后完成验收。',
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
                          ? '验收协作者'
                          : phase == 0
                          ? '验收隐藏记录更新'
                          : phase == 1
                          ? '核对共享规则'
                          : '完成视图验收',
                    ),
                  ),
                  if (failure != null) Text('失败：$failure'),
                  if (passed) Text('通过 ${checks.length} 项'),
                  for (final check in checks) Text('✓ $check'),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
