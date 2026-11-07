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

const objectId = String.fromEnvironment('OUTLINE_OBJECT'),
    headingId = String.fromEnvironment('OUTLINE_HEADING'),
    nonce = String.fromEnvironment('OUTLINE_NONCE'),
    run = String.fromEnvironment('SMARTDOC_RUN'),
    workspace = String.fromEnvironment('SMARTDOC_WORKSPACE'),
    origin = String.fromEnvironment('SMARTDOC_ORIGIN');
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
  DocumentRealtimeSession? realtime;
  String? failure;
  bool busy = false, passed = false;
  int phase = 0;
  DocumentBlockReference get target =>
      DocumentBlockReference(objectId: objectId, blockId: headingId);
  String get token => actor == 'bob'
      ? const String.fromEnvironment('SMARTDOC_BOB_TOKEN')
      : const String.fromEnvironment('SMARTDOC_ALICE_TOKEN');
  @override
  void initState() {
    super.initState();
    unawaited(open());
  }

  Future<void> open() async {
    try {
      final c = await SmartDocumentController.open(
        core: await WasmDocumentCore.load(),
        store: IndexedDbSnapshotStore(
          namespace: 'outline:$workspace:$run:$actor',
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
                deviceId: 'outline-web-$actor-$run',
                accessToken: () async => token,
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
            deviceId: 'outline-ws-$actor-$run',
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

  Future<void> receipt(String kind) async {
    final r = await http.post(
      Uri.base.resolve('/__outline/$kind/$nonce'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'status': 'passed',
        'actor': actor,
        'objectId': objectId,
        'checks': checks,
        'platform': reopening ? 'web-reload' : 'web',
        'outline': doc!.snapshot['outline'],
        'phase': phase,
      }),
    );
    if (r.statusCode != 204) {
      throw StateError('receipt-not-saved');
    }
  }

  Future<void> rename() async {
    final c = doc!, node = c.resolveBlock(target);
    if (node == null) {
      throw StateError('missing-heading');
    }
    await c.editor.apply(
      c.editor.transaction
        ..insertNode([0], paragraphNode(text: 'Web Bob 前缀'), deepCopy: false)
        ..insertText(node, 0, 'Web '),
    );
    await c.flush();
    require(
      c.objectId == objectId && c.resolveBlock(target) != null,
      'peer-original-block-identity',
    );
    require(
      c.outline.entries.any(
        (e) => e.reference == target && e.text == 'Web 重连 远端 协作章节😀',
      ),
      'peer-title-and-prefix-command-accepted',
    );
    phase = 1;
  }

  Future<void> remove() async {
    final c = doc!, node = c.resolveBlock(target);
    if (node == null) {
      throw StateError('missing-heading');
    }
    await c.editor.apply(c.editor.transaction..deleteNode(node));
    await c.flush();
    require(
      c.resolveBlock(target) == null,
      'peer-title-delete-command-accepted',
    );
    await verifyCheckpoint('peer-deletion-checkpoint-roundtrip');
    phase = 2;
  }

  Future<void> restore() async {
    await doc!.history();
    await doc!.flush();
    phase = 3;
    require(
      doc!.outline.entries.any(
        (e) => e.reference == target && e.text == 'Web 重连 远端 协作章节😀',
      ),
      'peer-origin-undo-restores-title',
    );
    await receipt('peer');
  }

  bool get verifyReady {
    final c = doc;
    if (c == null || realtime?.connection.actorUid == null) return false;
    final matching = c.outline.entries.any(
      (e) => e.reference == target && e.text == 'Web 重连 远端 协作章节😀',
    );
    return phase == 1 ? c.resolveBlock(target) == null : matching;
  }

  Future<void> verifyCheckpoint(String label) async {
    final core = await WasmDocumentCore.load(), state = doc!.snapshot;
    final copy = core.call({
      'action': 'open',
      'objectId': objectId,
      'docState': state['docState'],
    });
    try {
      require(
        jsonEncode(copy['outline']) == jsonEncode(state['outline']),
        label,
      );
    } finally {
      core.call({'action': 'close', 'handle': copy['handle']});
    }
  }

  Future<void> diagnostic() async {
    final state = doc!.snapshot;
    final response = await http.post(
      Uri.base.resolve('/__outline/diagnostic-$actor/$nonce'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'actor': actor,
        'objectId': objectId,
        'outline': state['outline'],
        'docState': state['docState'],
        'stateVector': state['stateVector'],
        'mutationEpoch': doc!.localMutationEpoch,
        'accepted': !doc!.hasPendingLocalChanges,
        'realtimeFailure': realtime?.failureCode,
      }),
    );
    if (response.statusCode != 204) {
      throw StateError('diagnostic-not-saved');
    }
  }

  Future<void> verify() async {
    final c = doc!;
    if (!reopening) {
      await verifyCheckpoint(
        'original-wasm-checkpoint-roundtrip-matches-live-outline',
      );
    }
    require(c.objectId == objectId, 'native-browser-original-object-identity');
    if (reopening) {
      require(
        c.outline.entries.any(
          (e) => e.reference == target && e.text == 'Web 重连 远端 协作章节😀',
        ),
        'offline-original-checkpoint-reconstructs-final-outline',
      );
      require(
        realtime == null && !c.canWrite,
        'offline-provider-free-readonly-open',
      );
      require(
        !jsonEncode(await c.store.read()).contains('accessToken'),
        'credentials-absent-from-content-checkpoint',
      );
      await receipt('reload');
      passed = true;
      return;
    }
    require(
      realtime!.connection.actorUid != null,
      'original-profile-authenticated',
    );
    if (phase == 0) {
      require(
        c.outline.entries.any(
          (e) => e.reference == target && e.text == 'Web 重连 远端 协作章节😀',
        ),
        'live-peer-prefix-and-title-update-projects-stable-identity',
      );
      require(
        c.resolveBlock(target)!.path.first == 36,
        'fresh-path-resolves-two-peer-prefix-insertions',
      );
      phase = 1;
    } else if (phase == 1) {
      require(
        !c.outline.entries.any((e) => e.reference == target) &&
            c.resolveBlock(target) == null,
        'remote-title-deletion-removes-derived-outline-entry',
      );
      phase = 2;
    } else {
      require(
        c.outline.entries.any(
          (e) => e.reference == target && e.text == 'Web 重连 远端 协作章节😀',
        ),
        'peer-origin-undo-restores-original-heading-id',
      );
      await c.flush();
      await c.synchronize();
      require(
        !c.hasPendingLocalChanges,
        'original-cloud-accepted-content-checkpoint',
      );
      await receipt('result');
      passed = true;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: doc == null
        ? Center(child: Text(failure ?? '加载原文档…'))
        : Row(
            children: [
              Expanded(
                child: SmartDocumentView(
                  controller: doc!,
                  title: '智能文档 · 目录协作验证',
                  realtime: realtime,
                ),
              ),
              const VerticalDivider(width: 1),
              SizedBox(
                width: 290,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('目录验收 · $actor${reopening ? ' / offline' : ''}'),
                    const SizedBox(height: 12),
                    if (failure != null) Text('FAIL: $failure'),
                    if (!reopening && actor == 'bob') ...[
                      ElevatedButton(
                        onPressed: busy || phase != 0
                            ? null
                            : () => action(rename),
                        child: const Text('改名并插入前缀'),
                      ),
                      ElevatedButton(
                        onPressed: busy || phase != 1
                            ? null
                            : () => action(remove),
                        child: const Text('删除协作标题'),
                      ),
                      ElevatedButton(
                        onPressed: busy || phase != 2
                            ? null
                            : () => action(restore),
                        child: const Text('撤销删除'),
                      ),
                    ],
                    if (actor == 'alice')
                      ElevatedButton(
                        onPressed:
                            busy || passed || (!reopening && !verifyReady)
                            ? null
                            : () => action(verify),
                        child: Text(
                          reopening
                              ? '验证离线目录'
                              : phase == 0
                              ? '验证远端改名'
                              : phase == 1
                              ? '验证远端删除'
                              : '验证恢复并保存',
                        ),
                      ),
                    TextButton(
                      onPressed: busy ? null : () => action(diagnostic),
                      child: const Text('导出内容诊断'),
                    ),
                    Text('阶段 $phase'),
                    Text('目录 ${doc!.outline.entries.length} 项'),
                    ...checks.map((s) => Text('✓ $s')),
                    if (passed) Text('PASS · ${checks.length} 项'),
                    if (!reopening)
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => action(() async {
                                await realtime?.close();
                                await doc!.flush();
                                setState(() => passed = true);
                              }),
                        child: const Text('保存并离开'),
                      ),
                  ],
                ),
              ),
            ],
          ),
  );
}
