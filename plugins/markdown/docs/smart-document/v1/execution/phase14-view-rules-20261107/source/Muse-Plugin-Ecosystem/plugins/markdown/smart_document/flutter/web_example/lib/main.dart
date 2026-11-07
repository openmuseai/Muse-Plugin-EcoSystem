import 'dart:async';
import 'dart:convert';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:openmuse_smart_document/openmuse_smart_document.dart';
import 'package:openmuse_smart_document/browser.dart';

const workspace = String.fromEnvironment('SMARTDOC_WORKSPACE');
const objectId = String.fromEnvironment(
  'SMARTDOC_OBJECT',
  defaultValue: 'a18704b8-7290-4002-b31c-67f1b4cad1ae',
);
const run = String.fromEnvironment('SMARTDOC_RUN', defaultValue: 'local');
const acceptance = bool.fromEnvironment('SMARTDOC_ACCEPTANCE');
const nonce = String.fromEnvironment('SMARTDOC_EVIDENCE_NONCE');
const origin = String.fromEnvironment(
  'SMARTDOC_ORIGIN',
  defaultValue: 'http://127.0.0.1:18000',
);

String namespace(String user) => '$workspace:$run:$user';
AppFlowyCollaborationProvider provider(String user) =>
    AppFlowyCollaborationProvider(
      origin: Uri.parse(origin),
      workspaceId: workspace,
      deviceId: 'web-$run-$user',
      accessToken: () async => switch (user) {
        'alice' => const String.fromEnvironment('SMARTDOC_ALICE_TOKEN'),
        'bob' => const String.fromEnvironment('SMARTDOC_BOB_TOKEN'),
        _ => const String.fromEnvironment('SMARTDOC_OUTSIDER_TOKEN'),
      },
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
      locale: const Locale('zh', 'CN'),
      theme: ThemeData(
        colorSchemeSeed: const Color(0xff4c63d9),
        useMaterial3: true,
      ),
      home: const BrowserWorkbench(),
    ),
  );
}

class BrowserWorkbench extends StatefulWidget {
  const BrowserWorkbench({super.key});
  @override
  State<BrowserWorkbench> createState() => _BrowserWorkbenchState();
}

