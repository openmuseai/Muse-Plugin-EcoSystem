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

const objectId = String.fromEnvironment('EMBEDDED_OBJECT'),
    datasetId = String.fromEnvironment('EMBEDDED_DATASET'),
    rowId = String.fromEnvironment('EMBEDDED_ROW'),
    targetJson = String.fromEnvironment('EMBEDDED_TARGET'),
    run = String.fromEnvironment('SMARTDOC_RUN'),
    workspace = String.fromEnvironment('SMARTDOC_WORKSPACE'),
    origin = String.fromEnvironment('SMARTDOC_ORIGIN'),
    nonce = String.fromEnvironment('EMBEDDED_NONCE');
String token(String user) => user == 'alice'
    ? const String.fromEnvironment('SMARTDOC_ALICE_TOKEN')
    : const String.fromEnvironment('SMARTDOC_BOB_TOKEN');
DatasetProviderFactory provider(String user) =>
    (type) => AppFlowyObjectTransport(
      origin: Uri.parse(origin),
      workspaceId: workspace,
      deviceId: 'embedded-web-$run-$user-$type',
      accessToken: () async => token(user),
      binding: datasetBinding(type),
      collabType: type,
    );
IndexedDbSnapshotStore store(String object, String who) =>
    IndexedDbSnapshotStore(
      namespace: 'embedded:$workspace:$run:$who',
      objectId: object,
    );
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
  SmartDocumentController? doc;
  DatasetController? data;
  DatasetCore? core;
  DatasetEmbedRegistry? registry;
  ResourceEmbedHost? host;
  final reopening = Uri.base.queryParameters['reopen'] == '1';
  final checks = <String>[];
  bool busy = false, passed = false;
  String? failure;
  int phase = 0;
  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      final target = ResourceEmbedTarget.fromJson(jsonDecode(targetJson));
      core = await loadDatasetCore();
      registry = DatasetEmbedRegistry(
        open: (request) async {
          if (request.key != target.key) {
            throw const ResourceFailure('RESOURCE_NOT_AUTHORIZED');
          }
          final c = await DatasetController.open(
            core: core!,
            store: store(datasetId, 'alice'),
            objectId: datasetId,
            providerFactory: reopening ? null : provider('alice'),
            syncInterval: null,
          );
          if (mounted) setState(() => data = c);
          return DatasetEmbedSession(
            controller: c,
            title: '项目数据库',
            close: c.close,
          );
        },
      );
      host = ResourceEmbedHost(build: registry!.build);
      final c = await SmartDocumentController.open(
        core: await WasmDocumentCore.load(),
        store: store(objectId, 'alice'),
        objectId: objectId,
        provider: reopening
            ? null
            : AppFlowyCollaborationProvider(
                origin: Uri.parse(origin),
                workspaceId: workspace,
                deviceId: 'embedded-web-$run',
                accessToken: () async => token('alice'),
              ),
        createRemote: false,
        syncInterval: null,
      );
      if (mounted) setState(() => doc = c);
    } on Object catch (e) {
      if (mounted) setState(() => failure = '$e');
    }
  }

  void require(bool ok, String name) {
    if (!ok) throw StateError(name);
    setState(() => checks.add(name));
  }

  Future<void> receipt(String kind) async {
    final response = await http.post(
      Uri.base.resolve('/__embedded/$kind/$nonce'),
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

  Future<void> verify() async {
    setState(() => busy = true);
    try {
      final d = doc!,
          a = data!,
          r = a.views.single.rows.single,
          f = a.views.single.columns.first;
      require(
        d.blocks.any(
          (b) =>
              b.type == 'grid' &&
              ResourceEmbedTarget.fromJson(b.attributes['muse_embed']).key ==
                  ResourceEmbedTarget.fromJson(jsonDecode(targetJson)).key,
        ),
        'wasm-reads-native-original-inline-block-and-portable-resource-target',
      );
      require(
        r.id == rowId && a.objectId == datasetId,
        'embedded-child-resolves-independent-native-database-and-row-identities',
      );
      if (reopening) {
        require(
          r.cells[f.id]!.value == '网页嵌入编辑😀',
          'separate-document-and-dataset-indexeddb-checkpoints-reopen-without-cloud',
        );
        await receipt('reload');
        setState(() => passed = true);
        return;
      }
      if (phase == 0) {
        require(
          r.cells[f.id]!.value == '网页嵌入编辑😀',
          'actual-browser-embedded-cell-dialog-applies-to-independent-row',
        );
        final before = jsonEncode(d.snapshot['data']);
        await a.synchronize();
        final b = await DatasetController.open(
          core: core!,
          store: store(datasetId, 'bob'),
          objectId: datasetId,
          providerFactory: provider('bob'),
          syncInterval: null,
        );
        try {
          require(
            b.views.single.rows.single.cells[f.id]!.value == '网页嵌入编辑😀',
            'authenticated-native-web-cloud-row-acceptance',
          );
          final br = b.views.single.rows.single,
              other = b.views.single.columns.firstWhere((f) => f.id == 'done');
          await b.setCell(
            br,
            other,
            true,
            expectedHash: br.cells[other.id]!.hash,
          );
          await b.synchronize();
          await a.synchronize();
          require(
            a.views.single.rows.single.cells['done']!.value == true,
            'real-peer-update-projected-inside-document',
          );
          require(
            jsonEncode(d.snapshot['data']) == before,
            'child-edit-and-peer-merge-do-not-rewrite-parent-document-content',
          );
        } finally {
          await b.close();
        }
        setState(() => phase = 1);
      } else {
        require(
          a.views.single.rows.single.cells['title']!.value == '网页嵌入编辑😀' &&
              a.views.single.rows.single.cells['done']!.value == true,
          'actual-child-toolbar-redo-restores-local-value-and-preserves-peer-cell',
        );
        await a.synchronize();
        await a.flush();
        await d.flush();
        await receipt('result');
        setState(() => passed = true);
      }
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
                    title: '智能文档 · 数据库同屏协作',
                    embeds: host,
                  ),
          ),
          SizedBox(
            width: 280,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                children: [
                  const Text('文档嵌入数据库验收'),
                  const SizedBox(height: 12),
                  Text(
                    reopening
                        ? '从两个独立的本机副本恢复，不访问 Cloud'
                        : phase == 0
                        ? '请点击数据库标题单元格，输入“网页嵌入编辑😀”并应用，然后验收。'
                        : '请点击数据库工具栏的撤销，再重做，然后完成验收。',
                  ),
                  FilledButton(
                    onPressed: doc == null || data == null || busy || passed
                        ? null
                        : verify,
                    child: Text(
                      reopening
                          ? '验收重新打开'
                          : phase == 0
                          ? '验收编辑与协作'
                          : '完成验收',
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
