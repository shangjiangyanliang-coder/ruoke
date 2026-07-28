import 'package:flutter/material.dart';

import '../models/subject.dart';
import '../models/subject_scope.dart';

/// 范围选择结果，同时携带页面展示文案。
class SubjectScopeSelection {
  final SubjectScope scope;
  final String label;

  const SubjectScopeSelection({required this.scope, required this.label});
}

/// 显示“全部 / 指定层级 / 指定节点”的单选范围弹窗。
Future<SubjectScopeSelection?> showSubjectScopePicker({
  required BuildContext context,
  required List<Subject> subjects,
}) {
  return showDialog<SubjectScopeSelection>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('选择搜索范围'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            _scopeTile(
              dialogContext,
              label: '全部笔记',
              scope: const SubjectScope.all(),
            ),
            _scopeTile(
              dialogContext,
              label: '全部书',
              scope: const SubjectScope.level(0),
            ),
            _scopeTile(
              dialogContext,
              label: '全部章',
              scope: const SubjectScope.level(1),
            ),
            _scopeTile(
              dialogContext,
              label: '全部节',
              scope: const SubjectScope.level(2),
            ),
            if (subjects.isNotEmpty) const Divider(),
            for (final subject in subjects)
              ListTile(
                contentPadding: EdgeInsets.only(
                  left: 16 + subject.level * 20,
                  right: 8,
                ),
                leading: Icon(
                  switch (subject.level) {
                    0 => Icons.menu_book_outlined,
                    1 => Icons.article_outlined,
                    _ => Icons.notes_outlined,
                  },
                ),
                title: Text(subject.name),
                subtitle: Text('指定${subject.levelLabel}及其范围'),
                onTap: () => Navigator.pop(
                  dialogContext,
                  SubjectScopeSelection(
                    scope: SubjectScope.subtree(subject.id),
                    label: subject.name,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('取消'),
        ),
      ],
    ),
  );
}

Widget _scopeTile(
  BuildContext context, {
  required String label,
  required SubjectScope scope,
}) {
  return ListTile(
    title: Text(label),
    onTap: () => Navigator.pop(
      context,
      SubjectScopeSelection(scope: scope, label: label),
    ),
  );
}
