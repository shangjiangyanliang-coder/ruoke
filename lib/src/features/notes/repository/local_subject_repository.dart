// 文件: lib/src/features/notes/repository/local_subject_repository.dart
// 作用: SubjectRepository 的本地（Drift）实现。把 DAO 的 SubjectEntity 翻译成
//       领域 Subject，把底层异常翻译成 AppException 放进 Result。
//       详见技术方案 A §2.2 + B §二 + C §6.2。
// 注：Value 来自 drift；SubjectsCompanion 是 app_database.g.dart 生成的，
//     由 app_database.dart 的 part 暴露，故本文件另 import app_database.dart。
import 'package:drift/drift.dart' show Value;

import '../../../data/database/app_database.dart';
import '../../../data/database/daos/subject_dao.dart';
import '../../../data/errors/app_exception.dart';
import '../../../data/errors/result.dart';
import '../../../utils/id_generator.dart';
import '../../../utils/time_utils.dart';
import '../models/subject.dart';
import '../models/subject_path.dart';
import 'subject_repository.dart';

/// SubjectRepository 的本地（Drift）实现。
class LocalSubjectRepository implements SubjectRepository {
  final AppDatabase _db;

  LocalSubjectRepository(this._db);

  SubjectDao get _dao => _db.subjectDao;

  @override
  Future<Result<List<Subject>>> listAll() => guard(
    () async => (await _dao.listAll()).map(Subject.fromEntity).toList(),
    orElse: (e) =>
        const Failure(DatabaseException('读取科目树失败', techDetail: 'listAll')),
  );

  @override
  Future<Result<List<Subject>>> childrenOf(String? parentId) => guard(
    () async =>
        (await _dao.childrenOf(parentId)).map(Subject.fromEntity).toList(),
    orElse: (e) =>
        const Failure(DatabaseException('读取子科目失败', techDetail: 'childrenOf')),
  );

  @override
  Future<Result<List<SubjectPath>>> searchPaths(String keyword) {
    final normalized = keyword.trim();
    if (normalized.isEmpty) {
      return Future.value(const Success<List<SubjectPath>>([]));
    }
    return guard(
      () async {
        final matches = await _dao.searchByName(normalized);
        final paths = <SubjectPath>[];
        for (final entity in matches) {
          final path = await _buildPath(Subject.fromEntity(entity));
          if (path != null) paths.add(path);
        }
        return paths;
      },
      orElse: (e) =>
          const Failure(DatabaseException('搜索科目失败', techDetail: 'searchPaths')),
    );
  }

  /// 最多向上读取两级；层级、父子关系或软删除状态异常时丢弃该路径。
  Future<SubjectPath?> _buildPath(Subject target) async {
    final reversed = <Subject>[target];
    var current = target;
    while (current.parentId != null && reversed.length < 3) {
      final parentEntity = await _dao.getById(current.parentId!);
      if (parentEntity == null || parentEntity.isDeleted) return null;
      final parent = Subject.fromEntity(parentEntity);
      if (parent.level != current.level - 1) return null;
      reversed.add(parent);
      current = parent;
    }
    if (current.parentId != null || current.level != 0) return null;
    return SubjectPath(reversed.reversed);
  }

  @override
  Future<Result<Subject?>> getById(String id) => guard(
    () async {
      final e = await _dao.getById(id);
      return e == null ? null : Subject.fromEntity(e);
    },
    orElse: (e) =>
        const Failure(DatabaseException('读取科目失败', techDetail: 'getById')),
  );

