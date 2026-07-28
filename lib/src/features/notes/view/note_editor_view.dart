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

import '../models/tag.dart';
import '../view_model/note_editor_view_model.dart';
import '../view_model/view_model_providers.dart';

/// 笔记编辑器页（B1.a 最小占位）。
class NoteEditorView extends ConsumerStatefulWidget {
  final String noteId; // 'new' 或已有 id

  /// 新建时由 FAB 定级窗传入的归属科目 id（'new' 态用）。已有笔记忽略。
  final String? subjectId;

  const NoteEditorView({super.key, required this.noteId, this.subjectId});

  @override
  ConsumerState<NoteEditorView> createState() => _NoteEditorViewState();
}

class _NoteEditorViewState extends ConsumerState<NoteEditorView> {
  QuillController? _controller;
  TextEditingController? _titleCtrl;
  final TextEditingController _tagInputController = TextEditingController();
  final Set<String> _pendingTagNames = {};
  String? _activeSessionKey;
  String _tagInput = '';
  String? _tagSaveError;
  bool _sessionInitialized = false;
  bool _tagOperationInProgress = false;
  int _tagOperationGeneration = 0;

  String get _sessionKey => '${widget.noteId}|${widget.subjectId ?? ''}';

  @override
  void initState() {
    super.initState();
    _startEditorSession();
  }

