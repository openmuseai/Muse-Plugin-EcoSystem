import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:muse_collab_test_support/muse_collab_test_support.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';
import 'package:muse_smart_document_stage1/main.dart';

class _Memory implements DocumentStore {
  @override
  Future<Map<String, dynamic>?> read() async => null;
  @override
  Future<void> write(Map<String, dynamic> value) async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'original Flutter math editor shares one original formula block through Cloud',
    (t) async {
      final fatal = WidgetController.hitTestWarningShouldBeFatal;
      WidgetController.hitTestWarningShouldBeFatal = true;
      addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = fatal);
      final httpGate = HttpRequestGate(), captured = <String, int>{};
      final frames = OutgoingFrameGate(
        onHeld: (actor, _) => captured[actor] = (captured[actor] ?? 0) + 1,
      );
      final w = await StageOneWorkbench.open(
        realtime: true,
        transportClientFactory: () => httpGate.client(),
        realtimeSocketFactory: (uri) => frames.open('alice', uri),
      );
      await t.pumpWidget(StageOneApp(workbench: w));
      Future<void> until(bool Function() ready, String why) async {
        for (var i = 0; i < 300; i++) {
          await t.pump(const Duration(milliseconds: 100));
          if (ready()) return;
        }
        fail('Formula deadline: $why');
      }

      Future<void> tap(Finder f) async {
        await t.ensureVisible(f);
        await t.pump(const Duration(milliseconds: 150));
        await t.tap(f);
        await t.pump(const Duration(milliseconds: 350));
      }

