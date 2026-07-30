// 文件: lib/src/features/notes/repository/local_note_repository.dart
// 作用: NoteRepository 的本地实现（Drift）。Repository 是数据唯一真相源，
//       把 DAO 的 NoteEntity 翻译成领域 Note，把底层异常翻译成 AppException 放进 Result。
//       保存正文有变化时写一条 note_version 快照（第4批回退用，第2批先铺底）。
//       详见技术方案 A §2.2 + B §五 + C §6.2。
import 'package:drift/drift.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/daos/note_dao.dart';
import '../../../data/database/daos/note_highlight_dao.dart';
import '../../../data/database/daos/note_tag_dao.dart';
import '../../../data/database/daos/note_version_dao.dart';
import '../../../data/database/daos/tag_dao.dart';
import '../../../data/errors/app_exception.dart';
import '../../../data/errors/result.dart';
import '../../../utils/delta_plain_text.dart';
import '../../../utils/id_generator.dart';
import '../../../utils/time_utils.dart';
import '../models/note.dart';
import '../models/note_edit_snapshot.dart';
import '../models/note_search_query.dart';
import '../models/note_version.dart';
import '../models/search_match_mode.dart';
import '../models/subject_scope.dart';
import '../utils/highlight_extractor.dart';
import 'note_repository.dart';

/// NoteRepository 的本地（Drift）实现。
class LocalNoteRepository implements NoteRepository {
  final AppDatabase _db;

  LocalNoteRepository(this._db);

  NoteDao get _noteDao => _db.noteDao;
  NoteHighlightDao get _highlightDao => _db.noteHighlightDao;
  NoteVersionDao get _versionDao => _db.noteVersionDao;
  NoteTagDao get _noteTagDao => _db.noteTagDao;
  TagDao get _tagDao => _db.tagDao;

  @override
  Future<Result<List<Note>>> listAll() => guard(
    () async => (await _noteDao.listAll()).map(Note.fromEntity).toList(),
    orElse: (e) =>
        const Failure(DatabaseException('读取笔记列表失败', techDetail: 'listAll')),
  );

  @override
  Future<Result<Note?>> getById(String id) => guard(
    () async {
      final e = await _noteDao.getById(id);
      return e == null ? null : Note.fromEntity(e);
    },
    orElse: (e) =>
        const Failure(DatabaseException('读取笔记失败', techDetail: 'getById')),
  );

  @override
  Future<Result<List<Note>>> search(NoteSearchQuery query) => guard(
    () async {
      final keyword = query.keyword.trim();
      final sortOrder = switch (query.sortOrder) {
        NoteSortOrder.updatedDesc => NoteDaoSortOrder.updatedDesc,
        NoteSortOrder.updatedAsc => NoteDaoSortOrder.updatedAsc,
        NoteSortOrder.titleAsc => NoteDaoSortOrder.titleAsc,
      };
      final matchMode = switch (query.keywordMatchMode) {
        SearchMatchMode.contains => NoteDaoMatchMode.contains,
        SearchMatchMode.exact => NoteDaoMatchMode.exact,
      };
      final subjectIds = await _resolveSubjectIds(query.subjectScope);
      final entities = await _noteDao.search(
        keyword: keyword.isEmpty ? null : keyword,
        matchMode: matchMode,
        tagIds: query.tagIds,
        subjectIds: subjectIds,
        sortOrder: sortOrder,
      );
      return entities.map(Note.fromEntity).toList();
    },
    orElse: (e) => e is ValidationException
        ? Failure(e)
        : const Failure(DatabaseException('搜索笔记失败', techDetail: 'search')),
  );

