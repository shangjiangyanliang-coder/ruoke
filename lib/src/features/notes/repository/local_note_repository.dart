// 文件: lib/src/features/notes/repository/local_note_repository.dart
// 作用: NoteRepository 的本地实现（Drift）。Repository 是数据唯一真相源，
//       把 DAO 的 NoteEntity 翻译成领域 Note，把底层异常翻译成 AppException 放进 Result。
//       保存正文有变化时写一条 note_version 快照（第4批回退用，第2批先铺底）。
//       详见技术方案 A §2.2 + B §五 + C §6.2。
import 'package:drift/drift.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/daos/note_dao.dart';
import '../../../data/database/daos/note_highlight_dao.dart';
import '../../../data/database/daos/note_version_dao.dart';
import '../../../data/errors/app_exception.dart';
import '../../../data/errors/result.dart';
import '../../../utils/delta_plain_text.dart';
import '../../../utils/id_generator.dart';
import '../../../utils/time_utils.dart';
import '../models/note.dart';
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
    if (scope.kind == SubjectScopeKind.level) {
      return subjects
          .where((subject) => subject.level == scope.level)
          .map((subject) => subject.id)
          .toSet();
    }

    final targetId = scope.subjectId!;
    if (!subjects.any((subject) => subject.id == targetId)) {
      throw const ValidationException('所选范围已不存在，请重新选择');
    }
    final childrenByParent = <String, List<String>>{};
    for (final subject in subjects) {
      final parentId = subject.parentId;
      if (parentId != null) {
        childrenByParent.putIfAbsent(parentId, () => []).add(subject.id);
      }
    }
    final result = <String>{};
    final pending = <String>[targetId];
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
  }) => guard(
    () async {
      final now = nowMs();
      final id = newId();
      // plain_text 由 contentJson 派生（UI 不用关心）；外部显式传 plainText 时优先用
      final derivedPlain = plainText ?? deltaJsonToPlainText(contentJson);
      return _db.transaction(() async {
        await _noteDao.insertNote(
          NotesCompanion(
            id: Value(id),
            subjectId: Value(subjectId),
            title: Value(title),
            contentJson: Value(contentJson),
            plainText: Value(derivedPlain),
            isDraft: Value(isDraft),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
        await _replaceHighlights(id, contentJson, now);
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
  }) => guard(
    () async {
      final now = nowMs();
      await _db.transaction(() async {
        // 取旧笔记：若正文相对上一版有变化则写一条 version 快照。
        final old = await _noteDao.getById(id);
        if (old == null) {
          throw StateError('笔记不存在: $id');
        }
        if (contentJson != null && contentJson != old.contentJson) {
          await _saveVersion(
            noteId: id,
            snapshotJson: old.contentJson ?? '',
            createdAt: now,
          );
        }
        final updatedRows = await _noteDao.updateNote(
          id,
          title: title,
          contentJson: contentJson,
          plainText: plainText ?? deltaJsonToPlainText(contentJson),
          isDraft: isDraft,
          updatedAt: now,
        );
        if (updatedRows != 1) {
          throw StateError('更新笔记行数异常: $id/$updatedRows');
        }
        if (contentJson != null) {
          await _replaceHighlights(id, contentJson, now);
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
        if (current.contentJson != target.snapshotJson) {
          await _saveVersion(
            noteId: noteId,
            snapshotJson: current.contentJson ?? '',
            createdAt: now,
          );
        }
        final updatedRows = await _noteDao.updateNote(
          noteId,
          contentJson: target.snapshotJson,
          plainText: deltaJsonToPlainText(target.snapshotJson),
          updatedAt: now,
        );
        if (updatedRows != 1) {
          throw StateError('恢复笔记行数异常: $noteId/$updatedRows');
        }
        await _replaceHighlights(noteId, target.snapshotJson, now);
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
}
