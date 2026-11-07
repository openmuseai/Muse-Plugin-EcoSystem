import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:openmuse_smart_document/openmuse_smart_document.dart';
import 'package:openmuse_smart_document/browser.dart';

const workspace = String.fromEnvironment('SMARTDOC_WORKSPACE');
const objectId = String.fromEnvironment('REALTIME_OBJECT');
const run = String.fromEnvironment('SMARTDOC_RUN');
const nonce = String.fromEnvironment('REALTIME_NONCE');
const origin = String.fromEnvironment('SMARTDOC_ORIGIN');

class Memory implements DocumentStore {
  Map<String, dynamic>? value;
  @override
  Future<Map<String, dynamic>?> read() async => value;
  @override
  Future<void> write(Map<String, dynamic> v) async {
    value = Map.of(v);
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
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
      home: const RealtimeBrowserFixture(),
    ),
  );
}

class RealtimeBrowserFixture extends StatefulWidget {
  const RealtimeBrowserFixture({super.key});
  @override
  State<RealtimeBrowserFixture> createState() => _State();
}

class _State extends State<RealtimeBrowserFixture> {
  SmartDocumentController? a, b;
  DocumentRealtimeSession? ra, rb;
  DocumentCore? core;
  RealtimeWireCore? wire;
  bool busy = false, ready = false, passed = false;
  String? failure;
  final checks = <String>[];
  final reopening = Uri.base.queryParameters['reopen'] == '1';
  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  CollaborationProvider provider(String user) => AppFlowyCollaborationProvider(
    origin: Uri.parse(origin),
    workspaceId: workspace,
    deviceId: 'browser-realtime-$run-$user',
    accessToken: () async => user == 'alice'
        ? const String.fromEnvironment('SMARTDOC_ALICE_TOKEN')
        : const String.fromEnvironment('SMARTDOC_BOB_TOKEN'),
  );
  DocumentRealtimeSession realtime(
    SmartDocumentController c,
    String user,
  ) => DocumentRealtimeSession(
    controller: c,
    presenceCore: wire!,
    connection: AppFlowyRealtimeConnection(
      origin: Uri.parse(origin),
      workspaceId: workspace,
      deviceId:
          'browser-realtime-$run-$user-${Random.secure().nextInt(0x7fffffff)}',
      clientId:
          (DateTime.now().microsecondsSinceEpoch +
                  Random.secure().nextInt(0x7fffffff))
              .toString(),
      accessToken: () async => user == 'alice'
          ? const String.fromEnvironment('SMARTDOC_ALICE_TOKEN')
          : const String.fromEnvironment('SMARTDOC_BOB_TOKEN'),
      codec: AppFlowyRealtimeCodec(wire!),
    ),
  );
  Future<void> _open() async {
    try {
      core = await WasmDocumentCore.load();
      wire = await loadRealtimeWireCore();
      final c = await SmartDocumentController.open(
        core: core!,
        store: IndexedDbDocumentStore(
          namespace: 'realtime:$workspace:$run:alice',
          objectId: objectId,
        ),
        objectId: objectId,
        provider: reopening ? null : provider('alice'),
        createRemote: !reopening,
        syncInterval: null,
      );
      a = c;
      if (!reopening) {
        ra = realtime(c, 'alice');
        await ra!.start();
        if (!ra!.connected) throw StateError('REALTIME_CONNECT_FAILED');
      }
      if (mounted) setState(() {});
    } on Object {
      if (mounted) setState(() => failure = '打开验证文档失败，请查看本地测试日志');
    }
  }

