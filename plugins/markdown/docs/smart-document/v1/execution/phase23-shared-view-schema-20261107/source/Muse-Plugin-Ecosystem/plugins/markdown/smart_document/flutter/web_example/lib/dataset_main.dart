import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:muse_content_store/browser.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';

const workspace = String.fromEnvironment('SMARTDOC_WORKSPACE');
const objectId = String.fromEnvironment('DATASET_OBJECT');
const run = String.fromEnvironment('SMARTDOC_RUN');
const nonce = String.fromEnvironment('DATASET_NONCE');
const origin = String.fromEnvironment('SMARTDOC_ORIGIN');
DatasetProviderFactory provider(String user) =>
    (type) => AppFlowyObjectTransport(
      origin: Uri.parse(origin),
      workspaceId: workspace,
      deviceId: 'dataset-web-$run-$user-$type',
      accessToken: () async => user == 'alice'
          ? const String.fromEnvironment('SMARTDOC_ALICE_TOKEN')
          : user == 'bob'
          ? const String.fromEnvironment('SMARTDOC_BOB_TOKEN')
          : const String.fromEnvironment('SMARTDOC_OUTSIDER_TOKEN'),
      binding: datasetBinding(type),
      collabType: type,
    );
IndexedDbSnapshotStore store(String user) => IndexedDbSnapshotStore(
  namespace: 'dataset:$workspace:$run:$user',
  objectId: objectId,
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
      ],
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      locale: const Locale('zh', 'CN'),
      theme: ThemeData(
        colorSchemeSeed: const Color(0xff4c63d9),
        useMaterial3: true,
      ),
      home: const DatasetBrowserWorkbench(),
    ),
  );
}

class DatasetBrowserWorkbench extends StatefulWidget {
  const DatasetBrowserWorkbench({super.key});
  @override
  State<DatasetBrowserWorkbench> createState() =>
      _DatasetBrowserWorkbenchState();
}

class _DatasetBrowserWorkbenchState extends State<DatasetBrowserWorkbench> {
  DatasetController? c;
  DatasetCore? core;
  String? failure;
  bool busy = false, passed = false;
  final checks = <String>[];
  final reopening = Uri.base.queryParameters['reopen'] == '1';
  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      final engine = await loadDatasetCore();
      final controller = await DatasetController.open(
        core: engine,
        store: store('alice'),
        objectId: objectId,
        providerFactory: reopening ? null : provider('alice'),
        createRemote: !reopening,
        syncInterval: null,
      );
      if (!mounted) {
        await controller.close();
        return;
      }
      setState(() {
        c = controller;
        core = engine;
      });
    } on Object catch (e) {
      if (mounted) setState(() => failure = '$e');
    }
  }

  void require(bool valid, String check) {
    if (!valid) throw StateError(check);
    setState(() => checks.add(check));
  }

  Future<void> _run() async {
    setState(() {
      busy = true;
      failure = null;
    });
    DatasetController? bob;
    try {
      final a = c!;
      DatasetRow row(DatasetController x) => x.views.single.rows.single;
      DatasetColumn field(DatasetController x, String id) =>
          x.views.single.columns.firstWhere((f) => f.id == id);
      if (reopening) {
        require(
          row(a).cells['title']!.value == '最终浏览器任务😀',
          'actual-indexeddb-reload-exact-text-without-cloud',
        );
        require(
          row(a).cells['done']!.value == true,
          'independent-row-checkbox-and-address-preserved',
        );
        require(
          a.syncState == DatasetSyncState.local && !a.canUndo,
          'fresh-wasm-process-no-provider-or-stale-local-history',
        );
      } else {
        require(
          row(a).cells['title']!.value == '浏览器任务😀',
          'actual-browser-add-row-and-unicode-dialog',
        );
        await a.synchronize();
        require(
          a.syncState == DatasetSyncState.accepted,
          'original-cloud-root-1-and-row-4-synchronized',
        );
        bob = await DatasetController.open(
          core: core!,
          store: store('bob'),
          objectId: objectId,
          providerFactory: provider('bob'),
          syncInterval: null,
        );
        final b = bob;
        require(
          row(b).id == row(a).id && row(b).cells['title']!.value == '浏览器任务😀',
          'fresh-peer-original-root-bootstrap-and-independent-row',
        );
        await a.setCell(
          row(a),
          field(a, 'title'),
          '最终浏览器任务😀',
          expectedHash: row(a).cells['title']!.hash,
        );
        await b.setCell(
          row(b),
          field(b, 'done'),
          true,
          expectedHash: row(b).cells['done']!.hash,
        );
        await a.synchronize();
        await b.synchronize();
        await a.synchronize();
        require(
          jsonEncode(a.snapshot['views']) == jsonEncode(b.snapshot['views']),
          'offline-independent-cells-converge-with-original-yrs',
        );
        await a.history();
        require(
          row(a).cells['title']!.value == '浏览器任务😀' &&
              row(a).cells['done']!.value == true,
          'origin-undo-preserves-peer-checkbox',
        );
        await a.history(redo: true);
        await a.synchronize();
        await b.synchronize();
        require(
          jsonEncode(a.snapshot['views']) == jsonEncode(b.snapshot['views']),
          'redo-and-peer-convergence',
        );
        final outsider = provider('outsider')(4);
        var denied = false;
        try {
          await outsider.readState(row(a).id);
        } on AppFlowyTransportFailure catch (e) {
          denied = e.code == 'FORBIDDEN';
        } finally {
          outsider.close();
        }
        require(denied, 'outsider-independent-row-read-denied-by-actual-cloud');
        await a.flush();
        require(
          a.saveState == DatasetSaveState.saved,
          'indexeddb-transaction-completes-for-root-and-row-bundle',
        );
      }
      final response = await http.post(
        Uri.base.resolve(
          '/__dataset/${reopening ? 'reload' : 'result'}/$nonce',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'status': 'passed',
          'objectId': objectId,
          'rowId': row(a).id,
          'checks': checks,
          'platform': reopening ? 'web-reload' : 'web',
          'date': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      if (response.statusCode != 204) throw StateError('receipt-not-saved');
      setState(() => passed = true);
    } on Object catch (e) {
      setState(() => failure = '$e');
    } finally {
      await bob?.close();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Row(
        children: [
          Expanded(
            child: c == null
                ? Center(
                    child: failure == null
                        ? const CircularProgressIndicator()
                        : const Text('数据库无法打开'),
                  )
                : DatasetSurface(controller: c!, title: '项目数据库 · Web'),
          ),
          SizedBox(
            width: 300,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                children: [
                  Text(
                    '数据库端到端验证',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    reopening
                        ? '从本机 IndexedDB 恢复，不访问 Cloud'
                        : '先新增记录，将标题编辑为“浏览器任务😀”，再运行协作验证。',
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: c == null || busy || passed ? null : _run,
                    child: Text(
                      passed
                          ? '验证通过'
                          : busy
                          ? '正在验证…'
                          : '运行协作验收',
                    ),
                  ),
                  for (final check in checks)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('✓ $check'),
                    ),
                  if (failure != null)
                    Text(
                      failure!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
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
