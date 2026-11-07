import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openmuse_dataset/openmuse_dataset.dart';
import 'package:uuid/uuid.dart';
import 'support.dart';

class _HttpGate extends http.BaseClient {
  final http.Client inner = http.Client();
  bool blocked = false;
  int networkRequests = 0, blockedRequests = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest r) {
    if (blocked) {
      blockedRequests++;
      throw http.ClientException('test-http-route-offline');
    }
    networkRequests++;
    return inner.send(r);
  }

  @override
  void close() => inner.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'original WS2 database/row updates and cell awareness work while reader HTTP is unavailable',
    () async {
      final f =
          jsonDecode(await File('../../.build/e2e-fixture.json').readAsString())
              as Map;
      final id = const Uuid().v4(), stamp = const Uuid().v4();
      final gates = <String, List<_HttpGate>>{};
      DatasetProviderFactory provider(String user) => (type) {
        final gate = _HttpGate();
        (gates[user] ??= []).add(gate);
        return AppFlowyObjectTransport(
          origin: Uri.parse(f['origin'] as String),
          workspaceId: f['workspaceId'] as String,
          deviceId: 'dataset-rt-$stamp-$user-$type',
          accessToken: () async => f['users'][user]['accessToken'] as String,
          binding: datasetBinding(type),
          collabType: type,
          client: gate,
        );
      };
      final a = await DatasetController.open(
        core: NativeDatasetCore(),
        store: MemoryStore(),
        objectId: id,
        providerFactory: provider('alice'),
        createRemote: true,
        syncInterval: null,
      );
      final rowId = await a.addRow(cells: {'title': '原始行'});
      await a.synchronize();
      final b = await DatasetController.open(
        core: NativeDatasetCore(),
        store: MemoryStore(),
        objectId: id,
        providerFactory: provider('bob'),
        editable: false,
        syncInterval: null,
      );
      final wire = await loadRealtimeWireCore();
      DatasetRealtimeSession session(DatasetController c, String who) =>
          DatasetRealtimeSession(
            controller: c,
            presenceCore: wire,
            connection: AppFlowyRealtimeConnection(
              origin: Uri.parse(f['origin'] as String),
              workspaceId: f['workspaceId'] as String,
              deviceId: 'dataset-rt-$stamp-$who',
              clientId:
                  (DateTime.now().microsecondsSinceEpoch +
                          (who == 'alice' ? 1 : 2))
                      .toString(),
              accessToken: () async => f['users'][who]['accessToken'] as String,
              codec: AppFlowyRealtimeCodec(wire),
            ),
          );
      final ra = session(a, 'alice'), rb = session(b, 'bob');
      final checks = <String>[];
      Future<void> until(bool Function() ready, String reason) async {
        final clock = Stopwatch()..start();
        while (clock.elapsed < const Duration(seconds: 15)) {
          if (ready()) return;
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        fail('Dataset realtime deadline: $reason');
      }

      try {
        await ra.start();
        await rb.start();
        await until(
          () =>
              ra.connected &&
              rb.connected &&
              ra.collaborators.isNotEmpty &&
              rb.collaborators.isNotEmpty,
          'original root awareness',
        );
        expect(b.canWrite, isFalse);
        checks.add(
          'same-original-ws2-and-awareness-package-with-independent-database-root-and-row',
        );
        for (final gate in gates['bob']!) {
          gate.blocked = true;
        }
        final networkBefore = gates['bob']!.fold<int>(
              0,
              (sum, g) => sum + g.networkRequests,
            ),
            updatesBefore = rb.remoteUpdatesApplied;
        final row = a.views.single.rows.firstWhere((r) => r.id == rowId),
            field = a.views.single.columns.first;
        await a.setCell(
          row,
          field,
          '只经 WebSocket 到达😀',
          expectedHash: row.cells[field.id]!.hash,
        );
        await until(
          () =>
              b.views.single.rows.first.cells['title']!.value ==
                  '只经 WebSocket 到达😀' &&
              rb.remoteUpdatesApplied > updatesBefore,
          'row WS update with reader HTTP gate closed',
        );
        expect(
          gates['bob']!.fold<int>(0, (sum, g) => sum + g.networkRequests),
          networkBefore,
        );
        checks.add(
          'actual-row4-update-applies-through-ws-with-zero-reader-http-network-requests',
        );
        ra.selectCell(
          viewId: a.views.single.id,
          rowId: rowId,
          fieldId: 'title',
          editing: true,
        );
        await until(
          () => rb.collaborators.any(
            (c) =>
                c.cell?['rowId'] == rowId &&
                c.cell?['fieldId'] == 'title' &&
                c.cell?['editing'] == true,
          ),
          'root-scoped stable-cell presence',
        );
        expect(b.canWrite, isFalse);
        checks.add(
          'server-normalized-uid-and-stable-view-row-field-awareness-with-host-readonly-upper-bound',
        );
        final newRow = await a.addRow(cells: {'title': '实时新增独立行'});
        await a.synchronize();
        await until(
          () => b.views.single.rows.any(
            (r) =>
                r.id == newRow &&
                r.loaded &&
                r.cells['title']!.value == '实时新增独立行',
          ),
          'root delta and dynamically manifested full row',
        );
        expect(
          gates['bob']!.fold<int>(0, (sum, g) => sum + g.networkRequests),
          networkBefore,
        );
        expect(b.unavailableRows, isEmpty);
        checks.add(
          'new-root-reference-and-independent-row-bootstrap-via-original-state-vector-manifest',
        );
        await rb.connection.disconnect();
        await until(() => !rb.connected, 'explicit route disconnect');
        final current = a.views.single.rows.firstWhere((r) => r.id == rowId);
        await a.setCell(
          current,
          field,
          '断开后追赶',
          expectedHash: current.cells[field.id]!.hash,
        );
        await a.synchronize();
        await rb.start();
        await until(
          () =>
              b.views.single.rows
                  .firstWhere((r) => r.id == rowId)
                  .cells['title']!
                  .value ==
              '断开后追赶',
          'reconnect vector repair',
        );
        expect(
          gates['bob']!.fold<int>(0, (sum, g) => sum + g.networkRequests),
          networkBefore,
        );
        checks.add(
          'reconnect-original-vectors-catch-up-without-http-or-fabricated-rows',
        );
        await ra.close();
        await until(() => rb.collaborators.isEmpty, 'original awareness leave');
        checks.add(
          'transient-cell-awareness-leave-does-not-write-content-or-persist-credentials',
        );
        final encoded = jsonEncode(b.bundle);
        expect(encoded, isNot(contains('accessToken')));
        expect(encoded, isNot(contains('muse.dataset.presence')));
        await File(
          '../../.build/dataset-realtime-cloud-result.json',
        ).writeAsString(
          jsonEncode({
            'status': 'passed',
            'objectId': id,
            'rowId': rowId,
            'newRowId': newRow,
            'checks': checks,
            'fullProductAcceptance': 'not-complete',
          }),
        );
      } finally {
        await ra.close();
        await rb.close();
        await a.close();
        await b.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
