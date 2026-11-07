import 'dart:convert';
import 'dart:io';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';
import 'package:uuid/uuid.dart';

class Memory implements DocumentStore {
  Map<String, dynamic>? value;
  @override
  Future<Map<String, dynamic>?> read() async => value;
  @override
  Future<void> write(Map<String, dynamic> v) async {
    value = Map.of(v);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'real document adapter: peer update, stable remote selection, own undo and leave',
    () async {
      final f =
          jsonDecode(await File('../.build/e2e-fixture.json').readAsString())
              as Map;
      final origin = Uri.parse(f['origin'] as String),
          workspace = f['workspaceId'] as String;
      final core = NativeDocumentCore(), wire = NativeRealtimeWireCore();
      final id = const Uuid().v4();
      CollaborationProvider provider(String user) =>
          AppFlowyCollaborationProvider(
            origin: origin,
            workspaceId: workspace,
            deviceId: 'adapter-$user',
            accessToken: () async => f['users'][user]['accessToken'] as String,
          );
      final a = await SmartDocumentController.open(
        core: core,
        store: Memory(),
        objectId: id,
        provider: provider('alice'),
        createRemote: true,
        syncInterval: null,
      );
      await a.editor.apply(
        a.editor.transaction..insertText(a.blocks.first, 0, '共享正文😀'),
      );
      await a.synchronize();
      final b = await SmartDocumentController.open(
        core: core,
        store: Memory(),
        objectId: id,
        provider: provider('bob'),
        syncInterval: null,
      );
      DocumentRealtimeSession session(SmartDocumentController c, String user) =>
          DocumentRealtimeSession(
            controller: c,
            presenceCore: wire,
            connection: AppFlowyRealtimeConnection(
              origin: origin,
              workspaceId: workspace,
              deviceId: 'adapter-$user-${const Uuid().v4()}',
              clientId: BigInt.parse(
                const Uuid().v4().replaceAll('-', '').substring(0, 13),
                radix: 16,
              ).toString(),
              accessToken: () async =>
                  f['users'][user]['accessToken'] as String,
              codec: AppFlowyRealtimeCodec(wire),
            ),
          );
      final ra = session(a, 'alice'), rb = session(b, 'bob');
      Future<void> until(bool Function() ready, String reason) async {
        for (var i = 0; i < 120; i++) {
          if (ready()) return;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        fail(
          '$reason: ${ra.failureCode}, ${rb.failureCode}, ${a.syncState}, ${b.syncState}',
        );
      }

      final checks = <String>[];
      try {
        await ra.start();
        await rb.start();
        a.editor.selection = Selection.collapsed(
          Position(path: [0], offset: 2),
        );
        b.editor.selection = Selection.collapsed(
          Position(path: [0], offset: 0),
        );
        await until(
          () => rb.collaborators.length == 1 && ra.collaborators.length == 1,
          'Both peers appear',
        );
        expect(rb.collaborators.single.uid, matches(RegExp(r'^\d+$')));
        expect(rb.collaborators.single.name, '协作者');
        checks.add('authenticated-peer-presence-no-client-profile-trust');
        await until(
          () => b.editor.remoteSelections.value.any(
            (r) => r.selection.start.offset == 2,
          ),
          'Remote caret at original UTF16 index',
        );
        checks.add(
          'original-editor-remote-selection-from-yrs-relative-anchors',
        );
        await b.editor.apply(
          b.editor.transaction..insertText(b.blocks.first, 0, '前缀'),
        );
        await until(
          () => a.blocks.first.delta!.toPlainText() == '前缀共享正文😀',
          'WS peer content',
        );
        await until(
          () =>
              b.editor.remoteSelections.value.single.selection.start.offset ==
              4,
          'Relative anchor follows concurrent prefix',
        );
        checks.add('peer-update-and-relative-caret-after-concurrent-prefix');
        await b.history();
        await until(
          () => a.blocks.first.delta!.toPlainText() == '共享正文😀',
          'Undo keeps peer content',
        );
        checks.add('local-origin-undo-preserves-peer-text');
        a.acceptRealtimeAccess(
          canRead: true,
          canWrite: false,
          reason: 'denied',
        );
        await b.editor.apply(
          b.editor.transaction..insertText(b.blocks.first, 0, '只读接收'),
        );
        await until(
          () => a.blocks.first.delta!.toPlainText().startsWith('只读接收'),
          'Viewer receives remote projection',
        );
        expect(a.canWrite, isFalse);
        expect(a.editor.editable, isFalse);
        checks.add('read-only-receives-without-enabling-local-editing');
        await rb.close();
        await until(
          () =>
              ra.collaborators.isEmpty &&
              a.editor.remoteSelections.value.isEmpty,
          'Leave removes presence and cursor',
        );
        checks.add('null-awareness-removes-session-and-cursor');
        await File(
          '../.build/realtime-document-adapter-result.json',
        ).writeAsString(
          jsonEncode({
            'status': 'passed',
            'objectId': id,
            'checks': checks,
            'fullProductAcceptance': 'not-complete',
          }),
        );
      } finally {
        await rb.close();
        await ra.close();
        await b.close();
        await a.close();
      }
    },
  );
}