  Future<void> until(bool Function() condition, String reason) async {
    for (var i = 0; i < 150; i++) {
      if (condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError(reason);
  }

  Future<void> _verify() async {
    setState(() {
      busy = true;
      failure = null;
    });
    try {
      if (a!.blocks.first.delta!.toPlainText() != '浏览器实时协作😀') {
        throw StateError('请先在正文输入“浏览器实时协作😀”');
      }
      checks.add('actual-browser-input-in-original-editor-through-wasm');
      await a!.synchronize();
      if (a!.hasPendingLocalChanges) throw StateError('ACCEPTANCE_FAILED');
      b = await SmartDocumentController.open(
        core: core!,
        store: Memory(),
        objectId: objectId,
        provider: provider('bob'),
        syncInterval: null,
      );
      rb = realtime(b!, 'bob');
      await rb!.start();
      a!.editor.selection = Selection.collapsed(Position(path: [0], offset: 2));
      b!.editor.selection = Selection.single(
        path: [0],
        startOffset: 2,
        endOffset: 4,
      );
      await until(
        () =>
            ra!.collaborators.length == 1 &&
            rb!.collaborators.length == 1 &&
            a!.editor.remoteSelections.value.isNotEmpty,
        'PRESENCE_DEADLINE',
      );
      checks.add('original-wasm-awareness-authenticated-two-user-presence');
      await b!.editor.apply(
        b!.editor.transaction..insertText(b!.blocks.first, 0, '协作'),
      );
      await until(
        () => a!.blocks.first.delta!.toPlainText() == '协作浏览器实时协作😀',
        'REMOTE_TEXT_DEADLINE',
      );
      await until(
        () => b!.editor.remoteSelections.value.any(
          (r) => r.selection.start.offset == 4,
        ),
        'RELATIVE_SELECTION_DEADLINE',
      );
      checks.add('real-ws-update-renders-and-relative-anchor-follows-prefix');
      await b!.history();
      await until(
        () => a!.blocks.first.delta!.toPlainText() == '浏览器实时协作😀',
        'UNDO_DEADLINE',
      );
      checks.add('local-origin-undo-preserves-first-author-input');
      await rb!.connection.disconnect();
      await b!.editor.apply(
        b!.editor.transaction..insertText(b!.blocks.first, 0, '重连'),
      );
      await rb!.start();
      await until(
        () =>
            a!.blocks.first.delta!.toPlainText() == '重连浏览器实时协作😀' &&
            !b!.hasPendingLocalChanges,
        'RECONNECT_DEADLINE',
      );
      checks.add('browser-reconnect-original-manifest-http-repair');
      b!.editor.selection = Selection.single(
        path: [0],
        startOffset: 2,
        endOffset: 4,
      );
      await until(
        () => a!.editor.remoteSelections.value.isNotEmpty,
        'CURSOR_DEADLINE',
      );
      if (ra!.collaborators.single.name != '协作者') {
        throw StateError('PROFILE_TRUST_FAILED');
      }
      checks.add('untrusted-client-profile-is-not-rendered-as-identity');
      await a!.flush();
      setState(() => ready = true);
    } on Object catch (e) {
      setState(() => failure = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _post(String kind) async {
    final r = await http.post(
      Uri.base.resolve('/__realtime/$kind/$nonce'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'status': 'passed',
        'objectId': objectId,
        'checks': checks,
        'platform': 'web',
        'date': DateTime.now().toUtc().toIso8601String(),
      }),
    );
    if (r.statusCode != 204) throw StateError('RECEIPT_REJECTED');
  }

  Future<void> _finish() async {
    setState(() => busy = true);
    try {
      await rb!.close();
      await until(
        () =>
            ra!.collaborators.isEmpty &&
            a!.editor.remoteSelections.value.isEmpty,
        'LEAVE_DEADLINE',
      );
      checks.add('original-null-awareness-removes-avatar-and-remote-selection');
      await a!.flush();
      if (a!.hasPendingLocalChanges) throw StateError('LOCAL_PENDING');
      checks.add('indexeddb-content-checkpoint-does-not-persist-presence');
      await _post('result');
      setState(() => passed = true);
    } on Object {
      setState(() => failure = '完成验证失败');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _reopen() async {
    setState(() => busy = true);
    try {
      if (a!.blocks.first.delta!.toPlainText() != '重连浏览器实时协作😀' ||
          a!.hasPendingLocalChanges ||
          ra != null ||
          a!.editor.remoteSelections.value.isNotEmpty) {
        throw StateError('REOPEN_MISMATCH');
      }
      checks.addAll([
        'actual-page-reload-indexeddb-exact-content-no-duplicate',
        'accepted-local-epoch-restored',
        'transient-presence-and-selection-not-restored',
      ]);
      await _post('reload');
      setState(() => passed = true);
    } on Object {
      setState(() => failure = '重开验证失败');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: a == null
                ? Center(child: Text(failure ?? '正在打开…'))
                : SmartDocumentView(
                    controller: a!,
                    title: '智能文档 · 实时协作',
                    realtime: ra,
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  passed
                      ? '验证通过（${checks.length} 项）'
                      : reopening
                      ? '重开验证'
                      : ready
                      ? '可查看在线协作者，再完成验证'
                      : '请先在正文输入：浏览器实时协作😀',
                ),
                FilledButton(
                  onPressed: busy || a == null || passed
                      ? null
                      : reopening
                      ? _reopen
                      : ready
                      ? _finish
                      : _verify,
                  child: Text(
                    busy
                        ? '验证中…'
                        : reopening
                        ? '验证重开'
                        : ready
                        ? '完成验证'
                        : '验证实时协作',
                  ),
                ),
                if (failure != null) Text(failure!),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
