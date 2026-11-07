import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:muse_appflowy_transport/muse_appflowy_transport.dart';
import 'core_api.dart';
export 'package:muse_collab_contract/muse_collab_contract.dart';

/// Document-domain adapter. The reusable transport knows no editor, paragraph,
/// cell, asset or content schema implementation. Other plugins supply bindings.
final class AppFlowyCollaborationProvider implements CollaborationProvider {
  AppFlowyCollaborationProvider({
    required Uri origin,
    required String workspaceId,
    required Future<String> Function() accessToken,
    required String deviceId,
    http.Client? client,
  }) : _transport = AppFlowyObjectTransport(
         origin: origin,
         workspaceId: workspaceId,
         accessToken: accessToken,
         deviceId: deviceId,
         binding: smartDocumentCollaborationBinding,
         collabType: 0,
         client: client,
       );
  final AppFlowyObjectTransport _transport;
  Uri get origin => _transport.origin;
  String get workspaceId => _transport.workspaceId;
  @override
  CollaborationBinding get binding => _transport.binding;
  Future<T> _adapt<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AppFlowyTransportFailure catch (e) {
      throw SmartDocumentFailure(e.code);
    }
  }

  @override
  Future<Uint8List?> readState(String objectId) =>
      _adapt(() => _transport.readState(objectId));
  @override
  Future<void> initializeState(String objectId, Uint8List encodedCollab) =>
      _adapt(() => _transport.initializeState(objectId, encodedCollab));
  @override
  Future<Uint8List> exchange(String objectId, Uint8List request) =>
      _adapt(() => _transport.exchange(objectId, request));
  @override
  void close() => _transport.close();
}
