// 文件: lib/src/features/notes/view/library_content_create_dialog.dart
// 作用: 收集待创建内容的类型和名称，位置由主界面后续逐层选择。
import 'package:flutter/material.dart';

import '../models/library_navigation_state.dart';
import '../utils/library_creation_scope.dart';

Future<LibraryContentDraft?> showLibraryContentCreateDialog(
  BuildContext context,
) => showDialog<LibraryContentDraft>(
  context: context,
  builder: (_) => const _LibraryContentCreateDialog(),
);

class _LibraryContentCreateDialog extends StatefulWidget {
  const _LibraryContentCreateDialog();

  @override
  State<_LibraryContentCreateDialog> createState() => _LibraryContentCreateDialogState();
}

class _LibraryContentCreateDialogState extends State<_LibraryContentCreateDialog> {
  final _controller = TextEditingController();
  LibraryContentKind _kind = LibraryContentKind.folder;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('新建内容'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<LibraryContentKind>(
          initialValue: _kind,
          decoration: const InputDecoration(labelText: '创建类型'),
          items: LibraryContentKind.values.map((kind) => DropdownMenuItem(
            value: kind,
            child: Text(_label(kind)),
          )).toList(),
          onChanged: (kind) => setState(() => _kind = kind!),
        ),
        TextField(controller: _controller, decoration: const InputDecoration(labelText: '名称')),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
      FilledButton(
        onPressed: () {
          final name = _controller.text.trim();
          if (name.isEmpty) return;
          Navigator.pop(context, LibraryContentDraft(kind: _kind, name: name));
        },
        child: const Text('创建'),
      ),
    ],
  );
}

String _label(LibraryContentKind kind) => switch (kind) {
  LibraryContentKind.folder => '文件夹',
  LibraryContentKind.book => '书',
  LibraryContentKind.chapter => '章',
  LibraryContentKind.section => '节',
};
