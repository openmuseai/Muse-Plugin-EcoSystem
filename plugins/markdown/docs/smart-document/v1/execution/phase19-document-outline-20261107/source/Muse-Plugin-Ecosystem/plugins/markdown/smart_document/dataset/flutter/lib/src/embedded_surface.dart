import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:muse_resource_embed/muse_resource_embed.dart';
import 'controller.dart';
import 'surface.dart';
import 'realtime_session.dart';

/// Supplied after the Host resolves a bounded child ResourceEditorSession and
/// the dataset plugin opens it. Closing must flush its resource checkpoint too.
final class DatasetEmbedSession {
  const DatasetEmbedSession({
    required this.controller,
    required this.title,
    required this.close,
    this.checkpointStatus,
    this.checkpointFailure,
    this.flushCheckpoint,
    this.realtime,
  });
  final DatasetController controller;
  final String title;
  final Future<void> Function() close;
  final Listenable? checkpointStatus;
  final Object? Function()? checkpointFailure;
  final Future<void> Function()? flushCheckpoint;
  final DatasetRealtimeSession? realtime;
}

final class _Entry {
  _Entry(this.open);
  final Future<DatasetEmbedSession> open;
  int references = 0;
  Future<void>? closing;
}

/// One owner per referenced resource, including multiple document blocks/views.
/// The authorized opener must share this owner with any standalone surface.
/// Failed flushes retain the entry; callers can retry close instead of creating
/// another mutable local owner and overwriting unsaved work.
final class DatasetEmbedRegistry {
  DatasetEmbedRegistry({required this.open});
  final Future<DatasetEmbedSession> Function(ResourceEmbedTarget) open;
  final Map<String, _Entry> _entries = {};
  bool _closed = false;
  String _key(ResourceEmbedTarget t) =>
      '${jsonEncode(t.reference.toJson())}:${t.selector['objectId']}';
  Future<DatasetEmbedSession> acquire(ResourceEmbedTarget target) async {
    if (_closed ||
        target.surface != 'dataset.grid' ||
        target.selector.length != 2 ||
        !target.selector.keys.toSet().containsAll({'objectId', 'viewId'})) {
      throw const ResourceFailure('EMBED_UNAVAILABLE');
    }
    final key = _key(target);
    final existing = _entries[key];
    if (existing?.closing != null) {
      await existing!.closing;
      return acquire(target);
    }
    final entry = _entries.putIfAbsent(
      key,
      () => _Entry(Future.sync(() => open(target))),
    );
    entry.references++;
    DatasetEmbedSession session;
    try {
      session = await entry.open;
    } on Object {
      entry.references--;
      if (entry.references == 0) _entries.remove(key);
      rethrow;
    }
    try {
      if (session.controller.objectId != target.selector['objectId'] ||
          (target.reference.pinned && session.controller.editable)) {
        throw const ResourceFailure('EMBED_RESOURCE_MISMATCH');
      }
      return session;
    } on Object {
      entry.references--;
      if (entry.references == 0) {
        entry.closing = _close(key, entry);
        await entry.closing;
      }
      rethrow;
    }
  }

  Future<void> release(ResourceEmbedTarget target) async {
    final key = _key(target), entry = _entries[_key(target)];
    if (entry == null || entry.references == 0) return;
    entry.references--;
    // Keep a shared owner across synchronous projection/reparent rebuilds.
    await Future<void>.delayed(Duration.zero);
    if (entry.references != 0 || entry.closing != null) return;
    entry.closing = _close(key, entry);
    await entry.closing;
  }

  Future<void> _close(String key, _Entry entry) async {
    await (await entry.open).close();
    if (identical(_entries[key], entry)) _entries.remove(key);
  }

  Future<void> close() async {
    _closed = true;
    for (final e in _entries.entries.toList()) {
      if (e.value.closing != null) {
        try {
          await e.value.closing;
          continue;
        } on Object {
          /* explicit retry */
        }
      }
      // Explicit retry is permitted after a previous persistence failure.
      e.value.closing = _close(e.key, e.value);
      await e.value.closing;
    }
  }

  Widget build(
    BuildContext context,
    ResourceEmbedTarget target,
    ResourceEmbedPolicy policy,
  ) => _DatasetEmbed(
    key: ValueKey(
      '${identityHashCode(this)}:${target.key}:${policy.allowLive}',
    ),
    registry: this,
    target: target,
    policy: policy,
  );
}

class _DatasetEmbed extends StatefulWidget {
  const _DatasetEmbed({
    super.key,
    required this.registry,
    required this.target,
    required this.policy,
  });
  final DatasetEmbedRegistry registry;
  final ResourceEmbedTarget target;
  final ResourceEmbedPolicy policy;
  @override
  State<_DatasetEmbed> createState() => _DatasetEmbedState();
}

class _DatasetEmbedState extends State<_DatasetEmbed> {
  DatasetEmbedSession? session;
  Object? failure;
  bool acquired = false;
  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    if (!widget.policy.allowLive) return;
    try {
      final s = await widget.registry.acquire(widget.target);
      if (!mounted) {
        await widget.registry.release(widget.target);
        return;
      }
      acquired = true;
      setState(() => session = s);
    } on Object catch (e) {
      if (mounted) setState(() => failure = e);
    }
  }

  @override
  void dispose() {
    if (acquired)
      unawaited(
        widget.registry.release(widget.target).catchError((Object _) {
          // Registry retains the failed session for the Host's explicit close/save
          // barrier. Never discard or open a second mutable owner here.
        }),
      );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.policy.allowLive)
      return const Center(child: Text('历史文档中的数据库引用未连接实时内容'));
    if (failure != null)
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('数据库暂不可用，请检查访问权限'),
            TextButton(
              onPressed: () {
                setState(() => failure = null);
                unawaited(_start());
              },
              child: const Text('重试加载'),
            ),
          ],
        ),
      );
    final s = session;
    if (s == null) return const Center(child: CircularProgressIndicator());
    final surface = DatasetSurface(
      controller: s.controller,
      realtime: s.realtime,
      title: s.title,
      viewId: widget.target.selector['viewId'],
      embedded: true,
      allowEditing:
          widget.policy.allowEditing && !widget.target.reference.pinned,
    );
    if (s.checkpointStatus == null) return surface;
    return ListenableBuilder(
      listenable: s.checkpointStatus!,
      builder: (context, _) => Column(
        children: [
          if (s.checkpointFailure?.call() != null)
            Row(
              children: [
                const Expanded(child: Text('资源保存失败，本机修改保留')),
                TextButton(
                  onPressed: () => unawaited(
                    s.flushCheckpoint?.call().catchError((Object _) {}),
                  ),
                  child: const Text('重试保存'),
                ),
              ],
            ),
          Expanded(child: surface),
        ],
      ),
    );
  }
}
