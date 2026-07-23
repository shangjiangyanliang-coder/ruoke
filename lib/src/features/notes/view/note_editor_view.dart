// 文件: lib/src/features/notes/view/note_editor_view.dart
// 作用: 笔记编辑器页（B1.a 最小占位，沉浸页无底栏）。第2批不精修样式。
//       顶栏：< 返回 + 标题输入 + 保存 + 更多(删除)；正文 flutter_quill 富文本；
//       工具栏精简(加粗/斜体/下划线/红字/删除线/列表/H1/H2)；返回时按脏标记弹"保留草稿?"。
//       第3批加级别、第4批加历史版本入口、第5批加标签。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../view_model/view_model_providers.dart';

/// 笔记编辑器页（B1.a 最小占位）。
class NoteEditorView extends ConsumerStatefulWidget {
  final String noteId; // 'new' 或已有 id

  const NoteEditorView({super.key, required this.noteId});

  @override
  ConsumerState<NoteEditorView> createState() => _NoteEditorViewState();
}

class _NoteEditorViewState extends ConsumerState<NoteEditorView> {
  QuillController? _controller;
  TextEditingController? _titleCtrl;

  @override
  void initState() {
    super.initState();
    // 进入即触发 VM 加载对应 noteId
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(noteEditorVmProvider.notifier).init(widget.noteId);
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    _titleCtrl?.dispose();
    super.dispose();
  }

  /// 笔记加载完成后初始化富文本 controller
  void _ensureControllers(String? title, String? contentJson) {
    if (_controller != null) return;
    var doc = Document();
    if (contentJson != null && contentJson.trim().isNotEmpty) {
      try {
        doc = Document.fromJson(jsonDecode(contentJson) as List<dynamic>);
      } catch (_) {
        // 旧纯文字残留：降级为纯字
        doc = Document()..insert(0, contentJson);
      }
    }
    final c = QuillController(
      document: doc,
      selection: const TextSelection.collapsed(offset: 0),
    );
    c.addListener(_onContentChanged);
    _controller = c;
    final t = TextEditingController(text: title ?? '');
    t.addListener(_onContentChanged);
    _titleCtrl = t;
  }

  void _onContentChanged() {
    ref.read(noteEditorVmProvider.notifier).markDirty();
  }

  String _currentDeltaJson() =>
      jsonEncode(_controller!.document.toDelta().toJson());

  Future<bool> _save() async {
    final title = _titleCtrl?.text.trim();
    return ref.read(noteEditorVmProvider.notifier).save(
          title: (title == null || title.isEmpty) ? null : title,
          contentJson: _currentDeltaJson(),
        );
  }

  /// 返回：若有未保存改动弹确认
  Future<void> _back(BuildContext context) async {
    final dirty = ref.read(noteEditorVmProvider).value?.dirty ?? false;
    if (dirty) {
      final choice = await showDialog<_DiscardChoice>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('未保存的改动'),
          content: const Text('是否先保存再离开？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, _DiscardChoice.discard), child: const Text('不保存离开')),
            TextButton(onPressed: () => Navigator.pop(ctx, _DiscardChoice.cancel), child: const Text('继续编辑')),
            FilledButton(onPressed: () => Navigator.pop(ctx, _DiscardChoice.save), child: const Text('保存并离开')),
          ],
        ),
      );
      switch (choice) {
        case _DiscardChoice.save:
          final ok = await _save();
          if (ok && context.mounted) context.pop();
        case _DiscardChoice.discard:
          if (context.mounted) context.pop();
        case _DiscardChoice.cancel:
        case null:
          return;
      }
    } else {
      if (context.mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(noteEditorVmProvider);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back(context);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => _back(context)),
          title: const Text('编辑笔记'),
          actions: [
            IconButton(
              icon: const Icon(Icons.save_outlined),
              tooltip: '保存',
              onPressed: () async {
                final ok = await _save();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(ok ? '已保存' : '保存失败')),
                  );
                }
              },
            ),
            PopupMenuButton<String>(
              tooltip: '更多',
              onSelected: (v) async {
                if (v == 'delete') {
                  final ok = await _confirmDelete();
                  if (ok && context.mounted) context.pop();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'delete', child: Text('删除笔记')),
              ],
            ),
          ],
        ),
        body: state.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('加载失败：$e')),
          data: (s) {
            if (!s.ready) {
              return const Center(child: CircularProgressIndicator());
            }
            // ready 后（首次或新建）初始化 controller
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_controller == null) {
                _ensureControllers(s.note?.title, s.note?.contentJson);
                setState(() {});
              }
            });
            if (_controller == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: TextField(
                    controller: _titleCtrl,
                    decoration: const InputDecoration(
                      hintText: '标题（可留空）',
                      border: InputBorder.none,
                    ),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
                const Divider(height: 1),
                QuillSimpleToolbar(
                  controller: _controller!,
                  config: const QuillSimpleToolbarConfig(
                    showBoldButton: true,
                    showItalicButton: true,
                    showUnderLineButton: true,
                    showStrikeThrough: true,
                    showColorButton: true,
                    showListBullets: true,
                    showListNumbers: true,
                    showListCheck: false,
                    showHeaderStyle: true,
                    showLink: false,
                    showClearFormat: true,
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: QuillEditor.basic(
                      controller: _controller!,
                      config: const QuillEditorConfig(
                        scrollable: true,
                        placeholder: '在这里写下你的笔记……选中一段可标红/下划线为重点',
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<bool> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除笔记？'),
        content: const Text('删除后进回收站，可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(noteEditorVmProvider.notifier).delete();
    }
    return ok ?? false;
  }
}

enum _DiscardChoice { save, discard, cancel }
