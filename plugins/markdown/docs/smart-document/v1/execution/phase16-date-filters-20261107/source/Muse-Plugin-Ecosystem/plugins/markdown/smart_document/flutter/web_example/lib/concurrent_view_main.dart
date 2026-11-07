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

const objectId = String.fromEnvironment('CONCURRENT_OBJECT'),
    datasetId = String.fromEnvironment('CONCURRENT_DATASET'),
    rowId = String.fromEnvironment('CONCURRENT_ROW_A'),
    rowB = String.fromEnvironment('CONCURRENT_ROW_B'),
    targetJson = String.fromEnvironment('CONCURRENT_TARGET'),
    run = String.fromEnvironment('SMARTDOC_RUN'),
    workspace = String.fromEnvironment('SMARTDOC_WORKSPACE'),
    origin = String.fromEnvironment('SMARTDOC_ORIGIN'),
    nonce = String.fromEnvironment('CONCURRENT_NONCE'),
    ruleId = String.fromEnvironment('CONCURRENT_RULE_ID'),
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
  OutgoingFrameGate? frames;
  int heldFrames = 0;
  String? branch0, branch1, merge0;
  Map<String, dynamic>? merge1;
  bool obsoleteVerified = false;
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
    namespace: 'concurrent:$workspace:$run:$actor',
    objectId: id,
  );
  DatasetProviderFactory get provider => (type) {
    final gate = _HttpGate();
    gates.add(gate);
    return AppFlowyObjectTransport(
      origin: Uri.parse(origin),
      workspaceId: workspace,
      deviceId: 'concurrent-web-$run-$actor-$type',
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
      if (wire != null) {
        frames = OutgoingFrameGate(
          onHeld: (_, _) {
            heldFrames++;
            if (mounted) {
              setState(() {});
            }
          },
        );
      }
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
                deviceId: 'concurrent-web-$run-$actor',
                clientId: DateTime.now().microsecondsSinceEpoch.toString(),
                accessToken: () async => token(actor),
                codec: AppFlowyRealtimeCodec(wire),
                socketFactory: (uri) => frames!.open(actor, uri),
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
                deviceId: 'concurrent-document-web-$run-$actor',
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

  String get content => data!.views.single.filters.single['content'] as String;
  int get direction => data!.views.single.sorts.single['condition'] as int;
  void hold() {
    frames!.hold();
    heldFrames = 0;
    gated = true;
    for (final g in gates) {
      g.blocked = true;
    }
    networkBefore = gates.fold<int>(0, (s, g) => s + g.networkRequests);
    updatesBefore = realtime!.remoteUpdatesApplied;
    setState(() {});
  }

  void publish() {
    frames!.release();
    setState(() {});
  }

  void restoreHttp() {
    gated = false;
    for (final g in gates) {
      g.blocked = false;
    }
    unawaited(data!.synchronize());
    setState(() {});
  }

  void require(bool ok, String name) {
    if (!ok) throw StateError(name);
    if (!checks.contains(name)) checks.add(name);
  }

  Future<void> receipt(String kind) async {
    final r = await http.post(
      Uri.base.resolve('/__concurrent/$kind/$nonce'),
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
        'branch0': branch0,
        'branch1': branch1,
        'merge0': merge0,
        'merge1': merge1,
        'obsolete': obsoleteVerified,
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
  bool get noHttp =>
      gated &&
      gates.fold<int>(0, (s, g) => s + g.networkRequests) == networkBefore;
  Future<void> verify() async {
    setState(() {
      busy = true;
      failure = null;
    });
    try {
      final c = data!, d = doc!, v = c.views.single;
      require(
        c.objectId == datasetId && d.objectId == objectId,
        'original-native-parent-and-dataset-resource-identities',
      );
      require(
        jsonEncode(d.snapshot['data']) == parentBefore,
        'parent-keeps-only-original-generic-resource-reference',
      );
      require(
        v.rulesReady && c.rowObjectIds.containsAll([rowId, rowB]),
        'authoritative-row-dependencies-stay-independent-of-visible-view',
      );
      if (reopening) {
        require(
          realtime == null && !c.canWrite && !d.canWrite,
          'fresh-IndexedDB-reopen-without-provider-or-transient-presence-and-readonly-floor',
        );
        require(
          content == 'Muse' &&
              direction == 0 &&
              v.rows.first.id == rowId &&
              title(rowB) == 'Muse Browser',
          'shared-view-and-final-browser-row-restored-from-original-local-checkpoint',
        );
        await receipt('reload');
        setState(() => passed = true);
        return;
      }
      if (phase == 0) {
        require(
          frames!.holding &&
              noHttp &&
              heldFrames > 0 &&
              content == (actor == 'alice' ? 'Muse A' : 'Muse Z'),
          'different-local-rule-branch-committed-before-any-original-frame-is-published',
        );
        branch0 = content;
        setState(() => phase = 1);
        return;
      }
      if (phase == 1) {
        require(
          !frames!.holding &&
              noHttp &&
              realtime!.remoteUpdatesApplied > updatesBefore &&
              v.filters.length == 1 &&
              v.filters.single['id'] == ruleId &&
              {'Muse A', 'Muse Z'}.contains(content),
          'concurrent-original-WS2-leaf-merge-keeps-one-stable-rule-with-HTTP-blocked',
        );
        merge0 = content;
        setState(() => phase = 2);
        return;
      }
      if (phase == 2) {
        require(
          frames!.holding &&
              noHttp &&
              heldFrames > 0 &&
              (actor == 'alice'
                  ? content == 'Muse A' && direction == 1
                  : content == 'Muse' && direction == 0),
          'independent-local-filter-and-sort-branches-committed-before-publication',
        );
        branch1 = '$content/$direction';
        setState(() => phase = 3);
        return;
      }
      if (phase == 3) {
        require(
          !frames!.holding &&
              noHttp &&
              realtime!.remoteUpdatesApplied > updatesBefore &&
              content == 'Muse A' &&
              direction == 0 &&
              v.rows.single.id == rowId,
          'independent-concurrent-filter-and-sort-intents-both-survive-original-merge',
        );
        merge1 = {'filter': content, 'direction': direction};
        setState(() => phase = 4);
        return;
      }
      if (actor == 'bob') {
        require(
          !gated &&
              content == 'Muse' &&
              direction == 0 &&
              title(rowB) == 'Muse Browser',
          'peer-observes-final-shared-view-and-browser-row-edit',
        );
        await c.synchronize();
        await receipt('peer');
        setState(() => passed = true);
        return;
      }
      if (phase == 4) {
        require(
          c.lastHistoryApplied == false &&
              content == 'peer' &&
              v.filters.length == 1 &&
              c.rowObjectIds.length == 2,
          'actual-obsolete-undo-consumes-one-item-without-removing-peer-rule-or-earlier-root-command',
        );
        obsoleteVerified = true;
        setState(() => phase = 5);
        return;
      }
      require(
        !gated &&
            content == 'Muse' &&
            direction == 0 &&
            title(rowId) == 'Muse A' &&
            title(rowB) == 'Muse Browser' &&
            historyEvents.length >= 2 &&
            historyEvents[historyEvents.length - 2] == 'undo' &&
            historyEvents.last == 'redo',
        'actual-browser-cell-edit-and-bounded-original-row-undo-redo-preserve-stable-identities',
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

  String get instructions => reopening
      ? '只读恢复原文档与数据库本机副本'
      : switch (phase) {
          0 =>
            '两端先暂存出站原帧并阻止 HTTP；Alice 将筛选改为 Muse A，Bob 改为 Muse Z。分别核对本端分支后再发布。',
          1 => '两端分别发布暂存原帧，保持 HTTP 关闭；核对同一规则的合并结果。',
          2 =>
            '先恢复两端 HTTP；Alice 将筛选恢复为 Muse。两端再暂存原帧，Alice 改筛选为 Muse A，Bob 只将排序改为升序。',
          3 => '分别发布原帧，保持 HTTP 关闭；核对筛选 Muse A 与升序均保留。',
          4 =>
            actor == 'bob'
                ? '恢复 HTTP；等待 Alice 将筛选改为 Muse，再将其改为 peer。等待最终记录编辑后验收。'
                : '恢复 HTTP 并将筛选改为 Muse。等待 Bob 改为 peer 后点击子表撤销，确认保留提示，再核对撤销边界。',
          _ => '将筛选恢复为 Muse；将第二行改为 Muse Browser。使用子表撤销、重做后完成验收。',
        };
  String get verifyLabel => reopening
      ? '验收本机恢复'
      : switch (phase) {
          0 => '核对第一组本端分支',
          1 => '验收并发规则合并',
          2 => '核对第二组本端分支',
          3 => '验收独立配置合并',
          4 => actor == 'bob' ? '完成同伴验收' : '核对撤销边界',
          _ => '完成并发视图验收',
        };
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
                    title: '智能文档 · 并发数据库视图',
                    embeds: host,
                  ),
          ),
          SizedBox(
            width: 290,
            child: ListenableBuilder(
              listenable: Listenable.merge([data, doc]),
              builder: (context, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: ListView(
                  children: [
                    const Text('真实并发验收辅助'),
                    Text('当前测试会话：$actor'),
                    const SizedBox(height: 12),
                    Text(instructions),
                    if (data != null && data!.views.single.filters.isNotEmpty)
                      Text('实际筛选：$content；实际排序：$direction'),
                    if (!reopening) ...[
                      Text('已暂存原帧：$heldFrames；HTTP ${gated ? '已阻止' : '正常'}'),
                      if (frames?.holding != true && !gated)
                        OutlinedButton(
                          onPressed: data == null ? null : hold,
                          child: const Text('暂存原帧并阻止 HTTP'),
                        ),
                      if (frames?.holding == true)
                        OutlinedButton(
                          onPressed: publish,
                          child: const Text('发布原帧，仍阻止 HTTP'),
                        ),
                      if (gated && frames?.holding != true)
                        OutlinedButton(
                          onPressed: restoreHttp,
                          child: const Text('恢复 HTTP'),
                        ),
                    ],
                    FilledButton(
                      onPressed: data == null || busy || passed ? null : verify,
                      child: Text(verifyLabel),
                    ),
                    if (failure != null) Text('失败：$failure'),
                    if (passed) Text('通过 ${checks.length} 项'),
                    for (final check in checks) Text('✓ $check'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
