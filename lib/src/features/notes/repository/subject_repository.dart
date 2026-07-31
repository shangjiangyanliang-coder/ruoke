// 文件: lib/src/features/notes/repository/subject_repository.dart
// 作用: 科目树 Repository 抽象接口。ViewModel 只认此接口，不碰 Drift/DAO。
//       方法返回 Result<T>，把底层异常翻译成 AppException。
//       MVP 实现是 LocalSubjectRepository（Drift）。
//       详见技术方案 A §2.2/§6.2 + B §二 表1。
import '../../../data/errors/result.dart';
import '../models/subject.dart';
import '../models/subject_path.dart';

/// 科目树 Repository 接口。
abstract class SubjectRepository {
  /// 列出全部未软删科目节点（UI 构造树用，按 sortOrder 升序）。
  Future<Result<List<Subject>>> listAll();

  /// 按 parentId 取直接子节点（构造树/级联选用）。
  Future<Result<List<Subject>>> childrenOf(String? parentId);

  /// 按名称部分匹配，并返回每个命中节点从书开始的完整路径。
  Future<Result<List<SubjectPath>>> searchPaths(String keyword);

  /// 按 id 取一条。
  Future<Result<Subject?>> getById(String id);

  /// 新建科目节点（返回新 id），顺序由仓储按真实父级追加。
  Future<Result<String>> create({
    required String name,
    required int level,
    String? parentId,
    String? folderId,
  });

  /// 重命名书、章或节，不改变层级和归属。
  Future<Result<void>> rename({required String id, required String name});

  /// 将章或节移动到合法父级并插入指定位置。
  Future<Result<void>> moveSubject({
    required String subjectId,
    required String newParentId,
    required int targetIndex,
  });

  /// 按完整 id 列表重排一个书或章的直属子级。
  Future<Result<void>> reorderChildren({
    required String parentId,
    required List<String> orderedIds,
  });

  /// 软删科目节点。
  Future<Result<void>> softDelete(String id);

  /// 统计未软删子节点数（判叶/判空用）。parentId 为 null 时数顶层。
  Future<Result<int>> countChildren(String? parentId);

  /// 表是否完全为空（seed 幂等用：仅真的没有任何节点时true）。
  Future<Result<bool>> isEmpty();
}
