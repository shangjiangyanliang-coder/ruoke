// 文件: lib/src/features/notes/view/library_browser_view.dart
// 作用: 文件夹、书、章、节的逐级笔记浏览页面。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/errors/result.dart';
import '../models/library_location.dart';
import '../models/subject_folder.dart';
import '../providers.dart';
import '../view_model/library_browser_view_model.dart';

class LibraryBrowserView extends ConsumerWidget {
  final LibraryLocation location;
  const LibraryBrowserView({super.key, required this.location});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(libraryBrowserProvider(location));
    final state = data is AsyncData<LibraryBrowserState> ? data.value : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(state?.title ?? '笔记'),
        actions: [
          IconButton(
            tooltip: '搜索笔记',
            icon: const Icon(Icons.search),
            onPressed: () => context.push('/notes/search'),
          ),
          IconButton(
            tooltip: '标签搜索',
            icon: const Icon(Icons.sell_outlined),
            onPressed: () => context.push('/notes/tags'),
          ),
          if (location is LibraryRootLocation)
            IconButton(
              tooltip: '书章节管理',
              icon: const Icon(Icons.account_tree_outlined),
              onPressed: () => context.push('/settings/subjects/legacy'),
            ),
          if (location is LibraryRootLocation || location is LibraryFolderLocation)
            IconButton(
              tooltip: '新建文件夹',
              icon: const Icon(Icons.create_new_folder_outlined),
              onPressed: () => _createFolder(context, ref),
            ),
        ],
      ),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('加载失败：$error')),
        data: (state) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(libraryBrowserProvider(location));
            await ref.read(libraryBrowserProvider(location).future);
          },
          child: ListView(
            children: [
              if (state.breadcrumbs.length > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (var index = 0;
                          index < state.breadcrumbs.length;
                          index++) ...[
                        if (index > 0) const Icon(Icons.chevron_right, size: 16),
                        TextButton(
                          onPressed: () => context.go(
                            _locationRoute(state.breadcrumbs[index].location),
                          ),
                          child: Text(state.breadcrumbs[index].label),
                        ),
                      ],
                    ],
                  ),
                ),
              if (location is LibraryRootLocation && state.books.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.inbox_outlined),
                  title: const Text('未归类书籍'),
                  subtitle: Text('${state.books.length} 本'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/notes/ungrouped'),
                ),
              ...state.folders.map((folder) => ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(folder.name),
                    trailing: PopupMenuButton<_FolderAction>(
                      onSelected: (action) => _handleFolderAction(
                        context,
                        ref,
                        folder,
                        action,
                      ),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: _FolderAction.rename,
                          child: Text('重命名'),
                        ),
                        PopupMenuItem(
                          value: _FolderAction.move,
                          child: Text('移动'),
                        ),
                        PopupMenuItem(
                          value: _FolderAction.dissolve,
                          child: Text('安全解散'),
                        ),
                      ],
                    ),
                    onTap: () => context.push('/notes/folder/${folder.id}'),
                  )),
              ...state.books.map((book) => ListTile(
                    leading: const Icon(Icons.menu_book_outlined),
                    title: Text(book.name),
                    trailing: IconButton(
                      tooltip: '移动书',
                      icon: const Icon(Icons.drive_file_move_outlined),
                      onPressed: () => _moveBook(context, ref, book.id),
                    ),
                    onTap: () => context.push('/notes/subject/${book.id}'),
                  )),
              ...state.childSubjects.map((subject) => ListTile(
                    leading: Icon(subject.level == 1
                        ? Icons.bookmark_outline
                        : Icons.article_outlined),
                    title: Text(subject.name),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/notes/subject/${subject.id}'),
                  )),
              ...state.notes.map((note) => ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text(note.displayTitle),
                    subtitle: Text(note.summary, maxLines: 1),
                    onTap: () => context.push('/notes/editor/${note.id}'),
                  )),
            ],
          ),
        ),
      ),
      floatingActionButton: state?.subject == null
          ? null
          : FloatingActionButton(
              onPressed: () => context.push(
                '/notes/editor/new?subjectId=${state!.subject!.id}',
              ),
              child: const Icon(Icons.add),
            ),
    );
  }

  Future<void> _createFolder(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final parentId = switch (location) {
      LibraryFolderLocation(:final folderId) => folderId,
      _ => null,
    };
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    final result = await ref
        .read(folderRepositoryProvider)
        .create(name: name, parentId: parentId);
    if (!context.mounted) return;
    if (result case Failure<String>(:final exception)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(exception.userMessage)),
      );
      return;
    }
    ref.invalidate(libraryBrowserProvider(location));
  }

  Future<void> _handleFolderAction(
    BuildContext context,
    WidgetRef ref,
    SubjectFolder folder,
    _FolderAction action,
  ) async {
    if (action == _FolderAction.rename) {
      final controller = TextEditingController(text: folder.name);
      final name = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('重命名文件夹'),
          content: TextField(controller: controller, autofocus: true),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: const Text('保存'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (name == null) return;
      final result = await ref.read(folderRepositoryProvider).rename(
        id: folder.id,
        name: name,
      );
      if (!context.mounted) return;
      _showResult(context, result);
    } else if (action == _FolderAction.move) {
      final destination = await _chooseFolderDestination(context, ref);
      if (destination == null) return;
      final result = await ref.read(folderRepositoryProvider).moveFolder(
        folderId: folder.id,
        newParentId: destination == _rootDestination ? null : destination,
      );
      if (!context.mounted) return;
      _showResult(context, result);
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('安全解散文件夹'),
          content: const Text('直属子文件夹和书会自动上移，笔记不会被删除。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('解散'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      final result = await ref.read(folderRepositoryProvider).dissolve(folder.id);
      if (!context.mounted) return;
      _showResult(context, result);
    }
    ref.invalidate(libraryBrowserProvider(location));
  }

  Future<void> _moveBook(BuildContext context, WidgetRef ref, String bookId) async {
    final destination = await _chooseFolderDestination(context, ref);
    if (destination == null) return;
    final result = await ref.read(folderRepositoryProvider).moveBook(
      bookId: bookId,
      folderId: destination == _rootDestination ? null : destination,
    );
    if (!context.mounted) return;
    _showResult(context, result);
    ref.invalidate(libraryBrowserProvider(location));
  }
}

enum _FolderAction { rename, move, dissolve }

const _rootDestination = '__root_destination__';

String _locationRoute(LibraryLocation location) => switch (location) {
  LibraryRootLocation() => '/notes',
  LibraryFolderLocation(:final folderId) => '/notes/folder/$folderId',
  LibraryUngroupedBooksLocation() => '/notes/ungrouped',
  LibrarySubjectLocation(:final subjectId) => '/notes/subject/$subjectId',
};

Future<String?> _chooseFolderDestination(BuildContext context, WidgetRef ref) async {
  final result = await ref.read(folderRepositoryProvider).listAll();
  if (result case Failure<List<SubjectFolder>>(:final exception)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(exception.userMessage)),
      );
    }
    return null;
  }
  final folders = (result as Success<List<SubjectFolder>>).value;
  if (!context.mounted) return null;
  return showModalBottomSheet<String>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.home_outlined),
            title: const Text('根目录／未归类'),
            onTap: () => Navigator.pop(sheetContext, _rootDestination),
          ),
          for (final folder in folders)
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(folder.name),
              onTap: () => Navigator.pop(sheetContext, folder.id),
            ),
        ],
      ),
    ),
  );
}

void _showResult(BuildContext context, Result<void> result) {
  if (!context.mounted || result is Success<void>) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text((result as Failure<void>).exception.userMessage)),
  );
}
