import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:muse_content_store/snapshot_store.dart';
import 'package:muse_appflowy_transport/muse_appflowy_transport.dart';
import 'package:uuid/uuid.dart';
import 'core_api.dart';
import 'projection.dart';

typedef DatasetProviderFactory = CollaborationProvider Function(int collabType);

enum DatasetSaveState { dirty, saved, failed }

enum DatasetSyncState {
  local,
  pending,
  exchanging,
  accepted,
  unavailable,
  forbidden,
  removed,
}

/// Application session over an independent content domain. No document editor,
/// block paths, HTTP implementation or file-path policy enters here.
final class DatasetController extends ChangeNotifier {
  DatasetController._({
    required this.core,
    required this.store,
    required this.objectId,
    required this.editable,
    required this.createRemote,
    required Map<String, dynamic> state,
  }) : _state = state;
  final DatasetCore core;
  final SnapshotStore store;
  final String objectId;
  final bool editable, createRemote;
  late final String handle;
  Map<String, dynamic> _state;
  final Map<int, CollaborationProvider> _providers = {};
  final Set<String> _observedObjects = {}, _unavailableRows = {};
  Set<String> get unavailableRows => Set.unmodifiable(_unavailableRows);
  Timer? _timer;
  bool _closed = false, _closing = false, _paused = false, _everRemote = false;
  int _generation = 0, _durableGeneration = -1, _mutationEpoch = 0;
  Future<void> _writes = Future.value();
  Future<void>? _syncing, _closingTask;
  DatasetSaveState saveState = DatasetSaveState.saved;
  DatasetSyncState syncState = DatasetSyncState.local;
  Object? persistenceFailure, syncFailure;
  Map<String, dynamic> get snapshot => Map.unmodifiable(
    (jsonDecode(jsonEncode(_state)) as Map).cast<String, dynamic>(),
  );
  Map<String, dynamic> get bundle =>
      (jsonDecode(jsonEncode(_state['bundle'])) as Map).cast<String, dynamic>();
  List<DatasetViewProjection> get views => List.unmodifiable(
    (_state['views'] as List).map(
      (v) => DatasetViewProjection.fromJson(v as Map),
    ),
  );
  bool get canWrite =>
      editable &&
      !_closed &&
      !_closing &&
      _unavailableRows.isEmpty &&
      !{
        DatasetSyncState.forbidden,
        DatasetSyncState.removed,
      }.contains(syncState);
  bool get canUndo => _state['canUndo'] == true;
  bool get canRedo => _state['canRedo'] == true;

  static Future<DatasetController> open({
    required DatasetCore core,
    required SnapshotStore store,
    required String objectId,
    Map<String, dynamic>? initialBundle,
    bool editable = true,
    DatasetProviderFactory? providerFactory,
    bool createRemote = false,
    Duration? syncInterval = const Duration(seconds: 1),
  }) async {
    final cached = await store.read();
    if (cached != null) {
      if (cached['profile'] != 'muse.dataset.cache/0.1' ||
          cached['objectId'] != objectId)
        throw const DatasetFailure('CACHE_SCOPE_MISMATCH');
      final binding = CollaborationBinding.fromJson(
        (cached['binding'] as Map).cast<String, Object?>(),
      );
      if (!binding.compatibleWith(datasetBinding(1)))
        throw const DatasetFailure('INCOMPATIBLE_BINDING');
    }
    final providers = <int, CollaborationProvider>{};
    DatasetController? controller;
    try {
      if (providerFactory != null) {
        for (final type in [1, 4]) {
          final provider = providerFactory(type);
          if (!provider.binding.compatibleWith(datasetBinding(type))) {
            provider.close();
            throw const DatasetFailure('INCOMPATIBLE_BINDING');
          }
          providers[type] = provider;
        }
      }
      Map<String, dynamic>? source = cached?['bundle'] is Map
          ? (cached!['bundle'] as Map).cast<String, dynamic>()
          : initialBundle;
      var importedRemote = false;
      // Never create a second default CRDT root and merge it into an existing
      // dataset: concurrent nested-map initialization can replace whole branches.
      if (source == null && providers.isNotEmpty) {
        final remote = await providers[1]!.readState(objectId);
        if (remote != null) {
          source = {
            'profile': 'muse.dataset.bundle/0.1',
            'objectId': objectId,
            'objects': [
              {
                'objectId': objectId,
                'collabType': 1,
                'docState': base64Encode(remote),
              },
            ],
          };
          importedRemote = true;
        } else if (!createRemote || !editable) {
          throw const DatasetFailure('ROOT_NOT_FOUND');
        }
      }
      final state = core.call({
        'action': 'open',
        'objectId': objectId,
        if (source != null) 'bundle': source,
      });
      final c = DatasetController._(
        core: core,
        store: store,
        objectId: objectId,
        editable: editable,
        createRemote: createRemote,
        state: state,
      )..handle = state['handle'] as String;
      controller = c;
      c._everRemote = cached?['remoteInitialized'] == true || importedRemote;
      final observed = cached?['observedObjects'];
      if (observed != null) {
        final ids = (c.bundle['objects'] as List)
            .map((o) => o['objectId'])
            .toSet();
        if (observed is! List ||
            observed.length > 1001 ||
            observed.any((id) => id is! String || !ids.contains(id))) {
          throw const DatasetFailure('CACHE_SCOPE_MISMATCH');
        }
        c._observedObjects.addAll(observed.cast<String>());
      }
      c._providers.addAll(providers);
      if (providers.isNotEmpty) c.syncState = DatasetSyncState.pending;
      if (cached == null) {
        await c._queuePersist();
      } else {
        c._durableGeneration = c._generation;
      }
      if (providers.isNotEmpty) await c.synchronize();
      if (providers.isNotEmpty && syncInterval != null)
        c._timer = Timer.periodic(
          syncInterval,
          (_) => unawaited(c.synchronize()),
        );
      return c;
    } on Object {
      for (final provider in providers.values) {
        provider.close();
      }
      if (controller != null)
        core.call({'action': 'close', 'handle': controller.handle});
      rethrow;
    }
  }

