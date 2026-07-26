// 文件: lib/src/features/notes/utils/highlight_extractor.dart
// 作用: 从 flutter_quill 保存的 Delta JSON 中提取红字/下划线重点文字。
import 'dart:convert';

import '../models/note_highlight.dart';

/// Quill Delta 重点解析器。
class HighlightExtractor {
  /// 读取 Delta JSON，按操作顺序返回红字和下划线重点。
  ///
  /// 方案 A 只保存重点类型和文字，不保存正文偏移；非法 Delta 会抛出
  /// FormatException，交由 Repository 回滚事务，避免静默清空既有重点。
  static List<NoteHighlightDraft> extract(String? contentJson) {
    if (contentJson == null || contentJson.trim().isEmpty) {
      return const [];
    }

    final decoded = jsonDecode(contentJson);
    if (decoded is! List) {
      throw const FormatException('Delta JSON 顶层必须是数组');
    }

    final result = <NoteHighlightDraft>[];
    for (final rawOp in decoded) {
      if (rawOp is! Map) continue;
      final insert = rawOp['insert'];
      final attributes = rawOp['attributes'];
      if (insert is! String || insert.trim().isEmpty || attributes is! Map) {
        continue;
      }

      final color = attributes['color'];
      final normalizedColor = color is String ? color.toUpperCase() : null;
      if (normalizedColor == 'RED' ||
          normalizedColor == '#F44336' ||
          normalizedColor == '#FFF44336') {
        result.add(NoteHighlightDraft(kind: 'red', body: insert));
      }
      if (attributes['underline'] == true) {
        result.add(NoteHighlightDraft(kind: 'underline', body: insert));
      }
    }
    return result;
  }
}
