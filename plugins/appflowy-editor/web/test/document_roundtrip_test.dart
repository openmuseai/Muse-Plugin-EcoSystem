import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppFlowy document serializes and restores text', () {
    final initial = EditorState.blank(withInitialText: true);
    final data = initial.document.toJson();
    final restored = Document.fromJson(data);
    expect(restored.toJson(), data);
  });
}
