// 文件: lib/src/features/notes/models/note_edit_snapshot.dart
// 作用: 编解码标题、正文和标签的完整历史快照，并兼容旧正文 Delta。
import 'dart:convert';

import 'package:flutter_quill/flutter_quill.dart' show Document;

/// 可写入 note_version.snapshot_json 的完整编辑状态。
class NoteEditSnapshot {
  static const int currentSchemaVersion = 1;

  final String? title;
  final String? contentJson;
  final List<String> tagNames;
  final bool isLegacy;

  NoteEditSnapshot({
    required this.title,
    required this.contentJson,
    required Iterable<String> tagNames,
    this.isLegacy = false,
  }) : tagNames = List.unmodifiable(_normalizeTagNames(tagNames));

  /// 新格式编码为带版本号的 JSON 对象；旧格式只用于读取，不会继续写出。
  String encode() {
    return jsonEncode({
      'schemaVersion': currentSchemaVersion,
      'title': title,
      'contentJson': contentJson,
      'tagNames': tagNames,
    });
  }

  /// 顶层数组是旧正文 Delta；顶层对象必须是当前完整快照格式。
  static NoteEditSnapshot decode(String snapshotJson) {
    final Object? decoded;
    try {
      decoded = jsonDecode(snapshotJson);
    } on FormatException {
      throw const FormatException('历史版本 JSON 已损坏');
    }
    if (decoded is List<dynamic>) {
      if (!_isLegacyDocumentDelta(decoded)) {
        throw const FormatException('旧历史版本正文格式错误');
      }
      return NoteEditSnapshot(
        title: null,
        contentJson: snapshotJson,
        tagNames: const [],
        isLegacy: true,
      );
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['schemaVersion'] != currentSchemaVersion) {
      throw const FormatException('不支持的历史版本格式');
    }
    final title = decoded['title'];
    final contentJson = decoded['contentJson'];
    final tagNames = decoded['tagNames'];
    if (title != null && title is! String) {
      throw const FormatException('历史版本标题格式错误');
    }
    if (contentJson != null && contentJson is! String) {
      throw const FormatException('历史版本正文格式错误');
    }
    if (tagNames is! List<dynamic> || tagNames.any((name) => name is! String)) {
      throw const FormatException('历史版本标签格式错误');
    }
    return NoteEditSnapshot(
      title: title as String?,
      contentJson: contentJson as String?,
      tagNames: tagNames.cast<String>(),
    );
  }

  /// 历史正文是可重建文档的插入 Delta，不接受 retain/delete 或缺失 insert。
  static bool _isLegacyDocumentDelta(List<dynamic> operations) {
    if (operations.isEmpty) return false;
    try {
      Document.fromJson(operations);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 标签关联没有顺序语义，因此比较完整状态时忽略标签排列顺序。
  bool hasSameContent(NoteEditSnapshot other) {
    if (title != other.title || contentJson != other.contentJson) return false;
    final currentTags = [...tagNames]..sort();
    final otherTags = [...other.tagNames]..sort();
    if (currentTags.length != otherTags.length) return false;
    for (var index = 0; index < currentTags.length; index++) {
      if (currentTags[index] != otherTags[index]) return false;
    }
    return true;
  }

  static List<String> _normalizeTagNames(Iterable<String> names) {
    final result = <String>[];
    for (final name in names) {
      final normalized = name.trim();
      if (normalized.isNotEmpty && !result.contains(normalized)) {
        result.add(normalized);
      }
    }
    return result;
  }
}
