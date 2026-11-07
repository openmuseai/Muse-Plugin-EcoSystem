import 'document_outline.dart';
import 'dart:async';
import 'dart:convert';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/history/undo_manager.dart';
import 'package:flutter/foundation.dart';
import 'cloud_provider.dart';
import 'native_core.dart';
import 'store.dart';

enum LocalSaveState { dirty, durable, failed }

enum DocumentSyncState {
  localOnly,
  paused,
  pending,
  exchanging,
  accepted,
  failed,
  forbidden,
  removed,
}

final class SmartDocumentController extends ChangeNotifier {
  SmartDocumentController._(
    this.core,
    this.store,
    this.provider,
    this.objectId,
    this._state,
    this.handle,
    this.editable,
  ) {
    editor = EditorState(
      document: Document(root: _node(_state, _rootId(_state))),
      undoManager: _DomainUndoManager(this),
    );
    editor.editable = editable;
    _subscription = editor.transactionStream.listen((event) {
      if (event.$1 != TransactionTime.before || event.$2.operations.isEmpty)
        return;
      if (!canWrite) return;
      try {
        _state = core.call({
          'action': 'operations',
          'handle': handle,
          'operations': event.$2.operations.expand(_operations).toList(),
        });
        _markLocalMutation();
        _schedulePersist();
      } on Object catch (error) {
        contentFailure = '$error';
        editor.editable = false;
        localSave = LocalSaveState.failed;
      }
      notifyListeners();
    });
  }
  final DocumentCore core;
  final DocumentStore store;
  final CollaborationProvider? provider;
  final String objectId, handle;
  final bool editable;
  late final EditorState editor;
  late final StreamSubscription<EditorTransactionValue> _subscription;
  Timer? _timer;
  Map<String, dynamic> _state;
  Future<void> _writes = Future.value();
  Future<void>? _syncing;
  bool _disposed = false, _paused = false, _closing = false;
  bool _realtimeListening = false,
      _remoteCanRead = true,
      _remoteCanWrite = true;
  int _localMutationEpoch = 0, _acceptedLocalEpoch = 0;
  int _checkpointEpoch = 0;
  Future<void> _projections = Future.value();
  Future<void>? _closeFuture;
  bool get canRead => _remoteCanRead;
  bool get isClosed => _disposed || _closing;
  Future<void> get projectionReady => _projections;
  DocumentOutline get outline =>
      DocumentOutline.decode(objectId, _state['outline']);
  bool get collaborationPaused => _paused;
  int get localMutationEpoch => _localMutationEpoch;
  bool get hasPendingLocalChanges => _localMutationEpoch > _acceptedLocalEpoch;
  DocumentSyncState? _terminalSyncState;
  int _generation = 0;
  bool _resyncRequested = false;
  LocalSaveState localSave = LocalSaveState.dirty;
  DocumentSyncState syncState = DocumentSyncState.localOnly;
  String? contentFailure, persistenceFailure, collaborationFailure;
  String? get failure =>
      contentFailure ?? persistenceFailure ?? collaborationFailure;
  bool get canWrite =>
      editable &&
      !_disposed &&
      !_closing &&
      _remoteCanRead &&
      _remoteCanWrite &&
      contentFailure == null &&
      _terminalSyncState == null;
  int get revision => _state['revision'] as int;
  Map<String, dynamic> get snapshot =>
      jsonDecode(jsonEncode(_state)) as Map<String, dynamic>;
  List<Node> get blocks => editor.document.root.children;

