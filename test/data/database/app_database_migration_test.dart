// 作用：验证历史版本表从 schema v1 升级到 v2 时保留旧快照数据。
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' show Database;

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
        _createLegacyNotesTable(rawDatabase);
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
        _createLegacyNotesTable(rawDatabase);
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
        _createLegacyNotesTable(rawDatabase);
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

  test('从 v3 升级到 v4 生成稳定连续的目录顺序并保留笔记数据', () async {
    final executor = NativeDatabase.memory(
      setup: (rawDatabase) {
        rawDatabase.execute('''
          CREATE TABLE subject_folders (
            id TEXT NOT NULL PRIMARY KEY,
            parent_id TEXT,
            name TEXT NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0,
            deleted_at INTEGER
          )
        ''');
        rawDatabase.execute('''
          INSERT INTO subject_folders (
            id, parent_id, name, sort_order, created_at,
            updated_at, is_deleted, deleted_at
          ) VALUES
            ('folder-b', NULL, '资料 B', 5, 100, 100, 0, NULL),
            ('folder-a', NULL, '资料 A', 5, 100, 100, 0, NULL),
            ('folder-child', 'folder-a', '子目录', 8, 200, 200, 0, NULL)
        ''');
        rawDatabase.execute('''
          CREATE TABLE subjects (
            id TEXT NOT NULL PRIMARY KEY,
            parent_id TEXT,
            name TEXT NOT NULL,
            level INTEGER NOT NULL,
            folder_id TEXT,
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0,
            deleted_at INTEGER
          )
        ''');
        rawDatabase.execute('''
          INSERT INTO subjects (
            id, parent_id, name, level, folder_id, sort_order,
            created_at, updated_at, is_deleted, deleted_at
          ) VALUES
            ('book-b', NULL, '书 B', 0, NULL, 9, 100, 100, 0, NULL),
            ('book-a', NULL, '书 A', 0, NULL, 9, 100, 100, 0, NULL),
            ('chapter-a', 'book-a', '章 A', 1, NULL, 7, 200, 200, 0, NULL),
            ('chapter-b', 'book-a', '章 B', 1, NULL, 2, 300, 300, 0, NULL),
            ('section-a', 'chapter-a', '节 A', 2, NULL, 6, 400, 400, 0, NULL)
        ''');
        rawDatabase.execute('''
          CREATE TABLE notes (
            id TEXT NOT NULL PRIMARY KEY,
            subject_id TEXT NOT NULL,
            title TEXT,
            content_json TEXT,
            plain_text TEXT NOT NULL DEFAULT '',
            is_draft INTEGER NOT NULL DEFAULT 0,
            is_ai_hidden INTEGER NOT NULL DEFAULT 0,
            source_type TEXT,
            source_ref TEXT,
            last_read_at INTEGER,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0,
            deleted_at INTEGER
          )
        ''');
        rawDatabase.execute('''
          INSERT INTO notes (
            id, subject_id, title, content_json, plain_text,
            created_at, updated_at, is_deleted
          ) VALUES
            ('note-b', 'book-a', '第二条', '[{"insert":"B\\n"}]', 'B', 200, 210, 0),
            ('note-a', 'book-a', '第一条', '[{"insert":"A\\n"}]', 'A', 100, 110, 0),
            ('note-c', 'chapter-a', '章节笔记', '[{"insert":"C\\n"}]', 'C', 300, 310, 0)
        ''');
        rawDatabase.execute('''
          CREATE TABLE note_tags (
            note_id TEXT NOT NULL,
            tag_id TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            PRIMARY KEY (note_id, tag_id)
          )
        ''');
        rawDatabase.execute('''
          INSERT INTO note_tags (note_id, tag_id, created_at)
          VALUES ('note-a', 'tag-a', 500)
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
          ) VALUES (
            'version-a', 'note-a', 3, '[{"insert":"旧版本\\n"}]', 600, '保留版本'
          )
        ''');
        rawDatabase.execute('PRAGMA user_version = 3');
      },
    );
    final database = AppDatabase.forTesting(executor);
    addTearDown(database.close);

    final folders = await database.customSelect('''
      SELECT id, parent_id, sort_order
      FROM subject_folders
      WHERE is_deleted = 0
      ORDER BY COALESCE(parent_id, ''), sort_order, created_at, id
    ''').get();
    final subjects = await database.customSelect('''
      SELECT id, parent_id, folder_id, level, sort_order
      FROM subjects
      WHERE is_deleted = 0
      ORDER BY level, COALESCE(folder_id, ''), COALESCE(parent_id, ''), sort_order, created_at, id
    ''').get();
    final notes = await database.customSelect('''
      SELECT id, subject_id, title, content_json, plain_text, sort_order
      FROM notes
      WHERE is_deleted = 0
      ORDER BY subject_id, sort_order, created_at, id
    ''').get();
    final link = await database.customSelect('''
      SELECT note_id, tag_id FROM note_tags
    ''').getSingle();
    final version = await database.customSelect('''
      SELECT note_id, version_no, snapshot_json, name FROM note_versions
    ''').getSingle();

    expect(
      folders.map(
        (row) => (
          row.read<String>('id'),
          row.read<String?>('parent_id'),
          row.read<int>('sort_order'),
        ),
      ),
      [
        ('folder-a', null, 0),
        ('folder-b', null, 1),
        ('folder-child', 'folder-a', 0),
      ],
    );
    expect(
      subjects.map(
        (row) => (
          row.read<String>('id'),
          row.read<int>('level'),
          row.read<int>('sort_order'),
        ),
      ),
      [
        ('book-a', 0, 0),
        ('book-b', 0, 1),
        ('chapter-b', 1, 0),
        ('chapter-a', 1, 1),
        ('section-a', 2, 0),
      ],
    );
    expect(
      notes.map(
        (row) => (
          row.read<String>('id'),
          row.read<String>('subject_id'),
          row.read<int>('sort_order'),
          row.read<String?>('title'),
          row.read<String>('plain_text'),
        ),
      ),
      [
        ('note-a', 'book-a', 0, '第一条', 'A'),
        ('note-b', 'book-a', 1, '第二条', 'B'),
        ('note-c', 'chapter-a', 0, '章节笔记', 'C'),
      ],
    );
    expect(link.read<String>('note_id'), 'note-a');
    expect(link.read<String>('tag_id'), 'tag-a');
    expect(version.read<String>('note_id'), 'note-a');
    expect(version.read<int>('version_no'), 3);
    expect(version.read<String>('snapshot_json'), '[{"insert":"旧版本\\n"}]');
    expect(version.read<String?>('name'), '保留版本');
  });
}

/// v1～v3 均已存在的笔记表；v4 迁移只是在此结构上新增 sort_order。
void _createLegacyNotesTable(Database database) {
  database.execute('''
    CREATE TABLE notes (
      id TEXT NOT NULL PRIMARY KEY,
      subject_id TEXT NOT NULL,
      title TEXT,
      content_json TEXT,
      plain_text TEXT NOT NULL DEFAULT '',
      is_draft INTEGER NOT NULL DEFAULT 0,
      is_ai_hidden INTEGER NOT NULL DEFAULT 0,
      source_type TEXT,
      source_ref TEXT,
      last_read_at INTEGER,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      deleted_at INTEGER
    )
  ''');
}
