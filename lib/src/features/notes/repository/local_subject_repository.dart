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
    int sortOrder = 0,
  }) => guard(
    () async {
      final now = nowMs();
      final id = newId();
      await _dao.insertSubject(
        SubjectsCompanion(
          id: Value(id),
          parentId: Value(parentId),
          folderId: Value(folderId),
          name: Value(name),
          level: Value(level),
          sortOrder: Value(sortOrder),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      return id;
    },
    orElse: (e) =>
        const Failure(DatabaseException('新建科目失败', techDetail: 'create')),
  );

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
