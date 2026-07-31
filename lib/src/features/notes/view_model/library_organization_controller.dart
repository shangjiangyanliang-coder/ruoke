// 作用：在目录组织 UI 与三个 Repository 之间统一分派排序和移动请求。
import '../../../data/errors/app_exception.dart';
import '../../../data/errors/result.dart';
import '../models/library_organization.dart';
import '../models/note.dart';
import '../models/subject.dart';
import '../models/subject_folder.dart';
import '../repository/folder_repository.dart';
import '../repository/note_repository.dart';
import '../repository/subject_repository.dart';
import '../utils/library_organization_rules.dart';

/// 目录组织用例控制器；不持有页面草稿状态，也不直接访问 Drift。
class LibraryOrganizationController {
  final FolderRepository folders;
  final SubjectRepository subjects;
  final NoteRepository notes;

  const LibraryOrganizationController({
    required this.folders,
    required this.subjects,
    required this.notes,
  });

  /// 按请求类型读取真实父级下的完整同类列表。
  Future<Result<List<LibraryOrderItem>>> loadSiblings(
    LibraryReorderRequest request,
  ) async {
    switch (request.kind) {
      case LibraryItemKind.folder:
        return _mapFolders(await folders.childrenOf(request.parentId));
      case LibraryItemKind.book:
        return _mapSubjects(await folders.booksIn(request.parentId));
      case LibraryItemKind.chapter:
      case LibraryItemKind.section:
        final parentId = request.parentId;
        if (parentId == null) return _missingParentFailure();
        return _mapSubjects(await subjects.childrenOf(parentId));
      case LibraryItemKind.note:
        final parentId = request.parentId;
        if (parentId == null) return _missingParentFailure();
        return _mapNotes(await notes.listBySubject(parentId));
    }
  }

  /// 将排序页提交的完整 id 列表分派到对应仓储。
  Future<Result<void>> saveOrder(
    LibraryReorderRequest request,
    List<String> orderedIds,
  ) {
    switch (request.kind) {
      case LibraryItemKind.folder:
        return folders.reorderFolders(
          parentId: request.parentId,
          orderedIds: orderedIds,
        );
      case LibraryItemKind.book:
        return folders.reorderBooks(
          folderId: request.parentId,
          orderedIds: orderedIds,
        );
      case LibraryItemKind.chapter:
      case LibraryItemKind.section:
        final parentId = request.parentId;
        if (parentId == null) return Future.value(_missingParentFailure());
        return subjects.reorderChildren(
          parentId: parentId,
          orderedIds: orderedIds,
        );
      case LibraryItemKind.note:
        final parentId = request.parentId;
        if (parentId == null) return Future.value(_missingParentFailure());
        return notes.reorderNotes(subjectId: parentId, orderedIds: orderedIds);
    }
  }

  /// 一次读取完整目录快照，再由纯规则层生成移动目标。
  Future<Result<List<LibraryMoveTarget>>> loadTargets(
    LibraryMoveRequest request,
  ) async {
    final folderResult = await folders.listAll();
    if (folderResult case Failure<List<SubjectFolder>>(:final exception)) {
      return Failure(exception);
    }
    final subjectResult = await subjects.listAll();
    if (subjectResult case Failure<List<Subject>>(:final exception)) {
      return Failure(exception);
    }
    return Success(
      buildMoveTargets(
        request: request,
        folders: (folderResult as Success<List<SubjectFolder>>).value,
        subjects: (subjectResult as Success<List<Subject>>).value,
      ),
    );
  }

  /// 读取第二步插入位置页所需的目标同类列表。
  Future<Result<List<LibraryOrderItem>>> loadTargetSiblings(
    LibraryMoveRequest request,
    LibraryMoveTarget target,
  ) async {
    final invalid = _validateTarget(request, target);
    if (invalid != null) return Failure(invalid);
    switch (request.kind) {
      case LibraryItemKind.folder:
        return _mapFolders(await folders.childrenOf(target.id));
      case LibraryItemKind.book:
        return _mapSubjects(await folders.booksIn(target.id));
      case LibraryItemKind.chapter:
      case LibraryItemKind.section:
        return _mapSubjects(await subjects.childrenOf(target.id!));
      case LibraryItemKind.note:
        return _mapNotes(await notes.listBySubject(target.id!));
    }
  }

  /// 将目标和最终插入索引原样传给正确仓储。
  Future<Result<void>> move(
    LibraryMoveRequest request,
    LibraryMoveTarget target,
    int targetIndex,
  ) {
    final invalid = _validateTarget(request, target);
    if (invalid != null) return Future.value(Failure(invalid));
    switch (request.kind) {
      case LibraryItemKind.folder:
        return folders.moveFolder(
          folderId: request.itemId,
          newParentId: target.id,
          targetIndex: targetIndex,
        );
      case LibraryItemKind.book:
        return folders.moveBook(
          bookId: request.itemId,
          folderId: target.id,
          targetIndex: targetIndex,
        );
      case LibraryItemKind.chapter:
      case LibraryItemKind.section:
        return subjects.moveSubject(
          subjectId: request.itemId,
          newParentId: target.id!,
          targetIndex: targetIndex,
        );
      case LibraryItemKind.note:
        return notes.moveNote(
          noteId: request.itemId,
          subjectId: target.id!,
          targetIndex: targetIndex,
        );
    }
  }

  Result<List<LibraryOrderItem>> _mapFolders(
    Result<List<SubjectFolder>> result,
  ) => switch (result) {
    Success<List<SubjectFolder>>(:final value) => Success(
      value
          .map((item) => LibraryOrderItem(id: item.id, label: item.name))
          .toList(),
    ),
    Failure<List<SubjectFolder>>(:final exception) => Failure(exception),
  };

  Result<List<LibraryOrderItem>> _mapSubjects(Result<List<Subject>> result) =>
      switch (result) {
        Success<List<Subject>>(:final value) => Success(
          value
              .map((item) => LibraryOrderItem(id: item.id, label: item.name))
              .toList(),
        ),
        Failure<List<Subject>>(:final exception) => Failure(exception),
      };

  Result<List<LibraryOrderItem>> _mapNotes(Result<List<Note>> result) =>
      switch (result) {
        Success<List<Note>>(:final value) => Success(
          value
              .map(
                (item) =>
                    LibraryOrderItem(id: item.id, label: item.displayTitle),
              )
              .toList(),
        ),
        Failure<List<Note>>(:final exception) => Failure(exception),
      };

  ValidationException? _validateTarget(
    LibraryMoveRequest request,
    LibraryMoveTarget target,
  ) {
    if (!target.canSelect) {
      return const ValidationException('该目录节点不能作为移动目标');
    }
    final validKind = switch (request.kind) {
      LibraryItemKind.folder ||
      LibraryItemKind.book => target.kind == LibraryItemKind.folder,
      LibraryItemKind.chapter => target.kind == LibraryItemKind.book,
      LibraryItemKind.section => target.kind == LibraryItemKind.chapter,
      LibraryItemKind.note =>
        target.kind == LibraryItemKind.book ||
            target.kind == LibraryItemKind.chapter ||
            target.kind == LibraryItemKind.section,
    };
    if (!validKind ||
        (request.kind != LibraryItemKind.folder &&
            request.kind != LibraryItemKind.book &&
            target.id == null)) {
      return const ValidationException('移动目标层级不正确');
    }
    return null;
  }

  Failure<T> _missingParentFailure<T>() =>
      const Failure(ValidationException('排序父级不能为空'));
}
