import 'package:flutter/material.dart';
import 'realtime_session.dart';

/// Shared desktop/mobile presence entry. Permission controls belong to the Host;
/// these avatars show authenticated active sessions, not the sharing ACL roster.
final class DocumentCollaboratorsView extends StatelessWidget {
  const DocumentCollaboratorsView({super.key, required this.session});
  final DocumentRealtimeSession session;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) => Semantics(
      label: '在线协作',
      child: TextButton(
        key: const ValueKey('smart-document.collaborators'),
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (_) => SafeArea(
            child: ListenableBuilder(
              listenable: session,
              builder: (context, _) => Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const ListTile(title: Text('在线协作者')),
                    if (session.collaborators.isEmpty)
                      const ListTile(title: Text('暂无其他在线协作者')),
                    for (final person in session.collaborators)
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: person.color,
                          child: const Icon(Icons.person, color: Colors.white),
                        ),
                        title: Text(person.name),
                      ),
                    if (!session.connected)
                      const ListTile(title: Text('正在重新连接，本机修改仍保留')),
                  ],
                ),
              ),
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final person in session.collaborators.take(3))
              Padding(
                padding: const EdgeInsets.only(right: 3),
                child: CircleAvatar(
                  radius: 13,
                  backgroundColor: person.color,
                  child: const Icon(
                    Icons.person,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            if (session.collaborators.isEmpty)
              const Icon(Icons.group_outlined, size: 20),
            const SizedBox(width: 4),
            Text('${session.collaborators.length + 1} 人'),
          ],
        ),
      ),
    ),
  );
}