  Future<Set<String>?> _resolveSubjectIds(SubjectScope scope) async {
    if (scope.kind == SubjectScopeKind.all) return null;

    final subjects = await _db.subjectDao.listAll();
    if (scope.kind == SubjectScopeKind.ungroupedBooks) {
      return _descendantSubjectIds(
        subjects,
        subjects
            .where((subject) => subject.level == 0 && subject.folderId == null)
            .map((subject) => subject.id),
      );
    }
    if (scope.kind == SubjectScopeKind.level) {
      return subjects
          .where((subject) => subject.level == scope.level)
          .map((subject) => subject.id)
          .toSet();
    }

    if (scope.kind == SubjectScopeKind.folder) {
      final targetId = scope.subjectId!;
      final folders = await _db.folderDao.listAll();
      if (!folders.any((folder) => folder.id == targetId)) {
        throw const ValidationException('所选范围已不存在，请重新选择');
      }
      final folderChildren = <String, List<String>>{};
      for (final folder in folders) {
        if (folder.parentId != null) {
          (folderChildren[folder.parentId!] ??= []).add(folder.id);
        }
      }
      final folderIds = <String>{};
      final pendingFolders = <String>[targetId];
      while (pendingFolders.isNotEmpty) {
        final current = pendingFolders.removeLast();
        if (folderIds.add(current)) {
          pendingFolders.addAll(folderChildren[current] ?? const []);
        }
      }
      return _descendantSubjectIds(
        subjects,
        subjects
            .where((subject) => subject.level == 0 && folderIds.contains(subject.folderId))
            .map((subject) => subject.id),
      );
    }

    final targetId = scope.subjectId!;
    if (!subjects.any((subject) => subject.id == targetId)) {
      throw const ValidationException('所选范围已不存在，请重新选择');
    }
    return _descendantSubjectIds(subjects, [targetId]);
  }

