import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openmuse_smart_document/openmuse_smart_document.dart';
import 'package:uuid/uuid.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'actual Guest reader, upgrade, cached-writer downgrade and revoke on original WS2',
    () async {
      final f =
          jsonDecode(await File('../.build/e2e-fixture.json').readAsString())
              as Map;
      final origin = Uri.parse(f['origin'] as String),
          users = f['users'] as Map;
      Future<dynamic> request(
        String method,
        String path, [
        Object? body,
      ]) async {
        final req = http.Request(method, origin.resolve(path))
          ..headers.addAll({
            'Authorization': 'Bearer ${users['alice']['accessToken']}',
            'Content-Type': 'application/json',
          })
          ..followRedirects = false;
        if (body != null) req.body = jsonEncode(body);
        final response = await http.Response.fromStream(await req.send());
        final value = jsonDecode(response.body) as Map;
        if (response.statusCode != 200 || value['code'] != 0)
          fail(
            'Local Cloud API failed: ${response.statusCode}/${value['code']}',
          );
        return value['data'];
      }

      final created = await request('POST', '/api/workspace', {
        'workspace_name': 'smartdoc-guest-qualification-${const Uuid().v4()}',
      });
      final workspace = created['workspace_id'] as String,
          id = const Uuid().v4();
      Future<void> share(int access) async {
        await request('PUT', '/api/sharing/workspace/$workspace/view', {
          'view_id': id,
          'emails': [users['bob']['email']],
          'access_level': access,
          'auto_confirm': true,
        });
      }

      AppFlowyCollaborationProvider provider(String user) =>
          AppFlowyCollaborationProvider(
            origin: origin,
            workspaceId: workspace,
            deviceId: 'guest-qualified-$user',
            accessToken: () async => users[user]['accessToken'] as String,
          );
      final core = NativeDocumentCore(), wire = NativeRealtimeWireCore();
      final a = await SmartDocumentController.open(
        core: core,
        store: _Memory(),
        objectId: id,
        provider: provider('alice'),
        createRemote: true,
        syncInterval: null,
      );
      await a.insertParagraph('受保护的共享内容😀');
      await a.synchronize();
      await share(10);
      final b = await SmartDocumentController.open(
        core: core,
        store: _Memory(),
        objectId: id,
        provider: provider('bob'),
        syncInterval: null,
      );
      final sessions = <DocumentRealtimeSession>[];
      DocumentRealtimeSession realtime(SmartDocumentController c, String user) {
        final r = DocumentRealtimeSession(
          controller: c,
          presenceCore: wire,
          connection: AppFlowyRealtimeConnection(
            origin: origin,
            workspaceId: workspace,
            deviceId: 'guest-$user-${const Uuid().v4()}',
            clientId: BigInt.parse(
              const Uuid().v4().replaceAll('-', '').substring(0, 13),
              radix: 16,
            ).toString(),
            accessToken: () async => users[user]['accessToken'] as String,
            codec: AppFlowyRealtimeCodec(wire),
          ),
        );
        sessions.add(r);
        return r;
      }

      final ra = realtime(a, 'alice'), rb = realtime(b, 'bob');
      final packets = <RealtimePacket>[];
      final subscription = rb.connection.packets.listen(
        packets.add,
        onError: (Object _) {},
      );
      Future<void> until(bool Function() ready, String reason) async {
        for (var i = 0; i < 150; i++) {
          if (ready()) return;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        fail(
          '$reason: ${a.syncState}/${b.syncState}/${ra.failureCode}/${rb.failureCode}',
        );
      }

      void manifest() => rb.connection.send(
        RealtimeManifest(
          objectId: id,
          collabType: 0,
          stateVector: base64Decode(b.snapshot['stateVector'] as String),
        ),
      );
      String text(SmartDocumentController c) =>
          c.blocks.map((n) => n.delta?.toPlainText() ?? '').join('|');
      Future<void> rejectedWireWrite(String marker) async {
        final rogue = core.call({
          'action': 'open',
          'objectId': id,
          'docState': b.snapshot['docState'],
        });
        try {
          final edited = core.call({
            'action': 'operations',
            'handle': rogue['handle'],
            'operations': [
              {
                'op': 'update_text',
                'path': [0],
                'delta': [
                  {'insert': marker},
                ],
              },
            ],
          });
          packets.clear();
          rb.connection.send(
            RealtimeUpdate(
              objectId: id,
              collabType: 0,
              update: base64Decode(edited['docState'] as String),
            ),
          );
          await until(
            () => packets.any((p) => p is RealtimeAccess && !p.canWrite),
            'write denied on original wire',
          );
          final reader = provider('alice');
          try {
            final remote = await reader.readState(id);
            final inspect = core.call({
              'action': 'open',
              'objectId': id,
              'docState': base64Encode(remote!),
            });
            try {
              expect(jsonEncode(inspect['data']), isNot(contains(marker)));
            } finally {
              core.call({'action': 'close', 'handle': inspect['handle']});
            }
          } finally {
            reader.close();
          }
        } finally {
          core.call({'action': 'close', 'handle': rogue['handle']});
        }
      }

      final checks = <String>[];
      try {
        await ra.start();
        await rb.start();
        await until(
          () =>
              packets.any(
                (p) => p is RealtimeAccess && p.canRead && !p.canWrite,
              ) &&
              b.canRead &&
              !b.canWrite,
          'Guest reader capabilities',
        );
        checks.add(
          'actual-existing-guest-direct-share-read-only-original-capabilities',
        );
        await a.insertParagraph('只读用户实时接收');
        await until(
          () => text(b).contains('只读用户实时接收'),
          'reader receives original update',
        );
        expect(b.editor.editable, isFalse);
        checks.add('http-write-denial-recovers-as-authenticated-live-viewer');
        await rejectedWireWrite('访客越权写入');
        checks.add('raw-ws-write-denied-and-authoritative-readback-unchanged');
        packets.clear();
        await share(30);
        manifest();
        await until(
          () =>
              packets.any((p) => p is RealtimeAccess && p.canWrite) &&
              b.canWrite,
          'Guest grant upgrade',
        );
        await b.insertParagraph('获授权编辑');
        await until(
          () => text(a).contains('获授权编辑'),
          'granted write reaches owner',
        );
        checks.add('same-connection-guest-read-write-upgrade-and-peer-merge');
        await share(10);
        await rejectedWireWrite('缓存写权限绕过');
        await until(() => !b.canWrite, 'cached writer downgrade');
        checks.add(
          'downgrade-rechecks-authority-without-trusting-cached-writer',
        );
        await request(
          'POST',
          '/api/sharing/workspace/$workspace/view/$id/revoke-access',
          {
            'emails': [users['bob']['email']],
          },
        );
        manifest();
        await until(
          () => !b.canRead && !b.canWrite,
          'explicit capability refresh after revoke',
        );
        checks.add(
          'revocation-manifest-removes-live-read-and-write-capability',
        );
        packets.clear();
        await a.insertParagraph('撤权后私有内容');
        await a.synchronize();
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(packets.whereType<RealtimeUpdate>(), isEmpty);
        expect(text(b), isNot(contains('撤权后私有内容')));
        checks.add('revoked-recipient-does-not-receive-new-content-broadcast');
        final revoked = provider('bob');
        try {
          await expectLater(
            revoked.readState(id),
            throwsA(
              isA<SmartDocumentFailure>().having(
                (e) => e.code,
                'code',
                'FORBIDDEN',
              ),
            ),
          );
        } finally {
          revoked.close();
        }
        checks.add('revoked-http-read-also-denied');
        await File('../.build/realtime-permissions-result.json').writeAsString(
          jsonEncode({
            'status': 'passed',
            'workspaceId': workspace,
            'objectId': id,
            'checks': checks,
            'limits': [
              'Capability refresh is explicit/periodic; distributed immediate permission notifications remain unqualified',
            ],
            'fullProductAcceptance': 'not-complete',
          }),
        );
      } finally {
        await subscription.cancel();
        for (final s in sessions.reversed) {
          await s.close();
        }
        await b.close();
        await a.close();
      }
    },
  );
}