  @override
  void didUpdateWidget(covariant NoteEditorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.noteId != widget.noteId ||
        oldWidget.subjectId != widget.subjectId) {
      _tagOperationGeneration++;
      _tagOperationInProgress = false;
      _resetControllers();
      _startEditorSession();
    }
  }

  /// 为当前路由启动独立初始化；旧会话完成时不得解锁新页面。
  void _startEditorSession() {
    final sessionKey = _sessionKey;
    _activeSessionKey = sessionKey;
    _sessionInitialized = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeEditorSession(sessionKey);
    });
  }

  Future<void> _initializeEditorSession(String sessionKey) async {
    await ref
        .read(noteEditorVmProvider.notifier)
        .init(widget.noteId, subjectId: widget.subjectId);
    if (!mounted || _activeSessionKey != sessionKey) return;
    setState(() {
      _sessionInitialized = true;
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    _titleCtrl?.dispose();
    _tagInputController.dispose();
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

  bool _hasVisibleContent() =>
      _controller!.document.toPlainText().trim().isNotEmpty;

  Future<NoteSaveResult> _save() async {
    if (!_sessionInitialized ||
        _controller == null ||
        _titleCtrl == null ||
        _tagOperationInProgress ||
        ref.read(noteEditorVmProvider).value?.ready != true ||
        ref.read(noteEditorVmProvider).value?.saving == true) {
      return NoteSaveResult.failed;
    }
    final title = _titleCtrl?.text.trim();
    final result = await ref
        .read(noteEditorVmProvider.notifier)
        .save(
          title: (title == null || title.isEmpty) ? null : title,
          contentJson: _currentDeltaJson(),
          hasVisibleContent: _hasVisibleContent(),
        );
    if (result == NoteSaveResult.saved && _pendingTagNames.isNotEmpty) {
      final tagsSaved = await _flushPendingTags();
      if (!tagsSaved) return NoteSaveResult.savedWithTagFailure;
    }
    return result;
  }

  bool _isCurrentTagOperation(String sessionKey, int operationGeneration) =>
      mounted &&
      _activeSessionKey == sessionKey &&
      _tagOperationGeneration == operationGeneration;

  Future<void> _submitTagName([Tag? suggestion]) async {
    if (_tagOperationInProgress) return;
    final name = (suggestion?.name ?? _tagInputController.text).trim();
    if (name.isEmpty) {
      setState(() => _tagSaveError = '标签名称不能为空');
      return;
    }
    final noteId = ref.read(noteEditorVmProvider).value?.note?.id;
    if (noteId == null) {
      setState(() {
        _pendingTagNames.add(name);
        _tagInputController.clear();
        _tagInput = '';
        _tagSaveError = null;
      });
      return;
    }

    final sessionKey = _sessionKey;
    final generation = ++_tagOperationGeneration;
    setState(() => _tagOperationInProgress = true);
    final saved = await ref
        .read(noteTagsVmProvider(noteId).notifier)
        .addByName(name);
    if (!_isCurrentTagOperation(sessionKey, generation)) return;
    if (saved) {
      setState(() {
        _tagInputController.clear();
        _tagInput = '';
        _tagSaveError = null;
      });
      await ref.read(tagManagementVmProvider.notifier).refresh();
    } else {
      final message =
          ref
              .read(noteTagsVmProvider(noteId))
              .value
              ?.actionError
              ?.userMessage ??
          '标签添加失败，请重试';
      setState(() => _tagSaveError = message);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    }
    if (_isCurrentTagOperation(sessionKey, generation)) {
      setState(() => _tagOperationInProgress = false);
    }
  }

  Future<void> _removePersistedTag(String noteId, Tag tag) async {
    if (_tagOperationInProgress) return;
    final sessionKey = _sessionKey;
    final generation = ++_tagOperationGeneration;
    setState(() => _tagOperationInProgress = true);
    final removed = await ref
        .read(noteTagsVmProvider(noteId).notifier)
        .removeTag(tag.id);
    if (!_isCurrentTagOperation(sessionKey, generation)) return;
    if (!removed) {
      final message =
          ref
              .read(noteTagsVmProvider(noteId))
              .value
              ?.actionError
              ?.userMessage ??
          '移除标签失败，请重试';
      setState(() => _tagSaveError = message);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    }
    if (_isCurrentTagOperation(sessionKey, generation)) {
      setState(() => _tagOperationInProgress = false);
    }
  }

  Future<bool> _flushPendingTags() async {
    final noteId = ref.read(noteEditorVmProvider).value?.note?.id;
    if (noteId == null || _pendingTagNames.isEmpty || _tagOperationInProgress) {
      return false;
    }
    final sessionKey = _sessionKey;
    final generation = ++_tagOperationGeneration;
    final provider = noteTagsVmProvider(noteId);
    final subscription = ref.listenManual(provider, (_, _) {});
    final names = Set<String>.from(_pendingTagNames);
    setState(() => _tagOperationInProgress = true);
    try {
      final saved = await ref.read(provider.notifier).attachNames(names);
      if (!_isCurrentTagOperation(sessionKey, generation)) return false;
      if (saved) {
        setState(() {
          _pendingTagNames.clear();
          _tagSaveError = null;
        });
        await ref.read(tagManagementVmProvider.notifier).refresh();
        return true;
      } else {
        setState(() => _tagSaveError = '笔记已保存，但标签保存失败');
        return false;
      }
    } finally {
      subscription.close();
      if (_isCurrentTagOperation(sessionKey, generation)) {
        setState(() => _tagOperationInProgress = false);
      }
    }
  }

  Widget _buildTagSection(NoteEditorState state) {
    final noteId = state.note?.id;
    final noteTags = noteId == null
        ? null
        : ref.watch(noteTagsVmProvider(noteId));
    final tags = noteTags?.value?.tags ?? const <Tag>[];
    final catalogState = ref.watch(tagManagementVmProvider);
    final catalog = catalogState.value?.tags ?? const [];
    final existingNames = {...tags.map((tag) => tag.name), ..._pendingTagNames};
    final query = _tagInput.trim();
    final suggestions = query.isEmpty
        ? const <Tag>[]
        : catalog
              .where(
                (tag) =>
                    tag.name.contains(query) &&
                    !existingNames.contains(tag.name),
              )
              .map(
                (tag) => Tag(
                  id: tag.id,
                  name: tag.name,
                  color: tag.color,
                  createdAt: tag.createdAt,
                ),
              )
              .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('标签'),
              if (noteTags?.isLoading == true)
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              if (noteTags?.hasError == true)
                Text(
                  '标签加载失败',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              for (final tag in tags)
                InputChip(
                  label: Text(tag.name),
                  deleteIcon: Tooltip(
                    message: '移除标签 ${tag.name}',
                    child: const Icon(Icons.cancel, size: 18),
                  ),
                  onDeleted: _tagOperationInProgress || noteId == null
                      ? null
                      : () => _removePersistedTag(noteId, tag),
                  visualDensity: VisualDensity.compact,
                ),
              for (final name in _pendingTagNames)
                InputChip(
                  label: Text(name),
                  avatar: const Icon(Icons.schedule, size: 16),
                  deleteIcon: Tooltip(
                    message: '移除待保存标签 $name',
                    child: const Icon(Icons.cancel, size: 18),
                  ),
                  onDeleted: _tagOperationInProgress
                      ? null
                      : () => setState(() => _pendingTagNames.remove(name)),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('editor-tag-input'),
                  controller: _tagInputController,
                  enabled: !_tagOperationInProgress,
                  textInputAction: TextInputAction.done,
                  onChanged: (value) => setState(() {
                    _tagInput = value;
                    _tagSaveError = null;
                  }),
                  onSubmitted: (_) => _submitTagName(),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '输入标签，按回车添加',
                    errorText: _tagSaveError,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              IconButton(
                tooltip: '添加标签',
                onPressed: _tagOperationInProgress ? null : _submitTagName,
                icon: _tagOperationInProgress
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add),
              ),
            ],
          ),
          if (query.isNotEmpty && catalogState.isLoading)
            const LinearProgressIndicator(),
          if (query.isNotEmpty && catalogState.hasError)
            Row(
              children: [
                Expanded(
                  child: Text(
                    '标签建议加载失败',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      ref.read(tagManagementVmProvider.notifier).refresh(),
                  child: const Text('重试建议'),
                ),
              ],
            ),
          if (suggestions.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  for (final tag in suggestions)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        label: Text(tag.name),
                        avatar: const Icon(Icons.history, size: 16),
                        onPressed: _tagOperationInProgress
                            ? null
                            : () => _submitTagName(tag),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 打开历史版本前先保存当前未保存内容，确保版本快照基于编辑器最新正文。
  /// 新建笔记首次保存后使用 ViewModel 返回的真实 id，而不是继续使用路由中的 'new'。
  Future<void> _openHistory(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    var editorState = ref.read(noteEditorVmProvider).value;
    if (editorState?.dirty == true || _pendingTagNames.isNotEmpty) {
      final result = await _save();
      if (result == NoteSaveResult.failed ||
          result == NoteSaveResult.savedWithTagFailure) {
        if (context.mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('保存失败，无法打开历史版本')),
          );
        }
        return;
      }
      if (result == NoteSaveResult.skippedEmpty) {
        if (context.mounted) {
          messenger.showSnackBar(const SnackBar(content: Text('空笔记不会保存')));
        }
        return;
      }
      editorState = ref.read(noteEditorVmProvider).value;
    }

    final noteId = editorState?.note?.id;
    if (noteId == null || !context.mounted) return;

    final restored = await context.push<bool>('/notes/editor/$noteId/versions');
    if (restored == true && context.mounted) {
      _resetControllers();
      await ref.read(noteEditorVmProvider.notifier).init(noteId);
      if (mounted) {
        setState(() {});
        messenger.showSnackBar(const SnackBar(content: Text('已恢复历史版本')));
      }
    }
  }

  /// 返回：若有未保存改动弹确认
  Future<void> _back(BuildContext context) async {
    final dirty =
        (ref.read(noteEditorVmProvider).value?.dirty ?? false) ||
        _pendingTagNames.isNotEmpty;
    if (dirty) {
      final choice = await showDialog<_DiscardChoice>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('未保存的改动'),
          content: const Text('是否先保存再离开？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, _DiscardChoice.discard),
              child: const Text('不保存离开'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, _DiscardChoice.cancel),
              child: const Text('继续编辑'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, _DiscardChoice.save),
              child: const Text('保存并离开'),
            ),
          ],
        ),
      );
      switch (choice) {
        case _DiscardChoice.save:
          final result = await _save();
          if ((result == NoteSaveResult.saved ||
                  result == NoteSaveResult.skippedEmpty) &&
              context.mounted) {
            context.pop();
          }
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
    final providerState = ref.watch(noteEditorVmProvider);
    final state = _sessionInitialized
        ? providerState
        : const AsyncLoading<NoteEditorState>();
    final canSave =
        _sessionInitialized &&
        state.value?.ready == true &&
        state.value?.saving != true &&
        !_tagOperationInProgress &&
        _controller != null &&
        _titleCtrl != null;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back(context);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _back(context),
          ),
          title: const Text('编辑笔记'),
          actions: [
            IconButton(
              icon: const Icon(Icons.save_outlined),
              tooltip: '保存',
              onPressed: canSave
                  ? () async {
                      final result = await _save();
                      if (context.mounted) {
                        final message = switch (result) {
                          NoteSaveResult.saved => '已保存',
                          NoteSaveResult.savedWithTagFailure => '笔记已保存，但标签保存失败',
                          NoteSaveResult.skippedEmpty => '空笔记不会保存',
                          NoteSaveResult.failed => '保存失败',
                        };
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(message)));
                      }
                    }
                  : null,
            ),
            PopupMenuButton<String>(
              tooltip: '更多',
              onSelected: (v) async {
                if (v == 'history') {
                  await _openHistory(context);
                } else if (v == 'delete') {
                  final ok = await _confirmDelete();
                  if (ok && context.mounted) context.pop();
                }
              },
              itemBuilder: (_) => [
                if (state.value?.note != null)
                  const PopupMenuItem(value: 'history', child: Text('历史版本')),
                const PopupMenuItem(value: 'delete', child: Text('删除笔记')),
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
                    key: const ValueKey('note-title'),
                    controller: _titleCtrl,
                    decoration: const InputDecoration(
                      hintText: '标题（可留空）',
                      border: InputBorder.none,
                    ),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _buildTagSection(s),
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(noteEditorVmProvider.notifier).delete();
    }
    return ok ?? false;
  }

  void _resetControllers() {
    _controller?.removeListener(_onContentChanged);
    _controller?.dispose();
    _titleCtrl?.dispose();
    _controller = null;
    _titleCtrl = null;
    _tagInputController.clear();
    _tagInput = '';
    _pendingTagNames.clear();
    _tagSaveError = null;
  }
}

enum _DiscardChoice { save, discard, cancel }
