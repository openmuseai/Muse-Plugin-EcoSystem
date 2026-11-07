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

const objectId = String.fromEnvironment('USERS_OBJECT'),
    datasetId = String.fromEnvironment('USERS_DATASET'),
    rowId = String.fromEnvironment('USERS_ROW'),
    targetJson = String.fromEnvironment('USERS_TARGET'),
    nonce = String.fromEnvironment('USERS_NONCE'),
    run = String.fromEnvironment('SMARTDOC_RUN'),
    workspace = String.fromEnvironment('SMARTDOC_WORKSPACE'),
    origin = String.fromEnvironment('SMARTDOC_ORIGIN'),
    aliceUid = String.fromEnvironment('USERS_ALICE_UID'),
    bobUid = String.fromEnvironment('USERS_BOB_UID');
String token(String actor) => actor == 'bob'
    ? const String.fromEnvironment('SMARTDOC_BOB_TOKEN')
    : const String.fromEnvironment('SMARTDOC_ALICE_TOKEN');
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
  late final slot = Uri.base.queryParameters['slot'] ?? 'primary';
  final reopening = Uri.base.queryParameters['reopen'] == '1';
  final checks = <String>[], metrics = <Map<String, dynamic>>[];
  SmartDocumentController? doc;
  DatasetController? data;
  DocumentRealtimeSession? documentRealtime;
  DatasetRealtimeSession? datasetRealtime;
  ResourceEmbedHost? host;
  DatasetEmbedRegistry? registry;
  String? failure, parentBefore;
  bool busy = false, passed = false, left = false;
  int phase = 0, reconnects = 0;
  @override
  void initState() {
    super.initState();
    unawaited(open());
  }

  IndexedDbSnapshotStore store(String id) => IndexedDbSnapshotStore(
    namespace: 'users:$workspace:$run:$actor:$slot',
    objectId: id,
  );
  Future<void> open() async {
    try {
      final target = ResourceEmbedTarget.fromJson(jsonDecode(targetJson)),
          wire = reopening ? null : await loadRealtimeWireCore(),
          engine = await loadDatasetCore();
      final offset =
          (actor == 'bob' ? 20 : 0) +
          (slot == 'two'
              ? 2
              : slot == 'other'
              ? 3
              : slot == 'return'
              ? 4
              : 1);
      AppFlowyRealtimeConnection connection(String suffix) =>
          AppFlowyRealtimeConnection(
            origin: Uri.parse(origin),
            workspaceId: workspace,
            deviceId: 'users-$actor-$slot-$suffix-$run',
            clientId:
                (DateTime.now().microsecondsSinceEpoch +
                        offset +
                        (suffix == 'doc' ? 100 : 0))
                    .toString(),
            accessToken: () async => token(actor),
            codec: AppFlowyRealtimeCodec(wire!),
          );
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
                    deviceId: 'users-http-$actor-$slot-$type-$run',
                    accessToken: () async => token(actor),
                    binding: datasetBinding(type),
                    collabType: type,
                  ),
          );
          final rt = wire == null
              ? null
              : DatasetRealtimeSession(
                  controller: c,
                  presenceCore: wire,
                  connection: connection('data'),
                );
          await rt?.start();
          if (mounted) {
            setState(() {
              data = c;
              datasetRealtime = rt;
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
        createRemote: false,
        syncInterval: null,
        provider: reopening
            ? null
            : AppFlowyCollaborationProvider(
                origin: Uri.parse(origin),
                workspaceId: workspace,
                deviceId: 'users-parent-$actor-$slot-$run',
                accessToken: () async => token(actor),
              ),
      );
      final rt = wire == null
          ? null
          : DocumentRealtimeSession(
              controller: c,
              presenceCore: wire,
              connection: connection('doc'),
            );
      await rt?.start();
      if (mounted) {
        setState(() {
          doc = c;
          documentRealtime = rt;
          parentBefore = jsonEncode(c.snapshot['data']);
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => failure = '$e');
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
      if (mounted) setState(() => failure = '$e');
    }
    if (mounted) setState(() => busy = false);
  }

  void locate() {
    doc!.editor.selection = Selection.collapsed(
      Position(
        path: [0],
        offset: slot == 'two'
            ? 3
            : slot == 'other'
            ? 5
            : 1,
      ),
    );
    datasetRealtime!.selectCell(
      viewId: data!.views.single.id,
      rowId: rowId,
      fieldId: slot == 'two' ? 'done' : 'title',
      editing: true,
    );
  }

  Future<void> leave() async {
    doc!.pauseCollaboration(true);
    data!.pauseCollaboration(true);
    await documentRealtime?.close();
    await datasetRealtime?.close();
    if (mounted) setState(() => left = true);
  }

  Future<void> reconnect() async {
    await documentRealtime!.connection.disconnect();
    await datasetRealtime!.connection.disconnect();
    await documentRealtime!.start();
    await datasetRealtime!.start();
    reconnects++;
  }

  void require(bool ok, String name) {
    if (!ok) throw StateError(name);
    if (!checks.contains(name)) checks.add(name);
  }

  Future<void> receipt(String kind) async {
    final r = await http.post(
      Uri.base.resolve('/__users/$kind/$nonce'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'status': 'passed',
        'actor': actor,
        'slot': slot,
        'objectId': objectId,
        'datasetObjectId': datasetId,
        'checks': checks,
        'platform': reopening ? 'web-reload' : 'web',
        'metrics': metrics,
        'uid': documentRealtime?.connection.actorUid,
      }),
    );
    if (r.statusCode != 204) throw StateError('receipt-not-saved');
  }

  Future<void> verify() async {
    final c = doc!, d = data!;
    require(
      c.objectId == objectId && d.objectId == datasetId,
      'same-original-native-document-and-independent-dataset-identities',
    );
    require(
      jsonEncode(c.snapshot['data']) == parentBefore,
      'roster-and-locations-do-not-rewrite-parent-content',
    );
    require(
      !jsonEncode([c.snapshot['data'], d.bundle]).contains('accessToken') &&
          !jsonEncode(d.bundle).contains('muse.dataset.presence'),
      'profile-and-awareness-are-not-persisted-in-content',
    );
    if (reopening) {
      require(
        documentRealtime == null &&
            datasetRealtime == null &&
            !c.canWrite &&
            !d.canWrite,
        'offline-IndexedDB-reopen-has-no-profile-provider-presence-or-edit-grant',
      );
      await receipt('reload');
      setState(() => passed = true);
      return;
    }
    final dr = documentRealtime!,
        tr = datasetRealtime!,
        expected = actor == 'bob' ? bobUid : aliceUid;
    require(
      dr.connection.actorUid == expected && tr.connection.actorUid == expected,
      'actual-Web-Rust-profile-UID-matches-native-full-i64-identity',
    );
    final documentUsers = {expected, ...dr.collaborators.map((p) => p.uid)},
        datasetUsers = {expected, ...tr.collaborators.map((p) => p.uid)};
    if (actor != 'alice' || slot != 'primary') {
      require(
        dr.collaborators.length == 3 &&
            tr.collaborators.length == 3 &&
            documentUsers.length == 2 &&
            datasetUsers.length == 2,
        'four-live-positions-group-into-two-authenticated-users',
      );
      await receipt(actor == 'bob' ? 'peer-$slot' : 'self-other');
      setState(() => passed = true);
      return;
    }
    final wanted = [3, 2, 1, 0, 1][phase],
        users = [2, 2, 1, 1, 2][phase],
        bobSessions = [2, 1, 0, 0, 1][phase];
    require(
      dr.collaborators.length == wanted &&
          tr.collaborators.length == wanted &&
          documentUsers.length == users &&
          datasetUsers.length == users,
      'user-and-position-counts-at-real-leave-stage-$phase',
    );
    require(
      dr.collaborators.where((p) => p.uid == bobUid).length == bobSessions &&
          tr.collaborators.where((p) => p.uid == bobUid).length == bobSessions,
      'same-Bob-UID-position-lifetime-at-stage-$phase',
    );
    require(
      c.editor.remoteSelections.value.length == wanted,
      'original-independent-cursors-remain-at-stage-$phase',
    );
    metrics.add({
      'stage': phase,
      'remotePositions': wanted,
      'users': users,
      'bobPositions': bobSessions,
    });
    if (phase < 4) {
      setState(() => phase++);
      return;
    }
    require(
      reconnects > 0,
      'leader-disconnect-clears-and-original-authenticated-reconnect-restores-user-identity',
    );
    await c.synchronize();
    await d.synchronize();
    await c.flush();
    await d.flush();
    await receipt('result');
    setState(() => passed = true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: left
        ? const Center(child: Text('已离开协作'))
        : doc == null
        ? Center(child: Text(failure ?? '正在打开文档与在线位置'))
        : Row(
            children: [
              Expanded(
                child: SmartDocumentView(
                  controller: doc!,
                  title: '智能文档 · 多端在线',
                  embeds: host,
                  realtime: documentRealtime,
                ),
              ),
              SizedBox(
                width: 310,
                child: ListenableBuilder(
                  listenable: Listenable.merge([
                    doc,
                    data,
                    documentRealtime,
                    datasetRealtime,
                  ]),
                  builder: (context, _) => ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        '用户在线验收 · $actor / $slot${reopening ? ' / offline' : ''}',
                      ),
                      Text(
                        '阶段 $phase · 原连接 ${documentRealtime?.collaborators.length ?? 0}/${datasetRealtime?.collaborators.length ?? 0} · 光标 ${doc!.editor.remoteSelections.value.length}',
                      ),
                      Text(
                        '身份 ${documentRealtime?.connection.actorUid == null ? '待确认' : '已认证'}',
                      ),
                      if (data != null) ...[
                        if (!reopening) ...[
                          OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => action(() async => locate()),
                            child: const Text('定位到段落和单元格'),
                          ),
                          OutlinedButton(
                            onPressed: busy ? null : () => action(reconnect),
                            child: const Text('重连协作'),
                          ),
                          OutlinedButton(
                            onPressed: busy ? null : () => action(leave),
                            child: const Text('离开协作'),
                          ),
                        ],
                        FilledButton(
                          onPressed: busy || passed
                              ? null
                              : () => action(verify),
                          child: Text(
                            reopening
                                ? '验收离线重开'
                                : actor == 'alice' && slot == 'primary'
                                ? '核对当前阶段'
                                : '核对多端在线',
                          ),
                        ),
                      ],
                      if (failure != null)
                        Text(
                          failure!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      for (final check in checks) Text('✓ $check'),
                      if (passed)
                        Text(
                          'PASS · ${checks.length} checks',
                          style: const TextStyle(color: Colors.green),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
  );
}
