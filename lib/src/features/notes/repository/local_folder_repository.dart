// 文件: lib/src/features/notes/repository/local_folder_repository.dart
// 作用: FolderRepository 的本地 Drift 实现，负责文件夹基础持久化。
import 'package:drift/drift.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/daos/folder_dao.dart';
import '../../../data/errors/app_exception.dart';
import '../../../data/errors/result.dart';
import '../../../utils/id_generator.dart';
import '../../../utils/time_utils.dart';
import '../models/subject_folder.dart';
import '../models/subject.dart';
import 'folder_repository.dart';

/// 文件夹仓储的本地实现。
class LocalFolderRepository implements FolderRepository {
  final AppDatabase _db;

  LocalFolderRepository(this._db);

  FolderDao get _dao => _db.folderDao;

  @override
  Future<Result<List<SubjectFolder>>> listAll() => guard(
    () async => (await _dao.listAll()).map(SubjectFolder.fromEntity).toList(),
    orElse: (error) => const Failure(
      DatabaseException('读取文件夹失败', techDetail: 'listAllFolders'),
    ),
  );

  @override
  Future<Result<List<Subject>>> booksIn(String? folderId) => guard(
    () async => (await _dao.booksIn(folderId)).map(Subject.fromEntity).toList(),
    orElse: (error) => const Failure(
      DatabaseException('读取文件夹内书籍失败', techDetail: 'booksInFolder'),
    ),
  );

