import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:muse_content_store/browser.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';

const workspace = String.fromEnvironment('SMARTDOC_WORKSPACE');
const objectId = String.fromEnvironment('CHOICES_OBJECT');
const run = String.fromEnvironment('SMARTDOC_RUN');
const nonce = String.fromEnvironment('CHOICES_NONCE');
const origin = String.fromEnvironment('SMARTDOC_ORIGIN');
const sourceRow = String.fromEnvironment('CHOICES_ROW');
const stateField = String.fromEnvironment('CHOICES_STATE_FIELD');
const tagsField = String.fromEnvironment('CHOICES_TAGS_FIELD');
DatasetProviderFactory provider(String user) =>
    (type) => AppFlowyObjectTransport(
      origin: Uri.parse(origin),
      workspaceId: workspace,
      deviceId: 'choices-web-$run-$user-$type',
      accessToken: () async => user == 'alice'
          ? const String.fromEnvironment('SMARTDOC_ALICE_TOKEN')
          : user == 'bob'
          ? const String.fromEnvironment('SMARTDOC_BOB_TOKEN')
          : const String.fromEnvironment('SMARTDOC_OUTSIDER_TOKEN'),
      binding: datasetBinding(type),
      collabType: type,
    );
IndexedDbSnapshotStore store(String user) => IndexedDbSnapshotStore(
  namespace: 'choices:$workspace:$run:$user',
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
  int phase = 0;
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
        createRemote: false,
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

  Future<void> _post(String kind) async {
    final response = await http.post(
      Uri.base.resolve('/__choices/$kind/$nonce'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'status': 'passed',
        'objectId': objectId,
        'rowId': sourceRow,
        'checks': checks,
        'platform': reopening ? 'web-reload' : 'web',
        'date': DateTime.now().toUtc().toIso8601String(),
      }),
    );
    if (response.statusCode != 204) throw StateError('receipt-not-saved');
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
          row(a).id == sourceRow && row(a).cells[stateField]!.value == '进行中',
          'actual-indexeddb-reload-preserves-original-native-row-and-single-choice',
        );
        require(
          jsonEncode(row(a).cells[tagsField]!.value) == jsonEncode(['质量']) &&
              field(a, stateField).options.first.name == '待办,A😀',
          'original-choice-ids-color-comma-name-and-peer-cell-retained',
        );
        require(
          a.syncState == DatasetSyncState.local && !a.canUndo,
          'fresh-wasm-no-provider-or-stale-history',
        );
        await _post('reload');
        setState(() => passed = true);
      } else if (phase == 0) {
        require(
          row(a).id == sourceRow &&
              field(a, stateField).semanticType == 'singleSelect' &&
              field(a, tagsField).semanticType == 'multiSelect' &&
              field(a, stateField).options.first.name == '待办,A😀',
          'native-created-original-field-schema-and-row-identities-read-by-wasm',
        );
        require(
          row(a).cells[stateField]!.value == '进行中' &&
              jsonEncode(row(a).cells[tagsField]!.value) ==
                  jsonEncode(['研发', '设计']),
          'actual-browser-choice-dialog-single-multi-and-selection-order',
        );
        await a.synchronize();
        require(
          a.syncState == DatasetSyncState.accepted,
          'original-root-1-row-4-cloud-acceptance',
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
          row(b).id == sourceRow &&
              field(b, stateField).options.map((v) => v.id).join('|') ==
                  field(a, stateField).options.map((v) => v.id).join('|'),
          'second-authenticated-peer-bootstrap-same-original-option-identities',
        );
        await a.setCell(row(a), field(a, stateField), [
          field(a, stateField).options.last.id,
        ], expectedHash: row(a).cells[stateField]!.hash);
        await b.setCell(row(b), field(b, tagsField), [
          field(b, tagsField).options.last.id,
        ], expectedHash: row(b).cells[tagsField]!.hash);
        await a.synchronize();
        await b.synchronize();
        await a.synchronize();
        require(
          jsonEncode(a.snapshot['views']) == jsonEncode(b.snapshot['views']),
          'concurrent-independent-choice-cells-converge-with-original-yrs',
        );
        setState(() => phase = 1);
      } else {
        require(
          row(a).cells[stateField]!.value == '进行中' &&
              jsonEncode(row(a).cells[tagsField]!.value) == jsonEncode(['质量']),
          'actual-browser-toolbar-origin-undo-preserves-peer-choice-cell',
        );
        await a.synchronize();
        await a.flush();
        require(
          a.saveState == DatasetSaveState.saved,
          'indexeddb-original-bundle-checkpoint-completed',
        );
        await _post('result');
        setState(() => passed = true);
      }
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
                : DatasetSurface(controller: c!, title: '数据库 · 跨端选择字段'),
          ),
          SizedBox(
            width: 300,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                children: [
                  Text(
                    '跨端字段验收',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    reopening
                        ? '从本机 IndexedDB 恢复，不访问 Cloud'
                        : phase == 0
                        ? '打开流程状态，选“进行中”；打开标签，清空后依次选“研发”和“设计”，再运行验收。'
                        : '请点击表格工具栏“撤销”，保留协作者的标签，再完成验收。',
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: c == null || busy || passed ? null : _run,
                    child: Text(
                      passed
                          ? '验证通过'
                          : busy
                          ? '正在验证…'
                          : reopening
                          ? '验证重开'
                          : phase == 0
                          ? '运行协作验收'
                          : '完成验收',
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
