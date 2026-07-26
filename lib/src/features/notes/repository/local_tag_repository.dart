// 标签 Repository 的 Drift 本地实现，负责领域转换、校验和事务。
import 'package:drift/native.dart' show SqliteException;

import '../../../data/database/app_database.dart';
import '../../../data/database/daos/note_tag_dao.dart';
import '../../../data/database/daos/tag_dao.dart';
import '../../../data/errors/app_exception.dart';
import '../../../data/errors/result.dart';
import '../../../utils/id_generator.dart';
import '../../../utils/time_utils.dart';
import '../models/tag.dart';
import 'tag_repository.dart';

/// 通过本地 Drift 数据库管理标签和笔记标签关联。
class LocalTagRepository implements TagRepository {
  final AppDatabase _db;

  LocalTagRepository(this._db);

  TagDao get _tagDao => _db.tagDao;
  NoteTagDao get _noteTagDao => _db.noteTagDao;

  @override
  Future<Result<List<TagWithCount>>> listTags() => guard(
    () async {
      final tags = await _tagDao.listAll();
      return Future.wait(
        tags.map((entity) async {
          final count = await _noteTagDao.countActiveNotesForTag(entity.id);
          return TagWithCount(
            id: entity.id,
            name: entity.name,
            color: entity.color,
            createdAt: entity.createdAt,
            noteCount: count,
          );
        }),
      );
    },
    orElse: (error) =>
        const Failure(DatabaseException('读取标签列表失败', techDetail: 'listTags')),
  );

  @override
  Future<Result<Tag>> createTag({required String name, String? color}) async {
    final normalizedName = _normalizedName(name);
    if (normalizedName == null) {
      return const Failure(ValidationException('标签名称不能为空'));
    }
    return guard(
      () async {
        final entity = TagEntity(
          id: newId(),
          name: normalizedName,
          color: color,
          createdAt: nowMs(),
        );
        await _tagDao.insertTag(entity);
        return Tag.fromEntity(entity);
      },
      orElse: (error) => _tagWriteFailure(
        error,
        fallbackMessage: '新建标签失败',
        operation: 'createTag',
      ),
    );
  }

  @override
  Future<Result<void>> renameTag({
    required String id,
    required String name,
  }) async {
    final normalizedName = _normalizedName(name);
    if (normalizedName == null) {
      return const Failure(ValidationException('标签名称不能为空'));
    }
    return guard(
      () async => _tagDao.renameTag(id, normalizedName),
      orElse: (error) => _tagWriteFailure(
        error,
        fallbackMessage: '重命名标签失败',
        operation: 'renameTag',
      ),
    );
  }

  @override
  Future<Result<void>> deleteTag(String id) => guard(
    () async => _db.transaction(() async {
      await _noteTagDao.deleteByTag(id);
      await _tagDao.deleteTag(id);
    }),
    orElse: (error) =>
        const Failure(DatabaseException('删除标签失败', techDetail: 'deleteTag')),
  );

  @override
  Future<Result<List<Tag>>> listTagsForNote(String noteId) => guard(
    () async {
      final links = await _noteTagDao.listByNote(noteId);
      final tagIds = links.map((link) => link.tagId).toList();
      final tags = await _tagDao.listByIds(tagIds);
      return tags.map(Tag.fromEntity).toList();
    },
    orElse: (error) => const Failure(
      DatabaseException('读取笔记标签失败', techDetail: 'listTagsForNote'),
    ),
  );

  @override
  Future<Result<void>> replaceNoteTags({
    required String noteId,
    required List<String> tagIds,
  }) => guard(
    () async => _db.transaction(() async {
      await _noteTagDao.deleteByNote(noteId);
      final now = nowMs();
      for (final tagId in tagIds.toSet()) {
        await _noteTagDao.insertNoteTag(
          NoteTagEntity(noteId: noteId, tagId: tagId, createdAt: now),
        );
      }
    }),
    orElse: (error) => const Failure(
      DatabaseException('保存笔记标签失败', techDetail: 'replaceNoteTags'),
    ),
  );

  String? _normalizedName(String name) {
    final normalized = name.trim();
    return normalized.isEmpty ? null : normalized;
  }

  Failure<T> _tagWriteFailure<T>(
    Object error, {
    required String fallbackMessage,
    required String operation,
  }) {
    if (error is SqliteException && error.extendedResultCode == 2067) {
      return Failure(
        DatabaseException('标签名称已存在，请换一个名称', techDetail: '$operation/unique'),
      );
    }
    return Failure(
      DatabaseException(
        fallbackMessage,
        techDetail: '$operation/${error.runtimeType}',
      ),
    );
  }
}
