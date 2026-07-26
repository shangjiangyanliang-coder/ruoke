// 标签数据访问的抽象接口，供 ViewModel 依赖而不接触 Drift。
import '../../../data/errors/result.dart';
import '../models/tag.dart';

/// 标签的领域数据操作。
abstract class TagRepository {
  Future<Result<List<TagWithCount>>> listTags();

  Future<Result<Tag>> createTag({required String name, String? color});

  Future<Result<void>> renameTag({required String id, required String name});

  Future<Result<void>> deleteTag(String id);

  Future<Result<List<Tag>>> listTagsForNote(String noteId);

  Future<Result<void>> replaceNoteTags({
    required String noteId,
    required List<String> tagIds,
  });
}
