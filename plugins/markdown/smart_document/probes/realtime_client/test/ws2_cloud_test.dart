import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muse_appflowy_realtime/muse_appflowy_realtime.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';
import 'package:uuid/uuid.dart';

class Memory implements DocumentStore {
  Map<String, dynamic>? value;
  @override
  Future<Map<String, dynamic>?> read() async => value;
  @override
  Future<void> write(Map<String, dynamic> v) async {
    value = v;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'original WS2 peer update and actual nonmember read/write boundary',
    () async {
      final f =
          jsonDecode(await File('../../.build/e2e-fixture.json').readAsString())
              as Map;
      final origin = Uri.parse(f['origin'] as String),
          workspace = f['workspaceId'] as String;
      final core = NativeDocumentCore(),
          codec = AppFlowyRealtimeCodec(NativeRealtimeWireCore());
      final id = const Uuid().v4();
      final a = await SmartDocumentController.open(
        core: core,
        store: Memory(),
        objectId: id,
        provider: AppFlowyCollaborationProvider(
          origin: origin,
          workspaceId: workspace,
          deviceId: 'ws2-source',
          accessToken: () async => f['users']['alice']['accessToken'] as String,
        ),
        createRemote: true,
        syncInterval: null,
      );
      final peer = core.call({
        'action': 'open',
        'objectId': id,
        'docState': a.snapshot['docState'],
      });
      final sockets = <AppFlowyRealtimeConnection>[],
          subscriptions = <StreamSubscription<RealtimePacket>>[];
      Future<(AppFlowyRealtimeConnection, List<RealtimePacket>)> socket(
        String user,
      ) async {
        final messages = <RealtimePacket>[];
        final connection = AppFlowyRealtimeConnection(
          origin: origin,
          workspaceId: workspace,
          deviceId: 'qualification-$user-${const Uuid().v4()}',
          clientId: BigInt.parse(
            const Uuid().v4().replaceAll('-', '').substring(0, 13),
            radix: 16,
          ).toString(),
          accessToken: () async => f['users'][user]['accessToken'] as String,
          codec: codec,
        );
        sockets.add(connection);
        subscriptions.add(
          connection.packets.listen(
            messages.add,
            onError: (Object e) {
              fail('Sanitized realtime failure: $e');
            },
          ),
        );
        await connection.connect();
        return (connection, messages);
      }

      final (alice, am) = await socket('alice');
      final (bob, bm) = await socket('bob');
      AppFlowyRealtimeConnection? outsider;
      List<RealtimePacket> om = [];
      var deniedAtHandshake = false;
      try {
        final connected = await socket('outsider');
        outsider = connected.$1;
        om = connected.$2;
      } on RealtimeFailure catch (e) {
        deniedAtHandshake = e.code == 'CONNECT_FAILED';
      }

      try {
        alice.send(
          RealtimeManifest(
            objectId: id,
            collabType: 0,
            stateVector: base64Decode(a.snapshot['stateVector'] as String),
          ),
        );
        bob.send(
          RealtimeManifest(
            objectId: id,
            collabType: 0,
            stateVector: base64Decode(peer['stateVector'] as String),
          ),
        );
        for (var i = 0; i < 40 && !bm.any((m) => m is RealtimeManifest); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(
          bm.any((m) => m is RealtimeManifest),
          isTrue,
          reason: 'Original server manifest should reach peer',
        );
        bm.clear();
        am.clear();
        om.clear();
        await a.editor.apply(
          a.editor.transaction..insertText(a.blocks.first, 0, '实时协作😀'),
        );
        await a.flush();
        alice.send(
          RealtimeUpdate(
            objectId: id,
            collabType: 0,
            update: base64Decode(a.snapshot['docState'] as String),
          ),
        );
        for (
          var i = 0;
          i < 40 && !bm.any((m) => m is RealtimeUpdate && m.objectId == id);
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        final received = bm
            .whereType<RealtimeUpdate>()
            .where((m) => m.objectId == id)
            .toList();
        expect(received, isNotEmpty);
        final converged = core.call({
          'action': 'applyUpdate',
          'handle': peer['handle'],
          'update': base64Encode(received.last.update),
        });
        expect(
          converged['data']['meta']['text_map'].values.join(),
          contains('实时协作😀'),
        );
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final unexpectedRead = om.whereType<RealtimeUpdate>().any(
          (m) => m.objectId == id,
        );
        final ghostId = const Uuid().v4();
        final ghost = core.call({'action': 'open', 'objectId': ghostId});
        outsider?.send(
          RealtimeUpdate(
            objectId: ghostId,
            collabType: 0,
            update: base64Decode(ghost['docState'] as String),
          ),
        );
        core.call({'action': 'close', 'handle': ghost['handle']});
        for (
          var i = 0;
          i < 15 &&
              !bm.whereType<RealtimeUpdate>().any((m) => m.objectId == ghostId);
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        final unexpectedWrite = bm.whereType<RealtimeUpdate>().any(
          (m) => m.objectId == ghostId,
        );
        final contentBefore = a.snapshot['docState'];
        final presenceA = RealtimePresence(
          core: codec.core,
          objectId: id,
          clientId: alice.clientId,
        );
        final presenceB = RealtimePresence(
          core: codec.core,
          objectId: id,
          clientId: bob.clientId,
        );
        final foreignSlot = RealtimePresence(
          core: codec.core,
          objectId: id,
          clientId: bob.clientId,
        );
        try {
          bm.clear();
          alice.send(
            presenceA.update({
              'profile': 'muse.presence/1',
              'actor': {'uid': 'forged'},
              'selection': null,
            }, collabType: 0),
          );
          for (
            var i = 0;
            i < 40 &&
                !bm.whereType<RealtimeAwareness>().any((m) => m.objectId == id);
            i++
          ) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          final packet = bm.whereType<RealtimeAwareness>().lastWhere(
            (m) => m.objectId == id,
          );
          presenceB.apply(packet);
          final participant = presenceB.clients.single;
          expect(participant.clientId, alice.clientId);
          expect(participant.actorUid, isNot('forged'));
          expect(BigInt.tryParse(participant.actorUid!), isNotNull);
          expect(
            (participant.state['actor'] as Map)['clientId'],
            alice.clientId,
          );
          bm.clear();
          alice.send(presenceA.leave(collabType: 0));
          for (
            var i = 0;
            i < 40 &&
                !bm.whereType<RealtimeAwareness>().any((m) => m.objectId == id);
            i++
          ) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          presenceB.apply(
            bm.whereType<RealtimeAwareness>().lastWhere(
              (m) => m.objectId == id,
            ),
          );
          expect(presenceB.clients, isEmpty);
          bm.clear();
          alice.send(
            foreignSlot.update({
              'actor': {'uid': 'forged-peer'},
              'selection': null,
            }, collabType: 0),
          );
          await Future<void>.delayed(const Duration(milliseconds: 500));
          for (final packet in bm.whereType<RealtimeAwareness>().where(
            (m) => m.objectId == id,
          )) {
            presenceB.apply(packet);
          }
          expect(
            presenceB.clients,
            isEmpty,
            reason: 'An authenticated connection cannot forge another slot',
          );
          expect(
            a.snapshot['docState'],
            contentBefore,
            reason: 'Awareness is not document content',
          );
        } finally {
          presenceA.close();
          presenceB.close();
          foreignSlot.close();
        }
        final result = {
          'status': unexpectedRead || unexpectedWrite
              ? 'failed-authorization-boundary'
              : 'passed-original-ws2-boundary',
          'objectId': id,
          'ghostId': ghostId,
          'peerMerge': true,
          'unexpectedNonmemberRead': unexpectedRead,
          'nonmemberDeniedAtHandshake': deniedAtHandshake,
          'unexpectedNonmemberWrite': unexpectedWrite,
          'checks': [
            'original-protobuf-two-member-socket-manifest',
            'original-peer-update-applied-by-same-document-core',
            'nonmember-data-not-broadcast',
            'nonmember-unregistered-object-write-not-published',
            'original-awareness-authenticated-uid-and-client-slot',
            'awareness-null-leave-removes-online-member-without-content-change',
            'foreign-presence-slot-filtered-by-authenticated-connection',
          ],
        };
        await File(
          '../../.build/ws2-cloud-qualification.json',
        ).writeAsString(jsonEncode(result));
        expect(
          unexpectedRead,
          isFalse,
          reason:
              'An authenticated outsider must not receive workspace content',
        );
        expect(
          unexpectedWrite,
          isFalse,
          reason: 'A missing object must not bypass workspace write permission',
        );
      } finally {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
        for (final socket in sockets) {
          await socket.close();
        }
        core.call({'action': 'close', 'handle': peer['handle']});
        await a.close();
      }
    },
  );
}
