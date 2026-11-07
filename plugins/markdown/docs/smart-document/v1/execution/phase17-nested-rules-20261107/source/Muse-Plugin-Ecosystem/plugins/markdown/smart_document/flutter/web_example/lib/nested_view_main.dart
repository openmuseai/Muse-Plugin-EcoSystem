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

const objectId = String.fromEnvironment('NESTED_OBJECT'),
    datasetId = String.fromEnvironment('NESTED_DATASET'),
    rowId = String.fromEnvironment('NESTED_ROW_A'),
    rowB = String.fromEnvironment('NESTED_ROW_B'),
    targetJson = String.fromEnvironment('NESTED_TARGET'),
    run = String.fromEnvironment('SMARTDOC_RUN'),
    workspace = String.fromEnvironment('SMARTDOC_WORKSPACE'),
    origin = String.fromEnvironment('SMARTDOC_ORIGIN'),
    nonce = String.fromEnvironment('NESTED_NONCE'),
    ruleId = String.fromEnvironment('NESTED_RULE_ID'),
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
    namespace: 'nested:$workspace:$run:$actor',
    objectId: id,
  );
  DatasetProviderFactory get provider => (type) {
    final gate = _HttpGate();
    gates.add(gate);
    return AppFlowyObjectTransport(
      origin: Uri.parse(origin),
      workspaceId: workspace,
      deviceId: 'nested-web-$run-$actor-$type',
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
                deviceId: 'nested-web-$run-$actor',
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
                deviceId: 'nested-document-web-$run-$actor',
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

  Map<String, dynamic> get group => Map<String, dynamic>.from(
    jsonDecode(jsonEncode(data!.views.single.filters.single)) as Map,
  );
  String child(int index) =>
      (group['children'] as List)[index]['content'] as String;
  String get content => '${child(0)}/${child(1)}';
  int get mode => group['filter_type'] as int;
  void hold() {
    frames!.hold();
    heldFrames = 0;
    gated = true;
    for (final gate in gates) {
      gate.blocked = true;
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

  Future<void> prepare() async {
    final c = data!, draft = group;
    draft['filter_type'] = 0;
    (draft['children'] as List)[0]['content'] = 'Muse';
    (draft['children'] as List)[1]['content'] = '';
    await c.configureViewRules(c.views.single, filters: [draft], sorts: []);
    await c.synchronize();
  }

  Future<void> receipt(String kind) async {
    final r = await http.post(
      Uri.base.resolve('/__nested/$kind/$nonce'),
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
        'obsolete': false,
      }),
    );
    if (r.statusCode != 204) throw StateError('receipt-not-saved');
  }

  bool get noHttp =>
      gated &&
      gates.fold<int>(0, (s, g) => s + g.networkRequests) == networkBefore;
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

  Future<void> verify() async {
    final c = data!, d = doc!, v = c.views.single;
    require(
      c.objectId == datasetId && d.objectId == objectId,
      'same-native-document-and-independent-dataset-identities',
    );
    require(
      jsonEncode(d.snapshot['data']) == parentBefore,
      'nested-rule-edits-preserve-parent-resource-reference',
    );
    require(
      v.rulesReady && v.filters.single['id'] == ruleId && v.allRows.length == 2,
      'original-filter-JSON-and-filter-independent-row-dependencies',
    );
    if (reopening) {
      require(
        realtime == null && !c.canWrite && !d.canWrite,
        'offline-IndexedDB-readonly-floor-no-provider-or-presence',
      );
      require(
        mode == 1 && content == 'Muse/B' && v.rows.length == 2,
        'nested-group-mode-and-both-child-values-restored',
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
            mode == 0 &&
            content == (actor == 'alice' ? 'Muse A/' : 'Muse/B'),
        'independent-child-branches-committed-before-any-original-frame-is-published',
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
            content == 'Muse A/B' &&
            mode == 0 &&
            v.rows.isEmpty,
        'original-WS2-keeps-both-independent-child-intents-with-HTTP-held',
      );
      merge0 = content;
      setState(() => phase = 2);
      return;
    }
    require(
      !gated && mode == 1 && content == 'Muse/B' && v.rows.length == 2,
      'final-shared-OR-group-keeps-peer-child-and-original-two-rows',
    );
    if (actor == 'alice') {
      require(
        historyEvents.contains('undo') && historyEvents.contains('redo'),
        'actual-browser-child-origin-undo-redo-observed-at-original-core',
      );
    }
    await c.synchronize();
    await c.flush();
    await d.flush();
    require(
      c.syncState == DatasetSyncState.accepted,
      'original-Root1-Row4-repair-accepted-and-independent-checkpoints-flushed',
    );
    await receipt(actor == 'bob' ? 'peer' : 'result');
    setState(() => passed = true);
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
                    title: 'Nested shared view qualification',
                    embeds: host,
                  ),
          ),
          SizedBox(
            width: 300,
            child: ListenableBuilder(
              listenable: Listenable.merge([data, doc]),
              builder: (context, _) => ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('Nested rules: $actor${reopening ? ' / offline' : ''}'),
                  if (data != null && data!.views.single.filters.isNotEmpty)
                    Text(
                      'Children: $content; mode: $mode; rows: ${data!.views.single.rows.length}/${data!.views.single.allRows.length}',
                    ),
                  Text(
                    'Phase: $phase; held frames: $heldFrames; HTTP: ${gated ? 'held' : 'live'}',
                  ),
                  Text('History: ${historyEvents.join(',')}'),
                  if (!reopening && data != null) ...[
                    if (actor == 'alice' && phase == 0 && !gated)
                      OutlinedButton(
                        onPressed: busy ? null : () => action(prepare),
                        child: const Text('Prepare nested branches'),
                      ),
                    if (frames?.holding != true && !gated)
                      OutlinedButton(
                        onPressed: busy ? null : hold,
                        child: const Text('Hold frames and HTTP'),
                      ),
                    if (frames?.holding == true)
                      OutlinedButton(
                        onPressed: busy ? null : publish,
                        child: const Text('Publish original frames'),
                      ),
                    if (gated && frames?.holding != true)
                      OutlinedButton(
                        onPressed: busy ? null : restoreHttp,
                        child: const Text('Restore HTTP'),
                      ),
                  ],
                  FilledButton(
                    onPressed: data == null || busy || passed
                        ? null
                        : () => action(verify),
                    child: Text(
                      reopening
                          ? 'Verify offline'
                          : phase == 0
                          ? 'Verify local branch'
                          : phase == 1
                          ? 'Verify merged children'
                          : 'Verify final',
                    ),
                  ),
                  if (failure != null)
                    Text(failure!, style: const TextStyle(color: Colors.red)),
                  for (final check in checks) Text('OK: $check'),
                  if (passed)
                    Text(
                      'PASS: ${checks.length} checks',
                      style: const TextStyle(color: Colors.green),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
