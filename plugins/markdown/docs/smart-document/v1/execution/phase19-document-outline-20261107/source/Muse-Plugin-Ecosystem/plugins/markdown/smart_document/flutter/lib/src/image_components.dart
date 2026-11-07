import 'dart:typed_data';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'asset_repository.dart';
import 'controller.dart';
import 'core_api.dart';
import 'image_commands.dart';
import 'media_session.dart';

ImageBlockComponentBuilder documentImageBuilder(
  SmartDocumentController c,
  DocumentMediaSession? media,
) => ImageBlockComponentBuilder(
  showMenu: false,
  contentBuilder: (context, node, width, height) => _AssetImage(
    key: ValueKey('${node.id}:${node.attributes['asset']}'),
    media: media,
    asset: node.attributes['asset'],
    width: width,
    height: height,
    alt: node.attributes['alt'] as String? ?? '',
  ),
  contentWrapper: (context, node, child) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      child,
      if ((node.attributes['title'] as String? ?? '').isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            node.attributes['title'] as String,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      if (c.canWrite && c.editor.editable)
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            key: ValueKey('smart-document.image-actions.${node.id}'),
            tooltip: '图片设置',
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: const Icon(Icons.more_horiz),
            onPressed: () => showImageProperties(
              context,
              c,
              DocumentBlockReference(objectId: c.objectId, blockId: node.id),
            ),
          ),
        ),
    ],
  ),
);

class _AssetImage extends StatefulWidget {
  const _AssetImage({
    super.key,
    required this.media,
    required this.asset,
    required this.width,
    required this.height,
    required this.alt,
  });
  final DocumentMediaSession? media;
  final Object? asset;
  final double width;
  final double? height;
  final String alt;
  @override
  State<_AssetImage> createState() => _AssetImageState();
}

class _AssetImageState extends State<_AssetImage> {
  late Future<Uint8List> _bytes = _read();
  Future<Uint8List> _read() async {
    if (widget.media == null)
      throw const AssetFailure('ASSET_PROVIDER_UNAVAILABLE');
    return widget.media!.repository.read(
      AssetReference.fromJson((widget.asset as Map).cast<String, dynamic>()),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _bytes,
    builder: (context, state) {
      if (state.hasData)
        return Image.memory(
          state.data!,
          width: widget.width,
          height: widget.height,
          fit: BoxFit.contain,
          semanticLabel: widget.alt.isEmpty ? '文档图片' : widget.alt,
          errorBuilder: (_, _, _) => const Text('图片解码失败'),
        );
      return SizedBox(
        width: widget.width,
        height: widget.height ?? 160,
        child: Center(
          child: state.hasError
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      state.error.toString().contains('FORBIDDEN')
                          ? '无权访问此图片'
                          : '图片暂时无法加载',
                    ),
                    TextButton(
                      onPressed: () => setState(() => _bytes = _read()),
                      child: const Text('重试加载'),
                    ),
                  ],
                )
              : const CircularProgressIndicator(),
        ),
      );
    },
  );
}

