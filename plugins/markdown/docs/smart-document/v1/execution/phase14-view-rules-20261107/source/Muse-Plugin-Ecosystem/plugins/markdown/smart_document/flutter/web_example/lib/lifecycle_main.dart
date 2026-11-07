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

const objectId = String.fromEnvironment('LIFECYCLE_OBJECT'),
    datasetId = String.fromEnvironment('LIFECYCLE_DATASET'),
    rowId = String.fromEnvironment('LIFECYCLE_ROW'),
    targetJson = String.fromEnvironment('LIFECYCLE_TARGET'),
    workspace = String.fromEnvironment('SMARTDOC_WORKSPACE'),
    origin = String.fromEnvironment('SMARTDOC_ORIGIN'),
    run = String.fromEnvironment('SMARTDOC_RUN'),
    nonce = String.fromEnvironment('LIFECYCLE_NONCE'),
    token = String.fromEnvironment('SMARTDOC_ALICE_TOKEN');

class _Gate extends http.BaseClient {
  final http.Client inner = http.Client();
  String? method, object;
  bool held = false, closed = false;
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest r) async {
    if (!held &&
        r.method == method &&
        object != null &&
        r.url.path.contains('/$object')) {
      held = true;
      final actual = await http.Response.fromStream(await inner.send(r));
      if (actual.statusCode != 200) {
        throw StateError('original-cloud-response-${actual.statusCode}');
      }
      entered.complete();
      await release.future;
      return http.StreamedResponse(
        Stream.value(actual.bodyBytes),
        actual.statusCode,
        headers: actual.headers,
        request: r,
      );
    }
    return inner.send(r);
  }

  @override
  void close() {
    closed = true;
    inner.close();
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
  final reopening = Uri.base.queryParameters['reopen'] == '1';
  final clients = <int, List<_Gate>>{1: [], 4: []},
      rootClient = _Gate(),
      checks = <String>[];
  SmartDocumentController? doc;
  DatasetController? data, oldData;
  DocumentRealtimeSession? rootRealtime;
  DatasetEmbedRegistry? registry;
  ResourceEmbedHost? host;
  Future<void>? pendingRow, pendingRoot;
  _Gate? rowGate;
  String? oldRowState, parentBefore, failure;
  bool busy = false, passed = false, documentClosed = false;
  bool rowFinishedBeforeRelease = false, rootFinishedBeforeRelease = false;
  int opens = 0;
  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  IndexedDbSnapshotStore store(String id) => IndexedDbSnapshotStore(
    namespace: 'lifecycle:$workspace:$run',
    objectId: id,
  );
  Future<void> _open() async {
    try {
      final target = ResourceEmbedTarget.fromJson(jsonDecode(targetJson));
      final engine = await loadDatasetCore();
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
                : (type) {
                    final gate = _Gate();
                    clients[type]!.add(gate);
                    return AppFlowyObjectTransport(
                      origin: Uri.parse(origin),
                      workspaceId: workspace,
                      deviceId: 'lifecycle-web-$run-$type-$opens',
                      accessToken: () async => token,
                      binding: datasetBinding(type),
                      collabType: type,
                      client: gate,
                    );
                  },
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
                deviceId: 'lifecycle-web-data-$run-$opens',
                clientId: DateTime.now().microsecondsSinceEpoch.toString(),
                accessToken: () async => token,
                codec: AppFlowyRealtimeCodec(wire),
              ),
            );
            await rt.start();
          }
          opens++;
          if (mounted) setState(() => data = c);
          return DatasetEmbedSession(
            controller: c,
            title: '项目数据库',
            realtime: rt,
            close: () async {
              await rt?.close();
              await c.close();
              if (mounted && identical(data, c)) setState(() => data = null);
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
                deviceId: 'lifecycle-web-document-$run',
                accessToken: () async => token,
                client: rootClient,
              ),
      );
      if (!reopening) {
        final wire = await loadRealtimeWireCore();
        rootRealtime = DocumentRealtimeSession(
          controller: c,
          presenceCore: wire,
          connection: AppFlowyRealtimeConnection(
            origin: Uri.parse(origin),
            workspaceId: workspace,
            deviceId: 'lifecycle-web-document-$run',
            clientId: DateTime.now().microsecondsSinceEpoch.toString(),
            accessToken: () async => token,
            codec: AppFlowyRealtimeCodec(wire),
          ),
        );
        await rootRealtime!.start();
      }
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

  void require(bool value, String name) {
    if (!value) throw StateError(name);
    if (!checks.contains(name)) checks.add(name);
  }

  Future<void> action(Future<void> Function() work) async {
    setState(() {
      busy = true;
      failure = null;
    });
    try {
      await work();
    } on Object catch (e) {
      if (mounted) setState(() => failure = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String? title(DatasetController c) =>
      c.views.single.rows
              .singleWhere((r) => r.id == rowId)
              .cells['title']!
              .value
          as String?;
  Future<void> holdRow() async {
    final c = data!;
    await c.synchronize();
    oldData = c;
    rowGate = clients[4]!.last;
    rowGate!.method = 'GET';
    rowGate!.object = rowId;
    pendingRow = c.synchronize().whenComplete(() {
      if (!rowGate!.release.isCompleted) rowFinishedBeforeRelease = true;
    });
    await rowGate!.entered.future;
    oldRowState = jsonEncode(c.snapshot);
    setState(() {});
  }

  Future<void> releaseRow() async {
    require(
      opens == 2 &&
          data != null &&
          !identical(data, oldData) &&
          rowGate!.closed,
      'actual-remove-reference-and-document-undo-release-old-owner-and-open-one-new-child',
    );
    require(
      !rowGate!.release.isCompleted &&
          !rowFinishedBeforeRelease &&
          title(data!) == '浏览器恢复后的编辑',
      'fresh-child-UI-edits-the-same-row-while-old-HTTP-response-remains-held',
    );
    await data!.synchronize();
    await data!.flush();
    final checkpoint = jsonEncode((await store(datasetId).read())!['bundle']);
    if (rowFinishedBeforeRelease) {
      throw StateError('held-row-request-settled-before-release');
    }
    rowGate!.release.complete();
    await pendingRow;
    require(
      jsonEncode(oldData!.snapshot) == oldRowState,
      'closed-old-dataset-ignores-actual-delayed-row-response',
    );
    require(
      jsonEncode((await store(datasetId).read())!['bundle']) == checkpoint &&
          title(data!) == '浏览器恢复后的编辑',
      'late-row-response-cannot-overwrite-current-session-or-IndexedDB-checkpoint',
    );
    require(
      jsonEncode(doc!.snapshot['data']) == parentBefore,
      'parent-grid-locator-identity-survives-remove-and-undo',
    );
    await doc!.synchronize();
    await doc!.flush();
    setState(() {});
  }

  Future<void> holdRoot() async {
    if (checks.length < 5 || doc == null) {
      throw StateError('complete-row-lifetime-slice-first');
    }
    await doc!.synchronize();
    rootClient.method = 'POST';
    rootClient.object = objectId;
    rootRealtime!.connection.send(
      RealtimeManifest(
        objectId: objectId,
        collabType: 0,
        stateVector: base64Decode(doc!.snapshot['stateVector'] as String),
      ),
    );
    await rootClient.entered.future;
    pendingRoot = doc!.synchronize().whenComplete(() {
      if (!rootClient.release.isCompleted) rootFinishedBeforeRelease = true;
    });
    setState(() {});
  }

  Future<void> closeAndVerify() async {
    final c = doc!;
    require(
      rootClient.held &&
          !rootClient.release.isCompleted &&
          !rootFinishedBeforeRelease,
      'actual-server-manifest-HTTP-repair-response-held',
    );
    setState(() {
      doc = null;
      documentClosed = true;
    });
    await WidgetsBinding.instance.endOfFrame;
    await registry!.close();
    await rootRealtime!.close();
    await c.close();
    require(
      rootClient.closed &&
          !rootClient.release.isCompleted &&
          !rootFinishedBeforeRelease,
      'document-and-socket-release-before-original-HTTP-response',
    );
    final before = jsonEncode(c.snapshot),
        checkpoint = jsonEncode(await store(objectId).read());
    rootClient.release.complete();
    await pendingRoot;
    require(
      jsonEncode(c.snapshot) == before &&
          jsonEncode(await store(objectId).read()) == checkpoint,
      'late-original-root-success-cannot-rewrite-closed-document-or-IndexedDB',
    );
    await receipt('result');
    setState(() => passed = true);
  }

  Future<void> verifyReopen() async {
    require(
      reopening && rootRealtime == null,
      'fresh-IndexedDB-reopen-without-credentials-or-realtime-socket',
    );
    require(
      doc!.blocks.singleWhere((b) => b.type == 'grid').attributes['view_id'] ==
          jsonDecode(targetJson)['selector']['viewId'],
      'same-parent-document-generic-locator-restored',
    );
    require(
      data!.objectId == datasetId && title(data!) == '浏览器恢复后的编辑',
      'fresh-dataset-row-and-latest-browser-UI-edit-restored',
    );
    require(
      !doc!.canWrite && !data!.canWrite,
      'explicit-offline-readonly-reopen-keeps-Host-permission-floor',
    );
    await receipt('reload');
    setState(() => passed = true);
  }

  Future<void> receipt(String kind) async {
    final response = await http.post(
      Uri.base.resolve('/__lifecycle/$kind/$nonce'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'status': 'passed',
        'objectId': objectId,
        'datasetObjectId': datasetId,
        'rowId': rowId,
        'checks': checks,
        'platform': reopening ? 'web-reload' : 'web',
        'date': DateTime.now().toUtc().toIso8601String(),
      }),
    );
    if (response.statusCode != 204) throw StateError('receipt-not-saved');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Row(
        children: [
          Expanded(
            child: doc == null
                ? Center(
                    child: Text(documentClosed ? '文档已关闭，本机副本已保留' : '正在打开文档…'),
                  )
                : SmartDocumentView(
                    controller: doc!,
                    title: '智能文档 · 会话生命周期',
                    embeds: host,
                    realtime: rootRealtime,
                  ),
          ),
          SizedBox(
            width: 285,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                children: [
                  const Text('实际 Cloud 生命周期验收辅助'),
                  Text('子资源打开次数：$opens；${data == null ? '已释放' : '正在编辑'}'),
                  if (!reopening) ...[
                    const Text(
                      '先延迟行回包；在正文中移除数据库引用，再用正文撤销恢复。随后实际编辑该行标题为“浏览器恢复后的编辑”。',
                    ),
                    OutlinedButton(
                      onPressed: busy || oldData != null || data == null
                          ? null
                          : () => action(holdRow),
                      child: const Text('延迟下次行回包'),
                    ),
                    FilledButton(
                      onPressed:
                          busy ||
                              rowGate?.held != true ||
                              rowGate!.release.isCompleted
                          ? null
                          : () => action(releaseRow),
                      child: const Text('放行旧行回包并核对'),
                    ),
                    OutlinedButton(
                      onPressed: busy || checks.length < 5 || rootClient.held
                          ? null
                          : () => action(holdRoot),
                      child: const Text('延迟正文修复回包'),
                    ),
                    FilledButton(
                      onPressed: busy || !rootClient.held || documentClosed
                          ? null
                          : () => action(closeAndVerify),
                      child: const Text('关闭并验收迟到回包'),
                    ),
                  ] else
                    FilledButton(
                      onPressed: busy || passed || data == null
                          ? null
                          : () => action(verifyReopen),
                      child: const Text('验收本机恢复'),
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
