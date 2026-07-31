// 文件: lib/src/data/database/tables/note_table.dart
// 作用: 笔记表。轻富文本正文存 content_json（Delta JSON，决策②），
//       派生 plain_text 供搜索/备份降级纯文字（写入时同步生成）。
//       is_draft 草稿态、ai_hidden AI 不可见、source_type 来源、
//       last_read_at 续学用。软删 + 软删时间走回收站。
//       详见技术方案 B §二 笔记块 表2。
import 'package:drift/drift.dart';

/// 笔记表。
@DataClassName('NoteEntity')
class Notes extends Table {
  /// UUID 主键
  TextColumn get id => text()();

  /// 所属科目节点（书/章/节任一级）
  TextColumn get subjectId => text()();

  /// 可空标题（决策：空标题不影响创建）
  TextColumn get title => text().nullable()();

  /// 轻富文本正文，Delta JSON 结构（决策②）
  TextColumn get contentJson => text().nullable()();

  /// 由 content_json 派生的纯文字（Trigram/LIKE 搜索用，写入时同步生成）
  TextColumn get plainText => text().withDefault(const Constant(''))();

  /// 草稿态（C6 待整理笔记来源）
  BoolColumn get isDraft => boolean().withDefault(const Constant(false))();

  /// 本条 AI 不可见（A3.b 笔记级开关）
  BoolColumn get isAiHidden => boolean().withDefault(const Constant(false))();

  /// 来源：manual/ocr/import/highlight-transfer 等
  TextColumn get sourceType => text().nullable()();

  /// 来源指针（如识图素材 id / 笔记段定位）
  TextColumn get sourceRef => text().nullable()();

  /// F1.19 续学用
  IntColumn get lastReadAt => integer().nullable()();

  /// 同一书、章或节内的显示顺序。
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// 创建时间（毫秒）
  IntColumn get createdAt => integer()();

  /// 更新时间（毫秒）
  IntColumn get updatedAt => integer()();

  /// 软删标志
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  /// 软删时间，置 isDeleted=true 时写；恢复回 null
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