  static Future<SmartDocumentController> open({
    required DocumentCore core,
    required DocumentStore store,
    required String objectId,
    String? initialDocState,
    CollaborationProvider? provider,
    bool editable = true,
    bool createRemote = false,
    Duration? syncInterval = const Duration(seconds: 1),
  }) async {
    if (provider != null &&
        !provider.binding.compatibleWith(smartDocumentCollaborationBinding)) {
      provider.close();
      throw const SmartDocumentFailure('INCOMPATIBLE_COLLABORATION_BINDING');
    }
    final local = await store.read();
    if (local != null && local['objectId'] != objectId)
      throw const SmartDocumentFailure('CACHE_OBJECT_MISMATCH');
    Uint8List? remote;
    Object? openingFailure;
    if (provider != null) {
      try {
        remote = await provider.readState(objectId);
      } on Object catch (e) {
        openingFailure = e;
      }
    }
    final seed =
        local?['docState'] as String? ??
        initialDocState ??
        (remote == null ? null : base64Encode(remote));
    if (provider != null && seed == null && !createRemote)
      throw const SmartDocumentFailure('SOURCE_UNAVAILABLE');
    final state = core.call({
      'action': 'open',
      'objectId': objectId,
      if (seed != null) 'docState': seed,
    });
    final controller = SmartDocumentController._(
      core,
      store,
      provider,
      objectId,
      state,
      state['handle'] as String,
      editable,
    );
    if (local?['pendingLocalChanges'] == true) {
      controller._localMutationEpoch = 1;
    }
    try {
      if (remote != null && (local != null || initialDocState != null)) {
        controller._state = core.call({
          'action': 'applyUpdate',
          'handle': controller.handle,
          'update': base64Encode(remote),
        });
        await controller._projectRemote();
      }
      await controller._persist();
      if (openingFailure != null) {
        controller.collaborationFailure = '$openingFailure';
        controller._recordCollaborationFailure(openingFailure);
      } else if (provider != null) {
        if (remote == null) {
          if (!createRemote || !editable)
            throw const SmartDocumentFailure('REMOTE_NOT_FOUND');
          await provider.initializeState(
            objectId,
            base64Decode(controller._state['encodedCollab'] as String),
          );
        }
        if (editable) await controller.synchronize();
      }
      if (provider != null && syncInterval != null) {
        controller._timer = Timer.periodic(syncInterval, (_) {
          if (!controller._paused && !controller._realtimeListening) {
            unawaited(controller.synchronize());
          }
        });
      }
      return controller;
    } on Object {
      await controller.close();
      rethrow;
    }
  }

  static String _rootId(Map<String, dynamic> state) =>
      state['data']['page_id'] as String;
  static Node _node(Map<String, dynamic> state, String id) {
    final data = state['data'] as Map;
    final block = data['blocks'][id] as Map;
    final attrs = Map<String, dynamic>.from(block['data'] as Map);
    final external = block['external_id'];
    if (external != null) {
      attrs['delta'] = jsonDecode(
        data['meta']['text_map'][external] as String? ?? '[]',
      );
    }
    final children =
        data['meta']['children_map'][block['children']] as List? ?? [];
    return Node(
      id: id,
      type: block['ty'] as String,
      attributes: attrs,
      children: children
          .cast<String>()
          .map((child) => _node(state, child))
          .toList(),
    );
  }

  static Map<String, dynamic> _serializedNode(Node node) => {
    'id': node.id,
    'type': node.type,
    'data': node.attributes,
    'children': node.children.map(_serializedNode).toList(),
  };
  static Iterable<Map<String, dynamic>> _operations(Operation op) sync* {
    switch (op) {
      case InsertOperation():
        yield {
          'op': 'insert',
          'path': op.path,
          'nodes': op.nodes.map(_serializedNode).toList(),
        };
      case DeleteOperation():
        yield {'op': 'delete', 'path': op.path, 'count': op.nodes.length};
      case UpdateOperation():
        final attributes = Map<String, dynamic>.from(op.attributes)
          ..remove('delta');
        if (attributes.isNotEmpty)
          yield {'op': 'update', 'path': op.path, 'attributes': attributes};
        // AppFlowy oldAttributes is a sparse inverse patch. An unchanged
        // delta can be carried with block attributes but is absent in the
        // inverse. Treating that absence as [] duplicates the full text.
        if (op.attributes.containsKey('delta') &&
            op.oldAttributes.containsKey('delta')) {
          final before = Delta.fromJson(
            op.oldAttributes['delta'] as List? ?? [],
          );
          final after = Delta.fromJson(op.attributes['delta'] as List? ?? []);
          final delta = before.diff(after);
          if (delta.isNotEmpty)
            yield {
              'op': 'update_text',
              'path': op.path,
              'delta': delta.toJson(),
            };
        }
      case UpdateTextOperation():
        yield {
          'op': 'update_text',
          'path': op.path,
          'delta': op.delta.toJson(),
        };
    }
  }

