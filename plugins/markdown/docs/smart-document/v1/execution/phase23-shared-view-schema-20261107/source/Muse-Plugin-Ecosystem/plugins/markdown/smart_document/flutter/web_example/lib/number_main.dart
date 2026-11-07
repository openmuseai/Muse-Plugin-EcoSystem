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

const objectId = String.fromEnvironment('NUMBER_OBJECT'),
    datasetId = String.fromEnvironment('NUMBER_DATASET'),
    rowId = String.fromEnvironment('NUMBER_ROW'),
    fieldId = String.fromEnvironment('NUMBER_FIELD'),
    targetJson = String.fromEnvironment('NUMBER_TARGET'),
    parentJson = String.fromEnvironment('NUMBER_PARENT_DATA'),
    nonce = String.fromEnvironment('NUMBER_NONCE'),
    run = String.fromEnvironment('SMARTDOC_RUN'),
    workspace = String.fromEnvironment('SMARTDOC_WORKSPACE'),
    origin = String.fromEnvironment('SMARTDOC_ORIGIN');
const finalNumber = '12345678901234567890.12345678',
    largeNumber = '9007199254740993.123456789';
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
  final checks = <String>[];
  SmartDocumentController? doc;
  DatasetController? data;
  DatasetRealtimeSession? realtime;
  DatasetEmbedRegistry? registry;
  ResourceEmbedHost? host;
  String? failure, beforeNoop;
  int? beforeEpoch;
  bool busy = false, passed = false, left = false;
  int phase = 0;
  String get token => actor == 'bob'
      ? const String.fromEnvironment('SMARTDOC_BOB_TOKEN')
      : const String.fromEnvironment('SMARTDOC_ALICE_TOKEN');
  String? get number =>
      data?.views.single.rows.single.cells[fieldId]?.numberInput;
  int? get format =>
      (data?.snapshot['views'][0]['columns'] as List?)?.cast<Map>().firstWhere(
            (f) => f['id'] == fieldId,
          )['raw']['type_options']['1']['format']
          as int?;
  IndexedDbSnapshotStore store(String id) => IndexedDbSnapshotStore(
    namespace: 'number:$workspace:$run:$actor',
    objectId: id,
  );
  @override
  void initState() {
    super.initState();
    unawaited(open());
  }

  Future<void> open() async {
    try {
      final target = ResourceEmbedTarget.fromJson(jsonDecode(targetJson)),
          engine = await loadDatasetCore();
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
                    deviceId: 'number-http-$actor-$type-$run',
                    accessToken: () async => token,
                    binding: datasetBinding(type),
                    collabType: type,
                  ),
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
                deviceId: 'number-web-$actor-$run',
                clientId: DateTime.now().microsecondsSinceEpoch.toString(),
                accessToken: () async => token,
                codec: AppFlowyRealtimeCodec(wire),
              ),
            );
            await rt.start();
          }
          c.addListener(changed);
          if (mounted) {
            setState(() {
              data = c;
              realtime = rt;
            });
          }
          return DatasetEmbedSession(
            controller: c,
            title: '项目金额',
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
        syncInterval: null,
        provider: reopening
            ? null
            : AppFlowyCollaborationProvider(
                origin: Uri.parse(origin),
                workspaceId: workspace,
                deviceId: 'number-doc-$actor-$run',
                accessToken: () async => token,
              ),
      );
      if (mounted) {
        setState(() => doc = c);
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() => failure = '$e');
      }
    }
  }

  void changed() {
    if (mounted) {
      setState(() {});
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
      if (mounted) {
        setState(() => failure = '$e');
      }
    }
    if (mounted) {
      setState(() => busy = false);
    }
  }

  void require(bool ok, String label) {
    if (!ok) {
      throw StateError(label);
    }
    if (!checks.contains(label)) {
      checks.add(label);
    }
  }

  Future<void> receipt(String kind) async {
    final response = await http.post(
      Uri.base.resolve('/__number/$kind/$nonce'),
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
        'phase': phase,
        'value': number,
        'numberFormat': format,
      }),
    );
    if (response.statusCode != 204) {
      throw StateError('receipt-not-saved');
    }
  }

  bool get ready {
    if (data == null || doc == null) {
      return false;
    }
    if (reopening) {
      return true;
    }
    return switch (phase) {
      0 => number == largeNumber,
      1 => number == largeNumber,
      2 => number == '-0.0125',
      3 => number == '42.125',
      4 => format == 1 && number == '42.125',
      _ => number == finalNumber,
    };
  }

  Future<void> verify() async {
    final c = data!;
    require(
      c.objectId == datasetId &&
          doc!.objectId == objectId &&
          c.views.single.rows.single.id == rowId,
      'same-native-document-dataset-and-independent-row-identities',
    );
    require(
      jsonEncode(doc!.snapshot['data']) == parentJson,
      'parent-document-retains-only-its-original-resource-reference',
    );
    if (reopening) {
      require(
        number == finalNumber && format == 1,
        'offline-original-decimal-and-format-survive-IndexedDB-reopen',
      );
      require(
        realtime == null && !c.canWrite && !doc!.canWrite,
        'offline-no-network-provider-presence-or-edit-grant',
      );
      require(
        !jsonEncode(c.bundle).contains('accessToken'),
        'credentials-absent-from-original-content-checkpoint',
      );
      await receipt('reload');
      passed = true;
      return;
    }
    require(
      realtime!.connection.actorUid != null,
      'original-authenticated-actor-with-independent-row-collaboration',
    );
    if (phase == 0) {
      require(
        number == largeNumber,
        'actual-editor-commits-decimal-above-JS-safe-integer-with-fraction-precision',
      );
      beforeNoop = jsonEncode(c.bundle);
      beforeEpoch = c.localMutationEpoch;
      phase = 1;
    } else if (phase == 1) {
      require(
        number == largeNumber &&
            jsonEncode(c.bundle) == beforeNoop &&
            c.localMutationEpoch == beforeEpoch,
        'unchanged-editor-apply-does-not-rewrite-rounded-display-or-history',
      );
      phase = 2;
    } else if (phase == 2) {
      require(
        number == '-0.0125',
        'scientific-input-normalizes-to-exact-original-number-string',
      );
      phase = 3;
    } else if (phase == 3) {
      require(
        number == '42.125',
        'peer-cell-command-keeps-its-exact-value-while-local-stale-draft-is-rejected',
      );
      phase = 4;
    } else if (phase == 4) {
      require(
        number == '42.125' && format == 1,
        'peer-root-format-command-keeps-row-value-while-stale-schema-draft-is-rejected',
      );
      phase = 5;
    } else {
      require(
        number == finalNumber,
        'final-28-digit-decimal-stays-an-original-Row4-string',
      );
      await c.flush();
      await c.synchronize();
      await doc!.flush();
      await doc!.synchronize();
      await receipt('result');
      passed = true;
    }
  }

  Future<void> peerWrite() async {
    final c = data!;
    require(number == '-0.0125', 'peer-receives-original-scientific-value');
    await c.setCell(
      c.views.single.rows.single,
      c.views.single.columns.firstWhere((f) => f.id == fieldId),
      '42.125',
      expectedHash: c.views.single.rows.single.cells[fieldId]!.hash,
    );
    require(number == '42.125', 'peer-original-exact-number-command');
    phase = 1;
  }

  Future<void> peerFormat() async {
    await data!.configureNumberField(
      data!.views.single.columns.firstWhere((f) => f.id == fieldId),
      1,
    );
    require(
      format == 1 && number == '42.125',
      'peer-original-format-metadata-does-not-rewrite-row',
    );
    phase = 2;
  }

  Future<void> peerVerify() async {
    require(
      number == finalNumber && format == 1,
      'peer-receives-final-original-28-digit-decimal-and-format',
    );
    require(
      doc!.objectId == objectId && data!.objectId == datasetId,
      'peer-same-independent-native-resource-identities',
    );
    await receipt('peer');
    passed = true;
  }

  Future<void> leave() async {
    data!.pauseCollaboration(true);
    await realtime?.close();
    await data!.flush();
    await doc!.flush();
    left = true;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: doc == null
        ? Center(child: Text(failure ?? '加载原协作文档…'))
        : Row(
            children: [
              Expanded(
                child: SmartDocumentView(
                  controller: doc!,
                  title: '智能文档 · 金额协作',
                  embeds: host,
                ),
              ),
              const VerticalDivider(width: 1),
              SizedBox(
                width: 290,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('数字验收 · $actor${reopening ? ' / offline' : ''}'),
                    if (failure != null) Text('FAIL: $failure'),
                    if (data == null) const Text('加载独立数据库…'),
                    if (actor == 'alice' && data != null)
                      ElevatedButton(
                        onPressed: busy || passed || !ready
                            ? null
                            : () => action(verify),
                        child: Text(
                          reopening
                              ? '验证离线数字'
                              : switch (phase) {
                                  0 => '验证高精度并记录',
                                  1 => '验证无修改应用',
                                  2 => '验证科学计数',
                                  3 => '验证单元格冲突',
                                  4 => '验证字段冲突',
                                  _ => '验证最终值并保存',
                                },
                        ),
                      ),
                    if (actor == 'bob' && data != null && !reopening) ...[
                      ElevatedButton(
                        onPressed: busy || phase != 0 || number != '-0.0125'
                            ? null
                            : () => action(peerWrite),
                        child: const Text('协作端写入 42.125'),
                      ),
                      ElevatedButton(
                        onPressed: busy || phase != 1
                            ? null
                            : () => action(peerFormat),
                        child: const Text('协作端变更格式'),
                      ),
                      ElevatedButton(
                        onPressed: busy || phase != 2 || number != finalNumber
                            ? null
                            : () => action(peerVerify),
                        child: const Text('验证最终同步'),
                      ),
                    ],
                    Text('阶段 $phase'),
                    Text('原数值 ${number ?? "待加载"}'),
                    ...checks.map((c) => Text('✓ $c')),
                    if (passed) Text('PASS · ${checks.length} 项'),
                    if (!reopening && !left)
                      TextButton(
                        onPressed: busy || data == null
                            ? null
                            : () => action(leave),
                        child: const Text('保存并离开'),
                      ),
                  ],
                ),
              ),
            ],
          ),
  );
}
