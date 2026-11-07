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

const objectId = String.fromEnvironment('DATE_FILTER_OBJECT'),
    datasetId = String.fromEnvironment('DATE_FILTER_DATASET'),
    rowId = String.fromEnvironment('DATE_FILTER_ROW'),
    targetJson = String.fromEnvironment('DATE_FILTER_TARGET'),
    run = String.fromEnvironment('SMARTDOC_RUN'),
    workspace = String.fromEnvironment('SMARTDOC_WORKSPACE'),
    origin = String.fromEnvironment('SMARTDOC_ORIGIN'),
    nonce = String.fromEnvironment('DATE_FILTER_NONCE'),
    fieldId = String.fromEnvironment('DATE_FILTER_FIELD');
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
  int networkBefore = 0, updatesBefore = 0;
  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  IndexedDbSnapshotStore store(String id) => IndexedDbSnapshotStore(
    namespace: 'date_filter:$workspace:$run:$actor',
    objectId: id,
  );
  DatasetProviderFactory get provider => (type) {
    final gate = _HttpGate();
    gates.add(gate);
    return AppFlowyObjectTransport(
      origin: Uri.parse(origin),
      workspaceId: workspace,
      deviceId: 'date_filter-web-$run-$actor-$type',
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
                deviceId: 'date_filter-web-$run-$actor',
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
                deviceId: 'date_filter-document-web-$run-$actor',
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
    }
    setState(() {});
  }

  void require(bool ok, String check) {
    if (!ok) throw StateError(check);
    if (!checks.contains(check)) checks.add(check);
  }

  Future<void> runAction(Future<void> Function() action) async {
    setState(() {
      busy = true;
      failure = null;
    });
    try {
      await action();
    } on Object catch (e) {
      if (mounted) setState(() => failure = '$e');
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> peerWrite() async {
    final c = data!,
        view = c.views.single,
        row = c.readRow(view.id, rowId),
        field = view.columns.singleWhere((f) => f.id == fieldId);
    await c.setCell(row, field, {
      'start': '2026-11-10',
      'end': '2026-11-11',
      'includeTime': false,
      'isRange': true,
    }, expectedHash: row.cells[fieldId]!.hash);
  }

  Future<void> receipt(String kind) async {
    final response = await http.post(
      Uri.base.resolve('/__date_filter/$kind/$nonce'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'status': 'passed',
        'actor': actor,
        'objectId': objectId,
        'datasetObjectId': datasetId,
        'rowId': rowId,
        'fieldId': fieldId,
        'checks': checks,
        'platform': reopening ? 'web-reload' : 'web',
        'date': DateTime.now().toUtc().toIso8601String(),
      }),
    );
    if (response.statusCode != 204) throw StateError('receipt-not-saved');
  }

  Future<void> verify() async {
    final c = data!, d = doc!, view = c.views.single;
    require(
      d.blocks.any(
        (b) =>
            b.type == 'grid' &&
            ResourceEmbedTarget.fromJson(b.attributes['muse_embed']).key ==
                ResourceEmbedTarget.fromJson(jsonDecode(targetJson)).key,
      ),
      'native-parent-resolves-same-independent-Root1-Row4-dataset',
    );
    require(
      jsonEncode(d.snapshot['data']) == parentBefore,
      'date-rules-and-row-edits-preserve-parent-generic-reference',
    );
    require(
      view.columns.singleWhere((f) => f.id == fieldId).timezone ==
          'Asia/Shanghai',
      'persisted-field-IANA-zone-used-by-browser-date-rules',
    );
    require(
      view.filters.single['condition'] == 7 &&
          view.rows.length == 4 &&
          view.allRows.length == 4,
      'final-not-empty-rule-shows-four-authoritative-rows',
    );
    final date = c.readRow(view.id, rowId).cells[fieldId]!.value as Map;
    require(
      date['start'] == '2026-11-10' && date['end'] == '2026-11-11',
      'same-original-row-peer-date-edit-preserves-range-end',
    );
    require(
      view.rows.any(
        (r) => (r.cells[fieldId]?.value as Map?)?['start'] == '2026-11-11',
      ),
      'actual-browser-created-row-local-date-edit-retained',
    );
    if (reopening) {
      require(
        realtime == null && gates.isEmpty,
        'IndexedDB-offline-reopen-without-credential-provider-or-socket',
      );
    } else {
      require(
        gated &&
            gates.fold<int>(0, (s, g) => s + g.networkRequests) ==
                networkBefore &&
            realtime!.remoteUpdatesApplied > updatesBefore,
        'original-WS2-converges-Root1-and-Row4-with-HTTP-held',
      );
      if (actor == 'alice') {
        require(
          historyEvents.contains('undo') && historyEvents.contains('redo'),
          'actual-browser-child-original-undo-and-redo-at-core-boundary',
        );
      }
      toggleGate();
      await c.synchronize();
    }
    await receipt(
      reopening
          ? 'reload'
          : actor == 'bob'
          ? 'peer'
          : 'result',
    );
    setState(() => passed = true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: doc == null
        ? Center(child: Text(failure ?? '正在打开独立文档与数据库'))
        : Row(
            children: [
              Expanded(
                child: SmartDocumentView(
                  controller: doc!,
                  title: '智能文档 · 日期筛选',
                  embeds: host,
                ),
              ),
              SizedBox(
                width: 330,
                child: ListenableBuilder(
                  listenable: Listenable.merge([doc!, ?data]),
                  builder: (context, _) => SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('日期筛选验收 · $actor${reopening ? ' · 离线重开' : ''}'),
                        if (data != null) ...[
                          Text(
                            '显示 ${data!.views.single.rows.length}/${data!.views.single.allRows.length} 条 · 条件 ${data!.views.single.filters.map((f) => f['condition']).join(',')}',
                          ),
                          Text(
                            'HTTP ${gates.fold<int>(0, (s, g) => s + g.networkRequests)} · WS更新 ${realtime?.remoteUpdatesApplied ?? 0}',
                          ),
                          Text('历史 ${historyEvents.join(',')}'),
                          if (!reopening)
                            OutlinedButton(
                              onPressed: busy ? null : toggleGate,
                              child: Text(gated ? '恢复HTTP' : '阻断HTTP'),
                            ),
                          if (!reopening && actor == 'bob')
                            FilledButton(
                              onPressed: busy
                                  ? null
                                  : () => runAction(peerWrite),
                              child: const Text('写入同伴日期'),
                            ),
                          FilledButton(
                            onPressed: busy ? null : () => runAction(verify),
                            child: Text(
                              reopening
                                  ? '验收离线重开'
                                  : actor == 'bob'
                                  ? '验收同伴'
                                  : '验收浏览器',
                            ),
                          ),
                        ],
                        for (final check in checks) Text('✓ $check'),
                        if (failure != null)
                          Text(
                            failure!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        if (passed)
                          Text(
                            'PASS · ${checks.length} checks',
                            style: const TextStyle(color: Colors.green),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
  );
}
