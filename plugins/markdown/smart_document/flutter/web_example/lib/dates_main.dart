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

const objectId = String.fromEnvironment('DATES_OBJECT'),
    datasetId = String.fromEnvironment('DATES_DATASET'),
    rowId = String.fromEnvironment('DATES_ROW'),
    targetJson = String.fromEnvironment('DATES_TARGET'),
    run = String.fromEnvironment('SMARTDOC_RUN'),
    workspace = String.fromEnvironment('SMARTDOC_WORKSPACE'),
    origin = String.fromEnvironment('SMARTDOC_ORIGIN'),
    nonce = String.fromEnvironment('DATES_NONCE'),
    fieldId = String.fromEnvironment('DATES_FIELD');
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
    namespace: 'dates:$workspace:$run:$actor',
    objectId: id,
  );
  DatasetProviderFactory get provider => (type) {
    final gate = _HttpGate();
    gates.add(gate);
    return AppFlowyObjectTransport(
      origin: Uri.parse(origin),
      workspaceId: workspace,
      deviceId: 'dates-web-$run-$actor-$type',
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
                deviceId: 'dates-web-$run-$actor',
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
                deviceId: 'dates-document-web-$run-$actor',
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

  Future<void> receipt(String kind) async {
    final response = await http.post(
      Uri.base.resolve('/__dates/$kind/$nonce'),
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
    setState(() {
      busy = true;
      failure = null;
    });
    try {
      final d = doc!, c = data!;
      final cell = c.views.single.rows
          .singleWhere((r) => r.id == rowId)
          .cells[fieldId]!;
      final value = cell.value as Map;
      require(
        d.blocks.any(
          (b) =>
              b.type == 'grid' &&
              ResourceEmbedTarget.fromJson(b.attributes['muse_embed']).key ==
                  ResourceEmbedTarget.fromJson(jsonDecode(targetJson)).key,
        ),
        'native-parent-locator-resolves-the-same-independent-original-database-and-row',
      );
      require(
        jsonEncode(d.snapshot['data']) == parentBefore,
        'child-date-edits-preserve-parent-document-data',
      );
      require(
        c.views.single.columns.singleWhere((f) => f.id == fieldId).timezone ==
                'America/New_York' &&
            value['includeTime'] == true &&
            value['isRange'] == true,
        'original-date-field2-uses-persisted-IANA-timezone-time-and-range-flags',
      );
      final finalValue = reopening || actor == 'bob' || phase > 0;
      require(
        value['start'] ==
                (finalValue
                    ? '2026-11-18T09:10:11-05:00'
                    : '2026-11-16T11:22:33-05:00') &&
            value['end'] ==
                (finalValue
                    ? '2026-11-19T12:13:14-05:00'
                    : '2026-11-17T12:34:56-05:00'),
        'actual-browser-date-form-values-keep-seconds-and-range-end-in-original-row',
      );
      if (reopening) {
        require(
          realtime == null,
          'IndexedDB-reopen-keeps-date-values-without-live-socket-or-credentials',
        );
        await receipt('reload');
        setState(() => passed = true);
        return;
      }
      require(
        realtime!.connected && realtime!.collaborators.isNotEmpty,
        'original-root-awareness-has-authenticated-peer',
      );
      if (actor == 'bob' || phase == 0) {
        require(
          gated &&
              gates.fold<int>(0, (s, g) => s + g.networkRequests) ==
                  networkBefore,
          'HTTP-content-routes-gated-with-zero-additional-network-requests',
        );
        require(
          realtime!.remoteUpdatesApplied > updatesBefore,
          'date-row-update-arrived-over-original-WS2-while-HTTP-gated',
        );
      }
      if (actor == 'bob') {
        await receipt('peer');
        setState(() => passed = true);
        return;
      }
      if (phase == 0) {
        setState(() => phase = 1);
        return;
      }
      require(
        !gated &&
            historyEvents.length >= 2 &&
            historyEvents[historyEvents.length - 2] == 'undo' &&
            historyEvents.last == 'redo',
        'actual-shared-child-undo-redo-keeps-peer-date-and-parent-locator',
      );
      await c.synchronize();
      await c.flush();
      await d.flush();
      require(
        c.syncState == DatasetSyncState.accepted,
        'root-row-HTTP-repair-accepted-and-local-checkpoint-flushed',
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
                    title: '智能文档 · 日期协作',
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
                        ? '暂停此端 HTTP；编辑日期范围为 11月16日 11:22:33 至 11月17日 12:34:56。等待 Alice 继续编辑后核对。'
                        : phase == 0
                        ? '暂停此端 HTTP；打开日期输入草稿。让 Bob 修改同格后提交，确认草稿冲突并取消，再验收。'
                        : '恢复此端 HTTP；实际编辑日期为 11月18日 09:10:11 至 11月19日 12:13:14。子表格撤销、重做后完成验收。',
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
                          ? '核对远端日期'
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
