import 'package:flutter/material.dart';
import 'package:muse_collab_widgets/muse_collab_widgets.dart';
import 'realtime_session.dart';

/// Resource-neutral shared UI; identity and text selection remain document-owned.
final class DocumentCollaboratorsView extends StatelessWidget {
  const DocumentCollaboratorsView({super.key, required this.session});
  final DocumentRealtimeSession session;
  @override
  Widget build(BuildContext context) => CollaboratorsButton(
    buttonKey: const ValueKey('smart-document.collaborators'),
    listenable: session,
    selfUid: () => session.connection.actorUid,
    selfSessionId: session.connection.clientId,
    people: () => [
      for (final p in session.collaborators)
        CollaborationPerson(
          uid: p.uid,
          sessionId: p.clientId,
          name: p.name,
          location: p.location,
        ),
    ],
    connected: () => session.connected,
  );
}
