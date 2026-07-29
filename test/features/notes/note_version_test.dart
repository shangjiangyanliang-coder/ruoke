// 作用：验证历史版本的用户可见名称规则。
import 'package:flutter_test/flutter_test.dart';

import 'package:ruoke/src/features/notes/models/note_version.dart';

void main() {
  test('自定义名称优先于默认版本号显示', () {
    const version = NoteVersion(
      id: 'version-1',
      noteId: 'note-1',
      versionNo: 3,
      snapshotJson: '[]',
      createdAt: 1,
      name: '考试前复习',
    );

    expect(version.displayName, '考试前复习');
  });

  test('未命名版本显示稳定的默认版本号', () {
    const version = NoteVersion(
      id: 'version-2',
      noteId: 'note-1',
      versionNo: 8,
      snapshotJson: '[]',
      createdAt: 2,
    );

    expect(version.displayName, '版本 8');
  });
}