  Set<String> _descendantSubjectIds(
    List<SubjectEntity> subjects,
    Iterable<String> roots,
  ) {
    final childrenByParent = <String, List<String>>{};
    for (final subject in subjects) {
      final parentId = subject.parentId;
      if (parentId != null) {
        childrenByParent.putIfAbsent(parentId, () => []).add(subject.id);
      }
    }
    final result = <String>{};
    final pending = <String>[...roots];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (result.add(current)) {
        pending.addAll(childrenByParent[current] ?? const []);
      }
    }
    return result;
  }

  @override
  Future<Result<Note>> create({
    required String subjectId,
    String? title,
    String? contentJson,
    String? plainText,
    bool isDraft = false,
    Iterable<String> tagNames = const [],
  }) => guard(
    () async {
      final now = nowMs();
      final id = newId();
      final normalizedTitle = title?.trim();
      final storedTitle = normalizedTitle == null || normalizedTitle.isEmpty
          ? null
          : normalizedTitle;
      // plain_text 由 contentJson 派生（UI 不用关心）；外部显式传 plainText 时优先用
      final derivedPlain = plainText ?? deltaJsonToPlainText(contentJson);
      return _db.transaction(() async {
        await _noteDao.insertNote(
          NotesCompanion(
            id: Value(id),
            subjectId: Value(subjectId),
            title: Value(storedTitle),
            contentJson: Value(contentJson),
            plainText: Value(derivedPlain),
            isDraft: Value(isDraft),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
        await _replaceHighlights(id, contentJson, now);
        await _replaceTagsByNames(id, tagNames, now);
        final created = await _noteDao.getById(id);
        if (created == null) {
          throw StateError('新建笔记后回读失败: $id');
        }
        return Note.fromEntity(created);
      });
    },
    orElse: (e) =>
        const Failure(DatabaseException('新建笔记失败', techDetail: 'create')),
  );

  @override
  Future<Result<void>> update({
    required String id,
    String? title,
    String? contentJson,
    String? plainText,
    bool? isDraft,
    Iterable<String>? tagNames,
  }) => guard(
    () async {
      final now = nowMs();
      await _db.transaction(() async {
        final old = await _noteDao.getById(id);
        if (old == null) {
          throw StateError('笔记不存在: $id');
        }
        final oldTagNames = await _listTagNames(id);
        final nextTitle = title == null
            ? old.title
            : (title.trim().isEmpty ? null : title.trim());
        final nextContentJson = contentJson ?? old.contentJson;
        final nextTagNames = tagNames == null
            ? oldTagNames
            : NoteEditSnapshot(
                title: null,
                contentJson: null,
                tagNames: tagNames,
              ).tagNames;
        final oldSnapshot = NoteEditSnapshot(
          title: old.title,
          contentJson: old.contentJson,
          tagNames: oldTagNames,
        );
        final nextSnapshot = NoteEditSnapshot(
          title: nextTitle,
          contentJson: nextContentJson,
          tagNames: nextTagNames,
        );
        if (oldSnapshot.hasSameContent(nextSnapshot)) return;
        await _saveVersion(
          noteId: id,
          snapshotJson: oldSnapshot.encode(),
          createdAt: now,
        );
        final updatedRows = await _noteDao.replaceEditableState(
          id,
          title: nextTitle,
          contentJson: nextContentJson,
          plainText:
              plainText ??
              (contentJson == null
                  ? old.plainText
                  : deltaJsonToPlainText(nextContentJson)),
          isDraft: isDraft ?? old.isDraft,
          updatedAt: now,
        );
        if (updatedRows != 1) {
          throw StateError('更新笔记行数异常: $id/$updatedRows');
        }
        if (contentJson != null) {
          await _replaceHighlights(id, nextContentJson, now);
        }
        if (tagNames != null) {
          await _replaceTagsByNames(id, nextTagNames, now);
        }
      });
    },
    orElse: (e) =>
        const Failure(DatabaseException('保存笔记失败', techDetail: 'update')),
  );

  @override
  Future<Result<void>> softDelete(String id) => guard(
    () async => _noteDao.softDelete(id, nowMs()),
    orElse: (e) =>
        const Failure(DatabaseException('删除笔记失败', techDetail: 'softDelete')),
  );

  @override
  Future<Result<void>> restoreVersion({
    required String noteId,
    required int versionNo,
    bool saveCurrentBeforeRestore = false,
  }) => guard(
    () async {
      final now = nowMs();
      await _db.transaction(() async {
        final current = await _noteDao.getById(noteId);
        if (current == null) {
          throw StateError('笔记不存在: $noteId');
        }
        final target = await _versionDao.getByVersion(noteId, versionNo);
        if (target == null) {
          throw StateError('历史版本不存在: $noteId/$versionNo');
        }
        final currentTagNames = await _listTagNames(noteId);
        final currentSnapshot = NoteEditSnapshot(
          title: current.title,
          contentJson: current.contentJson,
          tagNames: currentTagNames,
        );
        final decodedTarget = NoteEditSnapshot.decode(target.snapshotJson);
        final restoredSnapshot = decodedTarget.isLegacy
            ? NoteEditSnapshot(
                title: current.title,
                contentJson: decodedTarget.contentJson,
                tagNames: currentTagNames,
              )
            : decodedTarget;
        if (saveCurrentBeforeRestore &&
            !currentSnapshot.hasSameContent(restoredSnapshot)) {
          await _saveVersion(
            noteId: noteId,
            snapshotJson: currentSnapshot.encode(),
            createdAt: now,
          );
        }
        final updatedRows = await _noteDao.replaceEditableState(
          noteId,
          title: restoredSnapshot.title,
          contentJson: restoredSnapshot.contentJson,
          plainText: deltaJsonToPlainText(restoredSnapshot.contentJson),
          isDraft: current.isDraft,
          updatedAt: now,
        );
        if (updatedRows != 1) {
          throw StateError('恢复笔记行数异常: $noteId/$updatedRows');
        }
        await _replaceHighlights(noteId, restoredSnapshot.contentJson, now);
        await _replaceTagsByNames(noteId, restoredSnapshot.tagNames, now);
      });
    },
    orElse: (e) => const Failure(
      DatabaseException('恢复历史版本失败', techDetail: 'restoreVersion'),
    ),
  );

  @override
  Future<Result<List<NoteVersion>>> listVersions(String noteId) => guard(
    () async => (await _versionDao.listByNote(
      noteId,
    )).map(NoteVersion.fromEntity).toList(),
    orElse: (e) => const Failure(
      DatabaseException('读取历史版本失败', techDetail: 'listVersions'),
    ),
  );

  @override
  Future<Result<void>> deleteVersions({
    required String noteId,
    required Set<String> versionIds,
  }) => guard(
    () async {
      if (versionIds.isEmpty) return;
      // 先全量校验再删除，避免跨笔记 ID 导致部分版本已被误删。
      await _db.transaction(() async {
        final versions = await _versionDao.listByIds(versionIds);
        if (versions.any((version) => version.noteId != noteId)) {
          throw const ValidationException('历史版本不属于当前笔记');
        }
        await _versionDao.deleteByIds(
          versions.map((version) => version.id).toSet(),
        );
      });
    },
    orElse: (e) => e is ValidationException
        ? Failure(e)
        : const Failure(
            DatabaseException('删除历史版本失败', techDetail: 'deleteVersions'),
          ),
  );

  @override
  Future<Result<void>> renameVersion({
    required String noteId,
    required String versionId,
    required String? name,
  }) => guard(
    () async {
      await _db.transaction(() async {
        final version = await _versionDao.getById(versionId);
        if (version == null) {
          throw const ValidationException('历史版本已不存在，请刷新后重试');
        }
        if (version.noteId != noteId) {
          throw const ValidationException('历史版本不属于当前笔记');
        }
        final normalized = name?.trim();
        final storedName = normalized == null || normalized.isEmpty
            ? null
            : normalized;
        if (storedName != null && storedName.length > 50) {
          throw const ValidationException('版本名称不能超过50个字符');
        }
        if (storedName != null) {
          final conflict = await _versionDao.getByName(
            noteId: noteId,
            name: storedName,
            excludingVersionId: versionId,
          );
          if (conflict != null) {
            throw const ValidationException('版本名称已存在');
          }
        }
        final updated = await _versionDao.renameVersion(versionId, storedName);
        if (updated != 1) {
          throw StateError('更新历史版本名称行数异常: $versionId/$updated');
        }
      });
    },
    orElse: (e) => e is ValidationException
        ? Failure(e)
        : const Failure(
            DatabaseException('重命名历史版本失败', techDetail: 'renameVersion'),
          ),
  );

  Future<void> _saveVersion({
    required String noteId,
    required String snapshotJson,
    required int createdAt,
  }) async {
    final maxVersion = await _versionDao.maxVersionNo(noteId);
    await _versionDao.insertVersion(
      NoteVersionsCompanion(
        id: Value(newId()),
        noteId: Value(noteId),
        versionNo: Value(maxVersion + 1),
        snapshotJson: Value(snapshotJson),
        createdAt: Value(createdAt),
      ),
    );
  }

  Future<void> _replaceHighlights(
    String noteId,
    String? contentJson,
    int createdAt,
  ) async {
    final drafts = HighlightExtractor.extract(contentJson);
    await _highlightDao.deleteByNote(noteId);
    for (final draft in drafts) {
      await _highlightDao.insertHighlight(
        NoteHighlightsCompanion(
          id: Value(newId()),
          noteId: Value(noteId),
          kind: Value(draft.kind),
          body: Value(draft.body),
          createdAt: Value(createdAt),
        ),
      );
    }
  }

  Future<List<String>> _listTagNames(String noteId) async {
    final links = await _noteTagDao.listByNote(noteId);
    final tags = await _tagDao.listByIds(
      links.map((link) => link.tagId).toList(),
    );
    return tags.map((tag) => tag.name).toList();
  }

  Future<void> _replaceTagsByNames(
    String noteId,
    Iterable<String> names,
    int createdAt,
  ) async {
    final normalizedNames = NoteEditSnapshot(
      title: null,
      contentJson: null,
      tagNames: names,
    ).tagNames;
    await _noteTagDao.deleteByNote(noteId);
    for (final name in normalizedNames) {
      var tag = await _tagDao.getByName(name);
      tag ??= TagEntity(
        id: newId(),
        name: name,
        color: null,
        createdAt: createdAt,
      );
      if (await _tagDao.getByName(name) == null) {
        await _tagDao.insertTag(tag);
      }
      await _noteTagDao.insertNoteTag(
        NoteTagEntity(noteId: noteId, tagId: tag.id, createdAt: createdAt),
      );
    }
  }
}
