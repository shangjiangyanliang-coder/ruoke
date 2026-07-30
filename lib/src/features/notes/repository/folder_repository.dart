// 文件: lib/src/features/notes/repository/folder_repository.dart
// 作用: 定义文件夹功能与数据存储之间的最小抽象接口。
import '../../../data/errors/result.dart';
import '../models/subject_folder.dart';
import '../models/subject.dart';

/// 文件夹仓储接口。
abstract class FolderRepository {
  /// 读取全部未删除文件夹，用于构建选择器路径和移动目标。
  Future<Result<List<SubjectFolder>>> listAll();

  /// 读取指定文件夹内的直属书；null 表示未归类书。
  Future<Result<List<Subject>>> booksIn(String? folderId);

  /// 创建文件夹并返回新 id。
  Future<Result<String>> create({required String name, String? parentId});

  /// 更新文件夹名称。
  Future<Result<void>> rename({required String id, required String name});

  /// 将文件夹移动到新父目录；null 表示移动到根目录。
  Future<Result<void>> moveFolder({
    required String folderId,
    required String? newParentId,
  });

  /// 将书移动至文件夹；null 表示移回未归类书。
  Future<Result<void>> moveBook({
    required String bookId,
    required String? folderId,
  });

  /// 解散文件夹，将直属内容安全上移后软删除该文件夹。
  Future<Result<void>> dissolve(String folderId);

  /// 读取某个目录的直属、未删除文件夹。
  Future<Result<List<SubjectFolder>>> childrenOf(String? parentId);
}
