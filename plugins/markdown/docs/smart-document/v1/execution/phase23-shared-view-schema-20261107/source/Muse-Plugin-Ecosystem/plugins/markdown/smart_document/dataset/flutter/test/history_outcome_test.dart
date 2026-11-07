import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';
import 'support.dart';

void main() {
  test(
    'history outcome belongs to its command while a newer peer projection arrives during checkpoint IO',
    () async {
      final store = MemoryStore();
      final c = await DatasetController.open(
        core: NativeDatasetCore(),
        store: store,
        objectId: 'cbd29e9e-d32c-4bd7-a467-545895c871b3',
        syncInterval: null,
      );
      await c.addRow(cells: {'title': 'Muse'});
      Map<String, dynamic> rule(String value) => {
        'id': 'shared',
        'filter_type': 2,
        'field_id': 'title',
        'ty': 0,
        'condition': 2,
        'content': value,
      };
      await c.configureViewRules(
        c.views.single,
        filters: [rule('base')],
        sorts: [],
      );
      await c.configureViewRules(
        c.views.single,
        filters: [rule('local')],
        sorts: [],
      );
      final b = await DatasetController.open(
        core: NativeDatasetCore(),
        store: MemoryStore(),
        objectId: c.objectId,
        initialBundle: c.bundle,
        syncInterval: null,
      );
      Future<void> receive() async {
        final original = b.core.call({
          'action': 'syncObject',
          'handle': b.handle,
          'objectId': b.objectId,
        });
        await c.applyRealtimeUpdate(
          c.objectId,
          1,
          base64Decode(original['docState'] as String),
        );
      }

      await b.configureViewRules(
        b.views.single,
        filters: [rule('peer1')],
        sorts: [],
      );
      await receive();
      final held = Completer<void>();
      store.gate = held;
      store.entered = Completer<void>();
      final undo = c.history();
      await store.entered!.future;
      await b.configureViewRules(
        b.views.single,
        filters: [rule('peer2')],
        sorts: [],
      );
      final incoming = receive();
      expect(c.views.single.filters.single['content'], 'peer2');
      expect(c.lastHistoryApplied, false);
      held.complete();
      expect(await undo, false);
      await incoming;
      expect(c.views.single.filters.single['content'], 'peer2');
      expect(c.lastHistoryApplied, false);
      await b.close();
      await c.close();
    },
  );
}
