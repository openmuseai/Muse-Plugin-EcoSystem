import 'dart:typed_data';

/// Transient domain association buffer, not storage or an alternative CRDT.
/// Unknown rows remain outside the database until a validated root references
/// them. Expiry/drop is repaired from the authoritative row object.
final class DatasetRowReorderBuffer {
  static const maximumBytes = 2 * 1024 * 1024,
      maximumObjects = 32,
      maximumFramesPerObject = 4,
      lifetimeMs = 5000;
  final Map<String, List<({int time, Uint8List update})>> _rows = {};
  int _bytes = 0;
  int get bytes => _bytes;
  int get objects => _rows.length;
  bool add(String id, Uint8List update, int nowMs) {
    expire(nowMs);
    if (update.length > maximumBytes ||
        _bytes + update.length > maximumBytes ||
        (!_rows.containsKey(id) && _rows.length >= maximumObjects) ||
        (_rows[id]?.length ?? 0) >= maximumFramesPerObject)
      return false;
    (_rows[id] ??= []).add((
      time: nowMs,
      update: Uint8List.fromList(update).asUnmodifiableView(),
    ));
    _bytes += update.length;
    return true;
  }

  List<Uint8List> take(String id, int nowMs) {
    expire(nowMs);
    final entries = _rows.remove(id) ?? const [];
    for (final e in entries) {
      _bytes -= e.update.length;
    }
    return [for (final e in entries) e.update];
  }

  void expire(int nowMs) {
    for (final key in _rows.keys.toList()) {
      final entries = _rows[key]!;
      entries.removeWhere((e) {
        if (nowMs - e.time >= lifetimeMs) {
          _bytes -= e.update.length;
          return true;
        }
        return false;
      });
      if (entries.isEmpty) _rows.remove(key);
    }
  }

  void clear() {
    _rows.clear();
    _bytes = 0;
  }
}
