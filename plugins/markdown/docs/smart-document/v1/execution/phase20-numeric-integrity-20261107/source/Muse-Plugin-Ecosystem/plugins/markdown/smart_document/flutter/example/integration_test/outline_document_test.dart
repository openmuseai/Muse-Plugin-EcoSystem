import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';
import 'package:muse_smart_document_stage1/main.dart';

class _Memory implements DocumentStore {
  @override
  Future<Map<String, dynamic>?> read() async => null;
  @override
  Future<void> write(Map<String, dynamic> v) async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'original editor outline UI follows Cloud peer headings with stable identity',
    (t) async {
      final fatal = WidgetController.hitTestWarningShouldBeFatal;
      WidgetController.hitTestWarningShouldBeFatal = true;
      addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = fatal);
      final w = await StageOneWorkbench.open(realtime: true);
      await t.pumpWidget(StageOneApp(workbench: w));
      Future<void> until(bool Function() ready, String why) async {
        for (var i = 0; i < 300; i++) {
          await t.pump(const Duration(milliseconds: 100));
          if (ready()) return;
        }
        fail('Outline deadline: $why');
      }

      Future<void> tap(Finder f) async {
        await t.ensureVisible(f);
        await t.pump(const Duration(milliseconds: 150));
        await t.tap(f);
        await t.pump(const Duration(milliseconds: 350));
      }

      await until(() => w.controller != null, 'public plugin');
      final c = w.controller!;
      final mobile = t.view.physicalSize.width / t.view.devicePixelRatio < 700;
      if (mobile) await tap(find.text('编辑').last);
      final h1 = headingNode(level: 1, text: '项目计划');
      final h3 = headingNode(level: 3, text: '协作章节😀');
      final h2 = headingNode(level: 2, text: '验收清单');
      await c.editor.apply(
        c.editor.transaction..insertNodes(
          [1],
          [
            h1,
            ...List.generate(
              32,
              (i) => paragraphNode(text: '第 $i 段：智能文档沿用原 AppFlowy 内容与协作内核。'),
            ),
            h3,
            h2,
            ...List.generate(30, (i) => paragraphNode(text: '后续 $i 段正文。')),
          ],
          deepCopy: false,
        ),
      );
      await c.flush();
      await c.synchronize();
      final leader = w.plugin.realtimeFor(w.session.record.identity)!;
      await until(
        () => leader.connection.actorUid != null,
        'original authenticated leader',
      );
      final p = await SmartDocumentController.open(
        core: NativeDocumentCore(),
        store: _Memory(),
        objectId: c.objectId,
        provider: AppFlowyCollaborationProvider(
          origin: Uri.parse(StageOneWorkbench.origin),
          workspaceId: StageOneWorkbench.workspace,
          deviceId: 'outline-bob-${StageOneWorkbench.run}',
          accessToken: () async => StageOneWorkbench.bobToken,
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
          deviceId: 'outline-peer-${StageOneWorkbench.run}',
          clientId: DateTime.now().microsecondsSinceEpoch.toString(),
          accessToken: () async => StageOneWorkbench.bobToken,
          codec: AppFlowyRealtimeCodec(wire),
        ),
      );
      await rt.start();
      await until(() => rt.connection.actorUid != null, 'authenticated peer');
      final checks = <String>[];
      expect(c.outline.entries.map((e) => e.level).toList(), [1, 3, 2]);
      expect(c.outline.entries[1].parentId, h1.id);
      expect(c.outline.entries[2].parentId, h1.id);
      checks.add('original-kernel-text-projection-h1-h3-h2-hierarchy');
      Future<void> openOutline() async {
        if (mobile) {
          if (find.text('完成').evaluate().isNotEmpty) {
            await tap(find.text('完成').first);
          }
          await tap(find.text('目录').last);
        } else if (find.byType(DocumentOutlineView).evaluate().isEmpty) {
          await tap(
            find.byKey(const ValueKey('smart-document.outline.toggle')),
          );
        }
      }

