// 文件: lib/src/features/notes/view/subject_manage_view.dart
// 作用: 学科管理页（我的tab 学科管理入口）。显示书-章-节扁平列表（带层级缩进），
//       支持新建（选 level + 父节点）、改名、软删。ViewModel 为 SubjectManageVm。
//       第3批.5简易版，后续可加拖拽排序、批量操作等。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/subject.dart';
import '../view_model/view_model_providers.dart';

/// 学科管理页。
class SubjectManageView extends ConsumerWidget {
  const SubjectManageView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(subjectManageVmProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('学科管理')),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (s) {
          if (s.subjects.isEmpty) {
            return const Center(child: Text('还没有科目，点右下角 + 新建'));
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: s.subjects.length,
            itemBuilder: (_, i) {
              final subj = s.subjects[i];
              return _SubjectRow(subject: subj);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: '新建科目',
        onPressed: () => _showCreateDialog(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// 扁平列表中每条科目行。
class _SubjectRow extends ConsumerWidget {
  final Subject subject;
  const _SubjectRow({required this.subject});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final levelIcons = const {
      0: Icons.menu_book,
      1: Icons.bookmark,
      2: Icons.article,
    };
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.only(left: 16.0 + (subject.level * 24)),
      leading: Icon(levelIcons[subject.level] ?? Icons.circle, size: 18),
      title: Text(subject.name),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(subject.levelLabel,
              style: Theme.of(context).textTheme.bodySmall),
          IconButton(
            icon: const Icon(Icons.edit, size: 18),
            tooltip: '改名',
            onPressed: () => _showRenameDialog(context, ref, subject),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            tooltip: '删除',
            onPressed: () => _confirmDelete(context, ref, subject),
          ),
        ],
      ),
    );
  }
}

/// 新建科目弹窗：名字 + level + 父节点。
Future<void> _showCreateDialog(
    BuildContext context, WidgetRef ref) async {
  final nameCtrl = TextEditingController();
  int level = 0;
  String? parentId;
  final state = ref.read(subjectManageVmProvider).value;
  final subjects = state?.subjects ?? [];

  // 可选父节点=现有所有非节级科目（节不能再建子节点，节下更没子层）
  final parentOptions = subjects
      .where((s) => s.level <= 1) // 书(0)和章(1)可当父
      .toList();

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSt) {
          return AlertDialog(
            title: const Text('新建科目'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                        labelText: '名称', hintText: '输入书/章/节名称'),
                  ),
                  const SizedBox(height: 12),
                  // Level 选择
                  DropdownButtonFormField<int>(
                    initialValue: level,
                    decoration: const InputDecoration(labelText: '层级'),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('书(📚)')),
                      DropdownMenuItem(value: 1, child: Text('章(📖)')),
                      DropdownMenuItem(value: 2, child: Text('节(📄)')),
                    ],
                    onChanged: (v) {
                      setSt(() {
                        level = v ?? 0;
                        // level 变动时清父节点选择（选书后默认不挂父）
                        parentId = null;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  // 父节点选择（level>0 才能选父）
                  if (level > 0 && parentOptions.isNotEmpty) ...[
                    DropdownButtonFormField<String?>(
                      initialValue: parentId,
                      decoration: const InputDecoration(labelText: '父节点（可选）'),
                      items: [
                        const DropdownMenuItem<String?>(
                            value: null, child: Text('无(顶级)')),
                        ...parentOptions.map((s) => DropdownMenuItem<String?>(
                              value: s.id,
                              child: Text('${s.levelLabel}: ${s.name}'),
                            )),
                      ],
                      onChanged: (v) => setSt(() => parentId = v),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消')),
              FilledButton(
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty) return;
                  try {
                    await ref.read(subjectManageVmProvider.notifier).create(
                          name: nameCtrl.text.trim(),
                          level: level,
                          parentId: level > 0 ? parentId : null,
                        );
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text('新建失败：$e')));
                    }
                  }
                },
                child: const Text('新建'),
              ),
            ],
          );
        },
      );
    },
  );
  nameCtrl.dispose();
  // 刷新 B1 树（科目变更后树要重拉）
  if (result == true) {
    ref.read(subjectTreeVmProvider.notifier).refresh();
  }
}

/// 改名弹窗。
Future<void> _showRenameDialog(
    BuildContext context, WidgetRef ref, Subject subject) async {
  final nameCtrl = TextEditingController(text: subject.name);
  await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('改名'),
      content: TextField(
        controller: nameCtrl,
        decoration: const InputDecoration(hintText: '新名称'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消')),
        FilledButton(
          onPressed: () async {
            if (nameCtrl.text.trim().isEmpty) return;
            // TODO: 改名调 Repository.create 新建并软删旧？MVP 先不用重命名接口
            //   当前 Repository/Dao 无 rename 方法，留 V2 补（同 F1.1.12）。先提示不可用。
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('改名功能待 V2 补充（当前走新建+删旧）')));
              Navigator.pop(ctx, false);
            }
          },
          child: const Text('确认'),
        ),
      ],
    ),
  );
  nameCtrl.dispose();
}

/// 删除确认。
Future<void> _confirmDelete(
    BuildContext context, WidgetRef ref, Subject subject) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('删除科目？'),
      content:
          const Text('删除后科目及其下笔记仍保留在库（软删），\n可在回收站恢复。'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
      ],
    ),
  );
  if (ok == true && context.mounted) {
    await ref.read(subjectManageVmProvider.notifier).delete(subject.id);
    // 刷新 B1 树
    ref.read(subjectTreeVmProvider.notifier).refresh();
  }
}
