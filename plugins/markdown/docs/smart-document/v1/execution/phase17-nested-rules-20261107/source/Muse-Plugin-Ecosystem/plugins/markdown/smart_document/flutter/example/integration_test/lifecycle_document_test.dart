import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';
import 'package:muse_smart_document_stage1/main.dart';
import 'package:muse_smart_document_stage1/embedded_main.dart';

/// Buffers one actual response from the original Cloud. Request execution,
/// authorization, full-sync codecs and object state are never replaced.
class _ResponseGate extends http.BaseClient {
  final http.Client inner = http.Client();
  String? method, object;
  Completer<void> entered = Completer<void>(), release = Completer<void>();
  bool held = false, closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest r) async {
    if (method == r.method &&
        object != null &&
        r.url.path.contains('/$object') &&
        !held) {
      held = true;
      final actual = await http.Response.fromStream(await inner.send(r));
      if (actual.statusCode != 200) {
        throw StateError(
          'expected original Cloud acceptance, got ${actual.statusCode}',
        );
      }
      entered.complete();
      await release.future;
      return http.StreamedResponse(
        Stream.value(actual.bodyBytes),
        actual.statusCode,
        headers: actual.headers,
        request: r,
      );
    }
    return inner.send(r);
  }

  @override
  void close() {
    closed = true;
    inner.close();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'actual Cloud late root/row responses cannot retain a removed resource owner or mutate closed sessions',
    (t) async {
      final old = WidgetController.hitTestWarningShouldBeFatal;
      WidgetController.hitTestWarningShouldBeFatal = true;
      addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = old);
      final children = <int, List<_ResponseGate>>{1: [], 4: []},
          rootClient = _ResponseGate();
      final w = await EmbeddedWorkbench.open(
        realtime: true,
        documentRealtime: true,
        transportClientFactory: (type) {
          final client = _ResponseGate();
          children[type]!.add(client);
          return client;
        },
        documentTransportClientFactory: () => rootClient,
      );
      await t.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('lifecycle.capture'),
          child: StageOneApp(workbench: w.document),
        ),
      );
      Future<void> until(
        bool Function() ready,
        String why, {
        int ticks = 250,
      }) async {
        for (var i = 0; i < ticks; i++) {
          await t.pump(const Duration(milliseconds: 100));
          if (ready()) return;
        }
        fail('Lifecycle UI deadline: $why');
      }

      Future<void> tap(Finder f) async {
        await t.ensureVisible(f);
        await t.pump(const Duration(milliseconds: 200));
        await t.tap(f);
        await t.pump(const Duration(milliseconds: 300));
      }

      await until(() => w.document.controller != null, 'public document');
      final doc = w.document.controller!;
      final mobile = t.view.physicalSize.width / t.view.devicePixelRatio < 700;
      if (mobile) await tap(find.text('编辑').last);
      await doc.editor.apply(
        doc.editor.transaction
          ..insertText(doc.blocks.first, 0, '项目计划｜会话关闭与重新打开'),
      );
      await tap(
        find.byKey(
          ValueKey(
            mobile ? 'smart-document.mobile.insert' : 'smart-document.insert',
          ),
        ),
      );
      await tap(find.text('数据库').last);
      await tap(find.byKey(const ValueKey('embed.pick-dataset')));
      await until(() => w.dataset.controller != null, 'public child');
      final c = w.dataset.controller!;
      final rootRealtime = w.document.plugin.realtimeFor(
        w.document.session.record.identity,
      )!;
      await until(
        () =>
            rootRealtime.connected &&
            w.dataset.plugin
                .realtimeFor(w.dataset.session.record.identity)!
                .connected,
        'two independently bound WS2 sessions',
      );
      final checks = <String>[
        'actual-public-document-and-independent-embedded-dataset-with-original-Cloud-WS2',
      ];
      await tap(find.byKey(const ValueKey('dataset.add-row')));
      await until(() => c.views.single.rows.length == 1, 'actual add row');
      final rowId = c.views.single.rows.single.id;
      Future<void> text(String value) async {
        await tap(find.byKey(ValueKey('dataset.cell.$rowId.title')));
        await t.enterText(
          find.byKey(const ValueKey('dataset.cell-input')),
          value,
        );
        await tap(find.byKey(const ValueKey('dataset.cell-apply')));
      }

      await text('等待回包时移除引用');
      await c.synchronize();
      await doc.synchronize();
      await t.pump(const Duration(milliseconds: 600));
      final rowClient = children[4]!.last;
      rowClient.method = 'GET';
      rowClient.object = rowId;
      final pendingRow = c.synchronize();
      await until(
        () => rowClient.entered.isCompleted,
        'buffered actual row4 HTTP response',
      );
      expect(rowClient.release.isCompleted, false);
      final reference = doc.blocks.singleWhere((b) => b.type == 'grid');
      await tap(
        find.byKey(ValueKey('smart-document.embed-menu.${reference.id}')),
      );
      await tap(find.text('移除引用').last);
      await until(
        () => w.dataset.controller == null,
        'release old owner without awaiting network',
        ticks: 50,
      );
      expect(rowClient.closed, true);
      expect(rowClient.release.isCompleted, false);
      final closedRowState = jsonEncode(c.snapshot),
          closedRowStore = jsonEncode(await c.store.read());
      checks.add(
        'actual-remove-reference-releases-public-child-session-before-held-row-response',
      );
      await tap(
        find.byKey(
          ValueKey(
            mobile ? 'smart-document.mobile.undo' : 'smart-document.undo',
          ),
        ),
      );
      await until(
        () => w.dataset.controller != null,
        'undo locator and open a fresh owned session',
      );
      final restored = w.dataset.controller!;
      expect(identical(c, restored), false);
      expect(restored.objectId, c.objectId);
      expect(
        restored.views.single.rows.single.cells['title']!.value,
        '等待回包时移除引用',
      );
      rowClient.release.complete();
      await pendingRow;
      expect(jsonEncode(c.snapshot), closedRowState);
      expect(jsonEncode(await c.store.read()), closedRowStore);
      expect(restored.canWrite, true);
      checks.add(
        'document-undo-reopens-one-fresh-child-owner-and-late-old-response-cannot-overwrite-it',
      );
      await text('恢复后的编辑');
      await restored.synchronize();
      await doc.synchronize();
      expect(await w.dataset.session.prepareToClose(), true);
      expect(await w.document.session.prepareToClose(), true);
      checks.add(
        'restored-same-row-remains-editable-and-two-resource-checkpoints-commit',
      );
      final evidence = Directory('${w.document.directory.path}/evidence');
      await evidence.create(recursive: true);
      final render = t.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('lifecycle.capture')),
      );
      final image = await render.toImage(pixelRatio: 1);
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await File(
        '${evidence.path}/lifecycle-editor.png',
      ).writeAsBytes(png.buffer.asUint8List());
      image.dispose();
      final views = restored.snapshot['views'];
      // Trigger original server manifest/HTTP repair, then hold its already
      // authorized success. Socket teardown must not wait for that repair queue.
      await t.pump(const Duration(milliseconds: 600));
      rootClient.method = 'POST';
      rootClient.object = doc.objectId;
      rootRealtime.connection.send(
        RealtimeManifest(
          objectId: doc.objectId,
          collabType: 0,
          stateVector: base64Decode(doc.snapshot['stateVector'] as String),
        ),
      );
      await until(
        () => rootClient.entered.isCompleted,
        'buffered actual document0 full-sync response',
      );
      final pendingRoot = doc.synchronize();
      await t.pumpWidget(const SizedBox());
      await t.pump();
      var closed = false;
      final closing = w.close().then((_) => closed = true);
      await until(
        () => closed,
        'close public Host sessions before held root response',
        ticks: 50,
      );
      expect(rootClient.closed, true);
      expect(rootClient.release.isCompleted, false);
      final closedDocState = jsonEncode(doc.snapshot),
          closedDocStore = jsonEncode(await doc.store.read());
      checks.add(
        'socket-manifest-repair-does-not-retain-closed-public-resource-owner',
      );
      rootClient.release.complete();
      await pendingRoot;
      await closing;
      expect(jsonEncode(doc.snapshot), closedDocState);
      expect(jsonEncode(await doc.store.read()), closedDocStore);
      expect(t.takeException(), isNull);
      checks.add(
        'actual-late-root-HTTP-success-cannot-mutate-closed-state-or-durable-local-checkpoint',
      );
      await File('${evidence.path}/lifecycle-e2e.json').writeAsString(
        jsonEncode({
          'status': 'passed',
          'platform': Platform.isIOS ? 'ios' : 'macos',
          'run': StageOneWorkbench.run,
          'objectId': doc.objectId,
          'datasetObjectId': restored.objectId,
          'rowId': rowId,
          'target': w.target.toJson(),
          'views': views,
          'checks': checks,
          'fullProductAcceptance': 'not-complete',
        }),
      );
      debugPrint('SMARTDOC_LIFECYCLE_EVIDENCE=${evidence.path}');
    },
  );
}