  @override
  Future<Result<String>> create({
    required String name,
    required int level,
    String? parentId,
    String? folderId,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      return const Failure(ValidationException('名称不能为空'));
    }
    return _transaction(
      userMessage: '新建科目失败',
      techDetail: 'create',
      action: () async {
        if (level < 0 || level > 2) {
          throw const ValidationException('层级不正确');
        }

        late final int sortOrder;
        if (level == 0) {
          if (parentId != null) {
            throw const ValidationException('书不能设置上级书章节');
          }
          if (folderId != null &&
              await _db.folderDao.getActiveById(folderId) == null) {
            throw const ValidationException('目标文件夹不存在或已删除');
          }
          sortOrder = _nextOrder(await _db.folderDao.booksIn(folderId));
        } else {
          if (folderId != null || parentId == null) {
            throw const ValidationException('章或节必须设置正确父级');
          }
          final parent = await _dao.getById(parentId);
          if (parent == null || parent.isDeleted || parent.level != level - 1) {
            throw const ValidationException('目标父级不存在或层级不正确');
          }
          sortOrder = _nextOrder(await _dao.childrenOf(parentId));
        }

        final now = nowMs();
        final id = newId();
        await _dao.insertSubject(
          SubjectsCompanion(
            id: Value(id),
            parentId: Value(level == 0 ? null : parentId),
            folderId: Value(level == 0 ? folderId : null),
            name: Value(normalizedName),
            level: Value(level),
            sortOrder: Value(sortOrder),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
        return id;
      },
    );
  }

  @override
  Future<Result<void>> rename({
    required String id,
    required String name,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      return const Failure(ValidationException('名称不能为空'));
    }
    return _transaction(
      userMessage: '重命名失败',
      techDetail: 'renameSubject',
      action: () async {
        final subject = await _dao.getById(id);
        if (subject == null || subject.isDeleted) {
          throw const ValidationException('书章节不存在或已删除');
        }
        final changed = await _dao.rename(id, normalizedName, nowMs());
        if (changed != 1) {
          throw const ValidationException('书章节已发生变化，请刷新后重试');
        }
      },
    );
  }

  @override
  Future<Result<void>> moveSubject({
    required String subjectId,
    required String newParentId,
    required int targetIndex,
  }) => _transaction(
    userMessage: '移动章节目失败',
    techDetail: 'moveSubject',
    action: () async {
      final moving = await _dao.getById(subjectId);
      if (moving == null || moving.isDeleted || moving.level == 0) {
        throw const ValidationException('只能移动未删除的章或节');
      }
      final targetParent = await _dao.getById(newParentId);
      if (targetParent == null || targetParent.isDeleted) {
        throw const ValidationException('目标父级不存在或已删除');
      }
      if (targetParent.level != moving.level - 1) {
        throw const ValidationException('目标层级不正确');
      }

      final source = await _dao.childrenOf(moving.parentId);
      final target = moving.parentId == newParentId
          ? source
          : await _dao.childrenOf(newParentId);
      final sourceIds = source.map((subject) => subject.id).toList();
      if (!sourceIds.remove(subjectId)) {
        throw const ValidationException('章节目列表已变化，请刷新后重试');
      }
      final targetIds = target
          .map((subject) => subject.id)
          .where((id) => id != subjectId)
          .toList();
      _validateTargetIndex(targetIndex, targetIds.length);
      targetIds.insert(targetIndex, subjectId);

      if (moving.parentId != newParentId) {
        await _writeOrder(sourceIds);
      }
      final changed = await _dao.updateParentAndOrder(
        subjectId,
        newParentId,
        targetIndex,
        nowMs(),
      );
      if (changed != 1) {
        throw const ValidationException('章节目已发生变化，请刷新后重试');
      }
      await _writeOrder(targetIds);
    },
  );

  @override
  Future<Result<void>> reorderChildren({
    required String parentId,
    required List<String> orderedIds,
  }) => _transaction(
    userMessage: '调整章节目顺序失败',
    techDetail: 'reorderChildren',
    action: () async {
      final parent = await _dao.getById(parentId);
      if (parent == null || parent.isDeleted || parent.level >= 2) {
        throw const ValidationException('目标父级不存在或层级不正确');
      }
      final actual = await _dao.childrenOf(parentId);
      _validateExactOrder(
        actualIds: actual.map((subject) => subject.id).toList(),
        orderedIds: orderedIds,
      );
      await _writeOrder(orderedIds);
    },
  );

  /// 在单一数据库事务内完成校验与写入，并保留领域校验错误。
  Future<Result<T>> _transaction<T>({
    required String userMessage,
    required String techDetail,
    required Future<T> Function() action,
  }) async {
    try {
      return Success(await _db.transaction(action));
    } on AppException catch (error) {
      return Failure(error);
    } catch (_) {
      return Failure(DatabaseException(userMessage, techDetail: techDetail));
    }
  }

  int _nextOrder(List<SubjectEntity> siblings) => siblings.fold(
    0,
    (next, subject) => subject.sortOrder >= next ? subject.sortOrder + 1 : next,
  );

  void _validateExactOrder({
    required List<String> actualIds,
    required List<String> orderedIds,
  }) {
    if (orderedIds.length != orderedIds.toSet().length ||
        actualIds.length != orderedIds.length ||
        !actualIds.toSet().containsAll(orderedIds)) {
      throw const ValidationException('列表内容已变化，请刷新后重试');
    }
  }

  void _validateTargetIndex(int targetIndex, int targetLength) {
    if (targetIndex < 0 || targetIndex > targetLength) {
      throw const ValidationException('插入位置已变化，请刷新后重试');
    }
  }

  Future<void> _writeOrder(List<String> orderedIds) async {
    for (var index = 0; index < orderedIds.length; index++) {
      final changed = await _dao.updateSubjectSortOrder(
        orderedIds[index],
        index,
      );
      if (changed != 1) {
        throw const ValidationException('章节目列表已变化，请刷新后重试');
      }
    }
  }

  @override
  Future<Result<void>> softDelete(String id) => guard(
    () async => _dao.softDelete(id, nowMs()),
    orElse: (e) =>
        const Failure(DatabaseException('删除科目失败', techDetail: 'softDelete')),
  );

  @override
  Future<Result<int>> countChildren(String? parentId) => guard(
    () async => _dao.countChildren(parentId),
    orElse: (e) => const Failure(
      DatabaseException('统计子科目失败', techDetail: 'countChildren'),
    ),
  );

  @override
  Future<Result<bool>> isEmpty() => guard(
    () async => (await _dao.totalCount()) == 0,
    orElse: (e) =>
        const Failure(DatabaseException('判空科目表失败', techDetail: 'isEmpty')),
  );
}
