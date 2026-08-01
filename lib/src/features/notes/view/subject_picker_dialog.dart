// 文件: lib/src/features/notes/view/subject_picker_dialog.dart
// 作用: FAB 新建笔记的"一键定级"弹窗（B1 FAB 线框 + F1.1.8）。
//       让用户选新建笔记挂到哪个科目节点：书级(整本笔记)/章级(整章笔记)/节级。
//       返回所选 subjectId；取消返回 null。
//       简化实现：把书-章-节铺成带缩进的单选列表，选一个即定级。
//       V2 可加"当前选中位置默认/最近用"等增强。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/subject.dart';
import '../note_constants.dart';
import '../view_model/view_model_providers.dart';

/// 弹出定级窗，返回选中的 subjectId（取消/空树返回 null）。
Future<String?> showSubjectPickerDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final state = ref.read(subjectTreeVmProvider).value;
  if (state == null || state.books.isEmpty) {
    // 无科目：提示无法定级，但仍允许以"未分类"建（返回 defaultSubjectId）
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建笔记'),
        content: const Text('还没有科目树。\n是否作为"未分类"笔记新建？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('未分类新建'),
          ),
        ],
      ),
    );
    return ok == true ? defaultSubjectId : null;
  }

  // 扁平化书-章-节为可选条目
  final options = <_SubjectOption>[];
  for (final book in state.books) {
    options.add(_SubjectOption(book.subject, 0));
    for (final ch in book.children) {
      options.add(_SubjectOption(ch.subject, 1));
      for (final sec in ch.children) {
        options.add(_SubjectOption(sec.subject, 2));
      }
      // 整章笔记:章级节点本身也可选（已在上面 ch.subject 加了）
    }
    // 整本书笔记:书级节点本身已在上面 book.subject 加了
  }

  String? selected = options.first.subject.id;

  return showDialog<String?>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSt) {
          return AlertDialog(
            title: const Text('新建笔记 · 选定位置'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (_, i) {
                  final opt = options[i];
                  final isSel = opt.subject.id == selected;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.only(left: 8.0 + opt.depth * 16),
                    leading: Icon(
                      const {
                            0: Icons.menu_book,
                            1: Icons.bookmark,
                            2: Icons.article,
                          }[opt.subject.level] ??
                          Icons.circle,
                      size: 18,
                    ),
                    title: Text(opt.subject.name),
                    trailing: isSel
                        ? Icon(
                            Icons.check,
                            color: Theme.of(ctx).colorScheme.primary,
                          )
                        : Text(
                            opt.subject.levelLabel,
                            style: Theme.of(ctx).textTheme.bodySmall,
                          ),
                    onTap: () => setSt(() => selected = opt.subject.id),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, selected),
                child: const Text('新建'),
              ),
            ],
          );
        },
      );
    },
  );
}

/// 弹窗内的一条可选项。
class _SubjectOption {
  final Subject subject;
  final int depth; // 0=书 1=章 2=节，仅缩进用
  const _SubjectOption(this.subject, this.depth);
}