      final evidence = Directory('${w.directory.path}/evidence');
      await evidence.create(recursive: true);
      Future<void> shot(String name) async {
        await t.pump(const Duration(milliseconds: 200));
        final b = t.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('stage1.surface')),
        );
        final image = await b.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '${evidence.path}/$name',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }

      await openOutline();
      final before = c.snapshot['docState'],
          epoch = c.localMutationEpoch,
          undo = c.canUndo;
      final fold = find.byKey(ValueKey('smart-document.outline.fold.${h1.id}'));
      await tap(fold);
      expect(
        find.byKey(ValueKey('smart-document.outline.entry.${h3.id}')),
        findsNothing,
      );
      await tap(fold);
      expect(
        find.byKey(ValueKey('smart-document.outline.entry.${h3.id}')),
        findsOneWidget,
      );
      expect(c.snapshot['docState'], before);
      expect(c.localMutationEpoch, epoch);
      expect(c.canUndo, undo);
      await shot('outline-panel.png');
      checks.add(
        'actual-desktop-sidebar-or-mobile-bottom-panel-collapses-only-local-outline-without-content-history',
      );
      final ref = DocumentBlockReference(objectId: c.objectId, blockId: h3.id);
      await p.editor.apply(
        p.editor.transaction
          ..insertNode([0], paragraphNode(text: 'Bob 前缀'), deepCopy: false)
          ..insertText(p.resolveBlock(ref)!, 0, '远端 '),
      );
      await p.flush();
      await until(
        () => c.outline.entries.any((e) => e.text == '远端 协作章节😀'),
        'live peer rename',
      );
      expect(c.resolveBlock(ref)!.path.first, 35);
      checks.add(
        'real-two-user-original-websocket-prefix-and-title-rename-preserve-stable-block-id',
      );
      await tap(find.byKey(ValueKey('smart-document.outline.entry.${h3.id}')));
      final coord = mobile
          ? null
          : t
                .widget<DocumentOutlineView>(find.byType(DocumentOutlineView))
                .coordinator;
      await until(() {
        final box = c.resolveBlock(ref)?.key.currentContext?.findRenderObject();
        if (box is! RenderBox || !box.hasSize) return false;
        final y = box.localToGlobal(Offset.zero).dy;
        return y > 0 &&
            y < t.view.physicalSize.height / t.view.devicePixelRatio - 80;
      }, 'virtualized target visible');
      expect(c.editor.selection, isNull);
      if (mobile) {
        expect(
          find.byKey(const ValueKey('smart-document.mobile.panel.outline')),
          findsNothing,
        );
        expect(c.editor.editable, isFalse);
      } else {
        expect(coord!.activeId, h3.id);
      }
      checks.add(
        'actual-outline-click-scrolls-original-virtual-list-with-header-offset-and-no-edit-selection',
      );
      await shot('outline-navigation.png');
      await openOutline();
      await p.editor.apply(
        p.editor.transaction..deleteNode(p.resolveBlock(ref)!),
      );
      await p.flush();
      await until(
        () =>
            !c.outline.entries.any((e) => e.reference == ref) &&
            find
                .byKey(ValueKey('smart-document.outline.entry.${h3.id}'))
                .evaluate()
                .isEmpty,
        'remote deletion reflected in actual UI',
      );
      expect(
        find.byKey(ValueKey('smart-document.outline.entry.${h3.id}')),
        findsNothing,
      );
      final staleCoordinator = t
          .widget<DocumentOutlineView>(find.byType(DocumentOutlineView))
          .coordinator;
      expect(await staleCoordinator.navigate(ref), isFalse);
      expect(
        await staleCoordinator.navigate(
          DocumentBlockReference(objectId: 'foreign', blockId: h1.id),
        ),
        isFalse,
      );
      checks.add('deleted-and-foreign-targets-do-not-navigate-stale-path');
      await p.history();
      await until(
        () => c.outline.entries.any((e) => e.reference == ref),
        'peer origin undo',
      );
      checks.add(
        'peer-origin-undo-restores-outline-with-identity-and-remote-title',
      );
      // A range spanning a prior GC fragment and a restored heading used to
      // disappear from serialized deletion effects in original Yrs 0.23.5.
      await p.synchronize();
      await p.editor.apply(
        p.editor.transaction..deleteNode(p.resolveBlock(ref)!),
      );
      await p.flush();
      await p.synchronize();
      await until(
        () => !c.outline.entries.any((e) => e.reference == ref),
        'restored heading deletion',
      );
      final fresh = await SmartDocumentController.open(
        core: NativeDocumentCore(),
        store: _Memory(),
        objectId: c.objectId,
        editable: false,
        syncInterval: null,
        provider: AppFlowyCollaborationProvider(
          origin: Uri.parse(StageOneWorkbench.origin),
          workspaceId: StageOneWorkbench.workspace,
          deviceId: 'outline-gc-readback-${StageOneWorkbench.run}',
          accessToken: () async => StageOneWorkbench.bobToken,
        ),
      );
      expect(fresh.outline.entries.any((e) => e.reference == ref), isFalse);
      await fresh.close();
      await p.history();
      await until(
        () => c.outline.entries.any((e) => e.reference == ref),
        'second author undo',
      );
      checks.add(
        'gc-prefix-restored-heading-delete-persists-through-original-cloud-and-fresh-kernel-readback',
      );
      await leader.connection.disconnect();
      await leader.connection.connect();
      await until(() => leader.connection.actorUid != null, 'leader reconnect');
      await p.editor.apply(
        p.editor.transaction..insertText(p.resolveBlock(ref)!, 0, '重连 '),
      );
      await p.flush();
      await until(
        () => c.outline.entries.any((e) => e.text == '重连 远端 协作章节😀'),
        'post reconnect projection',
      );
      checks.add('authenticated-reconnect-continues-original-title-projection');
      await c.flush();
      await c.synchronize();
      expect(await w.session.prepareToClose(), isTrue);
      expect(t.takeException(), isNull);
      await File('${evidence.path}/outline-e2e.json').writeAsString(
        jsonEncode({
          'status': 'passed',
          'platform': Platform.isIOS ? 'ios' : 'macos',
          'run': StageOneWorkbench.run,
          'objectId': c.objectId,
          'headingId': h3.id,
          'outline': c.snapshot['outline'],
          'checks': checks,
          'fullProductAcceptance': 'not-complete',
        }),
      );
      await rt.close();
      await p.close();
      await t.pumpWidget(const SizedBox());
      await t.pump();
      await w.close();
      debugPrint('SMARTDOC_OUTLINE_EVIDENCE=${evidence.path}');
    },
  );
}
