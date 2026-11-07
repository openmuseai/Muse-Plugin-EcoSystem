import 'package:flutter/material.dart';
import 'package:muse_collab_widgets/muse_collab_widgets.dart';
import 'realtime_session.dart';

final class DatasetCollaboratorsView extends StatelessWidget {
  const DatasetCollaboratorsView({super.key, required this.session});
  final DatasetRealtimeSession session;
  @override
  Widget build(BuildContext context) => CollaboratorsButton(
    buttonKey: const ValueKey('dataset.collaborators'),
    listenable: session,
    people: () => [
      for (final p in session.collaborators)
        CollaborationPerson(
          name: p.name,
          color: collaboratorSlotColor(p.clientId),
        ),
    ],
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
      return collaboratorSlotColor(p.clientId);
  }
  return null;
}
