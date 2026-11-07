import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/base_component/selection/selection_area_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';
import 'package:muse_smart_document_stage1/main.dart';

class _Memory implements DocumentStore {
  Map<String, dynamic>? value;
  @override
  Future<Map<String, dynamic>?> read() async => value;
  @override
  Future<void> write(Map<String, dynamic> v) async {
    value = Map.of(v);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'public SDK realtime UI, native input, remote selection, reconnect and checkpoint',
    (t) async {
      final oldFatal = WidgetController.hitTestWarningShouldBeFatal;
      WidgetController.hitTestWarningShouldBeFatal = true;
      addTearDown(
        () => WidgetController.hitTestWarningShouldBeFatal = oldFatal,
      );
      expect(StageOneWorkbench.cloudEnabled, isTrue);
      final w = await StageOneWorkbench.open(realtime: true);
      await t.pumpWidget(StageOneApp(workbench: w));
      Future<void> until(bool Function() ready, String reason) async {
        for (var i = 0; i < 200; i++) {
          await t.pump(const Duration(milliseconds: 100));
          if (ready()) return;
        }
        fail('Realtime UI deadline: $reason');
      }

      await until(
        () =>
            w.controller != null &&
            w.plugin.realtimeFor(w.session.record.identity)?.connected == true,
        'resource and realtime connection',
      );
      final c = w.controller!,
          ra = w.plugin.realtimeFor(w.session.record.identity)!;
      final mobile = t.view.physicalSize.width / t.view.devicePixelRatio < 700;
      if (mobile) {
        await t.tap(find.text('编辑'));
        await t.pump(const Duration(milliseconds: 300));
      }
      // Blank text has a 4.5px render box; the actual editable line's gesture
      // target is its enclosing full-width selection container.
      await t.tapAt(t.getTopLeft(find.byType(AppFlowyRichText).first) + const Offset(12, 8));
      await t.pump(const Duration(milliseconds: 500));
      final client =
          (c.editor.service.keyboardService as KeyboardServiceWidgetState)
                  .textInputService
              as TextInputClient;
      expect((client as dynamic).attached, isTrue);
      final before = client.currentTextEditingValue!;
      const text = '实时智能文档😀';
      client.updateEditingValue(
        before.copyWith(
          text: before.text + text,
          selection: TextSelection.collapsed(
            offset: before.text.length + text.length,
          ),
          composing: TextRange.empty,
        ),
      );
      await until(
        () =>
            c.blocks.first.delta!.toPlainText() == text &&
            !c.hasPendingLocalChanges,
        'native input and accepted exchange',
      );
      final checks = <String>[
        'public-sdk-plugin-injected-neutral-realtime-session',
        'attached-native-text-input-through-original-editor-and-local-checkpoint',
      ];
      final bob = await SmartDocumentController.open(
        core: NativeDocumentCore(),
        store: _Memory(),
        objectId: c.objectId,
        provider: AppFlowyCollaborationProvider(
          origin: Uri.parse(StageOneWorkbench.origin),
          workspaceId: StageOneWorkbench.workspace,
          deviceId: 'realtime-native-bob-${StageOneWorkbench.run}',
          accessToken: () async => StageOneWorkbench.bobToken,
        ),
        syncInterval: null,
      );
      final wire = await loadRealtimeWireCore();
      final rb = DocumentRealtimeSession(
        controller: bob,
        presenceCore: wire,
        connection: AppFlowyRealtimeConnection(
          origin: Uri.parse(StageOneWorkbench.origin),
          workspaceId: StageOneWorkbench.workspace,
          deviceId: 'realtime-ui-bob-${StageOneWorkbench.run}',
          clientId: (DateTime.now().microsecondsSinceEpoch + 1).toString(),
          accessToken: () async => StageOneWorkbench.bobToken,
          codec: AppFlowyRealtimeCodec(wire),
        ),
      );
      await rb.start();
      bob.editor.selection = Selection.single(
        path: [0],
        startOffset: 2,
        endOffset: 4,
      );
      c.editor.selection = Selection.collapsed(Position(path: [0], offset: 2));
      await until(
        () =>
            ra.collaborators.length == 1 &&
            c.editor.remoteSelections.value.isNotEmpty,
        'authenticated remote participant and selection',
      );
      if (mobile) {
        await t.tap(find.byKey(const ValueKey('smart-document.mobile.done')));
        await t.pump(const Duration(milliseconds: 300));
      }
      expect(
        find.byKey(const ValueKey('smart-document.collaborators')),
        findsOneWidget,
      );
      await t.tap(find.byKey(const ValueKey('smart-document.collaborators')));
      await t.pump(const Duration(milliseconds: 350));
      expect(find.text('在线协作者'), findsOneWidget);
      expect(find.text('协作者'), findsOneWidget);
      Navigator.of(t.element(find.text('在线协作者'))).pop();
      await t.pump(const Duration(milliseconds: 350));
      checks.add(
        'real-online-avatar-and-participant-sheet-no-untrusted-profile-name',
      );
      // The participant sheet intentionally leaves editor focus. Re-establish
      // an active content selection before testing relative caret movement.
      c.editor.selection = Selection.collapsed(Position(path: [0], offset: 2));
      await until(() => bob.editor.remoteSelections.value.any((r) => r.selection.start.offset == 2), 'active selection after participant sheet');
      await bob.editor.apply(
        bob.editor.transaction..insertText(bob.blocks.first, 0, '协作'),
      );
      await until(
        () => c.blocks.first.delta!.toPlainText() == '协作$text',
        'WS remote text renders',
      );
      expect(find.byType(AppFlowyRichText), findsOneWidget);
      await until(
        () => bob.editor.remoteSelections.value.any(
          (r) => r.selection.start.offset == 4,
        ),
        'first author relative anchor follows peer prefix',
      );
      checks.add(
        'peer-text-renders-in-existing-editor-relative-selection-follows-prefix',
      );
      await bob.history();
      await until(
        () => c.blocks.first.delta!.toPlainText() == text,
        'original origin undo',
      );
      checks.add('peer-undo-preserves-first-author-input');
      await rb.connection.disconnect();
      await bob.editor.apply(
        bob.editor.transaction..insertText(bob.blocks.first, 0, '重连'),
      );
      await rb.start();
      await until(
        () =>
            c.blocks.first.delta!.toPlainText() == '重连$text' &&
            !bob.hasPendingLocalChanges,
        'reconnect and HTTP repair',
      );
      checks.add(
        'disconnect-reconnect-original-manifest-idempotent-http-repair',
      );
      bob.editor.selection = Selection.single(
        path: [0],
        startOffset: 2,
        endOffset: 4,
      );
      await until(
        () => c.editor.remoteSelections.value.isNotEmpty,
        'selection after reconnect',
      );
      await until(() => c.editor.remoteSelections.value.any((r) => !r.selection.isCollapsed && r.selection.start.offset == 2 && r.selection.end.offset == 4), 'latest peer range');
      final remoteColor = ra.collaborators.single.color.withValues(alpha: .18);
      await until(() => find.byWidgetPredicate((widget) => widget is SelectionAreaPaint && widget.selectionColor == remoteColor && widget.rects.any((r) => r.width > 0 && r.height > 0)).evaluate().isNotEmpty, 'original remote range painter with nonempty geometry');
      checks.add('original-remote-selection-painter-has-visible-range-geometry');
      await c.flush();
      expect(await w.session.prepareToClose(), isTrue);
      await t.pump(const Duration(milliseconds: 400));
      final evidence = Directory('${w.directory.path}/evidence');
      await evidence.create(recursive: true);
      final boundary = t.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('stage1.surface')),
      );
      final image = await boundary.toImage(pixelRatio: 1);
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await File(
        '${evidence.path}/realtime-editor.png',
      ).writeAsBytes(png.buffer.asUint8List());
      image.dispose();
      await rb.close();
      await until(
        () =>
            ra.collaborators.isEmpty && c.editor.remoteSelections.value.isEmpty,
        'presence leave',
      );
      checks.add('original-null-awareness-clears-remote-avatar-and-selection');
      expect(t.takeException(), isNull);
      await File('${evidence.path}/realtime-e2e.json').writeAsString(
        jsonEncode({
          'status': 'passed',
          'platform': Platform.isIOS ? 'ios' : 'macos',
          'run': StageOneWorkbench.run,
          'objectId': c.objectId,
          'text': c.blocks.first.delta!.toPlainText(),
          'checks': checks,
          'fullProductAcceptance': 'not-complete',
          'nativeInput':
              'attached TextInputClient callback; physical IME not asserted',
        }),
      );
      await bob.close();
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump();
      await w.close();
      debugPrint('SMARTDOC_REALTIME_EVIDENCE=${evidence.path}');
    },
  );
}
