// 文件: lib/src/utils/delta_plain_text.dart
// 作用: 从 flutter_quill 的 Delta JSON 派生纯文字（搜索/备份降级用，决策②）。
//       笔记保存时 Repository 传入 contentJson，调用本工具得 plainText 一并写库。
//       解析失败回退空串，不阻断保存。
import 'dart:convert';

import 'package:flutter_quill/flutter_quill.dart';

/// 把 Delta JSON 字符串转纯文字。null/非法 JSON 返回空串。
String deltaJsonToPlainText(String? deltaJson) {
  if (deltaJson == null || deltaJson.trim().isEmpty) return '';
  try {
    final doc = Document.fromJson(jsonDecode(deltaJson) as List<dynamic>);
    return doc.toPlainText();
  } catch (_) {
    // 非 Delta JSON（如旧纯文字残留）则当纯字直接返回
    return '';
  }
}