class _BrowserWorkbenchState extends State<BrowserWorkbench> {
  SmartDocumentController? controller;
  DocumentCore? core;
  DocumentMediaSession? media;
  String? failure;
  bool running = false, passed = false;
  final checks = <String>[];
  final reopening = Uri.base.queryParameters['reopen'] == '1';
  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      final engine = await WasmDocumentCore.load();
      final c = await SmartDocumentController.open(
        core: engine,
        store: IndexedDbDocumentStore(
          namespace: namespace('alice'),
          objectId: objectId,
        ),
        objectId: objectId,
        provider: workspace.isEmpty || reopening ? null : provider('alice'),
        syncInterval: acceptance ? null : const Duration(seconds: 1),
      );
      if (!mounted) {
        await c.close();
        return;
      }
      final cache = DocumentStoreAssetCache(
        (key) => IndexedDbDocumentStore(
          namespace: "${namespace('alice')}:assets",
          objectId: key,
        ),
      );
      final mediaSession = DocumentMediaSession(
        controller: c,
        repository: workspace.isEmpty || reopening
            ? LocalAssetRepository(scope: namespace('alice'), cache: cache)
            : CachedAssetRepository(
                source: CloudAssetRepository(
                  origin: Uri.parse(origin),
                  workspaceId: workspace,
                  accessToken: () async =>
                      const String.fromEnvironment('SMARTDOC_ALICE_TOKEN'),
                ),
                cache: cache,
                allowOffline: () => true,
              ),
        draftStore: IndexedDbDocumentStore(
          namespace: "${namespace('alice')}:upload-drafts",
          objectId: objectId,
        ),
      );
      await mediaSession.restore();
      if (!mounted) {
        mediaSession.dispose();
        await c.close();
        return;
      }
      setState(() {
        media = mediaSession;
        controller = c;
        core = engine;
      });
    } on Object catch (error) {
      if (mounted) setState(() => failure = '$error');
    }
  }

  void require(bool value, String message) {
    if (!value) throw StateError(message);
  }

  Future<void> record(String check) async {
    if (mounted) setState(() => checks.add(check));
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }

  String text(SmartDocumentController c) => c.blocks.first.delta!.toPlainText();
  Future<void> insert(
    SmartDocumentController c,
    String value, {
    bool bold = false,
  }) async {
    final t = c.editor.transaction
      ..insertText(
        c.blocks.first,
        c.blocks.first.delta!.length,
        value,
        attributes: bold ? {'bold': true} : null,
      );
    await c.editor.apply(t);
    await c.flush();
    require(c.contentFailure == null, 'Editor transaction rejected');
  }

  Future<void> converge(
    List<SmartDocumentController> clients,
    bool Function() condition,
  ) async {
    for (var i = 0; i < 60; i++) {
      for (final c in clients) {
        await c.synchronize();
        require(
          c.syncState == DocumentSyncState.accepted,
          'Cloud exchange failed: ${c.failure}',
        );
      }
      if (condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('Cloud convergence deadline exceeded');
  }

  Future<void> _verify() async {
    if (running || passed || controller == null) return;
    setState(() {
      running = true;
      failure = null;
    });
    SmartDocumentController? bob;
    try {
      final alice = controller!;
      if (reopening) {
        require(alice.provider == null, 'Offline reopen must not read Cloud');
        require(
          text(alice).contains('Native种子😀') &&
              text(alice).contains('Web甲') &&
              text(alice).contains('Web乙'),
          'IndexedDB page reload lost content',
        );
        require(
          alice.blocks.any((n) => n.delta?.toPlainText() == 'Web 新增块'),
          'IndexedDB page reload lost structure',
        );
        await record('page-reload-restores-actual-indexeddb-without-cloud');
        final table = alice.blocks.firstWhere((n) => n.type == 'table');
        final proof = await IndexedDbDocumentStore(
          namespace: '${namespace('alice')}:acceptance-proof',
          objectId: objectId,
        ).read();
        final firstCellText = table.children.first.children.first;
        require(
          proof?['objectId'] == objectId &&
              proof?['tableId'] == table.id &&
              proof?['cellId'] == table.children.first.id &&
              proof?['textBlockId'] == firstCellText.id &&
              proof?['externalTextId'] ==
                  alice.snapshot['data']['blocks'][firstCellText
                      .id]['external_id'] &&
              jsonEncode(proof?['delta']) ==
                  jsonEncode(firstCellText.delta!.toJson()),
          'Table identities or exact rich-text changed across reload',
        );
        require(
          table.children.first.children.first.delta!.toPlainText().contains(
                'Web表格甲',
              ) &&
              table.children.first.children.first.delta!.toPlainText().contains(
                'Web表格乙',
              ),
          'Table lost on offline whole-page reload',
        );
        await record(
          'page-reload-restores-table-cell-identities-and-rich-text',
        );
        final imageRef = DocumentBlockReference.fromJson(
          (proof!['image'] as Map).cast<String, dynamic>(),
        );
        require(
          alice.resolveBlock(imageRef)?.attributes['title'] == '浏览器私有图片😀',
          'Image properties lost on reload',
        );
        final imageBytes = await media!.repository.read(
          AssetReference.fromJson(
            (proof['asset'] as Map).cast<String, dynamic>(),
          ),
        );
        require(
          imageBytes.isNotEmpty,
          'Private cached image unavailable offline',
        );
        require(
          alice.blocks.first.delta!.toJson().any(
            (run) =>
                (run['attributes'] as Map?)?['href'] ==
                'https://example.com/browser-document',
          ),
          'Link mark lost on reload',
        );
        await record(
          'page-reload-restores-image-registers-href-and-private-indexeddb-bytes',
        );
      } else {
        require(text(alice) == 'Native种子😀', 'Native seed not received');
        final stable = alice.blocks.first.id;
        await record(
          'browser-wasm-reads-native-created-document-from-original-cloud',
        );
        bob = await SmartDocumentController.open(
          core: core!,
          store: IndexedDbDocumentStore(
            namespace: namespace('bob'),
            objectId: objectId,
          ),
          objectId: objectId,
          provider: provider('bob'),
          syncInterval: null,
        );
        final peer = bob;
        require(
          peer.blocks.first.id == stable,
          'Stable native block ID changed',
        );
        alice.pauseCollaboration(true);
        bob.pauseCollaboration(true);
        await insert(alice, '（Web甲）');
        await insert(bob, '（Web乙）', bold: true);
        require(
          !text(alice).contains('Web乙') && !text(peer).contains('Web甲'),
          'Offline sessions not independent',
        );
        await record('browser-offline-writes-are-local-before-exchange');
        alice.pauseCollaboration(false);
        bob.pauseCollaboration(false);
        await converge(
          [alice, bob],
          () =>
              text(alice) == text(peer) &&
              text(alice).contains('Web甲') &&
              text(alice).contains('Web乙'),
        );
        await record(
          'two-authenticated-browser-members-converge-unicode-and-marks',
        );
        await alice.history();
        await converge(
          [alice, bob],
          () =>
              text(alice) == text(peer) &&
              !text(alice).contains('Web甲') &&
              text(alice).contains('Web乙'),
        );
        await alice.history(redo: true);
        await converge([
          alice,
          bob,
        ], () => text(alice) == text(peer) && text(alice).contains('Web甲'));
        await record('browser-origin-undo-redo-preserves-peer-text');
        await bob.insertParagraph('Web 新增块');
        await converge([
          alice,
          bob,
        ], () => alice.blocks.length == 2 && peer.blocks.length == 2);
        require(
          alice.blocks.first.id == stable,
          'Remote projection changed stable ID',
        );
        await record('browser-inserted-block-projects-with-stable-native-id');
        final tableRef = await alice.insertTable(
          after: DocumentBlockReference(objectId: objectId, blockId: stable),
        );
        await converge([alice, bob], () => bob!.resolveBlock(tableRef) != null);
        Node tableText(SmartDocumentController x) =>
            x.resolveBlock(tableRef)!.children.first.children.first;
        final tableTextId = tableText(alice).id;
        alice.pauseCollaboration(true);
        bob.pauseCollaboration(true);
        await alice.editor.apply(
          alice.editor.transaction..insertText(
            tableText(alice),
            0,
            'Web表格甲😀',
            attributes: {'bold': true},
          ),
        );
        await bob.editor.apply(
          bob.editor.transaction..insertText(
            tableText(bob),
            0,
            'Web表格乙',
            attributes: {'italic': true},
          ),
        );
        await alice.flush();
        await bob.flush();
        alice.pauseCollaboration(false);
        bob.pauseCollaboration(false);
        await converge(
          [alice, bob],
          () =>
              tableText(alice).delta!.toPlainText() ==
                  tableText(peer).delta!.toPlainText() &&
              tableText(alice).delta!.toPlainText().contains('Web表格乙'),
        );
        require(
          tableText(alice).id == tableTextId,
          'Table text identity changed',
        );
        await alice.history();
        await converge([
          alice,
          bob,
        ], () => !tableText(peer).delta!.toPlainText().contains('Web表格甲'));
        require(
          tableText(alice).delta!.toPlainText().contains('Web表格乙'),
          'Table undo lost peer',
        );
        await alice.history(redo: true);
        await converge([
          alice,
          bob,
        ], () => tableText(peer).delta!.toPlainText().contains('Web表格甲'));
        await record(
          'browser-table-cell-offline-concurrency-rich-text-and-origin-undo',
        );
        final outsider = provider('outsider');
        var deniedReads = false, deniedWrites = false;
        try {
          await outsider.readState(objectId);
        } on SmartDocumentFailure catch (e) {
          deniedReads = e.code == 'FORBIDDEN';
        }
        final request = core!.call({
          'action': 'syncRequest',
          'handle': alice.handle,
        });
        try {
          await outsider.exchange(
            objectId,
            base64Decode(request['body'] as String),
          );
        } on SmartDocumentFailure catch (e) {
          deniedWrites = e.code == 'FORBIDDEN';
        }
        outsider.close();
        require(
          deniedReads && deniedWrites,
          'Browser raw nonmember access was not rejected',
        );
        await record('browser-nonmember-read-and-raw-write-rejected-by-cloud');
        await alice.flush();
        final cached = await IndexedDbDocumentStore(
          namespace: namespace('alice'),
          objectId: objectId,
        ).read();
        require(
          cached?['docState'] == alice.snapshot['docState'],
          'IndexedDB transaction not complete',
        );
        // Reuse href/Yrs range adapter and original image component model.
        alice.editor.selection = Selection.single(
          path: alice.blocks.first.path,
          startOffset: 0,
          endOffset: 2,
        );
        final link = alice.captureTextRange()!;
        await alice.applyLink(
          link,
          href: 'https://example.com/browser-document',
        );
        final png = (await rootBundle.load(
          'assets/test-image.png',
        )).buffer.asUint8List();
        final asset = await media!.repository.put(
          owner: alice.objectId,
          bytes: png,
          mediaType: 'image/png',
        );
        final imageId =
            'browser-image-${DateTime.now().microsecondsSinceEpoch}';
        await alice.insertImage(
          blockId: imageId,
          asset: asset,
          width: 160,
          height: 160,
        );
        final imageRef = DocumentBlockReference(
          objectId: alice.objectId,
          blockId: imageId,
        );
        await alice.updateImage(imageRef, {
          'title': '浏览器私有图片😀',
          'alt': '合成蓝色图片',
        });
        await converge(
          [alice, bob],
          () =>
              jsonEncode(alice.snapshot['data']) ==
              jsonEncode(bob!.snapshot['data']),
        );
        final bobAssets = CloudAssetRepository(
          origin: Uri.parse(origin),
          workspaceId: workspace,
          accessToken: () async =>
              const String.fromEnvironment('SMARTDOC_BOB_TOKEN'),
        );
        try {
          require(
            base64Encode(await bobAssets.read(asset)) == base64Encode(png),
            'Second user private image mismatch',
          );
        } finally {
          bobAssets.close();
        }
        await record(
          'browser-wasm-relative-href-and-original-image-model-converge-with-peer',
        );
        await record(
          'browser-authenticated-private-image-upload-and-second-user-bytes',
        );
        // Independent test namespace preserves the pre-reload expectation;
        // production document persistence is not modified by this proof data.
        final savedTable = alice.blocks.firstWhere((n) => n.type == 'table');
        final savedText = savedTable.children.first.children.first;
        await IndexedDbDocumentStore(
          namespace: '${namespace('alice')}:acceptance-proof',
          objectId: objectId,
        ).write({
          'objectId': objectId,
          'image': imageRef.toJson(),
          'asset': asset.toJson(),
          'tableId': savedTable.id,
          'cellId': savedTable.children.first.id,
          'textBlockId': savedText.id,
          'externalTextId':
              alice.snapshot['data']['blocks'][savedText.id]['external_id'],
          'delta': savedText.delta!.toJson(),
        });
        await record('browser-indexeddb-write-transaction-completed');
      }
      await bob?.close();
      bob = null;
      final result = {
        'status': 'passed',
        'platform': reopening ? 'web-reload' : 'web-browser',
        'checks': checks,
        'date': DateTime.now().toUtc().toIso8601String(),
      };
      final response = await http.post(
        Uri.base.resolve('/__stage2/${reopening ? 'reload' : 'result'}/$nonce'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(result),
      );
      require(response.statusCode == 204, 'Evidence receipt failed');
      if (mounted) {
        setState(() {
          running = false;
          passed = true;
        });
      }
    } on Object catch (error) {
      await bob?.close();
      if (mounted) {
        setState(() {
          failure = '$error';
          running = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Row(
        children: [
          Expanded(
            child: controller == null
                ? Center(child: Text(failure ?? '正在加载文档…'))
                : SmartDocumentView(
                    controller: controller!,
                    media: media,
                    title: '智能文档 · Web',
                  ),
          ),
          if (acceptance)
            SizedBox(
              width: 300,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ListView(
                  children: [
                    const Text(
                      '浏览器端到端验证',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      reopening
                          ? '重载后从 IndexedDB 恢复，不访问 Cloud'
                          : '同一 AppFlowy 内核 · 真实 Cloud · 两个账号',
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: controller == null || running || passed
                          ? null
                          : _verify,
                      child: Text(
                        passed
                            ? '验证通过'
                            : running
                            ? '正在验证…'
                            : '开始验证',
                      ),
                    ),
                    if (failure != null)
                      Text(failure!, style: const TextStyle(color: Colors.red)),
                    for (final check in checks)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('✓ $check'),
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
