import 'package:muse_content_store/browser.dart';
import 'core_api.dart';
import 'store_api.dart';

/// Preserve the existing database name and error API during extraction. No
/// migration, namespace change or deletion of previously saved documents.
final class IndexedDbDocumentStore implements DocumentStore {
  IndexedDbDocumentStore({required this.namespace, required this.objectId})
    : _store = IndexedDbSnapshotStore(
        namespace: namespace,
        objectId: objectId,
        databasePrefix: 'muse-smart-document:',
      );
  final String namespace, objectId;
  final IndexedDbSnapshotStore _store;
  Future<T> _adapt<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on SnapshotStoreFailure catch (e) {
      throw SmartDocumentFailure(e.code);
    }
  }

  @override
  Future<Map<String, dynamic>?> read() => _adapt(_store.read);
  @override
  Future<void> write(Map<String, dynamic> snapshot) =>
      _adapt(() => _store.write(snapshot));
}
