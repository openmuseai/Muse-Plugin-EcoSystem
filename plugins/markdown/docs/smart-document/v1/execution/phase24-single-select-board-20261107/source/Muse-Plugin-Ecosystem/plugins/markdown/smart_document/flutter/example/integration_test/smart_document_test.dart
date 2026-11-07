import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';
import 'package:openmuse_plugin_sdk/openmuse_plugin_sdk.dart';
import 'package:muse_smart_document_stage1/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'resource creator -> native editor/paste/format -> Cloud peer -> resource checkpoint/reopen',
    (tester) async {
      expect(
        StageOneWorkbench.cloudEnabled,
        isTrue,
        reason: 'Run with the isolated fixture --dart-define-from-file',
      );
      final checks = <String>[];
      final workbench = await StageOneWorkbench.open();
      await tester.pumpWidget(StageOneApp(workbench: workbench));
      Future<void> until(bool Function() condition) async {
        for (var i = 0; i < 100; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (condition()) return;
        }
        fail('Native UI deadline exceeded');
      }

      await until(() => workbench.controller != null);
      final c = workbench.controller!;
      expect(c.failure, isNull);
      checks.add('real-resource-creator-local-provider-hub-and-plugin-open');
      await tester.tap(find.byType(AppFlowyRichText).first);
      await tester.pump(const Duration(milliseconds: 200));
      final previousClipboard = await Clipboard.getData(Clipboard.kTextPlain);
      try {
        await Clipboard.setData(const ClipboardData(text: '智能文档端到端验证😀'));
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await until(
          () => c.blocks.first.delta!.toPlainText().contains('端到端验证'),
        );
      } finally {
        await Clipboard.setData(
          ClipboardData(text: previousClipboard?.text ?? ''),
        );
      }
      checks.add('native-keyboard-paste-through-appflowy-transaction-to-rust');
      c.editor.selection = Selection.single(
        path: [0],
        startOffset: 0,
        endOffset: 4,
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('smart-document.bold')));
      await tester.pump(const Duration(milliseconds: 200));
      final runs = c.blocks.first.delta!.toJson();
      expect(runs.first['insert'], '智能文档');
      expect(runs.first['attributes'], containsPair('bold', true));
      expect((runs.last['attributes'] as Map?)?['bold'], isNot(true));
      await c.flush();
      checks.add('native-selection-toolbar-formats-only-selected-range');
      final stableId = c.blocks.first.id;
      await tester.tap(find.byKey(const ValueKey('smart-document.block-type')));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('标题 6'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(c.blocks.first.id, stableId);
      expect(c.blocks.first.type, 'heading');
      await tester.tap(find.byKey(const ValueKey('smart-document.block-type')));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('正文'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(c.blocks.first.id, stableId);
      expect(c.blocks.first.type, 'paragraph');
      expect(
        c.blocks.first.delta!.toJson().first['attributes'],
        containsPair('bold', true),
      );
      checks.add('native-type-menu-keeps-block-id-and-selection-marks');

      final peer = await SmartDocumentController.open(
        core: NativeDocumentCore(),
        store: FileDocumentStore(File('${workbench.directory.path}/peer.json')),
        objectId: c.objectId,
        initialDocState: c.snapshot['docState'] as String,
        provider: AppFlowyCollaborationProvider(
          origin: Uri.parse(StageOneWorkbench.origin),
          workspaceId: StageOneWorkbench.workspace,
          deviceId: 'stage1-native-bob',
          accessToken: () async => StageOneWorkbench.bobToken,
        ),
        syncInterval: null,
      );
      for (var attempt = 0; attempt < 30; attempt++) {
        await c.synchronize();
        await peer.synchronize();
        if (peer.blocks.first.delta!.toPlainText() ==
            c.blocks.first.delta!.toPlainText()) {
          break;
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        peer.blocks.first.delta!.toPlainText(),
        c.blocks.first.delta!.toPlainText(),
      );
      await peer.insertParagraph('协作者 Bob：真实 Cloud 同步通过');
      for (var attempt = 0; attempt < 30; attempt++) {
        await peer.synchronize();
        await c.synchronize();
        if (c.blocks.length == 2) break;
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(c.blocks.last.delta!.toPlainText(), contains('协作者 Bob'));
      expect(c.failure, isNull);
      await tester.pump(const Duration(milliseconds: 400));
      checks.add('second-authenticated-user-change-renders-in-native-editor');
      final paragraphs = find.byType(AppFlowyRichText);
      expect(paragraphs, findsNWidgets(2));
      final blockGap =
          tester.getTopLeft(paragraphs.at(1)).dy -
          tester.getTopLeft(paragraphs.first).dy;
      expect(blockGap, inInclusiveRange(20, 64));
      checks.add('continuous-writing-block-spacing');
      expect(await workbench.session.prepareToClose(), isTrue);
      expect(workbench.session.dirty, isFalse);
      final saved = await workbench.hub.resolve(
        workbench.session.record.reference(),
        ResourceAccess(
          scope: workbench.hub.scope,
          audience: 'native-e2e',
          generation: workbench.hub.generation,
          expiresAtMs: DateTime.now().millisecondsSinceEpoch + 60000,
          operations: ResourceOperation.values.toSet(),
        ),
      );
      final text = await workbench.plugin.resourceConversationText(
        saved.content,
      );
      expect(text, contains('端到端验证'));
      expect(text, contains('协作者 Bob'));
      checks.add(
        'bounded-session-cas-checkpoint-and-ordered-context-extraction',
      );
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('stage1.surface')),
      );
      final image = await boundary.toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final evidence = Directory('${workbench.directory.path}/evidence');
      await evidence.create(recursive: true);
      await File(
        '${evidence.path}/native-editor.png',
      ).writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
      await peer.close();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 200));
      await workbench.close();
      final reopened = await StageOneWorkbench.open();
      final persisted = await reopened.plugin.resourceConversationText(
        reopened.session.opened.content,
      );
      expect(persisted, contains('协作者 Bob'));
      await reopened.close();
      checks.add('same-resource-reopens-through-real-private-ledger-and-blobs');
      final report = {
        'status': 'passed',
        'platform': 'macos-native',
        'checks': checks,
        'date': DateTime.now().toUtc().toIso8601String(),
        'limits': [
          'Clipboard input, not a manual CJK IME certification',
          'Public SDK workbench fixture; production Host release composition not enabled',
        ],
      };
      await File(
        '${evidence.path}/native-e2e.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
      // Only synthetic evidence paths are printed, never tokens or clipboard content.
      // ignore: avoid_print
      print('SMARTDOC_EVIDENCE_DIRECTORY=${evidence.path}');
    },
  );
}