  void _replace(Map<String, dynamic> value, {bool local = false}) {
    _state = value;
    if (value['changed'] == false) return;
    _generation++;
    if (local) _mutationEpoch++;
    saveState = DatasetSaveState.dirty;
    if (_providers.isNotEmpty && syncState != DatasetSyncState.exchanging)
      syncState = DatasetSyncState.pending;
    notifyListeners();
  }

  Future<void> _observeObject(String id) async {
    if (_observedObjects.add(id)) {
      _generation++;
      saveState = DatasetSaveState.dirty;
      await _queuePersist();
    }
  }

  Future<void> _observedRemote() async {
    if (!_everRemote) {
      _everRemote = true;
      _generation++;
      saveState = DatasetSaveState.dirty;
      await _queuePersist();
    }
  }

  Future<void> _queuePersist() {
    final next = _writes.catchError((Object _) {}).then((_) => _writeNow());
    _writes = next;
    return next;
  }

  Future<void> _writeNow() async {
    final generation = _generation;
    final record = {
      'profile': 'muse.dataset.cache/0.1',
      'objectId': objectId,
      'binding': datasetBinding(1).toJson(),
      'bundle': _state['bundle'],
      'remoteInitialized': _everRemote,
      'observedObjects': _observedObjects.toList()..sort(),
    };
    try {
      await store.write(record);
      persistenceFailure = null;
      _durableGeneration = generation;
      saveState = generation == _generation
          ? DatasetSaveState.saved
          : DatasetSaveState.dirty;
    } on Object catch (e) {
      persistenceFailure = e;
      saveState = DatasetSaveState.failed;
      rethrow;
    } finally {
      if (!_closed) notifyListeners();
    }
  }

  Future<void> flush() async {
    try {
      await _writes;
    } on Object {
      /* Explicit flush retries the current snapshot. */
    }
    while (_durableGeneration != _generation || persistenceFailure != null) {
      await _queuePersist();
    }
  }

  Future<void> command(Map<String, dynamic> command) async {
    if (!canWrite) throw const DatasetFailure('READ_ONLY');
    if (persistenceFailure != null) throw const DatasetFailure('SAVE_REQUIRED');
    _replace(
      core.call({'action': 'command', 'handle': handle, 'command': command}),
      local: true,
    );
    await _queuePersist();
  }

  Future<String> addRow({Map<String, Object?> cells = const {}}) async {
    final id = const Uuid().v4();
    await command({'op': 'addRow', 'rowId': id, 'cells': cells});
    return id;
  }

  Future<void> setCell(
    DatasetRow row,
    DatasetColumn column,
    Object? value, {
    required String expectedHash,
  }) => command({
    'op': 'setCell',
    'rowId': row.id,
    'fieldId': column.id,
    'value': value,
    'expectedHash': expectedHash,
    if (column.fieldHash != null) 'expectedFieldHash': column.fieldHash,
  });
  Future<void> createField(
    String name,
    String semanticType, {
    List<DatasetOptionDraft> options = const [],
  }) async => command({
    'op': 'createField',
    'id': const Uuid().v4(),
    'name': name,
    'semanticType': semanticType,
    'options': [
      for (final option in options)
        {'id': const Uuid().v4(), 'name': option.name, 'color': option.color},
    ],
  });
  Future<void> renameField(DatasetColumn field, String name) async => command({
    'op': 'renameField',
    'fieldId': field.id,
    'name': name,
    'expectedName': field.name,
  });
  Future<void> history({bool redo = false}) async {
    if (!canWrite) throw const DatasetFailure('READ_ONLY');
    if (persistenceFailure != null) throw const DatasetFailure('SAVE_REQUIRED');
    _replace(
      core.call({'action': redo ? 'redo' : 'undo', 'handle': handle}),
      local: true,
    );
    await _queuePersist();
  }

  void pauseCollaboration(bool value) {
    _paused = value;
    notifyListeners();
  }

