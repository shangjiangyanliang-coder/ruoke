// 文件: test/features/notes/note_edit_snapshot_test.dart
// 作用: 验证完整笔记历史快照的新格式和旧正文 Delta 兼容规则。
import 'package:flutter_test/flutter_test.dart';

import 'package:ruoke/src/features/notes/models/note_edit_snapshot.dart';

void main() {
  test('新格式往返保留标题正文并规范化标签', () {
    const contentJson = '[{"insert":"正文\\n"}]';
    final snapshot = NoteEditSnapshot(
      title: '标题',
      contentJson: contentJson,
      tagNames: const [' 重点 ', '复习', '重点', '  '],
    );

    final decoded = NoteEditSnapshot.decode(snapshot.encode());

    expect(decoded.isLegacy, isFalse);
    expect(decoded.title, '标题');
    expect(decoded.contentJson, contentJson);
    expect(decoded.tagNames, const ['重点', '复习']);
  });

  test('旧正文 Delta 被识别为仅正文历史版本', () {
    const legacyDelta = '[{"insert":"旧正文\\n"}]';

    final decoded = NoteEditSnapshot.decode(legacyDelta);

    expect(decoded.isLegacy, isTrue);
    expect(decoded.title, isNull);
    expect(decoded.contentJson, legacyDelta);
    expect(decoded.tagNames, isEmpty);
  });

  test('损坏或未知版本的快照会拒绝解析', () {
    expect(
      () => NoteEditSnapshot.decode('{"schemaVersion":2}'),
      throwsFormatException,
    );
    expect(() => NoteEditSnapshot.decode('"正文"'), throwsFormatException);
    expect(() => NoteEditSnapshot.decode('[1]'), throwsFormatException);
    expect(() => NoteEditSnapshot.decode('[{}]'), throwsFormatException);
    expect(
      () => NoteEditSnapshot.decode('[{"insert":1}]'),
      throwsFormatException,
    );
  });

  test('完整状态比较忽略标签输入顺序但区分标题正文', () {
    const contentJson = '[{"insert":"正文\\n"}]';
    final first = NoteEditSnapshot(
      title: '标题',
      contentJson: contentJson,
      tagNames: const ['重点', '复习'],
    );
    final reordered = NoteEditSnapshot(
      title: '标题',
      contentJson: contentJson,
      tagNames: const ['复习', '重点'],
    );
    final changedTitle = NoteEditSnapshot(
      title: '新标题',
      contentJson: contentJson,
      tagNames: const ['重点', '复习'],
    );

    expect(first.hasSameContent(reordered), isTrue);
    expect(first.hasSameContent(changedTitle), isFalse);
  });
}
