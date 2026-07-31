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
  Future<Result<String>> create({
    required String name,
    String? parentId,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      return const Failure(ValidationException('文件夹名称不能为空'));
    }
    return _transaction(
      userMessage: '新建文件夹失败',
      techDetail: 'createFolder',
      action: () async {
        if (parentId != null && await _dao.getActiveById(parentId) == null) {
          throw const ValidationException('父文件夹不存在或已删除');
        }
        final existing = await _dao.findActiveByParentAndName(
          parentId,
          normalizedName,
        );
        if (existing != null) {
          throw const ValidationException('同一目录下不能有同名文件夹');
        }
        final siblings = await _dao.childrenOf(parentId);
        final now = nowMs();
        final id = newId();
        await _dao.insertFolder(
          SubjectFoldersCompanion(
            id: Value(id),
            parentId: Value(parentId),
            name: Value(normalizedName),
            sortOrder: Value(_nextFolderOrder(siblings)),
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
    required int targetIndex,
  }) async {
    return _transaction(
      userMessage: '移动文件夹失败',
      techDetail: 'moveFolder',
      action: () async {
        final moving = await _dao.getActiveById(folderId);
        if (moving == null) {
          throw const ValidationException('文件夹不存在或已删除');
        }
        if (newParentId != null &&
            await _dao.getActiveById(newParentId) == null) {
          throw const ValidationException('目标文件夹不存在或已删除');
        }
        if (newParentId != null &&
            await _wouldCreateFolderCycle(folderId, newParentId)) {
          throw const ValidationException('不能将文件夹移动到自身或后代');
        }

        final source = await _dao.childrenOf(moving.parentId);
        final target = moving.parentId == newParentId
            ? source
            : await _dao.childrenOf(newParentId);
        final sourceIds = source.map((folder) => folder.id).toList();
        if (!sourceIds.remove(folderId)) {
          throw const ValidationException('文件夹列表已变化，请刷新后重试');
        }
        final targetIds = target
            .map((folder) => folder.id)
            .where((id) => id != folderId)
            .toList();
        _validateTargetIndex(targetIndex, targetIds.length);
        targetIds.insert(targetIndex, folderId);

        if (moving.parentId != newParentId) {
          await _writeFolderOrder(sourceIds);
        }
        await _dao.updateFolderParentAndOrder(
          folderId,
          newParentId,
          targetIndex,
          nowMs(),
        );
        await _writeFolderOrder(targetIds);
      },
    );
  }

  @override
  Future<Result<void>> reorderFolders({
    required String? parentId,
    required List<String> orderedIds,
  }) => _transaction(
    userMessage: '调整文件夹顺序失败',
    techDetail: 'reorderFolders',
    action: () async {
      final actual = await _dao.childrenOf(parentId);
      _validateExactOrder(
        actualIds: actual.map((folder) => folder.id).toList(),
        orderedIds: orderedIds,
      );
      await _writeFolderOrder(orderedIds);
    },
  );

  @override
  Future<Result<void>> moveBook({
    required String bookId,
    required String? folderId,
    required int targetIndex,
  }) async {
    return _transaction(
      userMessage: '移动书失败',
      techDetail: 'moveBook',
      action: () async {
        final book = await _db.subjectDao.getById(bookId);
        if (book == null || book.isDeleted || book.level != 0) {
          throw const ValidationException('只能移动未删除的书');
        }
        if (folderId != null && await _dao.getActiveById(folderId) == null) {
          throw const ValidationException('目标文件夹不存在或已删除');
        }

        final source = await _dao.booksIn(book.folderId);
        final target = book.folderId == folderId
            ? source
            : await _dao.booksIn(folderId);
        final sourceIds = source.map((subject) => subject.id).toList();
        if (!sourceIds.remove(bookId)) {
          throw const ValidationException('书籍列表已变化，请刷新后重试');
        }
        final targetIds = target
            .map((subject) => subject.id)
            .where((id) => id != bookId)
            .toList();
        _validateTargetIndex(targetIndex, targetIds.length);
        targetIds.insert(targetIndex, bookId);

        if (book.folderId != folderId) {
          await _writeSubjectOrder(sourceIds);
        }
        await _db.subjectDao.updateBookFolderAndOrder(
          bookId,
          folderId,
          targetIndex,
          nowMs(),
        );
        await _writeSubjectOrder(targetIds);
      },
    );
  }

  @override
  Future<Result<void>> reorderBooks({
    required String? folderId,
    required List<String> orderedIds,
  }) => _transaction(
    userMessage: '调整书籍顺序失败',
    techDetail: 'reorderBooks',
    action: () async {
      final actual = await _dao.booksIn(folderId);
      _validateExactOrder(
        actualIds: actual.map((subject) => subject.id).toList(),
        orderedIds: orderedIds,
      );
      await _writeSubjectOrder(orderedIds);
    },
  );

  @override
  Future<Result<void>> dissolve(String folderId) => _transaction(
    userMessage: '解散文件夹失败',
    techDetail: 'dissolveFolder',
    action: () async {
      final target = await _dao.getActiveById(folderId);
      if (target == null) {
        throw const ValidationException('文件夹不存在或已删除');
      }
      final now = nowMs();
      final destinationFolders = (await _dao.childrenOf(target.parentId))
          .where((folder) => folder.id != folderId)
          .map((folder) => folder.id)
          .toList();
      final movedFolders = await _dao.childrenOf(folderId);
      for (final folder in movedFolders) {
        final order = destinationFolders.length;
        await _dao.updateFolderParentAndOrder(
          folder.id,
          target.parentId,
          order,
          now,
        );
        destinationFolders.add(folder.id);
      }
      await _writeFolderOrder(destinationFolders);

      final destinationBooks = (await _dao.booksIn(
        target.parentId,
      )).map((book) => book.id).toList();
      final movedBooks = await _dao.booksIn(folderId);
      for (final book in movedBooks) {
        final order = destinationBooks.length;
        await _db.subjectDao.updateBookFolderAndOrder(
          book.id,
          target.parentId,
          order,
          now,
        );
        destinationBooks.add(book.id);
      }
      await _writeSubjectOrder(destinationBooks);

      await (_db.update(
        _db.subjectFolders,
      )..where((folder) => folder.id.equals(folderId))).write(
        SubjectFoldersCompanion(
          isDeleted: const Value(true),
          deletedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    },
  );

  /// 在单一数据库事务内完成校验和写入，并保留可读的领域校验错误。
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

  int _nextFolderOrder(List<SubjectFolderEntity> siblings) => siblings.fold(
    0,
    (next, folder) => folder.sortOrder >= next ? folder.sortOrder + 1 : next,
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

  Future<void> _writeFolderOrder(List<String> orderedIds) async {
    for (var index = 0; index < orderedIds.length; index++) {
      final changed = await _dao.updateFolderSortOrder(
        orderedIds[index],
        index,
      );
      if (changed != 1) {
        throw const ValidationException('文件夹列表已变化，请刷新后重试');
      }
    }
  }

  Future<void> _writeSubjectOrder(List<String> orderedIds) async {
    for (var index = 0; index < orderedIds.length; index++) {
      final changed = await _db.subjectDao.updateSubjectSortOrder(
        orderedIds[index],
        index,
      );
      if (changed != 1) {
        throw const ValidationException('书籍列表已变化，请刷新后重试');
      }
    }
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
    () async => (await _dao.childrenOf(
      parentId,
    )).map(SubjectFolder.fromEntity).toList(),
    orElse: (error) => const Failure(
      DatabaseException('读取文件夹失败', techDetail: 'folderChildrenOf'),
    ),
  );
}
