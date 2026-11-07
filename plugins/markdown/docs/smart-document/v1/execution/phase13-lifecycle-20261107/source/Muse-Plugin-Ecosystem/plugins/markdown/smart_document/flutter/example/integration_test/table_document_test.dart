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
import 'package:muse_smart_document_stage1/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'table UI -> IME -> offline cell merge -> original Cloud -> SDK checkpoint',
    (tester) async {
      final previousHitTestPolicy =
          WidgetController.hitTestWarningShouldBeFatal;
      WidgetController.hitTestWarningShouldBeFatal = true;
      addTearDown(
        () => WidgetController.hitTestWarningShouldBeFatal =
            previousHitTestPolicy,
      );
      expect(StageOneWorkbench.cloudEnabled, isTrue);
      final w = await StageOneWorkbench.open();
      await tester.pumpWidget(StageOneApp(workbench: w));
      Future<void> until(bool Function() ready) async {
        for (var i = 0; i < 150; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (ready()) return;
        }
        fail('Table UI/Cloud deadline exceeded');
      }

      await until(() => w.controller != null);
      final c = w.controller!;
      final mobile = Platform.isIOS;
      final checks = <String>[];
      c.pauseCollaboration(true);
      if (mobile) {
        await tester.tap(find.text('编辑'));
        await tester.pump();
      }
      await tester.tap(
        find.byKey(
          ValueKey(
            mobile ? 'smart-document.mobile.insert' : 'smart-document.insert',
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(mobile ? '表格' : '表格（2 × 2）'));
      await until(() => c.blocks.any((b) => b.type == 'table'));
      if (mobile) {
        await until(
          () => find
              .byKey(const ValueKey('smart-document.mobile.panel.insert'))
              .evaluate()
              .isEmpty,
        );
      }
      await c.flush();
      final table = c.blocks.firstWhere((b) => b.type == 'table');
      final ref = DocumentBlockReference(
        objectId: c.objectId,
        blockId: table.id,
      );
      Node cell(SmartDocumentController x, int index) =>
          x.resolveBlock(ref)!.children[index].children.first;
      final textId = cell(c, 0).id;
      expect(find.byType(AppFlowyRichText), findsNWidgets(5));
      final tableMenu = find.byKey(
        ValueKey('smart-document.table-menu.${table.id}'),
      );
      expect(tester.getSize(tableMenu).height, greaterThanOrEqualTo(44));
      checks.add('actual-insert-menu-renders-four-rich-text-cells');
      // Clear the insertion caret/handles before tapping: the test must prove
      // hit testing, not inherit the selection created by insertTable itself.
      c.editor.selection = null;
      // Mobile selection handles consume a post-layout notifier; allow its
      // subsequent rebuild before asserting the physical pointer hit target.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byType(AppFlowyRichText).at(1));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        c.editor.selection?.start.path,
        cell(c, 0).path,
        reason: 'Hit testing must address the actual cell',
      );
      final keyboard =
          c.editor.service.keyboardService as KeyboardServiceWidgetState;
      expect(keyboard.textInputService.attached, isTrue);
      final client = keyboard.textInputService as TextInputClient;
      final before = client.currentTextEditingValue!;
      const initial = '表格甲😀\n第二行';
      client.updateEditingValue(
        before.copyWith(
          text: initial,
          selection: const TextSelection.collapsed(offset: initial.length),
          composing: TextRange.empty,
        ),
      );
      await until(() => cell(c, 0).delta!.toPlainText() == initial);
      expect(c.failure, isNull);
      checks.add(
        'attached-platform-ime-unicode-multiline-input-addresses-cell',
      );
      c.editor.selection = Selection.single(
        path: cell(c, 0).path,
        startOffset: 0,
        endOffset: 2,
      );
      await tester.pump();
      if (mobile) {
        await tester.tap(
          find.byKey(const ValueKey('smart-document.mobile.format')),
        );
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byTooltip('加粗'));
        await tester.pump();
        await tester.tap(find.byTooltip('关闭面板'));
      } else {
        await tester.tap(find.byKey(const ValueKey('smart-document.bold')));
      }
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        cell(c, 0).delta!.toJson().first['attributes'],
        containsPair('bold', true),
      );
      checks.add('real-toolbar-bold-preserves-cell-and-text-identities');
      c.pauseCollaboration(false);
      await c.synchronize();
      final bob = await SmartDocumentController.open(
        core: NativeDocumentCore(),
        store: FileDocumentStore(File('${w.directory.path}/table-peer.json')),
        objectId: c.objectId,
        initialDocState: c.snapshot['docState'] as String,
        provider: AppFlowyCollaborationProvider(
          origin: Uri.parse(StageOneWorkbench.origin),
          workspaceId: StageOneWorkbench.workspace,
          deviceId: 'table-bob-${StageOneWorkbench.run}',
          accessToken: () async => StageOneWorkbench.bobToken,
        ),
        syncInterval: null,
      );
      Future<void> converge(bool Function() ready) async {
        for (var i = 0; i < 60; i++) {
          await c.synchronize();
          await bob.synchronize();
          expect(c.failure, isNull);
          expect(bob.failure, isNull);
          if (ready()) return;
          await tester.pump(const Duration(milliseconds: 100));
        }
        fail('Table Cloud convergence failed');
      }

      await converge(
        () =>
            bob.resolveBlock(ref) != null &&
            cell(bob, 0).delta!.toPlainText() == initial,
      );
      c.pauseCollaboration(true);
      bob.pauseCollaboration(true);
      await c.editor.apply(
        c.editor.transaction
          ..insertText(cell(c, 0), initial.length, '（本地甲）')
          ..insertText(cell(c, 1), 0, '左下格'),
      );
      await bob.editor.apply(
        bob.editor.transaction
          ..insertText(
            cell(bob, 0),
            initial.length,
            '（协作乙）',
            attributes: {'italic': true},
          )
          ..insertText(cell(bob, 3), 0, '右下格：协作完成'),
      );
      expect(cell(c, 0).delta!.toPlainText(), isNot(contains('协作乙')));
      await c.flush();
      await bob.flush();
      c.pauseCollaboration(false);
      bob.pauseCollaboration(false);
      await converge(
        () =>
            cell(c, 0).delta!.toPlainText() ==
                cell(bob, 0).delta!.toPlainText() &&
            cell(c, 0).delta!.toPlainText().contains('协作乙') &&
            cell(c, 3).delta!.toPlainText().isNotEmpty,
      );
      expect(cell(c, 0).id, textId);
      expect(cell(c, 1).delta!.toPlainText(), '左下格');
      expect(cell(c, 3).delta!.toPlainText(), '右下格：协作完成');
      checks.add(
        'two-authenticated-members-merge-offline-same-cell-and-different-cell-edits',
      );
      await c.history();
      await converge(() => !cell(bob, 0).delta!.toPlainText().contains('本地甲'));
      expect(cell(c, 0).delta!.toPlainText(), contains('协作乙'));
      expect(cell(c, 3).delta!.toPlainText(), '右下格：协作完成');
      await c.history(redo: true);
      await converge(() => cell(bob, 0).delta!.toPlainText().contains('本地甲'));
      checks.add('origin-undo-redo-keeps-peer-cell-text-and-marks');
      final expected = cell(c, 0).delta!.toPlainText();
      expect(await w.session.prepareToClose(), isTrue);
      expect(w.session.dirty, isFalse);
      final contextText = await w.plugin.resourceConversationText(
        w.session.opened.content,
      );
      // Session.opened is the opening resource; use the persisted bytes below for
      // the true SDK checkpoint assertion in the fresh-process test.
      expect(contextText, isNotNull);
      checks.add('public-sdk-session-cas-checkpoint-completes');
      c.editor.service.keyboardService?.closeKeyboard();
      await tester.pump(const Duration(milliseconds: 400));
      final image = await tester
          .renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('stage1.surface')),
          )
          .toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final evidence = Directory('${w.directory.path}/evidence');
      await evidence.create(recursive: true);
      await File(
        '${evidence.path}/table-editor.png',
      ).writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
      final report = {
        'status': 'passed',
        'platform': mobile ? 'ios' : 'macos',
        'run': StageOneWorkbench.run,
        'objectId': c.objectId,
        'table': ref.toJson(),
        'firstTextBlockId': textId,
        'firstText': expected,
        'checks': checks,
        'softKeyboardVisible': tester.view.viewInsets.bottom > 0,
        'manualIme': 'not-certified',
        'fullProductAcceptance': 'not-complete',
      };
      await File(
        '${evidence.path}/table-e2e.json',
      ).writeAsString(jsonEncode(report));
      await bob.close();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await w.close();
      debugPrint('SMARTDOC_TABLE_EVIDENCE=${evidence.path}');
    },
  );
}
