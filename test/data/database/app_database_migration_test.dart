// 作用：验证历史版本表从 schema v1 升级到 v2 时保留旧快照数据。
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ruoke/src/data/database/app_database.dart';

void main() {
  test('从 v1 升级到 v2 保留已有历史版本和快照', () async {
    final executor = NativeDatabase.memory(
      setup: (rawDatabase) {
        rawDatabase.execute('''
          CREATE TABLE note_versions (
            id TEXT NOT NULL PRIMARY KEY,
            note_id TEXT NOT NULL,
            version_no INTEGER NOT NULL,
            snapshot_json TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
        rawDatabase.execute('''
          INSERT INTO note_versions (
            id, note_id, version_no, snapshot_json, created_at
          ) VALUES (
            'version-v1', 'note-v1', 7, '[{"insert":"旧快照\\n"}]', 100
          )
        ''');
        rawDatabase.execute('PRAGMA user_version = 1');
      },
    );
    final database = AppDatabase.forTesting(executor);
    addTearDown(database.close);

    final row = await database.customSelect('''
      SELECT id, note_id, version_no, snapshot_json, created_at, name
      FROM note_versions
      WHERE id = 'version-v1'
    ''').getSingle();

    expect(row.read<String>('id'), 'version-v1');
    expect(row.read<String>('note_id'), 'note-v1');
    expect(row.read<int>('version_no'), 7);
    expect(row.read<String>('snapshot_json'), '[{"insert":"旧快照\\n"}]');
    expect(row.read<int>('created_at'), 100);
    expect(row.read<String?>('name'), isNull);
  });
}
