import 'package:muse_collab_test_support/muse_collab_test_support.dart';
import 'dart:async';
import 'dart:convert';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:muse_content_store/browser.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';
import 'package:openmuse_smart_document/browser.dart';

const objectId = String.fromEnvironment('FORMULA_OBJECT'),
    formulaId = String.fromEnvironment('FORMULA_BLOCK'),
    nativeSource = String.fromEnvironment('FORMULA_NATIVE_SOURCE'),
    nonce = String.fromEnvironment('FORMULA_NONCE'),
    run = String.fromEnvironment('SMARTDOC_RUN'),
    workspace = String.fromEnvironment('SMARTDOC_WORKSPACE'),
    origin = String.fromEnvironment('SMARTDOC_ORIGIN');
const webSource = r'\frac{a^2+b^2}{c^2}=1',
    peerSource = r'\sqrt{x^2+y^2}=z',
    finalSource = r'\int_0^\pi\sin x\,dx=2';

class _HistoryCore implements DocumentCore {
  _HistoryCore(this.inner, this.observe);
  final DocumentCore inner;
  final void Function(String, Map<String, dynamic>) observe;
  @override
  Map<String, dynamic> call(Map<String, dynamic> request) {
    final result = inner.call(request);
    if ({'undo', 'redo'}.contains(request['action'])) {
      observe(request['action'] as String, result);
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
  final actor = Uri.base.queryParameters['actor'] == 'bob' ? 'bob' : 'alice',
      reopening = Uri.base.queryParameters['reopen'] == '1';
  final checks = <String>[],
      history = <Map<String, dynamic>>[],
      branch = <String, dynamic>{};
  final httpGate = HttpRequestGate();
  int heldFrames = 0, phase = 0;
  late final frames = OutgoingFrameGate(
    onHeld: (_, bytes) {
      heldFrames++;
      if (mounted) setState(() {});
    },
  );
  SmartDocumentController? doc;
  DocumentRealtimeSession? realtime;
  String? failure;
  bool busy = false, passed = false, left = false;
  DocumentBlockReference get target =>
      DocumentBlockReference(objectId: objectId, blockId: formulaId);
  String get token => actor == 'bob'
      ? const String.fromEnvironment('SMARTDOC_BOB_TOKEN')
      : const String.fromEnvironment('SMARTDOC_ALICE_TOKEN');
  String? get formula =>
      doc?.resolveBlock(target)?.attributes['formula'] as String?;
  String get prose => doc?.blocks.first.delta?.toPlainText() ?? '';
  Node? get secondary => doc?.blocks
      .where((n) => n.type == 'math_equation' && n.id != formulaId)
      .firstOrNull;
  @override
  void initState() {
    super.initState();
    unawaited(open());
  }

  Future<void> open() async {
    try {
      final core = _HistoryCore(await WasmDocumentCore.load(), (
        action,
        result,
      ) {
        if (history.length < 32) {
          history.add({
            'action': action,
            'formula': result['data']['blocks'][formulaId]?['data']?['formula'],
          });
        }
      });
      final c = await SmartDocumentController.open(
        core: core,
        store: IndexedDbSnapshotStore(
          namespace: 'formula:$workspace:$run:$actor',
          objectId: objectId,
        ),
        objectId: objectId,
        editable: !reopening,
        syncInterval: null,
        provider: reopening
            ? null
            : AppFlowyCollaborationProvider(
                origin: Uri.parse(origin),
                workspaceId: workspace,
                deviceId: 'formula-http-$actor-$run',
                accessToken: () async => token,
                client: httpGate.client(),
              ),
      );
      DocumentRealtimeSession? rt;
      if (!reopening) {
        final wire = await loadRealtimeWireCore();
        rt = DocumentRealtimeSession(
          controller: c,
          presenceCore: wire,
          connection: AppFlowyRealtimeConnection(
            origin: Uri.parse(origin),
            workspaceId: workspace,
            deviceId: 'formula-ws-$actor-$run',
            clientId: DateTime.now().microsecondsSinceEpoch.toString(),
            accessToken: () async => token,
            codec: AppFlowyRealtimeCodec(wire),
            socketFactory: (uri) => frames.open(actor, uri),
          ),
        );
        await rt.start();
      }
      c.addListener(changed);
      if (mounted) {
        setState(() {
          doc = c;
          realtime = rt;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => failure = '$e');
    }
  }

  void changed() {
    if (mounted) setState(() {});
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

  void require(bool ok, String label) {
    if (!ok) throw StateError(label);
    if (!checks.contains(label)) checks.add(label);
  }

  void common() {
    require(
      doc!.objectId == objectId &&
          doc!.resolveBlock(target)?.type == 'math_equation',
      'original-native-document-and-formula-block-identity',
    );
    require(
      prose.contains('协作者公式旁正文😀'),
      'original-native-unicode-prose-retained',
    );
    final block = doc!.snapshot['data']['blocks'][formulaId];
    require(
      block['external_id'] == null &&
          block['external_type'] == null &&
          block['data']['formula'] is String,
      'original-formula-schema-has-no-parallel-text',
    );
  }

  bool get ready =>
      doc != null &&
      (reopening ||
          switch (phase) {
            0 => realtime?.connection.actorUid != null,
            1 => actor == 'bob' || formula == webSource,
            2 => true,
            3 => formula == webSource && prose.contains('Web协作正文'),
            _ =>
              formula == finalSource &&
                  secondary?.attributes['formula'] == r'E=mc^2',
          });
  void hold() {
    common();
    require(
      formula == nativeSource,
      'same-native-scientific-source-before-independent-edits',
    );
    httpGate.hold();
    frames.hold();
    phase = 1;
  }

  Future<void> localBranch() async {
    if (actor == 'bob') {
      final node = doc!.blocks.first;
      await doc!.editor.apply(
        doc!.editor.transaction
          ..insertText(node, node.delta!.length, ' Web协作正文'),
      );
      await doc!.flush();
    }
    unawaited(doc!.synchronize());
    require(
      formula == (actor == 'alice' ? webSource : nativeSource) &&
          prose.contains('Web协作正文') == (actor == 'bob'),
      'independent-formula-and-prose-branches-before-publish',
    );
    require(
      heldFrames > 0,
      'original-websocket-frames-held-on-independent-branches',
    );
    branch.addAll({
      'formula': formula,
      'prose': prose,
      'heldFrames': heldFrames,
      'httpHeld': httpGate.blockedRequests,
    });
    phase = 2;
  }

  void release() {
    frames.release();
    httpGate.release();
    phase = 3;
  }

  Future<void> merged() async {
    require(
      formula == webSource,
      'original-web-formula-edit-converges-with-stable-native-block',
    );
    require(
      prose.contains('Web协作正文'),
      'peer-unicode-prose-merges-without-replacing-formula',
    );
    if (actor == 'bob') {
      await doc!.updateFormula(doc!.captureFormula(target), peerSource);
    }
    phase = 4;
  }

  Future<void> finish(String kind) async {
    common();
    require(
      formula == finalSource &&
          secondary?.attributes['formula'] == r'E=mc^2' &&
          doc!.blocks.where((n) => n.type == 'math_equation').length == 2,
      'actual-formula-source-edit-and-second-insert-use-original-schema',
    );
    require(
      prose.contains('Web协作正文'),
      'independent-peer-prose-survives-author-history-and-new-formula',
    );
    if (actor == 'alice' && !reopening) {
      require(
        history.any(
              (e) => e['action'] == 'undo' && e['formula'] == peerSource,
            ) &&
            history.any(
              (e) => e['action'] == 'redo' && e['formula'] == finalSource,
            ),
        'actual-original-undo-redo-preserve-peer-source-and-prose',
      );
    }
    await doc!.flush();
    if (!reopening) await doc!.synchronize();
    await receipt(kind);
    passed = true;
  }

  Future<void> receipt(String kind) async {
    final response = await http.post(
      Uri.base.resolve('/__formula/$kind/$nonce'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'status': 'passed',
        'actor': actor,
        'objectId': objectId,
        'formulaId': formulaId,
        'secondaryId': secondary!.id,
        'checks': checks,
        'platform': reopening ? 'web-reload' : 'web',
        'branch': branch,
        'history': history,
        'data': doc!.snapshot['data'],
      }),
    );
    if (response.statusCode != 204) {
      throw StateError('receipt ${response.statusCode}');
    }
  }

  Future<void> leave() async {
    frames.release();
    httpGate.release();
    await doc!.flush();
    await realtime?.close();
    left = true;
  }

  Future<void> advance() async {
    if (reopening) {
      await finish('reload');
      return;
    }
    switch (phase) {
      case 0:
        hold();
      case 1:
        await localBranch();
      case 2:
        release();
      case 3:
        await merged();
      default:
        await finish(actor == 'alice' ? 'result' : 'peer');
    }
  }

  String get label => reopening
      ? '验证离线公式'
      : switch (phase) {
          0 => '锁定并发分支',
          1 => actor == 'alice' ? '确认本地公式' : '编辑并发正文',
          2 => '发布并发修改',
          3 => actor == 'alice' ? '验证并发合并' : '协作端更新公式',
          _ => '验证最终公式并保存',
        };
  @override
  Widget build(BuildContext context) => Scaffold(
    body: doc == null
        ? Center(child: Text(failure ?? '加载原协作文档…'))
        : Row(
            children: [
              Expanded(
                child: SmartDocumentView(
                  controller: doc!,
                  title: '智能文档 · 数学公式',
                  realtime: realtime,
                ),
              ),
              const VerticalDivider(width: 1),
              SizedBox(
                width: 300,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('公式验收 · $actor${reopening ? ' / offline' : ''}'),
                    if (failure != null) Text('FAIL: $failure'),
                    ElevatedButton(
                      onPressed: busy || passed || !ready
                          ? null
                          : () => action(advance),
                      child: Text(label),
                    ),
                    Text(
                      '阶段 $phase · ${doc!.blocks.where((n) => n.type == 'math_equation').length} 个公式',
                    ),
                    ...checks.map((c) => Text('✓ $c')),
                    if (passed) Text('PASS · ${checks.length} 项'),
                    if (!reopening && !left)
                      TextButton(
                        onPressed: busy ? null : () => action(leave),
                        child: const Text('保存并离开'),
                      ),
                  ],
                ),
              ),
            ],
          ),
  );
}