  void _markLocalMutation() {
    _localMutationEpoch++;
    localSave = LocalSaveState.dirty;
    syncState = provider == null
        ? DocumentSyncState.localOnly
        : DocumentSyncState.pending;
  }

  void _schedulePersist() {
    _checkpointEpoch++;
    final write = _writes.then(
      (_) => _persist(),
      onError: (Object _) => _persist(),
    );
    _writes = write;
    // Background failures are visible, while flush still receives the failure.
    unawaited(write.catchError((Object _) {}));
  }

  Future<void> _persist() async {
    final version = _checkpointEpoch;
    final checkpoint = {
      'profile': 'muse.smart-document/phase1',
      'objectId': objectId,
      'docState': _state['docState'],
      'pendingLocalChanges': hasPendingLocalChanges,
    };
    try {
      await store.write(checkpoint);
      persistenceFailure = null;
      if (_checkpointEpoch == version) localSave = LocalSaveState.durable;
    } on Object catch (error) {
      localSave = LocalSaveState.failed;
      persistenceFailure = '$error';
      rethrow;
    } finally {
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> flush() async {
    if (contentFailure != null)
      throw const SmartDocumentFailure('CONTENT_OPERATION_REJECTED');
    if (localSave == LocalSaveState.failed) _schedulePersist();
    while (true) {
      final pending = _writes;
      await pending;
      if (!identical(pending, _writes)) continue;
      if (localSave == LocalSaveState.durable) return;
      _schedulePersist();
    }
  }

  /// The content domain owns reconciliation. The socket only carries original
  /// AppFlowy updates; it has no authority to mark local changes durable.
  Future<void> applyRealtimeUpdate(Uint8List update) async {
    if (_disposed ||
        _closing ||
        _paused ||
        !_remoteCanRead ||
        _terminalSyncState != null)
      return;
    final changed = await _applyRemoteState({
      'action': 'applyUpdate',
      'handle': handle,
      'update': base64Encode(update),
    });
    if (!changed) return;
    localSave = LocalSaveState.dirty;
    if (_disposed) return;
    _schedulePersist();
    await flush();
    notifyListeners();
  }

  /// Called only by an authenticated, object-bound realtime adapter.
  void acceptRealtimeAccess({
    required bool canRead,
    required bool canWrite,
    required String reason,
  }) {
    if (_disposed || _closing) return;
    if (_terminalSyncState == DocumentSyncState.removed) return;
    final before = (_remoteCanRead, _remoteCanWrite, _terminalSyncState);
    _remoteCanRead = canRead;
    _remoteCanWrite = canRead && canWrite;
    // Only fresh authenticated object capabilities may recover a previous
    // HTTP denial. Pause/resume and reconnect alone never restore access.
    if (canRead && _terminalSyncState == DocumentSyncState.forbidden) {
      _terminalSyncState = null;
      collaborationFailure = null;
    }
    if (reason == 'deleted' || reason == 'object_deleted') {
      _terminalSyncState = DocumentSyncState.removed;
    }
    if (before != (_remoteCanRead, _remoteCanWrite, _terminalSyncState)) {
      _generation++;
      if (_syncing != null) _resyncRequested = true;
    }
    if (!canRead) {
      syncState = _terminalSyncState ?? DocumentSyncState.forbidden;
    } else if (_terminalSyncState == null) {
      syncState = hasPendingLocalChanges
          ? DocumentSyncState.pending
          : DocumentSyncState.accepted;
    }
    editor.editable = this.canWrite;
    notifyListeners();
  }

  void setRealtimeListening(bool value) {
    if (_disposed) return;
    _realtimeListening = value;
  }

  void pauseCollaboration(bool value) {
    if (_disposed || _closing) return;
    if (_paused != value) {
      _generation++;
      if (_syncing != null && !value) _resyncRequested = true;
    }
    _paused = value;
    if (_terminalSyncState != null) {
      syncState = _terminalSyncState!;
      notifyListeners();
      return;
    }
    syncState = provider == null
        ? DocumentSyncState.localOnly
        : value
        ? DocumentSyncState.paused
        : DocumentSyncState.pending;
    notifyListeners();
    if (!value) unawaited(synchronize());
  }

  Future<void> synchronize() {
    if (_disposed ||
        _closing ||
        _paused ||
        !_remoteCanRead ||
        provider == null ||
        _terminalSyncState != null)
      return Future.value();
    return _syncing ??= _exchange().whenComplete(() {
      _syncing = null;
      if (_resyncRequested) {
        _resyncRequested = false;
        // A stale response must settle before the current-authority repair;
        // this keeps one HTTP exchange in flight and preserves offline edits.
        unawaited(synchronize());
      }
    });
  }

  bool _exchangeCurrent(int generation) =>
      !_disposed &&
      !_closing &&
      generation == _generation &&
      !_paused &&
      _remoteCanRead &&
      _terminalSyncState == null;

  Future<void> _exchange() async {
    final generation = _generation;
    try {
      await flush();
      if (!_exchangeCurrent(generation)) return;
      syncState = DocumentSyncState.exchanging;
      notifyListeners();
      bool changed;
      final sentLocalEpoch = _localMutationEpoch;
      final sentWrites = canWrite;
      if (sentWrites) {
        final request = core.call({'action': 'syncRequest', 'handle': handle});
        final response = await provider!.exchange(
          objectId,
          base64Decode(request['body'] as String),
        );
        if (_disposed ||
            _closing ||
            generation != _generation ||
            _paused ||
            !_remoteCanRead)
          return;
        changed = await _applyRemoteState({
          'action': 'applySync',
          'handle': handle,
          'body': base64Encode(response),
        });
      } else {
        final remote = await provider!.readState(objectId);
        if (_disposed ||
            _closing ||
            generation != _generation ||
            _paused ||
            !_remoteCanRead)
          return;
        if (remote == null)
          throw const SmartDocumentFailure('REMOTE_NOT_FOUND');
        changed = await _applyRemoteState({
          'action': 'applyUpdate',
          'handle': handle,
          'update': base64Encode(remote),
        });
      }
      if (changed) {
        _schedulePersist();
        await flush();
      }
      if (!_exchangeCurrent(generation)) return;
      if (sentWrites) {
        _acceptedLocalEpoch = sentLocalEpoch;
        _schedulePersist();
        await flush();
      }
      if (!_exchangeCurrent(generation)) return;
      syncState = hasPendingLocalChanges
          ? DocumentSyncState.pending
          : DocumentSyncState.accepted;
      collaborationFailure = null;
    } on Object catch (error) {
      if (!_exchangeCurrent(generation)) return;
      _recordCollaborationFailure(error);
    }
    if (!_disposed && !_closing) notifyListeners();
  }

  void _recordCollaborationFailure(Object error) {
    collaborationFailure = '$error';
    if (error is SmartDocumentFailure) {
      if (error.code == 'FORBIDDEN')
        _terminalSyncState = DocumentSyncState.forbidden;
      if (error.code == 'OBJECT_DELETED')
        _terminalSyncState = DocumentSyncState.removed;
    }
    syncState = _terminalSyncState ?? DocumentSyncState.failed;
    if (_terminalSyncState != null) editor.editable = false;
  }

  Map<String, dynamic>? _capturePosition(Position position) {
    final node = editor.getNodeAtPath(position.path);
    if (node?.delta == null) return null;
    try {
      return core.call({
        'action': 'captureTextRange',
        'handle': handle,
        'blockId': node!.id,
        'start': position.offset,
        'end': position.offset,
      })..remove('text');
    } on Object {
      return null;
    }
  }

  Position? _resolvePosition(Map<String, dynamic> anchor) {
    try {
      final value = core.call({
        'action': 'resolveTextRange',
        'handle': handle,
        'anchor': anchor,
      });
      final node = resolveBlock(
        DocumentBlockReference(
          objectId: objectId,
          blockId: value['blockId'] as String,
        ),
      );
      return node == null
          ? null
          : Position(path: node.path, offset: value['start'] as int);
    } on Object {
      return null;
    }
  }

  Future<bool> _applyRemoteState(Map<String, dynamic> request) {
    final generation = _generation;
    final applied = _projections.then((_) async {
      if (_disposed ||
          _closing ||
          generation != _generation ||
          _paused ||
          !_remoteCanRead ||
          _terminalSyncState != null)
        return false;
      // Original EditorState transforms structural paths, but not text offsets.
      // Capture against the old Y.Text before merging; resolve against the new
      // text after projection. This also prevents a stale caret being published
      // as a newly captured awareness position after a remote prefix insert.
      final selection = editor.selection;
      final start = selection == null
          ? null
          : _capturePosition(selection.start);
      final end = selection == null ? null : _capturePosition(selection.end);
      _state = core.call(request);
      if (_state['changed'] != true) return false;
      await _projectCurrent();
      if (start != null && end != null) {
        final a = _resolvePosition(start), b = _resolvePosition(end);
        editor.selection = a == null || b == null
            ? null
            : Selection(start: a, end: b);
      }
      return true;
    });
    _projections = applied.then<void>((_) {}, onError: (Object _) {});
    return applied;
  }

  Future<void> _projectRemote() {
    final projection = _projections.then((_) => _projectCurrent());
    _projections = projection.catchError((Object _) {});
    return projection;
  }

  Future<void> _projectCurrent() async {
    if (_disposed) return;
    final desired = _node(_state, _rootId(_state));
    // Apply a remote transaction rather than replacing EditorState, preserving focus,
    // compatible node identity, selection mapping and local undo ownership.
    final transaction = editor.transaction;
    void reconcile(Node current, Node target) {
      final old = current.children;
      final fresh = target.children;
      final oldById = {for (final n in old) n.id: n};
      final keep = fresh
          .where((n) => oldById[n.id]?.type == n.type)
          .map((n) => n.id)
          .toSet();
      final priorOrder = old
          .where((n) => keep.contains(n.id))
          .map((n) => n.id)
          .toList();
      final nextOrder = fresh
          .where((n) => keep.contains(n.id))
          .map((n) => n.id)
          .toList();
      if (!listEquals(priorOrder, nextOrder)) {
        // Rebuild this sibling projection before touching descendants. Reusing
        // fresh child objects in a preceding recursive patch would detach them
        // from the fresh parent before that parent is inserted.
        for (final n in old.reversed) {
          transaction.add(DeleteOperation(n.path, [n]), transform: false);
        }
        for (var i = 0; i < fresh.length; i++) {
          transaction.add(
            InsertOperation(current.path + [i], [fresh[i]]),
            transform: false,
          );
        }
        return;
      }
      // Content updates precede sibling removals, so paths still address the
      // original projection. Structural actions then delete backwards/insert forwards.
      for (final n in fresh.where((n) => keep.contains(n.id))) {
        final existing = oldById[n.id]!;
        final patch = <String, dynamic>{};
        final keys = {...existing.attributes.keys, ...n.attributes.keys}
          ..remove('delta');
        for (final key in keys) {
          if (jsonEncode(existing.attributes[key]) !=
              jsonEncode(n.attributes[key]))
            patch[key] = n.attributes[key];
        }
        if (patch.isNotEmpty) transaction.updateNode(existing, patch);
        if (existing.delta != null && n.delta != null) {
          final delta = existing.delta!.diff(n.delta!);
          if (delta.isNotEmpty)
            transaction.add(
              UpdateTextOperation(
                existing.path,
                delta,
                delta.invert(existing.delta!),
              ),
            );
        }
        reconcile(existing, n);
      }
      {
        for (final n in old.reversed) {
          if (!keep.contains(n.id))
            transaction.add(DeleteOperation(n.path, [n]), transform: false);
        }
        for (var i = 0; i < fresh.length; i++) {
          if (!keep.contains(fresh[i].id))
            // i is an index in the final projection, not the original tree.
            // Do not transform it again through the preceding deletions.
            transaction.add(
              InsertOperation(current.path + [i], [fresh[i]]),
              transform: false,
            );
        }
      }
    }

    reconcile(editor.document.root, desired);
    if (transaction.operations.isNotEmpty) {
      await editor.apply(
        transaction,
        isRemote: true,
        options: const ApplyOptions(recordUndo: false),
      );
    }
  }

  Future<void> discardRejectedOperation() async {
    if (contentFailure == null) return;
    await _projectRemote();
    contentFailure = null;
    editor.editable = canWrite;
    _schedulePersist();
    await flush();
    notifyListeners();
  }

  bool get canUndo => _state['canUndo'] == true;
  bool get canRedo => _state['canRedo'] == true;
  Future<void> history({bool redo = false}) async {
    if (!canWrite || !editor.editable)
      throw const SmartDocumentFailure('READ_ONLY');
    _state = core.call({'action': redo ? 'redo' : 'undo', 'handle': handle});
    _markLocalMutation();
    await _projectRemote();
    _schedulePersist();
    await flush();
    notifyListeners();
  }

  Node? resolveBlock(DocumentBlockReference reference) {
    if (reference.objectId != objectId) {
      throw const SmartDocumentFailure('REFERENCE_OBJECT_MISMATCH');
    }
    final queue = [...blocks];
    while (queue.isNotEmpty) {
      final node = queue.removeLast();
      if (node.id == reference.blockId) return node;
      queue.addAll(node.children);
    }
    return null;
  }

  List<DocumentBlockReference> referencesForSelection([Selection? selection]) {
    selection ??= editor.selection;
    if (selection == null) return const [];
    return editor
        .getNodesInSelection(selection)
        .where((node) => node.delta != null && node.type != 'page')
        .map(
          (node) =>
              DocumentBlockReference(objectId: objectId, blockId: node.id),
        )
        .toList();
  }

  Future<void> convertSelection(
    String type, {
    int? level,
    bool attachTextService = true,
  }) => convertBlocks(
    referencesForSelection(),
    type,
    level: level,
    attachTextService: attachTextService,
  );

  /// Operate on stable block identities, never a stale path captured by a menu.
  Future<void> convertBlocks(
    List<DocumentBlockReference> targets,
    String type, {
    int? level,
    bool attachTextService = true,
  }) async {
    if (!canWrite || !editor.editable)
      throw const SmartDocumentFailure('READ_ONLY');
    if (targets.isEmpty) throw const SmartDocumentFailure('SELECTION_REQUIRED');
    final nodes = <Node>[];
    final seen = <String>{};
    for (final target in targets) {
      final node = resolveBlock(target);
      if (node == null) throw const SmartDocumentFailure('TARGET_MISSING');
      if (seen.add(node.id)) nodes.add(node);
    }
    final selection = editor.selection;
    final startId = selection == null
        ? null
        : editor.getNodeAtPath(selection.start.path)?.id;
    final endId = selection == null
        ? null
        : editor.getNodeAtPath(selection.end.path)?.id;
    final operations = [
      for (final node in nodes)
        if (node.type != type ||
            (type == 'heading' &&
                (node.attributes['level'] ?? 1) != (level ?? 1)))
          {
            'op': 'set_type',
            'blockId': node.id,
            'type': type,
            if (level != null) 'level': level,
          },
    ];
    if (operations.isEmpty) return;
    _state = core.call({
      'action': 'operations',
      'handle': handle,
      'operations': operations,
    });
    _markLocalMutation();
    await _projectRemote();
    // Text identity/content are unchanged by conversion; remap only tree paths.
    if (selection != null && startId != null && endId != null) {
      final start = resolveBlock(
        DocumentBlockReference(objectId: objectId, blockId: startId),
      );
      final end = resolveBlock(
        DocumentBlockReference(objectId: objectId, blockId: endId),
      );
      if (start != null && end != null) {
        editor.selectionExtraInfo = {
          selectionExtraInfoDoNotAttachTextService: !attachTextService,
        };
        editor.selection = Selection(
          start: selection.start.copyWith(path: start.path),
          end: selection.end.copyWith(path: end.path),
        );
      }
    }
    _schedulePersist();
    await flush();
    notifyListeners();
  }

  /// Consume a Markdown trigger as one CRDT undo unit without replacing its
  /// block or Y.Text. Prefix verification prevents applying a stale IME action.
  Future<void> formatMarkdownPrefix(
    String prefix,
    String type, {
    int? level,
    Map<String, dynamic> attributes = const {},
  }) async {
    if (!canWrite || !editor.editable)
      throw const SmartDocumentFailure('READ_ONLY');
    final selection = editor.selection;
    if (selection == null ||
        !selection.isCollapsed ||
        prefix.isEmpty ||
        selection.startIndex != prefix.length) {
      throw const SmartDocumentFailure('STALE_MARKDOWN_TRIGGER');
    }
    final node = editor.getNodeAtPath(selection.start.path);
    if (node == null ||
        !(node.delta?.toPlainText().startsWith(prefix) ?? false)) {
      throw const SmartDocumentFailure('STALE_MARKDOWN_TRIGGER');
    }
    final ref = DocumentBlockReference(objectId: objectId, blockId: node.id);
    _state = core.call({
      'action': 'operations',
      'handle': handle,
      'operations': [
        {
          'op': 'update_text',
          'path': node.path,
          'delta': [
            {'delete': prefix.length},
          ],
        },
        {
          'op': 'set_type',
          'blockId': node.id,
          'type': type,
          if (level != null) 'level': level,
        },
        if (attributes.isNotEmpty)
          {'op': 'update', 'path': node.path, 'attributes': attributes},
      ],
    });
    _markLocalMutation();
    await _projectRemote();
    final current = resolveBlock(ref)!;
    editor.selectionExtraInfo = {};
    editor.selection = Selection.collapsed(Position(path: current.path));
    _schedulePersist();
    await flush();
    notifyListeners();
  }

  Future<void> insertParagraph(String text) async {
    if (!canWrite || !editor.editable)
      throw const SmartDocumentFailure('READ_ONLY');
    final transaction = editor.transaction;
    transaction.insertNode(
      [blocks.length],
      paragraphNode(text: text),
      deepCopy: false,
    );
    await editor.apply(transaction);
    await flush();
  }

  /// Application command boundary used by domain adapters. UI surfaces never
  /// write storage/transport directly; the original core validates each batch.
  Future<void> executeDomainOperations(
    List<Map<String, dynamic>> operations,
  ) async {
    if (!canWrite || !editor.editable)
      throw const SmartDocumentFailure('READ_ONLY');
    _state = core.call({
      'action': 'operations',
      'handle': handle,
      'operations': operations,
    });
    _markLocalMutation();
    await _projectRemote();
    _schedulePersist();
    await flush();
    notifyListeners();
  }

  /// Root-level insertion address captured before opening a menu. Re-resolved
  /// when used, so a collaborator inserting a sibling cannot redirect the edit.
  DocumentBlockReference? get insertionAnchor {
    final path = editor.selection?.end.path;
    if (path == null || path.isEmpty || path.first >= blocks.length)
      return null;
    return DocumentBlockReference(
      objectId: objectId,
      blockId: blocks[path.first].id,
    );
  }

  Future<DocumentBlockReference> insertTable({
    int rows = 2,
    int columns = 2,
    DocumentBlockReference? after,
    bool attachTextService = true,
  }) async {
    if (!canWrite || !editor.editable)
      throw const SmartDocumentFailure('READ_ONLY');
    if (rows < 1 || rows > 20 || columns < 1 || columns > 10) {
      throw const SmartDocumentFailure('INVALID_TABLE_SIZE');
    }
    var index = blocks.length;
    if (after != null) {
      final target = resolveBlock(after);
      if (target == null) throw const SmartDocumentFailure('TARGET_MISSING');
      if (target.path.length != 1)
        throw const SmartDocumentFailure('ROOT_ANCHOR_REQUIRED');
      index = target.path.first + 1;
    }
    final table = Node(
      type: 'table',
      attributes: {
        'museTable': 'fixed-grid/1',
        'rowsLen': rows,
        'colsLen': columns,
      },
      children: [
        for (var col = 0; col < columns; col++)
          for (var row = 0; row < rows; row++)
            Node(
              type: 'table/cell',
              attributes: {'rowPosition': row, 'colPosition': col},
              children: [paragraphNode()],
            ),
      ],
    );
    final tx = editor.transaction
      ..insertNode([index], table, deepCopy: false)
      ..afterSelection = Selection.collapsed(Position(path: [index, 0, 0]))
      ..selectionExtraInfo = {
        selectionExtraInfoDoNotAttachTextService: !attachTextService,
      };
    await editor.apply(tx);
    await flush();
    return DocumentBlockReference(objectId: objectId, blockId: table.id);
  }

  Future<void> deleteTable(DocumentBlockReference reference) async {
    if (!canWrite || !editor.editable)
      throw const SmartDocumentFailure('READ_ONLY');
    final table = resolveBlock(reference);
    if (table == null) throw const SmartDocumentFailure('TARGET_MISSING');
    if (table.type != 'table') throw const SmartDocumentFailure('NOT_TABLE');
    final tx = editor.transaction..deleteNode(table);
    final remaining = blocks
        .where((n) => n.id != table.id && n.delta != null)
        .firstOrNull;
    if (remaining == null) {
      final paragraph = paragraphNode();
      tx.insertNode([0], paragraph, deepCopy: false);
      tx.afterSelection = Selection.collapsed(Position(path: [0]));
    } else {
      final index =
          blocks.indexOf(remaining) -
          (remaining.path.first > table.path.first ? 1 : 0);
      tx.afterSelection = Selection.collapsed(Position(path: [index]));
    }
    await editor.apply(tx);
    await flush();
  }

  Future<void> close() => _closeFuture ??= _close().whenComplete(() {
    if (!_disposed) _closeFuture = null;
  });

  Future<void> _close() async {
    if (_disposed) return;
    _closing = true;
    _generation++;
    try {
      await _projections;
      await flush();
      _timer?.cancel();
      await _subscription.cancel();
      _disposed = true;
      provider?.close();
      core.call({'action': 'close', 'handle': handle});
      editor.dispose();
      super.dispose();
    } finally {
      if (!_disposed) _closing = false;
    }
  }
}

// AppFlowy keyboard and IME undo calls are routed to the domain CRDT undo stack,
// never to stale full-text snapshots that could erase a collaborator's inserts.
final class _DomainUndoManager extends UndoManager {
  _DomainUndoManager(this.controller) : super(200);
  final SmartDocumentController controller;
  @override
  void undo() {
    unawaited(controller.history());
  }

  @override
  void redo() {
    unawaited(controller.history(redo: true));
  }
}
