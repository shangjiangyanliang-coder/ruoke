// 文件: lib/src/features/notes/repository/local_note_repository.dart
// 作用: NoteRepository 的本地实现（Drift）。Repository 是数据唯一真相源，
//       把 DAO 的 NoteEntity 翻译成领域 Note，把底层异常翻译成 AppException 放进 Result。
//       保存正文有变化时写一条 note_version 快照（第4批回退用，第2批先铺底）。
//       详见技术方案 A §2.2 + B §五 + C §6.2。
import 'package:drift/drift.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/daos/note_dao.dart';
import '../../../data/database/daos/note_version_dao.dart';
import '../../../data/errors/app_exception.dart';
import '../../../data/errors/result.dart';
import '../../../utils/delta_plain_text.dart';
import '../../../utils/id_generator.dart';
import '../../../utils/time_utils.dart';
import '../models/note.dart';
import '../models/note_version.dart';
import 'note_repository.dart';

/// NoteRepository 的本地（Drift）实现。
class LocalNoteRepository implements NoteRepository {
  final AppDatabase _db;

  LocalNoteRepository(this._db);

  NoteDao get _noteDao => _db.noteDao;
  NoteVersionDao get _versionDao => _db.noteVersionDao;

  @override
  Future<Result<List<Note>>> listAll() => guard(
        () async => (await _noteDao.listAll()).map(Note.fromEntity).toList(),
        orElse: (e) => const Failure(
          DatabaseException('读取笔记列表失败', techDetail: 'listAll'),
        ),
      );

  @override
  Future<Result<Note?>> getById(String id) => guard(
        () async {
          final e = await _noteDao.getById(id);
          return e == null ? null : Note.fromEntity(e);
        },
        orElse: (e) => const Failure(
          DatabaseException('读取笔记失败', techDetail: 'getById'),
        ),
      );

  @override
  Future<Result<String>> create({
    required String subjectId,
    String? title,
    String? contentJson,
    String? plainText,
    bool isDraft = false,
  }) =>
      guard(
        () async {
          final now = nowMs();
          final id = newId();
          // plain_text 由 contentJson 派生（UI 不用关心）；外部显式传 plainText 时优先用
          final derivedPlain = plainText ?? deltaJsonToPlainText(contentJson);
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
          return id;
        },
        orElse: (e) => const Failure(
          DatabaseException('新建笔记失败', techDetail: 'create'),
        ),
      );

  @override
  Future<Result<void>> update({
    required String id,
    String? title,
    String? contentJson,
    String? plainText,
    bool? isDraft,
  }) =>
      guard(
        () async {
          final now = nowMs();
          // 取旧笔记：若正文相对上一版有变化则写一条 version 快照
          final old = await _noteDao.getById(id);
          if (old != null && contentJson != null && contentJson != old.contentJson) {
            final maxVersion = await _versionDao.maxVersionNo(id);
            await _versionDao.insertVersion(
              NoteVersionsCompanion(
                id: Value(newId()),
                noteId: Value(id),
                versionNo: Value(maxVersion + 1),
                snapshotJson: Value(old.contentJson ?? ''),
                createdAt: Value(now),
              ),
            );
          }
          await _noteDao.updateNote(
            id,
            title: title,
            contentJson: contentJson,
            plainText: plainText ?? deltaJsonToPlainText(contentJson),
            isDraft: isDraft,
            updatedAt: now,
          );
        },
        orElse: (e) => const Failure(
          DatabaseException('保存笔记失败', techDetail: 'update'),
        ),
      );

  @override
  Future<Result<void>> softDelete(String id) => guard(
        () async => _noteDao.softDelete(id, nowMs()),
        orElse: (e) => const Failure(
          DatabaseException('删除笔记失败', techDetail: 'softDelete'),
        ),
      );

  @override
  Future<Result<List<NoteVersion>>> listVersions(String noteId) => guard(
        () async =>
            (await _versionDao.listByNote(noteId)).map(NoteVersion.fromEntity).toList(),
        orElse: (e) => const Failure(
          DatabaseException('读取历史版本失败', techDetail: 'listVersions'),
        ),
      );
}
