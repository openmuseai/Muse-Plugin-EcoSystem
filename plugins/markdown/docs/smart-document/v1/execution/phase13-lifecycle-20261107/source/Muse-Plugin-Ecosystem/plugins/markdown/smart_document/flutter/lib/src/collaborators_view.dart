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
    people: () => [
      for (final p in session.collaborators)
        CollaborationPerson(name: p.name, color: p.color),
    ],
    connected: () => session.connected,
  );
}
