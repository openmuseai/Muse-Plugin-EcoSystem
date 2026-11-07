import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:muse_appflowy_realtime/muse_appflowy_realtime.dart';
import 'controller.dart';
import 'core_api.dart';
import 'row_reorder_buffer.dart';

/// Independent Database/Row application adapter over the same original WS2 and
/// awareness package used by documents. No document blocks/paths enter here.
final class DatasetRealtimeSession extends ChangeNotifier {
  DatasetRealtimeSession({
    required this.controller,
    required this.connection,
    required RealtimeWireCore presenceCore,
    this.displayName,
    this.repairInterval = const Duration(seconds: 20),
  }) : _presence = _openPresence(controller, connection, presenceCore) {
    _localEpoch = controller.localMutationEpoch;
    controller.addListener(_changed);
    _packets = connection.packets.listen(
      (packet) {
        _incoming = _incoming.then((_) => _receive(packet)).catchError((
          Object _,
        ) {
          if (!_closed) {
            failureCode = 'REALTIME_UPDATE_FAILED';
            _scheduleRepair();
            notifyListeners();
          }
        });
      },
      onError: (Object _) {
        if (!_closed) {
          failureCode = 'REALTIME_CONNECTION_LOST';
          notifyListeners();
        }
      },
    );
    _states = connection.states.listen(_connectionChanged);
    _heartbeat = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _publishPresence(),
    );
    _expiry = Timer.periodic(const Duration(seconds: 1), (_) {
      _buffer.expire(_clock.elapsedMilliseconds);
      _projectPresence();
    });
    _repair = Timer.periodic(repairInterval, (_) {
      if (!_closed && !controller.collaborationPaused) {
        _manifest();
        _scheduleRepair();
      }
    });
  }
  static RealtimePresence _openPresence(
    DatasetController c,
    AppFlowyRealtimeConnection wire,
    RealtimeWireCore core,
  ) {
    final scope = c.realtimeScope;
    if (scope == null ||
        scope.origin.origin != wire.origin.origin ||
        scope.workspaceId.toLowerCase() != wire.workspaceId.toLowerCase()) {
      throw const DatasetFailure('REALTIME_SCOPE_MISMATCH');
    }
    return RealtimePresence(
      core: core,
      objectId: c.objectId,
      clientId: wire.clientId,
    );
  }

  final DatasetController controller;
  final AppFlowyRealtimeConnection connection;
  final String Function(String uid)? displayName;
  final Duration repairInterval;
  final RealtimePresence _presence;
  final _clock = Stopwatch()..start();
  final _buffer = DatasetRowReorderBuffer();
  final Set<String> _manifested = {}, _dirty = {};
  late final StreamSubscription<RealtimePacket> _packets;
  late final StreamSubscription<RealtimeConnectionState> _states;
  late final Timer _heartbeat, _expiry, _repair;
  Timer? _sendDebounce, _syncDebounce, _retry;
  Future<void> _incoming = Future.value();
  Future<void>? _closing;
  bool _closed = false;
  int _localEpoch = 0, _retryCount = 0;
  int remoteUpdatesApplied = 0, droppedUnassociatedFrames = 0;
  String? failureCode;
  Map<String, dynamic>? _selection;
  List<DatasetCollaborator> _collaborators = const [];
  List<DatasetCollaborator> get collaborators => _collaborators;
  int get bufferedRowObjects => _buffer.objects;
  bool get connected => connection.state == RealtimeConnectionState.connected;
  // Until the Grid exposes an explicit visible-row window, bound subscriptions
  // to 128 referenced rows. HTTP repair covers rows outside this window.
  Set<String> get _watched => controller.rowObjectIds.take(128).toSet();
  Future<void> start() async {
    if (_closed) return;
    try {
      await connection.connect();
    } on Object {
      if (!_closed) {
        failureCode = 'REALTIME_UNAVAILABLE';
        _reconnect();
        notifyListeners();
      }
    }
  }

  void _connectionChanged(RealtimeConnectionState value) {
    if (_closed) return;
    controller.setRealtimeListening(value == RealtimeConnectionState.connected);
    if (value == RealtimeConnectionState.connected) {
      _manifested.clear();
      _retryCount = 0;
      _retry?.cancel();
      failureCode = null;
      _manifest();
      _publishPresence();
      _scheduleRepair();
      _sendLocal();
    } else if (value == RealtimeConnectionState.disconnected) {
      _buffer.clear();
      _reconnect();
    }
    notifyListeners();
  }

  void _reconnect() {
    if (_closed || _retry?.isActive == true) return;
    final seconds = [1, 2, 4, 8, 15][_retryCount.clamp(0, 4)];
    _retryCount++;
    _retry = Timer(Duration(seconds: seconds), () => unawaited(start()));
  }

  void _scheduleRepair() {
    if (_closed || controller.collaborationPaused) return;
    _syncDebounce?.cancel();
    _syncDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!_closed) unawaited(controller.synchronize());
    });
  }

  void _manifest({bool onlyNew = false}) {
    if (_closed || !connected || controller.collaborationPaused) return;
    final ids = {controller.objectId, ..._watched};
    _manifested.removeWhere((id) => !ids.contains(id));
    for (final id in ids) {
      if (onlyNew && _manifested.contains(id)) continue;
      try {
        final state = controller.realtimeManifestState(id);
        connection.send(
          RealtimeManifest(
            objectId: id,
            collabType: state['collabType'] as int,
            stateVector: base64Decode(state['stateVector'] as String),
          ),
        );
        _manifested.add(id);
      } on Object {
        /* Missing/denied objects remain fenced; HTTP/ACL repair owns recovery. */
      }
    }
  }

  void _changed() {
    if (_closed) return;
    if (_localEpoch != controller.localMutationEpoch) {
      _localEpoch = controller.localMutationEpoch;
      _dirty.add(controller.lastMutationObjectId);
      _scheduleRepair();
    }
    _dirty.removeWhere(
      (id) =>
          id != controller.objectId && !controller.rowObjectIds.contains(id),
    );
    if (_dirty.isNotEmpty) {
      _sendDebounce?.cancel();
      _sendDebounce = Timer(const Duration(milliseconds: 80), _sendLocal);
    }
    _manifest(onlyNew: true);
    _projectPresence();
  }

  void _sendLocal() {
    if (_closed ||
        !connected ||
        !controller.canWrite ||
        controller.collaborationPaused)
      return;
    for (final id in _dirty.toList()) {
      if (!controller.remoteObjectKnown(id)) continue;
      // Do not expose references until the existing HTTP path registered every
      // dependent row. A WS update never creates/authorizes a missing object.
      if (id == controller.objectId &&
          controller.rowObjectIds.any((r) => !controller.remoteObjectKnown(r)))
        continue;
      try {
        final state = controller.realtimeObjectState(id);
        if (state['loaded'] != true) continue;
        connection.send(
          RealtimeUpdate(
            objectId: id,
            collabType: state['collabType'] as int,
            update: base64Decode(state['docState'] as String),
          ),
        );
        _dirty.remove(id);
      } on Object {
        failureCode = 'REALTIME_SEND_FAILED';
      }
    }
  }

  Future<void> _receive(RealtimePacket packet) async {
    if (_closed || controller.collaborationPaused) return;
    if (packet is RealtimeNotification) {
      if (packet.data['event'] == 'permission' &&
          {controller.objectId, ..._watched}.contains(packet.data['objectId']))
        _manifest();
      return;
    }
    if (packet is! ObjectRealtimePacket) return;
    final root = packet.objectId == controller.objectId;
    if (packet is RealtimeAwareness) {
      if (root && controller.canRead) {
        _presence.apply(packet);
        _projectPresence();
      }
      return;
    }
    if (packet is RealtimeUpdate &&
        controller.canRead &&
        !root &&
        packet.collabType == 4 &&
        !controller.rowObjectIds.contains(packet.objectId)) {
      if (!_buffer.add(
        packet.objectId,
        packet.update,
        _clock.elapsedMilliseconds,
      ))
        droppedUnassociatedFrames++;
      return;
    }
    if ((root && packet.collabType != 1) ||
        (!root &&
            (packet.collabType != 4 || !_watched.contains(packet.objectId))))
      return;
    switch (packet) {
      case RealtimeAccess():
        controller.acceptRealtimeAccess(
          id: packet.objectId,
          collabType: packet.collabType,
          canRead: packet.canRead,
          canWrite: packet.canWrite,
          reason: packet.reason,
        );
        if (!controller.canRead) {
          _selection = null;
          _collaborators = const [];
          notifyListeners();
        }
      case RealtimeManifest():
        _scheduleRepair();
      case RealtimeUpdate():
        final changed = await controller.applyRealtimeUpdate(
          packet.objectId,
          packet.collabType,
          packet.update,
        );
        if (changed) remoteUpdatesApplied++;
        if (_closed) return;
        if (root) {
          for (final row in _watched) {
            for (final update in _buffer.take(
              row,
              _clock.elapsedMilliseconds,
            )) {
              try {
                final changed = await controller.applyRealtimeUpdate(
                  row,
                  4,
                  update,
                );
                if (changed) remoteUpdatesApplied++;
              } on Object {
                _scheduleRepair();
              }
            }
          }
          _manifest(onlyNew: true);
        }
        _projectPresence();
      case RealtimeAwareness():
        break;
    }
  }

  void selectCell({
    required String viewId,
    required String rowId,
    required String fieldId,
    bool editing = false,
  }) {
    final view = controller.views.where((v) => v.id == viewId).firstOrNull;
    if (view == null ||
        !view.rows.any((r) => r.id == rowId) ||
        !view.columns.any((f) => f.id == fieldId)) {
      throw const DatasetFailure('CELL_SCOPE_MISMATCH');
    }
    _selection = {
      'viewId': viewId,
      'rowId': rowId,
      'fieldId': fieldId,
      'editing': editing,
    };
    _publishPresence();
  }

  void clearSelection() {
    _selection = null;
    _publishPresence();
  }

  void _publishPresence() {
    if (_closed ||
        !connected ||
        !controller.canRead ||
        controller.collaborationPaused)
      return;
    try {
      connection.send(
        _presence.update({
          'schema': 'muse.dataset.presence/1',
          if (_selection != null) 'cell': _selection,
        }, collabType: 1),
      );
    } on Object {
      failureCode = 'PRESENCE_SEND_FAILED';
    }
  }

  void _projectPresence() {
    if (_closed) return;
    final next = <DatasetCollaborator>[];
    if (controller.canRead) {
      for (final client in _presence.clients) {
        final uid = client.actorUid;
        if (client.local ||
            uid == null ||
            client.state['schema'] != 'muse.dataset.presence/1')
          continue;
        final raw = client.state['cell'];
        Map<String, dynamic>? cell;
        if (raw is Map &&
            raw.keys.toSet().difference({
              'viewId',
              'rowId',
              'fieldId',
              'editing',
            }).isEmpty &&
            raw['editing'] is bool) {
          final view = controller.views
              .where((v) => v.id == raw['viewId'])
              .firstOrNull;
          if (view != null &&
              view.rows.any((r) => r.id == raw['rowId']) &&
              view.columns.any((f) => f.id == raw['fieldId']))
            cell = Map<String, dynamic>.from(raw);
        }
        next.add(
          DatasetCollaborator(
            clientId: client.clientId,
            uid: uid,
            name: displayName?.call(uid) ?? '协作者',
            cell: cell,
          ),
        );
      }
    }
    next.sort((a, b) => a.uid.compareTo(b.uid));
    if (jsonEncode(next.map((c) => c.toJson()).toList()) !=
        jsonEncode(_collaborators.map((c) => c.toJson()).toList())) {
      _collaborators = List.unmodifiable(next);
      notifyListeners();
    }
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    if (_closed) return;
    if (connected) {
      try {
        connection.send(_presence.leave(collabType: 1));
      } on Object {}
    }
    _closed = true;
    controller.setRealtimeListening(false);
    controller.removeListener(_changed);
    _heartbeat.cancel();
    _expiry.cancel();
    _repair.cancel();
    _retry?.cancel();
    _sendDebounce?.cancel();
    _syncDebounce?.cancel();
    await _packets.cancel();
    await _states.cancel();
    await _incoming;
    await connection.close();
    _presence.close();
    _buffer.clear();
    _clock.stop();
    dispose();
  }
}

final class DatasetCollaborator {
  DatasetCollaborator({
    required this.clientId,
    required this.uid,
    required this.name,
    Map<String, dynamic>? cell,
  }) : cell = cell == null ? null : Map.unmodifiable(cell);
  final String uid, name, clientId;
  final Map<String, dynamic>? cell;
  Map<String, dynamic> toJson() => {
    'clientId': clientId,
    'uid': uid,
    'name': name,
    'cell': cell,
  };
}
