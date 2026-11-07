import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';
import 'package:muse_smart_document_stage1/main.dart';
import 'package:muse_smart_document_stage1/dataset_main.dart';
import 'package:muse_smart_document_stage1/embedded_main.dart';

class _Memory implements SnapshotStore {
  @override
  Future<Map<String, dynamic>?> read() async => null;
  @override
  Future<void> write(Map<String, dynamic> v) async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('exact numeric drafts use original independent Row and field collaboration', (
    t,
  ) async {
    final fatal = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = fatal);
    final w = await EmbeddedWorkbench.open(realtime: true);
    await t.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('number.capture'),
        child: StageOneApp(workbench: w.document),
      ),
    );
    Future<void> until(bool Function() ready, String why) async {
      for (var i = 0; i < 300; i++) {
        await t.pump(const Duration(milliseconds: 100));
        if (ready()) return;
      }
      fail('Number deadline: $why');
    }

    Future<void> tap(Finder f) async {
      await t.ensureVisible(f);
      await t.pump(const Duration(milliseconds: 150));
      await t.tap(f);
      await t.pump(const Duration(milliseconds: 300));
    }

    await until(() => w.document.controller != null, 'public document');
    final doc = w.document.controller!;
    doc.pauseCollaboration(true);
    final mobile = t.view.physicalSize.width / t.view.devicePixelRatio < 700;
    if (mobile) await tap(find.text('编辑').last);
    await tap(
      find.byKey(
        ValueKey(
          mobile ? 'smart-document.mobile.insert' : 'smart-document.insert',
        ),
      ),
    );
    await tap(find.text('数据库').last);
    await tap(find.byKey(const ValueKey('embed.pick-dataset')));
    await until(
      () => w.dataset.controller != null,
      'public independent dataset',
    );
    final c = w.dataset.controller!,
        rt = w.dataset.plugin.realtimeFor(w.dataset.session.record.identity)!;
    await until(() => rt.connected, 'original WS2');
    final checks = <String>[];
    await tap(find.byKey(const ValueKey('dataset.add-field')));
    await tap(find.text('数字').last);
    await t.enterText(find.byKey(const ValueKey('dataset.field-name')), '金额');
    await tap(find.byKey(const ValueKey('dataset.field-apply')));
    await until(
      () => c.views.single.columns.any((f) => f.semanticType == 'number'),
      'original field1',
    );
    final fieldId = c.views.single.columns.last.id;
    await c.configureNumberField(c.views.single.columns.last, 1);
    await tap(find.byKey(const ValueKey('dataset.add-row')));
    await until(() => c.views.single.rows.length == 1, 'original row4');
    final rowId = c.views.single.rows.single.id;
    String? value() => c.views.single.rows.single.cells[fieldId]!.numberInput;
    Future<void> open() =>
        tap(find.byKey(ValueKey('dataset.cell.$rowId.$fieldId')));
    final input = find.byKey(const ValueKey('dataset.cell-input')),
        apply = find.byKey(const ValueKey('dataset.cell-apply'));
    final evidence = Directory('${w.document.directory.path}/evidence');
    await evidence.create(recursive: true);
    Future<void> shot(String name) async {
      await t.pump(const Duration(milliseconds: 200));
      final boundary = t.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('number.capture')),
      );
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '${evidence.path}/$name',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    }

    checks.add('actual-public-sdk-embedded-number-field1-and-independent-row4');
    await open();
    await t.enterText(input, '9007199254740993.123456789');
    await tap(apply);
    await until(() => value() == '9007199254740993.123456789', 'exact decimal');
    final parentBefore = jsonEncode(doc.snapshot['data']);
    expect(c.views.single.rows.single.cells[fieldId]!.value, isNot(value()));
    await open();
    expect(t.widget<TextField>(input).controller!.text, value());
    final before = jsonEncode(c.bundle),
        epoch = c.localMutationEpoch,
        undo = c.canUndo;
    await shot('number-exact-draft.png');
    await tap(apply);
    expect(jsonEncode(c.bundle), before);
    expect(c.localMutationEpoch, epoch);
    expect(c.canUndo, undo);
    checks.add(
      'currency-display-rounding-never-enters-exact-draft-and-unchanged-apply-has-no-content-history',
    );
    await open();
    await t.enterText(input, '123abc');
    await tap(apply);
    expect(find.text('请输入有效数字，支持小数和科学计数法'), findsOneWidget);
    expect(t.widget<TextField>(input).controller!.text, '123abc');
    expect(value(), '9007199254740993.123456789');
    await shot('number-invalid.png');
    checks.add('invalid-numeric-input-keeps-draft-and-original-precise-value');
    await t.enterText(input, '-1.25e-2');
    await tap(apply);
    if (find
        .byKey(const ValueKey('dataset.cell-dialog'))
        .evaluate()
        .isNotEmpty) {
      debugPrint(
        'NUMBER_DRAFT_DIAGNOSTIC=${jsonEncode({'input': t.widget<TextField>(input).controller!.text, 'error': t.widget<TextField>(input).decoration?.errorText, 'value': value(), 'canWrite': c.canWrite, 'saveFailed': c.persistenceFailure != null, 'sync': c.syncState.name})}',
      );
    }
    await until(() => value() == '-0.0125', 'scientific exact normalization');
    await c.synchronize();
    final bob = await DatasetController.open(
      core: NativeDatasetCore(),
      store: _Memory(),
      objectId: c.objectId,
      providerFactory: DatasetWorkbench.providerFor('bob'),
      syncInterval: null,
    );
    final wire = await loadRealtimeWireCore();
    final peer = DatasetRealtimeSession(
      controller: bob,
      presenceCore: wire,
      connection: AppFlowyRealtimeConnection(
        origin: Uri.parse(DatasetWorkbench.origin),
        workspaceId: DatasetWorkbench.workspace,
        deviceId: 'number-bob-${DatasetWorkbench.run}',
        clientId: DateTime.now().microsecondsSinceEpoch.toString(),
        accessToken: () async => DatasetWorkbench.bobToken,
        codec: AppFlowyRealtimeCodec(wire),
      ),
    );
    await peer.start();
    await until(() => rt.collaborators.isNotEmpty, 'authenticated peer');
    expect(bob.views.single.rows.single.cells[fieldId]!.numberInput, '-0.0125');
    checks.add(
      'original-two-user-root-row-sync-preserves-scientific-exact-decimal',
    );
    await open();
    await t.enterText(input, '777.123456789');
    await bob.setCell(
      bob.views.single.rows.single,
      bob.views.single.columns.last,
      '42.125',
      expectedHash: bob.views.single.rows.single.cells[fieldId]!.hash,
    );
    await until(() => value() == '42.125', 'peer numeric value');
    await tap(apply);
    expect(find.text('内容已被修改，请取消后重新编辑'), findsOneWidget);
    expect(t.widget<TextField>(input).controller!.text, '777.123456789');
    expect(value(), '42.125');
    await shot('number-cell-conflict.png');
    await tap(find.text('取消').last);
    checks.add(
      'original-peer-cell-update-rejects-stale-numeric-draft-without-overwriting-peer',
    );
    await open();
    await t.enterText(input, '888.125');
    await bob.configureNumberField(bob.views.single.columns.last, 4);
    await until(
      () =>
          c.views.single.columns.last.fieldHash ==
          bob.views.single.columns.last.fieldHash,
      'peer number format',
    );
    await tap(apply);
    expect(find.text('字段设置已被修改，请取消后重新编辑'), findsOneWidget);
    expect(t.widget<TextField>(input).controller!.text, '888.125');
    expect(value(), '42.125');
    await shot('number-field-conflict.png');
    await tap(find.text('取消').last);
    checks.add(
      'independent-root-number-format-update-rejects-stale-field-draft-with-value-retained',
    );
    await open();
    await t.enterText(input, '0');
    await tap(apply);
    await until(() => value() == '0', 'zero');
    await open();
    await t.enterText(input, '');
    await tap(apply);
    await until(() => value() == '', 'clear distinct from zero');
    await tap(find.byKey(const ValueKey('dataset.undo')));
    await until(() => value() == '0', 'undo clear');
    await tap(find.byKey(const ValueKey('dataset.undo')));
    await until(() => value() == '42.125', 'undo own zero retains peer');
    await until(
      () =>
          bob.views.single.rows.single.cells[fieldId]!.numberInput == '42.125',
      'peer sees author undo',
    );
    checks.add(
      'actual-dataset-toolbar-undo-keeps-zero-empty-distinct-and-restores-peer-exact-value',
    );
    expect(jsonEncode(doc.snapshot['data']), parentBefore);
    doc.pauseCollaboration(false);
    await doc.flush();
    await doc.synchronize();
    await c.flush();
    await c.synchronize();
    expect(await w.document.session.prepareToClose(), isTrue);
    expect(await w.dataset.session.prepareToClose(), isTrue);
    checks.add(
      'parent-document-contains-only-resource-reference-and-independent-original-checkpoints-save',
    );
    await shot('number-editor.png');
    expect(t.takeException(), isNull);
    await File('${evidence.path}/number-e2e.json').writeAsString(
      jsonEncode({
        'status': 'passed',
        'platform': Platform.isIOS ? 'ios' : 'macos',
        'run': StageOneWorkbench.run,
        'objectId': doc.objectId,
        'datasetObjectId': c.objectId,
        'rowId': rowId,
        'fieldId': fieldId,
        'target': w.target.toJson(),
        'input': value(),
        'views': c.snapshot['views'],
        'checks': checks,
        'fullProductAcceptance': 'not-complete',
      }),
    );
    await peer.close();
    await bob.close();
    await t.pumpWidget(const SizedBox());
    await t.pump();
    await w.close();
    debugPrint('SMARTDOC_NUMBER_EVIDENCE=${evidence.path}');
  });
}
