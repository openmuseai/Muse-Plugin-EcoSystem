import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Integration fixture: explicitly restore real IO, not Flutter's unit-test HTTP mock.
  HttpOverrides.global = null;
  test(
    'real AppFlowy Cloud: two users, offline merge, undo, reopen, ACL, server restart',
    () async {
      final root = Directory.current.parent;
      final fixture =
          jsonDecode(
                await File(
                  '${root.path}/.build/e2e-fixture.json',
                ).readAsString(),
              )
              as Map;
      final evidence = <String>[];
      final dir = await Directory.systemTemp.createTemp('muse-smartdoc-cloud-');
      final core = NativeDocumentCore();
      // Independent test object: repeated runs must not append to another fixture.
      final id = const Uuid().v4();
      AppFlowyCollaborationProvider provider(String name, String device) =>
          AppFlowyCollaborationProvider(
            origin: Uri.parse(fixture['origin'] as String),
            workspaceId: fixture['workspaceId'] as String,
            deviceId: device,
            accessToken: () async =>
                fixture['users'][name]['accessToken'] as String,
          );
      Future<void> insert(SmartDocumentController c, String text) async {
        final node = c.blocks.first;
        final t = c.editor.transaction
          ..insertText(node, node.delta!.length, text);
        await c.editor.apply(t);
        await c.flush();
        expect(c.failure, isNull);
      }

      String text(SmartDocumentController c) =>
          c.blocks.first.delta!.toPlainText();
      Future<void> sync(SmartDocumentController c) async {
        await c.synchronize();
        expect(c.syncState, DocumentSyncState.accepted, reason: c.failure);
      }

      Future<void> eventually(
        List<SmartDocumentController> clients,
        bool Function() condition,
      ) async {
        for (var attempt = 0; attempt < 50; attempt++) {
          for (final client in clients) {
            await sync(client);
          }
          if (condition()) return;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        fail('Cloud did not converge before deadline');
      }

      var alice = await SmartDocumentController.open(
        core: core,
        store: FileDocumentStore(File('${dir.path}/alice.json')),
        objectId: id,
        provider: provider('alice', 'alice-device'),
        createRemote: true,
        syncInterval: null,
      );
      expect(
        alice.syncState,
        DocumentSyncState.accepted,
        reason: alice.failure,
      );
      evidence.add('authenticated-document-create-on-original-cloud');
      final bob = await SmartDocumentController.open(
        core: core,
        store: FileDocumentStore(File('${dir.path}/bob.json')),
        objectId: id,
        provider: provider('bob', 'bob-device'),
        syncInterval: null,
      );
      await insert(alice, '中文😀共享文档');
      final format = alice.editor.transaction
        ..formatText(alice.blocks.first, 0, 2, {'bold': true});
      await alice.editor.apply(format);
      await alice.flush();
      await eventually([alice, bob], () => text(bob) == text(alice));
      expect(text(bob), '中文😀共享文档');
      expect(bob.blocks.first.delta!.toJson().first['attributes'], {
        'bold': true,
      });
      evidence.add('two-registered-workspace-members-exchange-text-and-marks');
      alice.pauseCollaboration(true);
      bob.pauseCollaboration(true);
      await insert(alice, '甲');
      await insert(bob, '乙');
      expect(alice.localSave, LocalSaveState.durable);
      expect(bob.localSave, LocalSaveState.durable);
      alice.pauseCollaboration(false);
      await sync(alice);
      bob.pauseCollaboration(false);
      await eventually(
        [bob, alice],
        () =>
            text(alice).contains('甲') &&
            text(alice).contains('乙') &&
            text(alice) == text(bob),
      );
      expect(alice.snapshot['data'], bob.snapshot['data']);
      expect(text(alice), contains('甲'));
      expect(text(alice), contains('乙'));
      evidence.add(
        'offline-concurrent-unicode-edits-converge-without-overwrite',
      );
      await alice.history();
      await eventually([
        alice,
        bob,
      ], () => !text(bob).contains('甲') && text(bob) == text(alice));
      expect(text(alice), isNot(contains('甲')));
      expect(text(alice), contains('乙'));
      expect(text(alice), text(bob));
      await alice.history(redo: true);
      await eventually([
        alice,
        bob,
      ], () => text(bob).contains('甲') && text(bob) == text(alice));
      expect(text(bob), contains('甲'));
      evidence.add('domain-origin-undo-redo-preserves-collaborator-insert');
      await bob.insertParagraph('远端新增段落');
      await eventually([
        bob,
        alice,
      ], () => alice.blocks.length == bob.blocks.length);
      expect(alice.blocks.last.delta!.toPlainText(), '远端新增段落');
      final stable = alice.blocks.last.id;
      final remove = alice.editor.transaction..deleteNode(alice.blocks.first);
      await alice.editor.apply(remove);
      await alice.flush();
      await eventually([
        alice,
        bob,
      ], () => bob.blocks.length == alice.blocks.length);
      expect(bob.blocks.first.id, stable);
      expect(bob.blocks.first.delta!.toPlainText(), '远端新增段落');
      evidence.add('stable-block-insert-delete-remote-projection');
      final outsider = provider('outsider', 'outsider-device');
      await expectLater(
        outsider.readState(id),
        throwsA(
          isA<SmartDocumentFailure>().having(
            (e) => e.code,
            'code',
            'FORBIDDEN',
          ),
        ),
      );
      final request = core.call({
        'action': 'syncRequest',
        'handle': alice.handle,
      });
      await expectLater(
        outsider.exchange(id, base64Decode(request['body'] as String)),
        throwsA(
          isA<SmartDocumentFailure>().having(
            (e) => e.code,
            'code',
            'FORBIDDEN',
          ),
        ),
      );
      outsider.close();
      final denied = await SmartDocumentController.open(
        core: core,
        store: FileDocumentStore(File('${dir.path}/denied/doc.json')),
        objectId: id,
        initialDocState: alice.snapshot['docState'] as String,
        provider: provider('outsider', 'denied-cached-device'),
        syncInterval: null,
      );
      expect(denied.syncState, DocumentSyncState.forbidden);
      expect(denied.editor.editable, isFalse);
      await expectLater(
        denied.insertParagraph('拒绝后不可写'),
        throwsA(isA<SmartDocumentFailure>()),
      );
      await denied.close();
      evidence.add('server-rejects-nonmember-read-and-raw-full-sync-write');
      await alice.close();
      await insert(bob, '（关闭后的远端修改）');
      await sync(bob);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      alice = await SmartDocumentController.open(
        core: core,
        store: FileDocumentStore(File('${dir.path}/alice.json')),
        objectId: id,
        provider: provider('alice', 'alice-reopened'),
        syncInterval: null,
      );
      await eventually([alice, bob], () => text(alice).contains('关闭后的远端修改'));
      expect(alice.blocks.first.id, stable);
      expect(text(alice), contains('关闭后的远端修改'));
      evidence.add('file-reopen-merges-new-cloud-state-preserving-block-id');
      final expected = text(alice);
      await alice.close();
      await bob.close();
      // The isolated Cloud is configured to persist every second. Restart the
      // actual process and read through a new session, not its in-memory actor.
      await Future<void>.delayed(const Duration(seconds: 3));
      final restart = await Process.run('python3', [
        '${root.path}/scripts/dev_stack.py',
        'restart-cloud',
      ]);
      expect(restart.exitCode, 0, reason: '${restart.stderr}');
      final afterRestart = await SmartDocumentController.open(
        core: core,
        store: FileDocumentStore(File('${dir.path}/fresh.json')),
        objectId: id,
        provider: provider('alice', 'fresh-after-server-restart'),
        syncInterval: null,
      );
      expect(text(afterRestart), expected);
      expect(afterRestart.blocks.first.id, stable);
      await afterRestart.close();
      evidence.add(
        'fresh-client-after-real-cloud-restart-reads-persisted-content',
      );
      final report = {
        'status': 'passed',
        'checks': evidence,
        'engine':
            'AppFlowy-Collab e59260e524f33104b0ddcd6bb8f6218cad0f7e18 / Yrs 0.23.5',
        'transport':
            'original authenticated Cloud full-sync HTTP/protobuf exchange',
        'users': 2,
        'nonmemberRejections': 2,
        'date': DateTime.now().toUtc().toIso8601String(),
      };
      await File(
        '${root.path}/.build/cloud-e2e-result.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
      await dir.delete(recursive: true);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
