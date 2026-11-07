import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';
import 'support.dart';

void main() {
  test(
    'unfiltered record queries retain reference and authority guards after live row revoke',
    () async {
      final c = await DatasetController.open(
        core: NativeDatasetCore(),
        store: MemoryStore(),
        objectId: '9d238907-3ac2-4f29-aaac-66e5b606a64f',
        syncInterval: null,
      );
      final id = await c.addRow(cells: {'title': 'hidden'});
      await c.configureViewRules(
        c.views.single,
        filters: [
          {
            'id': 'filter',
            'filter_type': 2,
            'field_id': 'title',
            'ty': 0,
            'condition': 0,
            'content': 'visible',
          },
        ],
        sorts: [],
      );
      expect(c.views.single.rows, isEmpty);
      expect(c.readRow(c.views.single.id, id).cells['title']!.value, 'hidden');
      expect(
        () => c.readRow('unrelated-view', id),
        throwsA(isA<DatasetFailure>()),
      );
      c.acceptRealtimeAccess(
        id: id,
        collabType: 4,
        canRead: false,
        canWrite: false,
        reason: 'revoked',
      );
      expect(
        () => c.readRow(c.views.single.id, id),
        throwsA(isA<DatasetFailure>()),
      );
      await c.close();
    },
  );
}
