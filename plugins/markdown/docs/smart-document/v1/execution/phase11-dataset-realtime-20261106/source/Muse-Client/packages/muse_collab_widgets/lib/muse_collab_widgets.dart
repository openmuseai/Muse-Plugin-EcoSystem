import 'package:flutter/material.dart';

/// Shared desktop/mobile presence entry. Permission controls belong to the Host;
/// these avatars show authenticated active sessions, not the sharing ACL roster.
final class CollaboratorsButton extends StatelessWidget {
  const CollaboratorsButton({
    super.key,
    required this.listenable,
    required this.people,
    required this.connected,
    this.buttonKey,
  });
  final Listenable listenable;
  final List<CollaborationPerson> Function() people;
  final bool Function() connected;
  final Key? buttonKey;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: listenable,
    builder: (context, _) => Semantics(
      label: '在线协作',
      child: TextButton(
        key: buttonKey,
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (_) => SafeArea(
            child: ListenableBuilder(
              listenable: listenable,
              builder: (context, _) => Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const ListTile(title: Text('在线协作者')),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          if (people().isEmpty)
                            const ListTile(title: Text('暂无其他在线协作者')),
                          for (final person in people())
                            ListTile(
                              leading: CircleAvatar(
                                backgroundColor: person.color,
                                child: const Icon(
                                  Icons.person,
                                  color: Colors.white,
                                ),
                              ),
                              title: Text(person.name),
                            ),
                          if (!connected())
                            const ListTile(title: Text('正在重新连接，本机修改仍保留')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final person in people().take(3))
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
            if (people().isEmpty) const Icon(Icons.group_outlined, size: 20),
            const SizedBox(width: 4),
            Text('${people().length + 1} 人'),
          ],
        ),
      ),
    ),
  );
}

final class CollaborationPerson {
  const CollaborationPerson({required this.name, required this.color});
  final String name;
  final Color color;
}

Color collaboratorSlotColor(String clientId) {
  const colors = [
    Color(0xff6c5ce7),
    Color(0xff00897b),
    Color(0xffc75c21),
    Color(0xff1976d2),
    Color(0xffa7358b),
  ];
  final index =
      clientId.codeUnits.fold<int>(0, (a, b) => (a * 31 + b) & 0x7fffffff) %
      colors.length;
  return colors[index];
}
