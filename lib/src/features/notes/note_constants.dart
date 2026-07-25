// 文件: lib/src/features/notes/note_constants.dart
// 作用: 笔记模块常量。
//       第3批起 note 接真实 subject 树，但保留 defaultSubjectId 作为"未分类"兜底
//       （第2批遗留笔记 subjectId 即此值；新建笔记若未选科目也挂此）。
//       B1 树底部会展示 defaultSubjectId 的笔记为「未分类」组。
/// 占位"未分类"科目 id。第2批遗留笔记挂此值；新建笔记若未选章节亦挂此。
/// B1 树底部以「未分类」分组展示。第3批后真实 subjectId 接入，此值仅兜底。
const String defaultSubjectId = '__default_subject__';
