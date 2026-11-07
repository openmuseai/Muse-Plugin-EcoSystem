import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:muse_smart_document_stage1/main.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'mobile SDK editor, IME callback, tools, Cloud, checkpoint and reopen',
    (tester) async {
      const requireCloud = bool.fromEnvironment(
        'SMARTDOC_REQUIRE_CLOUD',
        defaultValue: true,
      );
      expect(StageOneWorkbench.cloudEnabled, requireCloud);
      final checks = <String>[];
      final workbench = await StageOneWorkbench.open();
      await tester.pumpWidget(StageOneApp(workbench: workbench));
      Future<void> until(bool Function() ready) async {
        for (var i = 0; i < 150; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (ready()) return;
        }
        fail('Mobile deadline exceeded: ${checks.join(", ")}');
      }

      await until(() => workbench.controller != null);
      final c = workbench.controller!;
      final stableBlockId = c.blocks.first.id;
      expect(c.failure, isNull);
      expect(find.text('编辑'), findsOneWidget);
      await tester.tap(find.text('编辑'));
      await until(
        () => find
            .byKey(const ValueKey('smart-document.mobile.tools'))
            .evaluate()
            .isNotEmpty,
      );
      await tester.tap(find.byType(AppFlowyRichText).first);
      await tester.pump(const Duration(milliseconds: 500));
      final keyboard =
          c.editor.service.keyboardService as KeyboardServiceWidgetState;
      expect(keyboard.textInputService.attached, isTrue);
      // Invoke the same public TextInputClient callback as the OS. Keep the real
      // platform connection: do not replace it with TestTextInput's mock channel.
      final client = keyboard.textInputService as TextInputClient;
      final before = client.currentTextEditingValue!;
      const text = '移动智能文档😀';
      client.updateEditingValue(
        before.copyWith(
          text: before.text + text,
          selection: TextSelection.collapsed(
            offset: before.text.length + text.length,
          ),
          composing: TextRange.empty,
        ),
      );
      await until(() => c.blocks.first.delta!.toPlainText().contains(text));
      expect(c.failure, isNull);
      checks.add(
        'real-mobile-sdk-and-attached-ime-unicode-callback-through-appflowy-to-rust',
      );
      final keyboardVisible = tester.view.viewInsets.bottom > 0;
      if (Platform.isAndroid ||
          const bool.fromEnvironment('SMARTDOC_REQUIRE_SOFT_KEYBOARD')) {
        expect(
          keyboardVisible,
          isTrue,
          reason: 'Actual Android soft keyboard must be visible',
        );
      }
      final tools = find.byKey(const ValueKey('smart-document.mobile.tools'));
      final toolbarRect = tester.getRect(tools);
      final screenHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final imeHeight =
          tester.view.viewInsets.bottom / tester.view.devicePixelRatio;
      expect(
        toolbarRect.bottom,
        lessThanOrEqualTo(screenHeight - imeHeight + 1),
      );
      checks.add('single-toolbar-above-platform-keyboard-inset');

      c.editor.selection = Selection.single(
        path: [0],
        startOffset: 0,
        endOffset: 2,
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('smart-document.mobile.format')),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byKey(const ValueKey('smart-document.mobile.panel.format')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('加粗'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        c.blocks.first.delta!.toJson().first['attributes'],
        containsPair('bold', true),
      );
      await tester.tap(find.text('标题 6'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(c.blocks.first.id, stableBlockId);
      expect(c.blocks.first.type, 'heading');
      expect(c.blocks.first.attributes['level'], 6);
      expect(c.blocks.first.delta!.toPlainText(), text);
      await tester.tap(find.text('正文'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(c.blocks.first.id, stableBlockId);
      expect(c.blocks.first.type, 'paragraph');
      expect(
        c.blocks.first.delta!.toJson().first['attributes'],
        containsPair('bold', true),
      );
      await tester.tap(find.byTooltip('关闭面板'));
      await tester.pump();
      checks.add(
        'aa-selection-bold-and-h6-paragraph-roundtrip-preserve-text-and-marks',
      );

      await tester.tap(
        find.byKey(const ValueKey('smart-document.mobile.keyboard')),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(
        find.byKey(const ValueKey('smart-document.mobile.list')),
      );
      await tester.pump();
      expect(
        find
            .byKey(const ValueKey('smart-document.mobile.list'))
            .evaluate()
            .length,
        2,
      );
      expect(keyboard.textInputService.attached, isTrue);
      await tester.tap(find.byTooltip('有序列表'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(c.blocks.first.id, stableBlockId);
      expect(c.blocks.first.type, 'numbered_list');
      await tester.tap(
        find.byKey(const ValueKey('smart-document.mobile.align')),
      );
      await tester.pump();
      expect(keyboard.textInputService.attached, isTrue);
      await tester.tap(find.byTooltip('居中对齐'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(c.blocks.first.attributes[blockComponentAlign], 'center');
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.format_indent_decrease),
            )
            .onPressed,
        isNull,
      );
      checks.add(
        'list-and-align-popovers-retain-ime-and-commit-domain-transactions',
      );
      expect(
        c.blocks.first.delta!.toPlainText(),
        text,
        reason: 'Toolbar/IME roundtrip must not duplicate input',
      );
      await c.flush();
      expect(c.localSave, LocalSaveState.durable);
      expect(c.failure, isNull);

      await tester.tap(
        find.byKey(const ValueKey('smart-document.mobile.insert')),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('代码块'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(c.blocks[1].type, 'code');
      expect(find.byType(AppFlowyRichText), findsNWidgets(2));
      c.editor.selection = Selection.collapsed(Position(path: [1]));
      c.editor.service.keyboardService!.enableKeyBoard(c.editor.selection!);
      await tester.pump(const Duration(milliseconds: 300));
      final codeKeyboard =
          c.editor.service.keyboardService as KeyboardServiceWidgetState;
      final codeClient = codeKeyboard.textInputService as TextInputClient;
      final codeBefore = codeClient.currentTextEditingValue!;
      const codeText = 'print("智能文档😀")\n# literal';
      codeClient.updateEditingValue(
        codeBefore.copyWith(
          text: codeBefore.text + codeText,
          selection: TextSelection.collapsed(
            offset: codeBefore.text.length + codeText.length,
          ),
          composing: TextRange.empty,
        ),
      );
      await until(() => c.blocks[1].delta!.toPlainText().contains('literal'));
      expect(c.blocks[1].delta!.toPlainText(), codeText);
      await c.flush();
      checks.add('mobile-code-block-real-renderer-and-literal-ime-input');

      SmartDocumentController? peer;
      if (requireCloud) {
        peer = await SmartDocumentController.open(
          core: NativeDocumentCore(),
          store: FileDocumentStore(
            File('${workbench.directory.path}/mobile-peer.json'),
          ),
          objectId: c.objectId,
          initialDocState: c.snapshot['docState'] as String,
          provider: AppFlowyCollaborationProvider(
            origin: Uri.parse(StageOneWorkbench.origin),
            workspaceId: StageOneWorkbench.workspace,
            deviceId: 'mobile-bob',
            accessToken: () async => StageOneWorkbench.bobToken,
          ),
          syncInterval: null,
        );
        await peer.insertParagraph('Bob：移动端协作通过');
        for (var i = 0; i < 40; i++) {
          await c.synchronize();
          await peer.synchronize();
          await tester.pump(const Duration(milliseconds: 200));
          if (c.blocks.any(
            (n) => n.delta?.toPlainText().contains('Bob：') == true,
          )) {
            break;
          }
        }
        expect(c.blocks.last.delta!.toPlainText(), contains('Bob：'));
        expect(c.failure, isNull);
        checks.add('second-authenticated-user-cloud-update-renders-in-mobile');
      }
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump(const Duration(milliseconds: 200));
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(c.localSave, LocalSaveState.durable);
      expect(await workbench.session.prepareToClose(), isTrue);
      checks.add('background-callback-flush-and-public-sdk-cas-checkpoint');
      final evidence = Directory('${workbench.directory.path}/evidence');
      await evidence.create(recursive: true);
      await tester.tap(
        find.byKey(const ValueKey('smart-document.mobile.done')),
      );
      await tester.pump(const Duration(milliseconds: 200));
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('stage1.surface')),
      );
      final image = await boundary.toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '${evidence.path}/mobile-editor.png',
      ).writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
      await peer?.close();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await workbench.close();
      final reopened = await StageOneWorkbench.open();
      final content = await reopened.plugin.resourceConversationText(
        reopened.session.opened.content,
      );
      expect(content, contains(text));
      if (requireCloud) expect(content, contains('Bob：'));
      await reopened.close();
      checks.add(
        'same-resource-reopen-through-private-ledger-and-resource-bytes',
      );
      final report = {
        'status': 'passed',
        'cloud': requireCloud ? 'tested' : 'not-run-backend-unavailable',
        'platform': Platform.operatingSystem,
        'run': StageOneWorkbench.run,
        'objectId': c.objectId,
        'softKeyboardVisible': keyboardVisible,
        'imeHeight': imeHeight,
        'toolbarBottom': toolbarRect.bottom,
        'checks': checks,
        'manualIme': 'not-certified',
        'processRestart': 'not-run',
      };
      await File(
        '${evidence.path}/mobile-result.json',
      ).writeAsString(jsonEncode(report));
      // The receipt contains synthetic resource identifiers only, never tokens.
      debugPrint('SMARTDOC_MOBILE_RESULT=${jsonEncode(report)}');
    },
  );
}
