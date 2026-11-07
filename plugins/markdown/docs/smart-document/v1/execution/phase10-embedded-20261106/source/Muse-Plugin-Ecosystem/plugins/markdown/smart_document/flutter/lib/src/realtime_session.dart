import 'dart:async';
import 'dart:convert';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:muse_appflowy_realtime/muse_appflowy_realtime.dart';
import 'controller.dart';
import 'cloud_provider.dart';
import 'core_api.dart';

/// A content-domain adapter over the independent AppFlowy wire/presence package.
/// No socket, bearer token or transient selection enters the content snapshot.
final class DocumentRealtimeSession extends ChangeNotifier {
  DocumentRealtimeSession({
    required this.controller,
    required this.connection,
    required RealtimeWireCore presenceCore,
    this.displayName,
  }) : _presence = _openPresence(controller, connection, presenceCore) {
    _localEpoch = controller.localMutationEpoch;
    controller.addListener(_documentChanged);
    controller.editor.selectionNotifier.addListener(_selectionChanged);
    _packets = connection.packets.listen(
      (packet) {
        final next = _incoming.then((_) => _receive(packet));
        _incoming = next.catchError((Object _) {
          if (!_closed) {
            failureCode = 'REALTIME_UPDATE_FAILED';
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
    _expiry = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _projectPresence(),
    );
    _repair = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!_closed && !controller.collaborationPaused) _manifest();
    });
  }
  static RealtimePresence _openPresence(
    SmartDocumentController controller,
    AppFlowyRealtimeConnection connection,
    RealtimeWireCore core,
  ) {
    final provider = controller.provider;
    if (provider is! AppFlowyCollaborationProvider ||
        provider.workspaceId.toLowerCase() !=
            connection.workspaceId.toLowerCase() ||
        provider.origin.origin != connection.origin.origin) {
      throw const SmartDocumentFailure('REALTIME_SCOPE_MISMATCH');
    }
    return RealtimePresence(
      core: core,
      objectId: controller.objectId,
      clientId: connection.clientId,
    );
  }

  final SmartDocumentController controller;
  final AppFlowyRealtimeConnection connection;

  /// Trusted Host profile resolver, indexed by the server-normalized UID.
  /// Client-provided names/roles from awareness are never rendered as identity.
  final String Function(String uid)? displayName;
  final RealtimePresence _presence;
  late final StreamSubscription<RealtimePacket> _packets;
  late final StreamSubscription<RealtimeConnectionState> _states;
  late final Timer _heartbeat, _expiry, _repair;
  Timer? _selectionDebounce, _sendDebounce, _syncDebounce, _retry;
  Future<void> _incoming = Future.value();
  Future<void>? _closing;
  bool _closed = false;
  int _localEpoch = 0, _retryCount = 0;
  String? failureCode;
  List<DocumentCollaborator> _collaborators = const [];
  List<DocumentCollaborator> get collaborators => _collaborators;
  bool get connected => connection.state == RealtimeConnectionState.connected;
  Future<void> start() async {
    if (_closed) return;
    try {
      await connection.connect();
    } on Object {
      if (!_closed) {
        failureCode = 'REALTIME_UNAVAILABLE';
        _scheduleReconnect();
        notifyListeners();
      }
    }
  }

  void _connectionChanged(RealtimeConnectionState value) {
    if (_closed) return;
    final ready = value == RealtimeConnectionState.connected;
    controller.setRealtimeListening(ready);
    if (ready) {
      failureCode = null;
      _retryCount = 0;
      _retry?.cancel();
      _manifest();
      _publishPresence();
      if (controller.hasPendingLocalChanges) _sendLocal();
    } else if (value == RealtimeConnectionState.disconnected) {
      _scheduleReconnect();
    }
    notifyListeners();
  }

  void _scheduleReconnect() {
    if (_closed || _retry?.isActive == true) return;
    final delay = [1, 2, 4, 8, 15][_retryCount.clamp(0, 4)];
    _retryCount++;
    _retry = Timer(Duration(seconds: delay), () => unawaited(start()));
  }

  void _manifest() {
    if (_closed || !connected || controller.collaborationPaused) return;
    try {
      connection.send(
        RealtimeManifest(
          objectId: controller.objectId,
          collabType: 0,
          stateVector: base64Decode(
            controller.snapshot['stateVector'] as String,
          ),
        ),
      );
    } on Object {
      failureCode = 'REALTIME_SEND_FAILED';
    }
  }

  void _documentChanged() {
    if (_closed) return;
    _projectPresence();
    if (_localEpoch == controller.localMutationEpoch) return;
    _localEpoch = controller.localMutationEpoch;
    _sendDebounce?.cancel();
    _sendDebounce = Timer(const Duration(milliseconds: 80), _sendLocal);
    _syncDebounce?.cancel();
    _syncDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!_closed) unawaited(controller.synchronize());
    });
  }

  void _sendLocal() {
    if (_closed ||
        !connected ||
        !controller.canWrite ||
        controller.collaborationPaused)
      return;
    try {
      // Original Yrs v1 update; duplicate HTTP repair is idempotent. Redis RID
      // is not a durable ACK. Only the existing HTTP exchange marks acceptance.
      connection.send(
        RealtimeUpdate(
          objectId: controller.objectId,
          collabType: 0,
          update: base64Decode(controller.snapshot['docState'] as String),
        ),
      );
    } on Object {
      failureCode = 'REALTIME_SEND_FAILED';
    }
  }

  Future<void> _receive(RealtimePacket packet) async {
    if (_closed) return;
    if (packet is RealtimeNotification) {
      if (packet.data['event'] == 'permission' &&
          packet.data['objectId'] == controller.objectId)
        _manifest();
      return;
    }
    if (packet is! ObjectRealtimePacket ||
        packet.objectId != controller.objectId)
      return;
    if (packet is RealtimeAwareness) {
      if (!controller.canRead) return;
      _presence.apply(packet);
      _projectPresence();
    } else if (packet.collabType == 0) {
      switch (packet) {
        case RealtimeUpdate():
          await controller.applyRealtimeUpdate(packet.update);
          _projectPresence();
        case RealtimeAccess():
          controller.acceptRealtimeAccess(
            canRead: packet.canRead,
            canWrite: packet.canWrite,
            reason: packet.reason,
          );
          if (!packet.canRead) {
            controller.editor.remoteSelections.value = [];
            _collaborators = const [];
            notifyListeners();
          }
        case RealtimeManifest():
          await controller.synchronize();
          if (controller.hasPendingLocalChanges) _sendLocal();
        default:
          break;
      }
    }
  }

  void _selectionChanged() {
    if (_closed) return;
    _selectionDebounce?.cancel();
    _selectionDebounce = Timer(
      const Duration(milliseconds: 100),
      _publishPresence,
    );
  }

  Map<String, dynamic>? _capture(Position position) {
    final node = controller.editor.getNodeAtPath(position.path);
    if (node?.delta == null) return null;
    try {
      return Map<String, dynamic>.of(
        controller.core.call({
          'action': 'captureTextRange',
          'handle': controller.handle,
          'blockId': node!.id,
          'start': position.offset,
          'end': position.offset,
        }),
      )..remove('text');
    } on Object {
      return null;
    }
  }

  void _publishPresence() {
    if (_closed ||
        !connected ||
        !controller.canRead ||
        controller.collaborationPaused)
      return;
    try {
      final selection = controller.editor.selection;
      final start = selection == null ? null : _capture(selection.start);
      final end = selection == null ? null : _capture(selection.end);
      connection.send(
        _presence.update({
          'schema': 'muse.document.presence/1',
          if (start != null && end != null)
            'selection': {'start': start, 'end': end},
        }, collabType: 0),
      );
    } on Object {
      failureCode = 'PRESENCE_SEND_FAILED';
    }
  }

  Position? _resolve(dynamic value) {
    if (value is! Map || value['objectId'] != controller.objectId) return null;
    try {
      final resolved = controller.core.call({
        'action': 'resolveTextRange',
        'handle': controller.handle,
        'anchor': value,
      });
      final node = controller.resolveBlock(
        DocumentBlockReference(
          objectId: controller.objectId,
          blockId: resolved['blockId'] as String,
        ),
      );
      if (node?.delta == null) return null;
      return Position(path: node!.path, offset: resolved['start'] as int);
    } on Object {
      return null;
    }
  }

  void _projectPresence() {
    if (_closed || !controller.canRead) return;
    final people = <DocumentCollaborator>[];
    final selections = <RemoteSelection>[];
    for (final client in _presence.clients) {
      final uid = client.actorUid;
      if (client.local ||
          uid == null ||
          client.state['schema'] != 'muse.document.presence/1')
        continue;
      final colorIndex =
          client.clientId.codeUnits.fold<int>(
            0,
            (a, b) => (a * 31 + b) & 0x7fffffff,
          ) %
          _colors.length;
      final color = _colors[colorIndex];
      final name = displayName?.call(uid) ?? '协作者';
      people.add(
        DocumentCollaborator(
          clientId: client.clientId,
          uid: uid,
          name: name,
          color: color,
        ),
      );
      final range = client.state['selection'];
      if (range is Map) {
        final start = _resolve(range['start']), end = _resolve(range['end']);
        if (start != null && end != null) {
          selections.add(
            RemoteSelection(
              id: client.clientId,
              selection: Selection(start: start, end: end),
              selectionColor: color.withValues(alpha: .18),
              cursorColor: color,
            ),
          );
        }
      }
    }
    controller.editor.remoteSelections.value = selections;
    final changed =
        jsonEncode(people.map((p) => [p.clientId, p.uid, p.name]).toList()) !=
        jsonEncode(
          _collaborators.map((p) => [p.clientId, p.uid, p.name]).toList(),
        );
    _collaborators = List.unmodifiable(people);
    if (changed) notifyListeners();
  }

  Future<void> close() => _closing ??= (() async {
    if (_closed) return;
    _closed = true;
    _heartbeat.cancel();
    _expiry.cancel();
    _repair.cancel();
    _retry?.cancel();
    _selectionDebounce?.cancel();
    _sendDebounce?.cancel();
    _syncDebounce?.cancel();
    controller.removeListener(_documentChanged);
    controller.editor.selectionNotifier.removeListener(_selectionChanged);
    controller.setRealtimeListening(false);
    try {
      if (connected) connection.send(_presence.leave(collabType: 0));
    } on Object {}
    await _packets.cancel();
    await _states.cancel();
    await _incoming;
    await connection.close();
    _presence.close();
    controller.editor.remoteSelections.value = [];
    super.dispose();
  })();

  static const _colors = [
    Color(0xff6c5ce7),
    Color(0xff00897b),
    Color(0xffc75c21),
    Color(0xff1976d2),
    Color(0xffa7358b),
  ];
}

final class DocumentCollaborator {
  const DocumentCollaborator({
    required this.clientId,
    required this.uid,
    required this.name,
    required this.color,
  });
  final String clientId, uid, name;
  final Color color;
}
