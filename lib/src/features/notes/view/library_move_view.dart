// 作用：提供“选择目标父级→拖拽精确位置”的两步目录项目移动页面。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/errors/app_exception.dart';
import '../../../data/errors/result.dart';
import '../models/library_organization.dart';
import '../providers.dart';
import '../view_model/library_organization_controller.dart';
import 'library_move_target_tree.dart';

enum LibraryMoveStep { choosingParent, choosingPosition }

/// 打开两步移动页；仅保存成功返回 true，取消返回 false。
Future<bool?> showLibraryMoveView(
  BuildContext context, {
  required LibraryMoveRequest request,
}) => Navigator.of(context).push<bool>(
  MaterialPageRoute(builder: (_) => LibraryMoveView(request: request)),
);

class LibraryMoveView extends ConsumerStatefulWidget {
  final LibraryMoveRequest request;

  /// 仅供测试或独立嵌入时注入；正常页面从 Provider 读取。
  final LibraryOrganizationController? controller;

  const LibraryMoveView({super.key, required this.request, this.controller});

  @override
  ConsumerState<LibraryMoveView> createState() => _LibraryMoveViewState();
}

class _LibraryMoveViewState extends ConsumerState<LibraryMoveView> {
  var _step = LibraryMoveStep.choosingParent;
  var _targets = <LibraryMoveTarget>[];
  var _items = <LibraryOrderItem>[];
  LibraryMoveTarget? _selectedTarget;
  AppException? _loadError;
  var _isLoading = true;
  var _isSaving = false;

  LibraryOrganizationController get _controller =>
      widget.controller ?? ref.read(libraryOrganizationControllerProvider);

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadTargets);
  }

  Future<void> _loadTargets() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final result = await _controller.loadTargets(widget.request);
      if (!mounted) return;
      switch (result) {
        case Success<List<LibraryMoveTarget>>(:final value):
          setState(() {
            _targets = value;
            _isLoading = false;
          });
        case Failure<List<LibraryMoveTarget>>(:final exception):
          setState(() {
            _loadError = exception;
            _isLoading = false;
          });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = const DatabaseException('加载移动目标失败，请重试');
        _isLoading = false;
      });
    }
  }

  Future<void> _chooseTarget(LibraryMoveTarget target) async {
    if (_isLoading || !target.canSelect) return;
    setState(() => _isLoading = true);
    try {
      final result = await _controller.loadTargetSiblings(
        widget.request,
        target,
      );
      if (!mounted) return;
      if (result case Failure<List<LibraryOrderItem>>(:final exception)) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(exception.userMessage)));
        return;
      }
      final siblings = [...(result as Success<List<LibraryOrderItem>>).value];
      if (!siblings.any((item) => item.id == widget.request.itemId)) {
        siblings.add(
          LibraryOrderItem(
            id: widget.request.itemId,
            label: widget.request.itemName,
          ),
        );
      }
      setState(() {
        _selectedTarget = target;
        _items = siblings;
        _step = LibraryMoveStep.choosingPosition;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('加载目标位置失败，请重试')));
    }
  }

  void _backToTargets() {
    if (_isSaving) return;
    setState(() {
      _step = LibraryMoveStep.choosingParent;
      _selectedTarget = null;
      _items = [];
    });
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      final item = _items.removeAt(oldIndex);
      _items.insert(newIndex, item);
    });
  }

  Future<void> _save() async {
    final target = _selectedTarget;
    if (_isSaving || target == null) return;
    final targetIndex = _items.indexWhere(
      (item) => item.id == widget.request.itemId,
    );
    if (targetIndex < 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('待移动项目已不在列表中，请返回重选')));
      return;
    }
    setState(() => _isSaving = true);
    try {
      final result = await _controller.move(
        widget.request,
        target,
        targetIndex,
      );
      if (!mounted) return;
      if (result case Failure<void>(:final exception)) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(exception.userMessage)));
        return;
      }
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('移动失败，请重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == LibraryMoveStep.choosingParent,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step == LibraryMoveStep.choosingPosition) {
          _backToTargets();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _step == LibraryMoveStep.choosingPosition
              ? IconButton(
                  key: const Key('move-back'),
                  tooltip: '返回选择目标',
                  onPressed: _isSaving ? null : _backToTargets,
                  icon: const Icon(Icons.arrow_back),
                )
              : null,
          title: Text(
            _step == LibraryMoveStep.choosingParent ? '选择移动目标' : '选择插入位置',
          ),
          actions: [
            TextButton(
              key: const Key('move-cancel'),
              onPressed: _isSaving
                  ? null
                  : () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            if (_step == LibraryMoveStep.choosingPosition)
              TextButton(
                key: const Key('move-save'),
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('保存'),
              ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError case final error?) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error.userMessage),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadTargets,
              icon: const Icon(Icons.refresh),
              label: const Text('重新加载'),
            ),
          ],
        ),
      );
    }
    if (_step == LibraryMoveStep.choosingParent) {
      return KeyedSubtree(
        key: const Key('move-target-step'),
        child: LibraryMoveTargetTree(
          targets: _targets,
          onSelected: _chooseTarget,
        ),
      );
    }
    return _buildPositionStep();
  }

  Widget _buildPositionStep() {
    final target = _selectedTarget!;
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      key: const Key('move-position-step'),
      children: [
        ListTile(
          leading: const Icon(Icons.drive_file_move_outline),
          title: const Text('目标位置'),
          subtitle: Text(target.pathLabels.join(' / ')),
        ),
        const Divider(height: 1),
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: _items.length,
            onReorderItem: _reorder,
            itemBuilder: (context, index) {
              final item = _items[index];
              final isMoving = item.id == widget.request.itemId;
              return ListTile(
                key: ValueKey('move-position-item-${item.id}'),
                tileColor: isMoving ? colorScheme.secondaryContainer : null,
                leading: CircleAvatar(child: Text('${index + 1}')),
                title: Text(
                  isMoving ? '正在移动：${widget.request.itemName}' : item.label,
                ),
                trailing: ReorderableDragStartListener(
                  key: Key('move-position-handle-${item.id}'),
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(Icons.drag_handle),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
