import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openmuse_dataset/openmuse_dataset.dart';
import 'package:uuid/uuid.dart';
import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'actual Guest root1 and row4 grants, raw writes, downgrade, independent row revoke and root deletion',
    () async {
      final f =
          jsonDecode(await File('../../.build/e2e-fixture.json').readAsString())
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
            'Local Guest Dataset API failed: ${response.statusCode}/${value['code']}',
          );
        return value['data'];
      }

      final created = await request('POST', '/api/workspace', {
        'workspace_name': 'dataset-guest-qualification-${const Uuid().v4()}',
      });
      final workspace = created['workspace_id'] as String,
          id = const Uuid().v4();
      Future<void> share(String object, int level) async {
        await request('PUT', '/api/sharing/workspace/$workspace/view', {
          'view_id': object,
          'emails': [users['bob']['email']],
          'access_level': level,
          'auto_confirm': true,
        });
      }

      DatasetProviderFactory provider(String user) =>
          (type) => AppFlowyObjectTransport(
            origin: origin,
            workspaceId: workspace,
            deviceId: 'dataset-guest-$user-$type',
            accessToken: () async => users[user]['accessToken'] as String,
            binding: datasetBinding(type),
            collabType: type,
          );
      final core = NativeDatasetCore(), wire = await loadRealtimeWireCore();
      final a = await DatasetController.open(
        core: core,
        store: MemoryStore(),
        objectId: id,
        providerFactory: provider('alice'),
        createRemote: true,
        syncInterval: null,
      );
      final rowId = await a.addRow(cells: {'title': '独立授权数据库行'});
      await a.synchronize();
      await share(id, 10);
      await share(rowId, 10);
      final b = await DatasetController.open(
        core: core,
        store: MemoryStore(),
        objectId: id,
        providerFactory: provider('bob'),
        syncInterval: null,
      );
      final sessions = <DatasetRealtimeSession>[];
      DatasetRealtimeSession session(DatasetController c, String user) {
        final s = DatasetRealtimeSession(
          controller: c,
          presenceCore: wire,
          connection: AppFlowyRealtimeConnection(
            origin: origin,
            workspaceId: workspace,
            deviceId: 'dataset-guest-$user-${const Uuid().v4()}',
            clientId: BigInt.parse(
              const Uuid().v4().replaceAll('-', '').substring(0, 13),
              radix: 16,
            ).toString(),
            accessToken: () async => users[user]['accessToken'] as String,
            codec: AppFlowyRealtimeCodec(wire),
          ),
        );
        sessions.add(s);
        return s;
      }

      final ra = session(a, 'alice'), rb = session(b, 'bob');
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
          'Guest Dataset deadline: $reason / ${a.syncState}/${b.syncState}/${ra.failureCode}/${rb.failureCode}',
        );
      }

      void manifest() {
        for (final object in [id, rowId]) {
          final state = b.realtimeManifestState(object);
          rb.connection.send(
            RealtimeManifest(
              objectId: object,
              collabType: state['collabType'] as int,
              stateVector: base64Decode(state['stateVector'] as String),
            ),
          );
        }
      }

      Future<void> ownerValue(String value) async {
        final row = a.views.single.rows.single,
            field = a.views.single.columns.first;
        await a.setCell(
          row,
          field,
          value,
          expectedHash: row.cells[field.id]!.hash,
        );
      }

      Future<void> rejectRaw(String marker, {bool root = false}) async {
        final rogue = core.call({
          'action': 'open',
          'objectId': id,
          'bundle': b.bundle,
        });
        try {
          if (root) {
            core.call({
              'action': 'command',
              'handle': rogue['handle'],
              'command': {
                'op': 'createField',
                'id': const Uuid().v4(),
                'name': marker,
                'semanticType': 'text',
              },
            });
          } else {
            final row = (rogue['views'] as List).single['rows'][0] as Map;
            core.call({
              'action': 'command',
              'handle': rogue['handle'],
              'command': {
                'op': 'setCell',
                'rowId': rowId,
                'fieldId': 'title',
                'value': marker,
                'expectedHash': row['cells']['title']['hash'],
              },
            });
          }
          final object = root ? id : rowId, type = root ? 1 : 4;
          final state = core.call({
            'action': 'realtimeObject',
            'handle': rogue['handle'],
            'objectId': object,
          });
          packets.clear();
          rb.connection.send(
            RealtimeUpdate(
              objectId: object,
              collabType: type,
              update: base64Decode(state['docState'] as String),
            ),
          );
          await until(
            () => packets.any(
              (p) => p is RealtimeAccess && p.objectId == object && !p.canWrite,
            ),
            'raw typed write denied',
          );
          final inspect = await DatasetController.open(
            core: core,
            store: MemoryStore(),
            objectId: id,
            providerFactory: provider('alice'),
            editable: false,
            syncInterval: null,
          );
          try {
            expect(
              jsonEncode(inspect.snapshot['views']),
              isNot(contains(marker)),
            );
          } finally {
            await inspect.close();
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
              b.canRead &&
              !b.canWrite &&
              packets.whereType<RealtimeAccess>().any(
                (p) => p.collabType == 4 && p.canRead && !p.canWrite,
              ),
          'actual Guest root/row capabilities',
        );
        checks.add(
          'separate-synthetic-workspace-actual-guest-explicit-root1-and-row4-read-grants',
        );
        await ownerValue('访客合法接收行更新');
        await until(
          () => b.views.single.rows.single.cells['title']!.value == '访客合法接收行更新',
          'guest receives row4 realtime',
        );
        checks.add(
          'write-denial-recovers-as-authorized-reader-with-real-row-updates',
        );
        await rejectRaw('不允许的行写入');
        manifest();
        await until(
          () => b.canRead && !b.canWrite,
          'reader restored after denied raw row write',
        );
        await rejectRaw('不允许的根字段写入', root: true);
        manifest();
        await until(
          () => b.canRead && !b.canWrite,
          'reader restored after denied raw root write',
        );
        checks.add(
          'original-raw-ws-root-and-row-writes-both-denied-with-authoritative-readback-unchanged',
        );
        await share(id, 30);
        await share(rowId, 30);
        manifest();
        await until(() => b.canWrite, 'both independent capabilities upgraded');
        var row = b.views.single.rows.single,
            field = b.views.single.columns.first;
        await b.setCell(
          row,
          field,
          '访客获授权编辑',
          expectedHash: row.cells[field.id]!.hash,
        );
        await until(
          () => a.views.single.rows.single.cells['title']!.value == '访客获授权编辑',
          'granted row edit reaches owner',
        );
        checks.add(
          'same-connection-root-row-grant-upgrade-enables-legitimate-guest-edit',
        );
        await share(id, 10);
        await share(rowId, 10);
        await rejectRaw('旧写权限不能绕过');
        manifest();
        await until(() => b.canRead && !b.canWrite, 'writer downgraded');
        checks.add(
          'cached-writer-cannot-bypass-fresh-downgrade-on-original-row-wire',
        );
        await request(
          'POST',
          '/api/sharing/workspace/$workspace/view/$rowId/revoke-access',
          {
            'emails': [users['bob']['email']],
          },
        );
        manifest();
        await until(
          () => !b.canRead && !b.canWrite,
          'row revoke conservatively hides dataset',
        );
        packets.clear();
        await ownerValue('撤权后行私有值');
        await a.synchronize();
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(
          packets.whereType<RealtimeUpdate>().where((p) => p.objectId == rowId),
          isEmpty,
        );
        expect(
          b.views.single.rows.single.cells['title']!.value,
          isNot('撤权后行私有值'),
        );
        final revoked = provider('bob')(4);
        try {
          await expectLater(
            revoked.readState(rowId),
            throwsA(
              isA<AppFlowyTransportFailure>().having(
                (e) => e.code,
                'code',
                'FORBIDDEN',
              ),
            ),
          );
        } finally {
          revoked.close();
        }
        checks.add(
          'independent-row-revocation-blocks-new-broadcast-and-http-read-without-grant-from-root',
        );
      await request('DELETE', '/api/workspace/$workspace/collab/$id', {'workspace_id':workspace,'object_id':id});
        manifest();
        await until(
          () => b.syncState == DatasetSyncState.removed,
          'root deletion capability',
        );
        b.acceptRealtimeAccess(
          id: id,
          collabType: 1,
          canRead: true,
          canWrite: true,
          reason: 'denied',
        );
        expect(b.canRead, isFalse);
        expect(b.canWrite, isFalse);
        expect(b.syncState, DatasetSyncState.removed);
        checks.add(
          'deleted-database-root-is-terminal-and-fresh-looking-grants-cannot-revive-it',
        );
        await File(
          '../../.build/dataset-realtime-permissions-result.json',
        ).writeAsString(
          jsonEncode({
            'status': 'passed',
            'workspaceId': workspace,
            'objectId': id,
            'rowId': rowId,
            'checks': checks,
            'limits': [
              'Direct root/row grants qualified; automatic inheritance/resource registry remains open',
              'Capability refresh explicit/periodic; immediate distributed permission notification remains open',
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
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
