import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'actual deleted document stays read only and cannot sync or recreate from its cached resource',
    () async {
      final fixture =
          jsonDecode(await File('../.build/e2e-fixture.json').readAsString())
              as Map;
      final origin = Uri.parse(fixture['origin'] as String),
          workspace = fixture['workspaceId'] as String;
      final token = fixture['users']['alice']['accessToken'] as String;
      AppFlowyCollaborationProvider provider() => AppFlowyCollaborationProvider(
        origin: origin,
        workspaceId: workspace,
        deviceId: 'document-lifecycle',
        accessToken: () async => token,
      );
      final dir = await Directory.systemTemp.createTemp(
        'document-cloud-delete-',
      );
      final store = FileDocumentStore(File('${dir.path}/cache.json'));
      final id = const Uuid().v4(), core = NativeDocumentCore();
      var c = await SmartDocumentController.open(
        core: core,
        store: store,
        objectId: id,
        provider: provider(),
        createRemote: true,
        syncInterval: null,
      );
      await c.editor.apply(
        c.editor.transaction..insertText(c.blocks.first, 0, '保留的本机文档😀'),
      );
      await c.flush();
      await c.synchronize();
      expect(c.syncState, DocumentSyncState.accepted);
      final wire = core.call({'action': 'syncRequest', 'handle': c.handle});
      final response = await http.delete(
        origin.resolve('/api/workspace/$workspace/collab/$id'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'workspace_id': workspace, 'object_id': id}),
      );
      expect(response.statusCode, 200);
      expect((jsonDecode(response.body) as Map)['code'], 0);
      final direct = provider();
      await expectLater(
        direct.exchange(id, base64Decode(wire['body'] as String)),
        throwsA(
          isA<SmartDocumentFailure>().having(
            (e) => e.code,
            'code',
            'OBJECT_DELETED',
          ),
        ),
      );
      direct.close();
      await c.synchronize();
      expect(c.syncState, DocumentSyncState.removed);
      expect(c.canWrite, isFalse);
      c.pauseCollaboration(true);
      c.pauseCollaboration(false);
      expect(c.canWrite, isFalse);
      expect(c.editor.editable, isFalse);
      expect(c.blocks.first.delta!.toPlainText(), '保留的本机文档😀');
      await c.close();
      c = await SmartDocumentController.open(
        core: core,
        store: store,
        objectId: id,
        provider: provider(),
        createRemote: true,
        syncInterval: null,
      );
      expect(c.syncState, DocumentSyncState.removed);
      expect(c.canWrite, isFalse);
      expect(c.blocks.first.delta!.toPlainText(), '保留的本机文档😀');
      await c.close();
      await File('../.build/document-cloud-deletion-result.json').writeAsString(
        jsonEncode({
          'status': 'passed-document-deletion-slice',
          'objectId': id,
          'checks': [
            'original-cloud-soft-deletion',
            'raw-full-sync-rejects-registered-tombstone',
            'local-document-state-readonly-and-visible',
            'pause-resume-does-not-clear-terminal-denial',
            'cached-resource-reopen-does-not-recreate',
          ],
        }),
      );
      await dir.delete(recursive: true);
    },
  );
}