class DocumentMediaStatus extends StatelessWidget {
  const DocumentMediaStatus({super.key, required this.media});
  final DocumentMediaSession? media;
  @override
  Widget build(BuildContext context) {
    final m = media;
    if (m == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: m,
      builder: (context, _) {
        if (!m.hasPending && m.error == null && !m.busy)
          return const SizedBox.shrink();
        return Material(
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    m.busy
                        ? '正在处理图片…'
                        : m.hasPending
                        ? '图片尚未插入：${m.draftName}'
                        : '图片未能插入，请检查格式与大小',
                  ),
                ),
                if (m.hasPending)
                  TextButton(
                    onPressed: m.busy
                        ? null
                        : () async {
                            try {
                              await m.retry();
                            } on Object {
                              /* persistent error */
                            }
                          },
                    child: const Text('重试上传'),
                  ),
                TextButton(
                  onPressed: m.busy
                      ? null
                      : () async {
                          try {
                            await m.cancel();
                          } on Object {
                            /* retain draft */
                          }
                        },
                  child: const Text('取消'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

Future<void> insertDocumentImage(
  BuildContext context,
  DocumentMediaSession? media, {
  DocumentBlockReference? after,
}) async {
  if (media == null) return;
  try {
    await media.insert(after: after);
  } on Object {
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            media.hasPending ? '图片尚未插入，请保留当前页面，可重试或取消' : '图片未能插入，请检查格式与大小',
          ),
        ),
      );
  }
}

Future<void> showImageProperties(
  BuildContext context,
  SmartDocumentController c,
  DocumentBlockReference reference,
) async {
  final node = c.resolveBlock(reference);
  if (node == null) return;
  final initial = Map<String, dynamic>.of(node.attributes);
  final title = TextEditingController(
    text: node.attributes['title'] as String? ?? '',
  );
  final alt = TextEditingController(
    text: node.attributes['alt'] as String? ?? '',
  );
  final width = TextEditingController(
    text: ((node.attributes['width'] as num?)?.toDouble() ?? 320)
        .round()
        .toString(),
  );
  var align = node.attributes['align'] as String? ?? 'center';
  String? error;
  bool busy = false;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => PopScope(
        canPop: !busy,
        child: AlertDialog(
          key: const ValueKey('smart-document.image-dialog'),
          title: const Text('图片设置'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    key: const ValueKey('smart-document.image-caption'),
                    controller: title,
                    enabled: !busy,
                    decoration: const InputDecoration(labelText: '图片说明'),
                  ),
                  TextField(
                    key: const ValueKey('smart-document.image-alt'),
                    controller: alt,
                    enabled: !busy,
                    decoration: const InputDecoration(labelText: '替代文字'),
                  ),
                  TextField(
                    key: const ValueKey('smart-document.image-width'),
                    controller: width,
                    enabled: !busy,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: '宽度（保持比例）',
                      errorText: error,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'left', label: Text('左对齐')),
                      ButtonSegment(value: 'center', label: Text('居中')),
                      ButtonSegment(value: 'right', label: Text('右对齐')),
                    ],
                    selected: {align},
                    onSelectionChanged: busy
                        ? null
                        : (v) => setState(() => align = v.single),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              key: const ValueKey('smart-document.image-delete'),
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      try {
                        await c.deleteImage(reference);
                        if (context.mounted) Navigator.pop(context);
                      } on Object {
                        if (context.mounted)
                          setState(() {
                            busy = false;
                            error = '图片已变化，请重新打开';
                          });
                      }
                    },
              child: const Text('删除图片'),
            ),
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const ValueKey('smart-document.image-apply'),
              onPressed: busy
                  ? null
                  : () async {
                      final n = double.tryParse(width.text);
                      if (n == null || !n.isFinite || n < 1 || n > 20000) {
                        setState(() => error = '请输入 1–20000 的宽度');
                        return;
                      }
                      setState(() => busy = true);
                      try {
                        final current = c.resolveBlock(reference);
                        if (current == null)
                          throw const AssetFailure('TARGET_MISSING');
                        final previousWidth =
                            (current.attributes['width'] as num).toDouble();
                        final previousHeight =
                            (current.attributes['height'] as num).toDouble();
                        final properties = <String, dynamic>{
                          if (title.text != (initial['title'] ?? ''))
                            'title': title.text,
                          if (alt.text != (initial['alt'] ?? ''))
                            'alt': alt.text,
                          if (align != (initial['align'] ?? 'center'))
                            'align': align,
                          if (n != (initial['width'] ?? 320)) ...{
                            'width': n,
                            'height': n * previousHeight / previousWidth,
                          },
                        };
                        if (properties.isNotEmpty)
                          await c.updateImage(reference, properties);
                        if (context.mounted) Navigator.pop(context);
                      } on Object {
                        if (context.mounted)
                          setState(() {
                            busy = false;
                            error = '图片已变化或保存失败，请重试';
                          });
                      }
                    },
              child: const Text('应用'),
            ),
          ],
        ),
      ),
    ),
  );
  // Wait for the closing route animation before disposing field controllers.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  title.dispose();
  alt.dispose();
  width.dispose();
}