  @override
  Future<Result<String>> create({required String name, String? parentId}) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      return const Failure(ValidationException('文件夹名称不能为空'));
    }
    try {
      if (parentId != null && await _dao.getActiveById(parentId) == null) {
        return const Failure(ValidationException('父文件夹不存在或已删除'));
      }
      final existing = await _dao.findActiveByParentAndName(
        parentId,
        normalizedName,
      );
      if (existing != null) {
        return const Failure(ValidationException('同一目录下不能有同名文件夹'));
      }
    } catch (_) {
      return const Failure(
        DatabaseException('新建文件夹失败', techDetail: 'checkFolderName'),
      );
    }
    return guard(
      () async {
        final now = nowMs();
        final id = newId();
        await _dao.insertFolder(
          SubjectFoldersCompanion(
            id: Value(id),
            parentId: Value(parentId),
            name: Value(normalizedName),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
        return id;
      },
      orElse: (error) => const Failure(
        DatabaseException('新建文件夹失败', techDetail: 'createFolder'),
      ),
    );
  }

  @override
  Future<Result<void>> rename({required String id, required String name}) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      return const Failure(ValidationException('文件夹名称不能为空'));
    }
    try {
      final target = await _dao.getActiveById(id);
      if (target == null) {
        return const Failure(ValidationException('文件夹不存在或已删除'));
      }
      final existing = await _dao.findActiveByParentAndName(
        target.parentId,
        normalizedName,
      );
      if (existing != null && existing.id != id) {
        return const Failure(ValidationException('同一目录下不能有同名文件夹'));
      }
    } catch (_) {
      return const Failure(
        DatabaseException('重命名文件夹失败', techDetail: 'checkRenameFolder'),
      );
    }
    return guard(
      () async {
        await _dao.rename(id, normalizedName, nowMs());
      },
      orElse: (error) => const Failure(
        DatabaseException('重命名文件夹失败', techDetail: 'renameFolder'),
      ),
    );
  }

  @override
  Future<Result<void>> moveFolder({
    required String folderId,
    required String? newParentId,
  }) async {
    try {
      if (await _dao.getActiveById(folderId) == null) {
        return const Failure(ValidationException('文件夹不存在或已删除'));
      }
      if (newParentId != null && await _dao.getActiveById(newParentId) == null) {
        return const Failure(ValidationException('目标文件夹不存在或已删除'));
      }
      if (newParentId != null &&
          await _wouldCreateFolderCycle(folderId, newParentId)) {
        return const Failure(ValidationException('不能将文件夹移动到自身或后代'));
      }
    } catch (_) {
      return const Failure(
        DatabaseException('移动文件夹失败', techDetail: 'checkMoveFolder'),
      );
    }
    return guard(
      () async {
        await _dao.move(folderId, newParentId, nowMs());
      },
      orElse: (error) => const Failure(
        DatabaseException('移动文件夹失败', techDetail: 'moveFolder'),
      ),
    );
  }

  @override
  Future<Result<void>> moveBook({
    required String bookId,
    required String? folderId,
  }) async {
    try {
      final book = await _db.subjectDao.getById(bookId);
      if (book == null || book.isDeleted || book.level != 0) {
        return const Failure(ValidationException('只能移动未删除的书'));
      }
      if (folderId != null && await _dao.getActiveById(folderId) == null) {
        return const Failure(ValidationException('目标文件夹不存在或已删除'));
      }
    } catch (_) {
      return const Failure(
        DatabaseException('移动书失败', techDetail: 'checkMoveBook'),
      );
    }
    return guard(
      () async {
        await _db.subjectDao.updateFolder(bookId, folderId, nowMs());
      },
      orElse: (error) =>
          const Failure(DatabaseException('移动书失败', techDetail: 'moveBook')),
    );
  }

  @override
  Future<Result<void>> dissolve(String folderId) async {
    final targetResult = await guard(
      () => _dao.getActiveById(folderId),
      orElse: (error) => const Failure<SubjectFolderEntity?>(
        DatabaseException('解散文件夹失败', techDetail: 'readDissolveTarget'),
      ),
    );
    if (targetResult case Failure<SubjectFolderEntity?>()) {
      return Failure(targetResult.exception);
    }
    final target = (targetResult as Success<SubjectFolderEntity?>).value;
    if (target == null) {
      return const Failure(ValidationException('文件夹不存在或已删除'));
    }
    return guard(
      () async {
        final now = nowMs();
        await _db.transaction(() async {
          await (_db.update(_db.subjectFolders)
                ..where((folder) => folder.parentId.equals(folderId)))
              .write(
                SubjectFoldersCompanion(
                  parentId: Value(target.parentId),
                  updatedAt: Value(now),
                ),
              );
          await (_db.update(_db.subjects)
                ..where(
                  (subject) =>
                      subject.folderId.equals(folderId) &
                      subject.level.equals(0),
                ))
              .write(
                SubjectsCompanion(
                  folderId: Value(target.parentId),
                  updatedAt: Value(now),
                ),
              );
          await (_db.update(_db.subjectFolders)
                ..where((folder) => folder.id.equals(folderId)))
              .write(
                SubjectFoldersCompanion(
                  isDeleted: const Value(true),
                  deletedAt: Value(now),
                  updatedAt: Value(now),
                ),
              );
        });
      },
      orElse: (error) => const Failure(
        DatabaseException('解散文件夹失败', techDetail: 'dissolveFolder'),
      ),
    );
  }

  /// 检查目标父目录是否为待移动文件夹自身或其任意后代。
  Future<bool> _wouldCreateFolderCycle(
    String folderId,
    String newParentId,
  ) async {
    final childrenByParent = <String, List<String>>{};
    for (final folder in await _dao.listAll()) {
      final parentId = folder.parentId;
      if (parentId != null) {
        (childrenByParent[parentId] ??= []).add(folder.id);
      }
    }
    final pending = <String>[folderId];
    final visited = <String>{};
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (!visited.add(current)) continue;
      if (current == newParentId) return true;
      pending.addAll(childrenByParent[current] ?? const []);
    }
    return false;
  }

  @override
  Future<Result<List<SubjectFolder>>> childrenOf(String? parentId) => guard(
    () async =>
        (await _dao.childrenOf(parentId)).map(SubjectFolder.fromEntity).toList(),
    orElse: (error) => const Failure(
      DatabaseException('读取文件夹失败', techDetail: 'folderChildrenOf'),
    ),
  );
}
