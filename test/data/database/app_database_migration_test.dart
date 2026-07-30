// 作用：验证历史版本表从 schema v1 升级到 v2 时保留旧快照数据。
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ruoke/src/data/database/app_database.dart';

void main() {
  test('从 v1 升级到 v2 保留已有历史版本和快照', () async {
    final executor = NativeDatabase.memory(
      setup: (rawDatabase) {
        rawDatabase.execute('''
          CREATE TABLE subjects (
            id TEXT NOT NULL PRIMARY KEY,
            parent_id TEXT,
            name TEXT NOT NULL,
            level INTEGER NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0,
            deleted_at INTEGER
          )
        ''');
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

  test('从 v2 升级到 v3 保留已有书和历史版本', () async {
    final executor = NativeDatabase.memory(
      setup: (rawDatabase) {
        rawDatabase.execute('''
          CREATE TABLE subjects (
            id TEXT NOT NULL PRIMARY KEY,
            parent_id TEXT,
            name TEXT NOT NULL,
            level INTEGER NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0,
            deleted_at INTEGER
          )
        ''');
        rawDatabase.execute('''
          INSERT INTO subjects (
            id, parent_id, name, level, sort_order,
            created_at, updated_at, is_deleted, deleted_at
          ) VALUES ('book-v2', NULL, '旧书', 0, 3, 100, 101, 0, NULL)
        ''');
        rawDatabase.execute('''
          CREATE TABLE note_versions (
            id TEXT NOT NULL PRIMARY KEY,
            note_id TEXT NOT NULL,
            version_no INTEGER NOT NULL,
            snapshot_json TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            name TEXT
          )
        ''');
        rawDatabase.execute('''
          INSERT INTO note_versions (
            id, note_id, version_no, snapshot_json, created_at, name
          ) VALUES ('version-v2', 'note-v2', 2, '[{"insert":"旧快照\\n"}]', 200, '旧版本')
        ''');
        rawDatabase.execute('PRAGMA user_version = 2');
      },
    );
    final database = AppDatabase.forTesting(executor);
    addTearDown(database.close);

    final subject = await database.customSelect('''
      SELECT id, name, level, folder_id
      FROM subjects
      WHERE id = 'book-v2'
    ''').getSingle();
    final version = await database.customSelect('''
      SELECT id, version_no, name
      FROM note_versions
      WHERE id = 'version-v2'
    ''').getSingle();

    expect(subject.read<String>('id'), 'book-v2');
    expect(subject.read<String>('name'), '旧书');
    expect(subject.read<int>('level'), 0);
    expect(subject.read<String?>('folder_id'), isNull);
    expect(version.read<String>('id'), 'version-v2');
    expect(version.read<int>('version_no'), 2);
    expect(version.read<String?>('name'), '旧版本');
  });

  test('从 v2 升级到 v3 创建文件夹表', () async {
    final executor = NativeDatabase.memory(
      setup: (rawDatabase) {
        rawDatabase.execute('''
          CREATE TABLE subjects (
            id TEXT NOT NULL PRIMARY KEY,
            parent_id TEXT,
            name TEXT NOT NULL,
            level INTEGER NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0,
            deleted_at INTEGER
          )
        ''');
        rawDatabase.execute('PRAGMA user_version = 2');
      },
    );
    final database = AppDatabase.forTesting(executor);
    addTearDown(database.close);

    await database.customStatement('''
      INSERT INTO subject_folders (
        id, parent_id, name, sort_order, created_at,
        updated_at, is_deleted, deleted_at
      ) VALUES ('folder-v3', NULL, '根文件夹', 4, 300, 301, 0, NULL)
    ''');
    final folder = await database.customSelect('''
      SELECT id, parent_id, name, sort_order, is_deleted
      FROM subject_folders
      WHERE id = 'folder-v3'
    ''').getSingle();

    expect(folder.read<String>('id'), 'folder-v3');
    expect(folder.read<String?>('parent_id'), isNull);
    expect(folder.read<String>('name'), '根文件夹');
    expect(folder.read<int>('sort_order'), 4);
    expect(folder.read<bool>('is_deleted'), isFalse);
  });
}