      await until(() => w.controller != null, 'public resource plugin');
      final c = w.controller!;
      final mobile = t.view.physicalSize.width / t.view.devicePixelRatio < 700;
      if (mobile) await tap(find.text('编辑').last);
      await tap(
        find.byKey(
          ValueKey(
            mobile ? 'smart-document.mobile.insert' : 'smart-document.insert',
          ),
        ),
      );
      await tap(find.text('公式').last);
      final input = find.byKey(const ValueKey('smart-document.formula-input')),
          apply = find.byKey(const ValueKey('smart-document.formula-apply'));
      const initial = r'\frac{1}{2}+\sqrt{x}',
          edited = r'\sum_{i=1}^{n}i=\frac{n(n+1)}{2}',
          finalSource = r'\int_0^1 x^2\,dx=\frac{1}{3}';
      await t.enterText(input, initial);
      final evidence = Directory('${w.directory.path}/evidence');
      await evidence.create(recursive: true);
      Future<void> shot(String name) async {
        await t.pump(const Duration(milliseconds: 200));
        final b = t.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('stage1.surface')),
        );
        final image = await b.toImage(pixelRatio: 1),
            bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '${evidence.path}/$name',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }

      await shot('formula-preview.png');
      await tap(apply);
      await until(
        () =>
            c.blocks.any((b) => b.type == 'math_equation') &&
            find
                .byKey(const ValueKey('smart-document.formula-dialog'))
                .evaluate()
                .isEmpty,
        'actual insert commits',
      );
      final formula = c.blocks.singleWhere((b) => b.type == 'math_equation'),
          ref = DocumentBlockReference(
            objectId: c.objectId,
            blockId: c.blocks.singleWhere((b) => b.type == 'math_equation').id,
          ),
          checks = <String>[];
      expect(c.captureFormula(ref).formula, initial);
      checks.add(
        'actual-desktop-or-mobile-insert-menu-and-original-flutter-math-preview',
      );
      final raw = (c.snapshot['data'] as Map)['blocks'][formula.id] as Map;
      expect(raw['external_id'], isNull);
      expect(raw['external_type'], isNull);
      expect(raw['ty'], 'math_equation');
      checks.add(
        'same-original-formula-schema-and-stable-block-without-parallel-text',
      );
      await c.synchronize();
      final leader = w.plugin.realtimeFor(w.session.record.identity)!;
      await until(
        () => leader.connection.actorUid != null,
        'authenticated original leader',
      );
      final p = await SmartDocumentController.open(
        core: NativeDocumentCore(),
        store: _Memory(),
        objectId: c.objectId,
        provider: AppFlowyCollaborationProvider(
          origin: Uri.parse(StageOneWorkbench.origin),
          workspaceId: StageOneWorkbench.workspace,
          deviceId: 'formula-bob-${StageOneWorkbench.run}',
          accessToken: () async => StageOneWorkbench.bobToken,
          client: httpGate.client(),
        ),
        syncInterval: null,
      );
      final wire = await loadRealtimeWireCore();
      final rt = DocumentRealtimeSession(
        controller: p,
        presenceCore: wire,
        connection: AppFlowyRealtimeConnection(
          origin: Uri.parse(StageOneWorkbench.origin),
          workspaceId: StageOneWorkbench.workspace,
          deviceId: 'formula-peer-${StageOneWorkbench.run}',
          clientId: DateTime.now().microsecondsSinceEpoch.toString(),
          accessToken: () async => StageOneWorkbench.bobToken,
          codec: AppFlowyRealtimeCodec(wire),
          socketFactory: (uri) => frames.open('bob', uri),
        ),
      );
      await rt.start();
      await until(
        () => rt.connection.actorUid != null,
        'authenticated original peer',
      );
      httpGate.hold();
      frames.hold();
      captured.clear();
      await tap(find.byKey(ValueKey('smart-document.formula.${formula.id}')));
      await t.enterText(input, edited);
      await tap(apply);
      await until(
        () => find
            .byKey(const ValueKey('smart-document.formula-dialog'))
            .evaluate()
            .isEmpty,
        'edit committed on local branch',
      );
      await p.editor.apply(
        p.editor.transaction..insertText(p.blocks.first, 0, '协作者公式旁正文😀'),
      );
      await p.flush();
      unawaited(c.synchronize());
      unawaited(p.synchronize());
      await until(
        () =>
            (captured['alice'] ?? 0) > 0 &&
            (captured['bob'] ?? 0) > 0 &&
            httpGate.blockedRequests > 0,
        'independent original frames and HTTP held',
      );
      expect(c.captureFormula(ref).formula, edited);
      expect(p.captureFormula(ref).formula, initial);
      expect(c.blocks.first.delta!.toPlainText(), '');
      expect(p.blocks.first.delta!.toPlainText(), '协作者公式旁正文😀');
      final split = {
        'aliceFormula': c.captureFormula(ref).formula,
        'bobFormula': p.captureFormula(ref).formula,
        'aliceText': c.blocks.first.delta!.toPlainText(),
        'bobText': p.blocks.first.delta!.toPlainText(),
        'heldOriginalFrames': Map.of(captured),
        'blockedHttpRequests': httpGate.blockedRequests,
      };
      checks.add(
        'formula-edit-and-peer-prose-are-truly-independent-before-publishing',
      );
      frames.release();
      httpGate.release();
      await c.synchronize();
      await p.synchronize();
      await until(
        () =>
            c.blocks.first.delta!.toPlainText().contains('协作者公式旁正文😀') &&
            p.captureFormula(ref).formula == edited,
        'both changes converge',
      );
      checks.add(
        'original-document-merge-retains-formula-source-and-independent-unicode-prose',
      );
      await shot('formula-concurrent.png');
      Future<void> history({bool redo = false}) async {
        await tap(
          find.byKey(
            ValueKey(
              mobile
                  ? 'smart-document.mobile.${redo ? 'redo' : 'undo'}'
                  : 'smart-document.${redo ? 'redo' : 'undo'}',
            ),
          ),
        );
      }

      await history();
      await until(
        () => p.captureFormula(ref).formula == initial,
        'author formula undo',
      );
      expect(c.blocks.first.delta!.toPlainText(), '协作者公式旁正文😀');
      await history(redo: true);
      await until(
        () => p.captureFormula(ref).formula == edited,
        'author formula redo',
      );
      checks.add(
        'actual-author-undo-redo-keep-peer-prose-and-original-formula-identity',
      );
      await tap(find.byKey(ValueKey('smart-document.formula.${formula.id}')));
      await t.enterText(input, r'x_{localDraft}');
      await p.updateFormula(p.captureFormula(ref), finalSource);
      await until(
        () => c.captureFormula(ref).formula == finalSource,
        'peer source reaches old dialog',
      );
      await tap(apply);
      expect(find.text('公式、位置或权限已变化；草稿已保留，请重新打开确认'), findsOneWidget);
      expect(t.widget<TextField>(input).controller!.text, r'x_{localDraft}');
      await shot('formula-stale.png');
      await tap(find.text('取消').last);
      checks.add(
        'actual-old-formula-dialog-keeps-draft-and-rejects-observed-peer-overwrite',
      );
      await tap(find.byKey(ValueKey('smart-document.formula.${formula.id}')));
      await t.enterText(input, r'\unsupportedCommand{source-retained}');
      await tap(apply);
      await until(
        () =>
            p.captureFormula(ref).formula ==
            r'\unsupportedCommand{source-retained}',
        'unsupported source retained',
      );
      expect(find.text('公式暂不能渲染，原文保留'), findsOneWidget);
      await shot('formula-fallback.png');
      checks.add(
        'unsupported-tex-preserves-original-source-instead-of-silent-clearing',
      );
      await tap(find.byKey(ValueKey('smart-document.formula.${formula.id}')));
      await tap(find.byKey(const ValueKey('smart-document.formula-delete')));
      await until(
        () => c.resolveBlock(ref) == null && p.resolveBlock(ref) == null,
        'stable delete',
      );
      await history();
      await until(
        () => c.resolveBlock(ref) != null && p.resolveBlock(ref) != null,
        'original block undo restore',
      );
      expect(c.resolveBlock(ref)!.id, formula.id);
      checks.add(
        'actual-formula-deletion-undo-restores-the-same-original-block',
      );
      await tap(find.byKey(ValueKey('smart-document.formula.${formula.id}')));
      await t.enterText(input, finalSource);
      await tap(apply);
      await until(
        () => p.captureFormula(ref).formula == finalSource,
        'final scientific source',
      );
      await c.flush();
      await c.synchronize();
      await p.synchronize();
      expect(await w.session.prepareToClose(), true);
      checks.add(
        'public-resource-checkpoint-and-cloud-retain-formula-and-prose',
      );
      await shot('formula-editor.png');
      expect(t.takeException(), isNull);
      await File('${evidence.path}/formula-e2e.json').writeAsString(
        jsonEncode({
          'status': 'passed',
          'platform': Platform.isIOS ? 'ios' : 'macos',
          'run': StageOneWorkbench.run,
          'objectId': c.objectId,
          'formulaId': formula.id,
          'formula': finalSource,
          'data': c.snapshot['data'],
          'split': split,
          'checks': checks,
          'fullProductAcceptance': 'not-complete',
        }),
      );
      await rt.close();
      await p.close();
      await t.pumpWidget(const SizedBox());
      await t.pump();
      await w.close();
      debugPrint('SMARTDOC_FORMULA_EVIDENCE=${evidence.path}');
    },
  );
}
