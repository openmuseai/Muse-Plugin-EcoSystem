import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';
import 'support.dart';

class _Gate implements CollaborationProvider {
  _Gate(this.inner);
  final CollaborationProvider inner;
  Completer<Uint8List?>? nextRead;
  Completer<void> entered = Completer<void>();
  bool closed = false;
  @override
  CollaborationBinding get binding => inner.binding;
  @override
  Future<Uint8List?> readState(String id) async {
    final wait = nextRead;
    nextRead = null;
    if (wait != null) {
      if (!entered.isCompleted) entered.complete();
      return wait.future;
    }
    return inner.readState(id);
  }

  @override
  Future<void> initializeState(String id, Uint8List state) =>
      inner.initializeState(id, state);
  @override
  Future<Uint8List> exchange(String id, Uint8List request) =>
      inner.exchange(id, request);
  @override
  void close() {
    closed = true;
    inner.close();
  }
}

Future<({DatasetController c, Map<int, _Gate> providers, MemoryStore store})>
open() async {
  final core = TracedCore();
  // One original tracing core must encode and decode the test HTTP bodies.
  final realCloud = FakeCloud(core);
  final providers = <int, _Gate>{
    for (final type in [1, 4]) type: _Gate(realCloud.provider(type)),
  };
  final store = MemoryStore();
  final c = await DatasetController.open(
    core: core,
    store: store,
    objectId: '6d36a4c9-0c52-42cd-8b8e-dc4a89d2c68a',
    createRemote: true,
    syncInterval: null,
    providerFactory: (type) => providers[type]!,
  );
  return (c: c, providers: providers, store: store);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'an already awaited row response cannot merge after its read capability is revoked',
    () async {
      final w = await open(), c = w.c, p = w.providers[4]!;
      final rowId = await c.addRow(cells: {'title': '原记录'});
      await c.synchronize();
      final peer = await DatasetController.open(
        core: NativeDatasetCore(),
        store: MemoryStore(),
        objectId: c.objectId,
        initialBundle: c.bundle,
        syncInterval: null,
      );
      final row = peer.views.single.rows.single,
          field = peer.views.single.columns.first;
      await peer.setCell(
        row,
        field,
        '旧行回包',
        expectedHash: row.cells[field.id]!.hash,
      );
      final remote = base64Decode(
        (peer.bundle['objects'] as List).singleWhere(
              (v) => v['objectId'] == rowId,
            )['docState']
            as String,
      );
      final gate = Completer<Uint8List?>();
      p.nextRead = gate;
      final sync = c.synchronize();
      await p.entered.future;
      c.acceptRealtimeAccess(
        id: rowId,
        collabType: 4,
        canRead: false,
        canWrite: false,
        reason: 'denied',
      );
      final before = jsonEncode(c.snapshot['views']);
      gate.complete(remote);
      await sync;
      expect(jsonEncode(c.snapshot['views']), before);
      expect(c.canRead, false);
      await c.close();
      await peer.close();
    },
  );
  test(
    'paused dataset rejects new incoming content while keeping cached state',
    () async {
      final w = await open(), c = w.c;
      final peer = await DatasetController.open(
        core: NativeDatasetCore(),
        store: MemoryStore(),
        objectId: c.objectId,
        initialBundle: c.bundle,
        syncInterval: null,
      );
      await peer.createField('暂停期间远端字段', 'text');
      final remote = base64Decode(
        (peer.bundle['objects'] as List).singleWhere(
              (v) => v['objectId'] == c.objectId,
            )['docState']
            as String,
      );
      c.pauseCollaboration(true);
      final before = jsonEncode(c.snapshot['views']);
      expect(await c.applyRealtimeUpdate(c.objectId, 1, remote), false);
      expect(jsonEncode(c.snapshot['views']), before);
      await c.close();
      await peer.close();
    },
  );
  for (final code in ['FORBIDDEN', 'OBJECT_DELETED', 'OFFLINE']) {
    test(
      'dataset closes locally before outstanding root HTTP and ignores late $code',
      () async {
        final w = await open(), c = w.c, p = w.providers[1]!;
        final gate = Completer<Uint8List?>();
        p.nextRead = gate;
        final sync = c.synchronize();
        await p.entered.future;
        var done = false;
        final closing = c.close().then((_) => done = true);
        // Memory-only checkpoint/close settles in microtasks; the held request
        // is the sole external gate. This checks ordering, not throughput.
        await Future<void>.delayed(Duration.zero);
        final state = c.syncState, failure = c.syncFailure;
        try {
          expect(
            done,
            true,
            reason: 'local resource release must not wait for HTTP',
          );
        } finally {
          gate.completeError(AppFlowyTransportFailure(code));
          await sync;
          await closing;
        }
        expect(p.closed, true);
        expect(c.syncState, state);
        expect(c.syncFailure, failure);
      },
    );
  }
  test(
    'an older root read denial cannot overwrite a fresh authenticated grant',
    () async {
      final w = await open(), c = w.c, p = w.providers[1]!;
      final gate = Completer<Uint8List?>();
      p.nextRead = gate;
      final sync = c.synchronize();
      await p.entered.future;
      void access(bool allowed) => c.acceptRealtimeAccess(
        id: c.objectId,
        collabType: 1,
        canRead: allowed,
        canWrite: allowed,
        reason: allowed ? 'granted' : 'denied',
      );
      access(false);
      access(true);
      gate.completeError(const AppFlowyTransportFailure('FORBIDDEN'));
      await sync;
      expect(c.canWrite, true);
      await c.close();
    },
  );
  test(
    'a root response after read revocation cannot merge previously authorized content',
    () async {
      final w = await open(), c = w.c, p = w.providers[1]!;
      final peer = await DatasetController.open(
        core: NativeDatasetCore(),
        store: MemoryStore(),
        objectId: c.objectId,
        initialBundle: c.bundle,
        syncInterval: null,
      );
      await peer.createField('旧请求回包的字段', 'text');
      final remote = base64Decode(
        (peer.bundle['objects'] as List).singleWhere(
              (v) => v['objectId'] == c.objectId,
            )['docState']
            as String,
      );
      final gate = Completer<Uint8List?>();
      p.nextRead = gate;
      final sync = c.synchronize();
      await p.entered.future;
      c.acceptRealtimeAccess(
        id: c.objectId,
        collabType: 1,
        canRead: false,
        canWrite: false,
        reason: 'denied',
      );
      final before = jsonEncode(c.snapshot['views']);
      gate.complete(remote);
      await sync;
      expect(jsonEncode(c.snapshot['views']), before);
      expect(c.canRead, false);
      expect(c.canWrite, false);
      await c.close();
      await peer.close();
    },
  );
  test(
    'pause-resume fences old root errors and preserves write authority',
    () async {
      final w = await open(), c = w.c, p = w.providers[1]!;
      final gate = Completer<Uint8List?>();
      p.nextRead = gate;
      final sync = c.synchronize();
      await p.entered.future;
      c.pauseCollaboration(true);
      c.pauseCollaboration(false);
      gate.completeError(const AppFlowyTransportFailure('FORBIDDEN'));
      await sync;
      expect(c.canWrite, true);
      await c.close();
    },
  );
}
