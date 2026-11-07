import 'package:flutter/material.dart';
import 'package:muse_collab_widgets/muse_collab_widgets.dart';
import 'realtime_session.dart';
import 'projection.dart';

final class DatasetCollaboratorsView extends StatelessWidget {
  const DatasetCollaboratorsView({super.key, required this.session});
  final DatasetRealtimeSession session;
  String? _location(DatasetCollaborator p, List<DatasetViewProjection> views) {
    final cell = p.cell;
    if (cell == null) return null;
    final view = views.where((v) => v.id == cell['viewId']).firstOrNull;
    final column = view?.columns
        .where((f) => f.id == cell['fieldId'])
        .firstOrNull;
    final index = view?.rows.indexWhere((r) => r.id == cell['rowId']) ?? -1;
    if (view == null || column == null || index < 0) return null;
    return '${view.name} · 第 ${index + 1} 条 · ${column.name}${cell['editing'] == true ? ' · 正在编辑' : ''}';
  }

  @override
  Widget build(BuildContext context) => CollaboratorsButton(
    buttonKey: const ValueKey('dataset.collaborators'),
    listenable: session,
    selfUid: () => session.connection.actorUid,
    selfSessionId: session.connection.clientId,
    people: () {
      final views = session.controller.views;
      return [
        for (final p in session.collaborators)
          CollaborationPerson(
            name: p.name,
            uid: p.uid,
            sessionId: p.clientId,
            location: _location(p, views),
          ),
      ];
    },
    connected: () => session.connected,
  );
}

Color? datasetRemoteCellColor(
  DatasetRealtimeSession? session,
  String view,
  String row,
  String field,
) {
  for (final p in session?.collaborators ?? const <DatasetCollaborator>[]) {
    if (p.cell?['viewId'] == view &&
        p.cell?['rowId'] == row &&
        p.cell?['fieldId'] == field)
      return collaboratorSlotColor(p.uid);
  }
  return null;
}