  Future<void> synchronize() {
    if (_closed ||
        _closing ||
        _paused ||
        _providers.isEmpty ||
        {
          DatasetSyncState.forbidden,
          DatasetSyncState.removed,
        }.contains(syncState))
      return Future.value();
    return _syncing ??= _exchange().whenComplete(() => _syncing = null);
  }

  Set<String> get _rowIds =>
      views.expand((v) => v.rows.map((r) => r.id)).toSet();
  Map<String, dynamic> _object(String id) =>
      core.call({'action': 'syncObject', 'handle': handle, 'objectId': id});
  void _apply(String id, List<int> bytes) {
    _replace(
      core.call({
        'action': 'applyUpdate',
        'handle': handle,
        'objectId': id,
        'update': base64Encode(bytes),
      }),
    );
  }

  Future<void> _exchangeObject(
    String id,
    int type, {
    bool allowCreate = false,
  }) async {
    final provider = _providers[type]!;
    Uint8List? remote;
    try {
      remote = await provider.readState(id);
    } on AppFlowyTransportFailure catch (e) {
      if (e.code == 'OBJECT_DELETED') {
        _unavailableRows.add(id);
        throw const DatasetFailure('ROW_REMOVED');
      }
      rethrow;
    }
    if (remote != null) {
      _apply(id, remote);
      _unavailableRows.remove(id);
      await _observeObject(id);
    } else if (_observedObjects.contains(id)) {
      _unavailableRows.add(id);
      throw const DatasetFailure('ROW_UNAVAILABLE');
    } else if (allowCreate && canWrite) {
      await provider.initializeState(
        id,
        base64Decode(_object(id)['encodedCollab'] as String),
      );
      await _observeObject(id);
    } else {
      _unavailableRows.add(id);
      throw const DatasetFailure('ROW_STATE_REQUIRED');
    }
    if (canWrite) {
      final request = _object(id);
      final update = await provider.exchange(
        id,
        base64Decode(request['body'] as String),
      );
      _replace(
        core.call({
          'action': 'applySync',
          'handle': handle,
          'objectId': id,
          'body': base64Encode(update),
        }),
      );
    }
  }

  Future<void> _exchange() async {
    try {
      await flush();
      final epoch = _mutationEpoch;
      syncState = DatasetSyncState.exchanging;
      notifyListeners();
      final root = _providers[1]!;
      final remote = await root.readState(objectId);
      if (remote == null && _everRemote) {
        syncState = DatasetSyncState.removed;
        throw const DatasetFailure('REMOTE_REMOVED');
      }
      if (remote == null && (!createRemote || !canWrite))
        throw const DatasetFailure('ROOT_NOT_FOUND');
      if (remote != null) {
        await _observedRemote();
        _apply(objectId, remote);
      }
      // Freeze the outbound root before awaiting dependent row uploads. Edits
      // made during network IO remain local/pending for the next exchange.
      final outboundRoot = _object(objectId);
      final dependencies = _rowIds;
      // Publish independent rows before exposing their references in a new root.
      for (final id in dependencies) {
        final loaded = views
            .expand((v) => v.rows)
            .any((r) => r.id == id && r.loaded);
        await _exchangeObject(id, 4, allowCreate: loaded);
      }
      if (remote == null) {
        await root.initializeState(
          objectId,
          base64Decode(outboundRoot['encodedCollab'] as String),
        );
        await _observedRemote();
      }
      if (canWrite) {
        final result = await root.exchange(
          objectId,
          base64Decode(outboundRoot['body'] as String),
        );
        _replace(
          core.call({
            'action': 'applySync',
            'handle': handle,
            'objectId': objectId,
            'body': base64Encode(result),
          }),
        );
      }
      // A peer may have introduced row references in the final root exchange.
      for (final id in _rowIds) {
        if (!views.expand((v) => v.rows).any((r) => r.id == id && r.loaded))
          await _exchangeObject(id, 4);
      }
      await flush();
      syncFailure = null;
      syncState = epoch == _mutationEpoch
          ? DatasetSyncState.accepted
          : DatasetSyncState.pending;
    } on Object catch (e) {
      syncFailure = e;
      final code = e is AppFlowyTransportFailure
          ? e.code
          : e is DatasetFailure
          ? e.code
          : '';
      syncState = code == 'FORBIDDEN'
          ? DatasetSyncState.forbidden
          : code == 'OBJECT_DELETED' || syncState == DatasetSyncState.removed
          ? DatasetSyncState.removed
          : DatasetSyncState.unavailable;
    } finally {
      if (!_closed) notifyListeners();
    }
  }

  Future<void> close() => _closingTask ??= _close().catchError((Object error) {
    _closingTask = null;
    throw error;
  });
  Future<void> _close() async {
    if (_closed) return;
    _closing = true;
    _timer?.cancel();
    try {
      await _syncing;
      await flush();
    } on Object {
      _closing = false;
      rethrow;
    }
    for (final p in _providers.values) {
      p.close();
    }
    core.call({'action': 'close', 'handle': handle});
    _closed = true;
    dispose();
  }
}
