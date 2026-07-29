// 文件: lib/src/data/database/app_database.dart
// 作用: Drift 数据库主入口。注册笔记模块 6 张表，
//       用 drift_flutter 的 driftDatabase() 在后台 isolate 打开本地 SQLite（package:drift_flutter）。
//       这是全项目共享的数据库单例，后续题库/复习/AI 表也在此登记。
//       详见技术方案 A §三 data/database + B 文档 + C 文档 §6.3 启动初始化。
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'daos/note_dao.dart';
import 'daos/note_highlight_dao.dart';
import 'daos/note_tag_dao.dart';
import 'daos/note_version_dao.dart';
import 'daos/subject_dao.dart';
import 'daos/tag_dao.dart';
import 'tables/note_highlight_table.dart';
import 'tables/note_table.dart';
import 'tables/note_tag_table.dart';
import 'tables/note_version_table.dart';
import 'tables/subject_table.dart';
import 'tables/tag_table.dart';

part 'app_database.g.dart';

/// 全项目 Drift 数据库单例。
///
/// 当前登记笔记模块 6 张表 + 6 个 DAO。题库/复习/AI 等后续表分批加入时，
/// 在 tables/daos 列表里追加即可，schemaVersion 顺次 +1。
@DriftDatabase(
  tables: [
    Subjects,
    Notes,
    NoteVersions,
    NoteHighlights,
    Tags,
    NoteTags,
  ],
  daos: [
    SubjectDao,
    NoteDao,
    NoteVersionDao,
    NoteHighlightDao,
    TagDao,
    NoteTagDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// 默认构造：用 drift_flutter 在后台 isolate 打开 ruoke.sqlite。
  AppDatabase() : super(driftDatabase(name: 'ruoke'));

  /// 测试构造：注入自定义连接（单测 mock 库用）。
  AppDatabase.forTesting(super.e);

  /// 数据库 schema 版本号。新增表或改表结构时 +1，并在 migration 里处理升级。
  /// 当前 = 2：历史版本增加可选自定义名称。
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(noteVersions, noteVersions.name);
      }
    },
  );
}
