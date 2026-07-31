// 作用：提供同级同类目录项目的草稿式拖拽排序与显式保存页面。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/errors/app_exception.dart';
import '../../../data/errors/result.dart';
import '../models/library_organization.dart';
import '../providers.dart';
import '../view_model/library_organization_controller.dart';

/// 打开排序页；仅保存成功返回 true，取消返回 false，系统返回可为 null。
Future<bool?> showLibraryReorderView(
  BuildContext context, {
  required LibraryReorderRequest request,
}) => Navigator.of(context).push<bool>(
  MaterialPageRoute(builder: (_) => LibraryReorderView(request: request)),
);

class LibraryReorderView extends ConsumerStatefulWidget {
  final LibraryReorderRequest request;

  /// 仅供测试或独立嵌入时注入；正常页面从 Provider 读取。
  final LibraryOrganizationController? controller;

  const LibraryReorderView({super.key, required this.request, this.controller});

  @override
  ConsumerState<LibraryReorderView> createState() => _LibraryReorderViewState();
}

class _LibraryReorderViewState extends ConsumerState<LibraryReorderView> {
  var _items = <LibraryOrderItem>[];
  var _isLoading = true;
  var _isSaving = false;
  AppException? _loadError;

  LibraryOrganizationController get _controller =>
      widget.controller ?? ref.read(libraryOrganizationControllerProvider);

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final result = await _controller.loadSiblings(widget.request);
      if (!mounted) return;
      switch (result) {
        case Success<List<LibraryOrderItem>>(:final value):
          setState(() {
            _items = [...value];
            _isLoading = false;
          });
        case Failure<List<LibraryOrderItem>>(:final exception):
          setState(() {
            _loadError = exception;
            _isLoading = false;
          });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = const DatabaseException('加载排序列表失败，请重试');
        _isLoading = false;
      });
    }
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      final item = _items.removeAt(oldIndex);
      _items.insert(newIndex, item);
    });
  }

  Future<void> _save() async {
    if (_isSaving || _isLoading || _loadError != null) return;
    setState(() => _isSaving = true);
    try {
      final result = await _controller.saveOrder(
        widget.request,
        _items.map((item) => item.id).toList(),
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
      ).showSnackBar(const SnackBar(content: Text('保存顺序失败，请重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.request.title),
        actions: [
          TextButton(
            key: const Key('reorder-cancel'),
            onPressed: _isSaving
                ? null
                : () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('reorder-save'),
            onPressed: _isSaving || _isLoading || _loadError != null
                ? null
                : _save,
            child: _isSaving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError case final error?) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error.userMessage, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('重新加载'),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(child: Text('当前没有可排序的项目'));
    }
    final colorScheme = Theme.of(context).colorScheme;
    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      buildDefaultDragHandles: false,
      itemCount: _items.length,
      onReorderItem: _reorder,
      itemBuilder: (context, index) {
        final item = _items[index];
        return ListTile(
          key: ValueKey('reorder-item-${item.id}'),
          leading: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer,
              shape: BoxShape.circle,
            ),
            child: Text('${index + 1}'),
          ),
          title: Text(item.label),
          trailing: ReorderableDragStartListener(
            key: ValueKey('reorder-handle-${item.id}'),
            index: index,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Icon(Icons.drag_handle),
            ),
          ),
        );
      },
    );
  }
}
