// 文件: lib/src/features/notes/models/note_highlight.dart
// 作用: 定义保存重点记录前的轻量领域对象。

/// 从 Quill Delta 提取出的重点文字草稿。
class NoteHighlightDraft {
  final String kind;
  final String body;

  const NoteHighlightDraft({required this.kind, required this.body});

  @override
  bool operator ==(Object other) =>
      other is NoteHighlightDraft && other.kind == kind && other.body == body;

  @override
  int get hashCode => Object.hash(kind, body);
}
