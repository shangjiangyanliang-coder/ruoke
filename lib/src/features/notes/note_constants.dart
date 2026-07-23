// 文件: lib/src/features/notes/note_constants.dart
// 作用: 笔记模块常量。
//       第2批无 subject 树 UI，新建笔记的 subjectId 一律挂到占位科目常量
//       defaultSubjectId；第3批做"书-章-节树"时再迁移挂到真实 subject 节点。
/// 占位科目 id（第2批无分级，笔记全挂此值；第3批做科目树后迁移）。
const String defaultSubjectId = '__default_subject__';
