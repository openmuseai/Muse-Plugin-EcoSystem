import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_dataset/src/row_reorder_buffer.dart';

void main() {
  test(
    'unassociated frames retain order, own bytes and expire without entering content',
    () {
      final b = DatasetRowReorderBuffer(), source = Uint8List.fromList([1, 2]);
      expect(b.add('row', source, 0), isTrue);
      source[0] = 9;
      expect(b.add('row', Uint8List.fromList([3]), 1), isTrue);
      expect(b.take('row', 2).map((v) => v.toList()).toList(), [
        [1, 2],
        [3],
      ]);
      expect(b.bytes, 0);
      expect(b.objects, 0);
      b.add('row', Uint8List(1), 3);
      b.expire(5003);
      expect(b.take('row', 5003), isEmpty);
      expect(b.bytes, 0);
    },
  );
  test(
    'byte, object and per-object frame budgets reject growth and can be cleared',
    () {
      final b = DatasetRowReorderBuffer();
      for (var i = 0; i < 32; i++) {
        expect(b.add('$i', Uint8List(1), 0), isTrue);
      }
      expect(b.add('extra', Uint8List(1), 1), isFalse);
      expect(b.objects, 32);
      b.clear();
      for (var i = 0; i < 4; i++) {
        expect(b.add('row', Uint8List(1), 0), isTrue);
      }
      expect(b.add('row', Uint8List(1), 1), isFalse);
      b.clear();
      expect(
        b.add('row', Uint8List(DatasetRowReorderBuffer.maximumBytes), 0),
        isTrue,
      );
      expect(b.add('row2', Uint8List(1), 1), isFalse);
      b.clear();
      expect(b.bytes, 0);
    },
  );
}
