import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

void main() => runApp(const EditorPluginApp());

class EditorPluginApp extends StatelessWidget {
  const EditorPluginApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AppFlowy Editor',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF465E4E)),
      scaffoldBackgroundColor: const Color(0xFFF7F6F3),
    ),
    home: const EditorPage(),
  );
}

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  static const storageKey = 'appflowy-editor-plugin.document.v1';
  late final EditorState state;
  late final StreamSubscription<Object?> changes;
  final title = TextEditingController(text: '无标题文档');
  Timer? autosave;
  String status = '已保存到此设备';

  @override
  void initState() {
    super.initState();
    final raw = html.window.localStorage[storageKey];
    try {
      final saved = raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
      state = EditorState(document: saved == null
          ? EditorState.blank(withInitialText: true).document
          : Document.fromJson(saved['document'] as Map<String, dynamic>));
      title.text = saved?['title'] as String? ?? title.text;
    } catch (_) {
      state = EditorState.blank(withInitialText: true);
    }
    changes = state.transactionStream.listen((_) => _scheduleSave());
    title.addListener(_scheduleSave);
  }

  void _scheduleSave() {
    if (!mounted) return;
    setState(() => status = '正在编辑…');
    autosave?.cancel();
    autosave = Timer(const Duration(milliseconds: 650), _save);
  }

  void _save() {
    html.window.localStorage[storageKey] = jsonEncode({
      'title': title.text,
      'document': state.document.toJson(),
    });
    if (mounted) setState(() => status = '已保存到此设备');
  }

  void _export() {
    _save();
    final data = jsonEncode({'title': title.text, 'document': state.document.toJson()});
    final blob = html.Blob([data], 'application/json');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..download = '${title.text.trim().isEmpty ? 'untitled' : title.text.trim()}.appflowy.json'
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  @override
  void dispose() {
    autosave?.cancel();
    changes.cancel();
    title.dispose();
    state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 620;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F6F3),
        title: const Text('AppFlowy Editor', style: TextStyle(fontFamily: 'Georgia', fontSize: 19)),
        actions: [
          if (!compact) Padding(padding: const EdgeInsets.only(right: 12), child: Center(child: Text(status, style: const TextStyle(fontSize: 12, color: Color(0xFF888B84))))),
          TextButton.icon(onPressed: _export, icon: const Icon(Icons.download_outlined, size: 17), label: Text(compact ? '导出' : '导出 JSON')),
          const SizedBox(width: 12),
        ],
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 870),
          margin: EdgeInsets.symmetric(horizontal: compact ? 0 : 18, vertical: compact ? 0 : 18),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(compact ? 0 : 12), border: Border.all(color: const Color(0xFFEAEAE5))),
          child: Column(children: [
            Padding(
              padding: EdgeInsets.fromLTRB(compact ? 20 : 48, compact ? 18 : 35, compact ? 20 : 48, 9),
              child: TextField(controller: title, maxLines: 1, style: TextStyle(fontFamily: 'Georgia', fontSize: compact ? 27 : 35), decoration: const InputDecoration(border: InputBorder.none, hintText: '文档标题')),
            ),
            Expanded(child: Padding(
              padding: EdgeInsets.fromLTRB(compact ? 20 : 48, 0, compact ? 20 : 48, 32),
              child: AppFlowyEditor(editorState: state),
            )),
            if (compact) Padding(padding: const EdgeInsets.all(8), child: Text(status, style: const TextStyle(fontSize: 11, color: Color(0xFF888B84)))),
          ]),
        ),
      ),
    );
  }
}
