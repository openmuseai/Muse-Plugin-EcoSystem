import 'dart:async';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';
import 'package:openmuse_smart_document/src/formula_components.dart';

class _Memory implements DocumentStore {
  Map<String, dynamic>? value;
  @override
  Future<Map<String, dynamic>?> read() async => value;
  @override
  Future<void> write(Map<String, dynamic> v) async {
    value = v;
  }
}

Widget app(SmartDocumentController c) => MaterialApp(
  localizationsDelegates: [AppFlowyEditorLocalizations.delegate],
  supportedLocales: AppFlowyEditorLocalizations.delegate.supportedLocales,
  home: Scaffold(
    body: SmartDocumentView(controller: c, title: '智能文档'),
  ),
);
void main() {
  for (final width in [390.0, 700.0, 1200.0]) {
    testWidgets(
      'formula insertion, original renderer, stale source and readonly at $width',
      (t) async {
        t.view.physicalSize = Size(width, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final fatal = WidgetController.hitTestWarningShouldBeFatal;
        WidgetController.hitTestWarningShouldBeFatal = true;
        addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = fatal);
        final c = (await t.runAsync(
          () => SmartDocumentController.open(
            core: NativeDocumentCore(),
            store: _Memory(),
            objectId: 'c68fc7ba-6830-4385-a860-60b387da2f33',
          ),
        ))!;
        debugPrint('FORMULA_UI_READY $width');
        await t.pumpWidget(app(c));
        await t.pumpAndSettle();
        Future<void> tap(Finder f) async {
          debugPrint('FORMULA_UI_TAP $f');
          await t.ensureVisible(f);
          await t.pumpAndSettle();
          await t.tap(f);
          await t.pumpAndSettle();
          for (var i = 0; i < 4; i++) {
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await t.pumpAndSettle();
          }
        }

        Future<void> domain(Future<void> Function() action) async {
          var done = false;
          Object? failure;
          unawaited(
            action().then(
              (_) => done = true,
              onError: (Object error) {
                failure = error;
                done = true;
              },
            ),
          );
          for (var i = 0; i < 100 && !done; i++) {
            await t.pump(const Duration(milliseconds: 20));
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 5)),
            );
          }
          if (failure != null) throw failure!;
          expect(
            done,
            true,
            reason:
                'domain and mounted UI must complete across both test scheduling zones',
          );
          await t.pumpAndSettle();
        }

        final mobile = width < 700;
        if (mobile) await tap(find.text('编辑').last);
        await tap(
          find.byKey(
            ValueKey(
              mobile ? 'smart-document.mobile.insert' : 'smart-document.insert',
            ),
          ),
        );
        await tap(find.text('公式').last);
        final input = find.byKey(
          const ValueKey('smart-document.formula-input'),
        );
        await t.enterText(input, r'\frac{1}{2}+\sqrt{x}');
        await t.pumpAndSettle();
        expect(find.byType(Math), findsOneWidget);
        final apply = find.byKey(
          const ValueKey('smart-document.formula-apply'),
        );
        expect(t.getSize(apply).height, greaterThanOrEqualTo(44));
        await tap(apply);
        debugPrint(
          'FORMULA_UI_STATE epoch=${c.localMutationEpoch} types=${c.blocks.map((b) => b.type).toList()} failure=${c.failure} editable=${c.editor.editable} text=${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().toList()}',
        );
        final node = c.blocks.singleWhere((b) => b.type == 'math_equation');
        final ref = DocumentBlockReference(
          objectId: c.objectId,
          blockId: node.id,
        );
        expect(c.captureFormula(ref).formula, r'\frac{1}{2}+\sqrt{x}');
        expect(find.byType(Math), findsOneWidget);
        await tap(find.byKey(ValueKey('smart-document.formula.${node.id}')));
        debugPrint('FORMULA_UI_DRAFT');
        await t.enterText(input, 'local draft');
        await t.pumpAndSettle();
        final epoch = c.localMutationEpoch;
        debugPrint('FORMULA_UI_KEYS');
        await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await t.sendKeyEvent(LogicalKeyboardKey.keyZ);
        await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await t.pumpAndSettle();
        expect(
          c.localMutationEpoch,
          epoch,
          reason: 'formula draft undo must not undo the document block',
        );
        await t.enterText(input, 'local draft');
        debugPrint('FORMULA_UI_REMOTE');
        await domain(
          () => c.updateFormula(c.captureFormula(ref), 'remote source'),
        );
        await t.pumpAndSettle();
        await tap(apply);
        expect(find.text('公式、位置或权限已变化；草稿已保留，请重新打开确认'), findsOneWidget);
        expect(t.widget<TextField>(input).controller!.text, 'local draft');
        expect(c.captureFormula(ref).formula, 'remote source');
        await tap(find.text('取消').last);
        await tap(find.byKey(ValueKey('smart-document.formula.${node.id}')));
        await t.enterText(input, r'\notARealCommand{preserved}');
        await tap(apply);
        expect(c.captureFormula(ref).formula, r'\notARealCommand{preserved}');
        expect(find.text('公式暂不能渲染，原文保留'), findsOneWidget);
        await tap(find.byKey(ValueKey('smart-document.formula.${node.id}')));
        await tap(find.byKey(const ValueKey('smart-document.formula-delete')));
        expect(c.resolveBlock(ref), isNull);
        await domain(() => c.history());
        await t.pumpAndSettle();
        expect(c.resolveBlock(ref)?.id, node.id);
        c.acceptRealtimeAccess(
          canRead: true,
          canWrite: false,
          reason: 'read_only',
        );
        await t.pumpAndSettle();
        await tap(find.byKey(ValueKey('smart-document.formula.${node.id}')));
        expect(t.widget<TextField>(input).readOnly, true);
        expect(
          find.byKey(const ValueKey('smart-document.formula-apply')),
          findsNothing,
        );
        c.acceptRealtimeAccess(
          canRead: false,
          canWrite: false,
          reason: 'forbidden',
        );
        await t.pumpAndSettle();
        expect(find.text('无法访问此文档'), findsOneWidget);
        expect(input, findsNothing);
        await tap(find.text('取消').last);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
        await domain(() => c.close());
      },
    );
  }
  testWidgets(
    'renderer bounds macros, dimensions and unsupported sources without changing source',
    (t) async {
      for (final source in [
        r'\def\a{\a}\a',
        r'\rule{999999999999em}{999999999em}',
        r'\href{https://example.com}{x}',
        '{' * 65 + 'x' + '}' * 65,
        r'\sqrt ' * 257,
      ]) {
        expect(DocumentFormulaRenderer.canRender(source), false);
        await t.pumpWidget(
          MaterialApp(home: Scaffold(body: DocumentFormulaRenderer(source))),
        );
        await t.pumpAndSettle();
        expect(find.text('公式暂不能渲染，原文保留'), findsOneWidget);
        expect(t.takeException(), isNull);
      }
    },
  );
}
