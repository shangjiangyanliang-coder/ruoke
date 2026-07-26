// 文件: lib/src/features/notes/repository/note_repository.dart
// 作用: 笔记 Repository 抽象接口。ViewModel 只认此接口，不碰 Drift/DAO。
//       方法返回 Result<T>，把底层异常翻译成 AppException，不让 SQL 异常泄漏到 ViewModel。
//       MVP 实现是 LocalNoteRepository（Drift），未来加 RemoteNoteRepository 走同一接口。
//       详见技术方案 A §2.2/§6.2 + B §五。
import '../../../data/errors/result.dart';
import '../models/note.dart';
import '../models/note_version.dart';

/// 笔记 Repository 接口。
abstract class NoteRepository {
  /// 列出全部未软删笔记（第2批无分级，先全列；第3批改成 listBySubject）。
  Future<Result<List<Note>>> listAll();

  /// 按 id 取一条。
  Future<Result<Note?>> getById(String id);

  /// 新建笔记并返回完整领域对象，保证调用方直接获得数据库生成后的真实状态。
  Future<Result<Note>> create({
    required String subjectId,
    String? title,
    String? contentJson,
    String? plainText,
    bool isDraft = false,
  });

  /// 更新笔记（标题/正文/派生纯字）。若正文相对上一版有变化，触发 note_version 写快照。
  Future<Result<void>> update({
    required String id,
    String? title,
    String? contentJson,
    String? plainText,
    bool? isDraft,
  });

  /// 软删笔记。
  Future<Result<void>> softDelete(String id);

  /// 列出某笔记历史版本（第4批用，第2批先备好口子）。
  Future<Result<List<NoteVersion>>> listVersions(String noteId);

  /// 将某个历史版本恢复为当前正文，并保留恢复前的正文快照。
  Future<Result<void>> restoreVersion({
    required String noteId,
    required int versionNo,
  });
}
