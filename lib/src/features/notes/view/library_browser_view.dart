// 文件: lib/src/features/notes/view/library_browser_view.dart
// 作用: 文件夹、书、章、节的逐级笔记浏览页面。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/errors/result.dart';
import '../../../data/errors/app_exception.dart';
import '../models/library_location.dart';
import '../models/library_navigation_state.dart';
import '../models/subject_folder.dart';
import '../providers.dart';
import '../utils/library_creation_scope.dart';
import '../utils/library_selection_rules.dart';
import '../view_model/library_browser_view_model.dart';
import '../view_model/library_selection_rules_provider.dart';
import '../view_model/view_model_providers.dart';
import 'library_content_create_dialog.dart';
import 'library_expanded_tree.dart';

class LibraryBrowserView extends ConsumerStatefulWidget {
  final LibraryLocation location;
  const LibraryBrowserView({super.key, required this.location});

  @override
  ConsumerState<LibraryBrowserView> createState() => _LibraryBrowserViewState();
}

class _LibraryBrowserViewState extends ConsumerState<LibraryBrowserView> {
  LibraryLocation get location => widget.location;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(libraryBrowserProvider(location));
    final navigation = ref.watch(libraryNavigationVmProvider).value ??
        const LibraryNavigationState();
    final browseMode = navigation.browseMode;
    final selection = navigation.selection;
    final selectionRules = selection == null
        ? null
        : ref.watch(librarySelectionRulesProvider);
    final rules = selectionRules?.value;
    final state = data is AsyncData<LibraryBrowserState> ? data.value : null;
    return PopScope(
      canPop: selection == null ||
          _locationRoute(location) != _locationRoute(selection.origin),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && selection != null) {
          _cancelSelection(context, selection);
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(selection == null ? state?.title ?? '笔记' : '选择创建位置'),
        actions: selection == null ? [
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
          IconButton(
              tooltip: browseMode == LibraryBrowseMode.drillDown
                  ? '展开浏览'
                  : '逐级浏览',
              icon: Icon(
                browseMode == LibraryBrowseMode.drillDown
                    ? Icons.unfold_more_outlined
                    : Icons.folder_open_outlined,
              ),
              onPressed: () =>
                  ref.read(libraryNavigationVmProvider.notifier).toggleBrowseMode(),
            ),
          if (state?.subject?.level != 2 && location is! LibraryUngroupedBooksLocation)
            IconButton(
              tooltip: '新建内容',
              icon: const Icon(Icons.add_box_outlined),
              onPressed: () async {
                final draft = await showLibraryContentCreateDialog(context);
                if (draft == null) return;
                ref.read(libraryNavigationVmProvider.notifier).startContentSelection(
                  origin: location,
                  draft: draft,
                );
              },
            ),
        ] : [
          TextButton(
            onPressed: () => _cancelSelection(context, selection),
            child: const Text('取消'),
          ),
        ],
      ),
      body: browseMode == LibraryBrowseMode.expanded
          ? LibraryExpandedTree(location: location)
          : data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('加载失败：$error')),
        data: (state) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(libraryBrowserProvider(location));
            await ref.read(libraryBrowserProvider(location).future);
          },
          child: ListView(
            children: [
              if (selection != null)
                ..._selectionCurrentLocationAction(
                  context,
                  selection,
                  selectionRules!,
                ),
              if (selection == null && state.breadcrumbs.length > 1)
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
                  onTap: selection != null &&
                          !(rules?.canEnter(
                                session: selection,
                                location: const LibraryLocation.ungroupedBooks(),
                              ) ??
                              false)
                      ? null
                      : () => context.push('/notes/ungrouped'),
                ),
              ...state.folders.map((folder) => ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(folder.name),
                    trailing: selection == null ? PopupMenuButton<_FolderAction>(
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
                    ) : const Icon(Icons.chevron_right),
                    onTap: selection != null &&
                            !(rules?.canEnter(
                                  session: selection,
                                  location: LibraryLocation.folder(folder.id),
                                ) ??
                                false)
                        ? null
                        : () => context.push('/notes/folder/${folder.id}'),
                  )),
              ...state.books.map((book) => ListTile(
                    leading: const Icon(Icons.menu_book_outlined),
                    title: Text(book.name),
                    trailing: selection == null ? IconButton(
                      tooltip: '移动书',
                      icon: const Icon(Icons.drive_file_move_outlined),
                      onPressed: () => _moveBook(context, ref, book.id),
                    ) : _selectionTrailing(
                      context,
                      selection,
                      LibraryLocation.subject(book.id),
                      rules,
                    ),
                    onTap: selection != null &&
                            !(rules?.canEnter(
                                  session: selection,
                                  location: LibraryLocation.subject(book.id),
                                ) ??
                                false)
                        ? null
                        : () => context.push('/notes/subject/${book.id}'),
                  )),
              ...state.childSubjects.map((subject) => ListTile(
                    leading: Icon(subject.level == 1
                        ? Icons.bookmark_outline
                        : Icons.article_outlined),
                    title: Text(subject.name),
                    trailing: selection == null
                        ? const Icon(Icons.chevron_right)
                        : _selectionTrailing(
                            context,
                            selection,
                            LibraryLocation.subject(subject.id),
                            rules,
                          ),
                    onTap: selection != null &&
                            !(rules?.canEnter(
                                  session: selection,
                                  location: LibraryLocation.subject(subject.id),
                                ) ??
                                false)
                        ? null
                        : selection?.kind == LibrarySelectionKind.noteLocation &&
                                subject.level == 2
                            ? () => _selectLocation(
                                  context,
                                  selection!,
                                  LibraryLocation.subject(subject.id),
                                )
                            : () => context.push('/notes/subject/${subject.id}'),
                  )),
              if (selection == null)
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
      floatingActionButton: selection == null ? FloatingActionButton(
        tooltip: '新建笔记',
        onPressed: () => ref
            .read(libraryNavigationVmProvider.notifier)
            .startNoteSelection(origin: location),
        child: const Icon(Icons.add),
      ) : null,
      ),
    );
  }

  List<Widget> _selectionCurrentLocationAction(
    BuildContext context,
    LibrarySelectionSession selection,
    AsyncValue<LibrarySelectionRules> rules,
  ) {
    return rules.when(
      loading: () => const [LinearProgressIndicator()],
      error: (error, _) => [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('读取可选位置失败：$error'),
        ),
      ],
      data: (value) {
        if (!value.canSelectCurrent(session: selection, location: location)) {
          return const [];
        }
        return [
          Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              icon: const Icon(Icons.check_circle_outline),
              label: Text(
                selection.kind == LibrarySelectionKind.contentLocation
                    ? '在当前目录创建'
                    : '在当前位置创建笔记',
              ),
              onPressed: () => _selectLocation(context, selection, location),
            ),
          ),
        ];
      },
    );
  }

  void _cancelSelection(
    BuildContext context,
    LibrarySelectionSession selection,
  ) {
    ref.read(libraryNavigationVmProvider.notifier).cancelSelection();
    if (_locationRoute(location) != _locationRoute(selection.origin)) {
      context.go(_locationRoute(selection.origin));
    }
  }

  Widget _selectionTrailing(
    BuildContext context,
    LibrarySelectionSession selection,
    LibraryLocation target,
    LibrarySelectionRules? rules,
  ) {
    if (rules?.canSelectCurrent(session: selection, location: target) ?? false) {
      return TextButton(
        onPressed: () => _selectLocation(context, selection, target),
        child: const Text('在此创建'),
      );
    }
    return const Icon(Icons.chevron_right);
  }

  Future<void> _selectLocation(
    BuildContext context,
    LibrarySelectionSession selection,
    LibraryLocation target,
  ) async {
    if (selection.kind == LibrarySelectionKind.noteLocation) {
      ref.invalidate(librarySelectionRulesProvider);
      final rules = await ref.read(librarySelectionRulesProvider.future);
      if (!rules.canSelectCurrent(session: selection, location: target)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('当前笔记位置不合法或已发生变化')),
          );
        }
        return;
      }
      ref.read(libraryNavigationVmProvider.notifier).completeSelection();
      await context.push(
        '/notes/editor/new?subjectId=${(target as LibrarySubjectLocation).subjectId}',
      );
      if (context.mounted) _refreshLibraryRoots(ref, location);
      return;
    }
    final result = await _createDraftAt(
      ref,
      draft: selection.contentDraft!,
      target: target,
      session: selection,
    );
    if (!context.mounted) return;
    if (result is Failure<void>) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.exception.userMessage)),
      );
      return;
    }
    ref.read(libraryNavigationVmProvider.notifier).completeSelection();
    _refreshLibraryRoots(ref, location);
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
    _refreshLibraryRoots(ref, location);
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
    _refreshLibraryRoots(ref, location);
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

void _refreshLibraryRoots(WidgetRef ref, LibraryLocation location) {
  ref.invalidate(libraryBrowserProvider(location));
  ref.invalidate(libraryBrowserProvider(const LibraryLocation.root()));
  ref.invalidate(librarySelectionRulesProvider);
  refreshLibraryExpandedTree(ref);
}

Future<Result<void>> _createDraftAt(
  WidgetRef ref, {
  required LibraryContentDraft draft,
  required LibraryLocation target,
  required LibrarySelectionSession session,
}) async {
  ref.invalidate(librarySelectionRulesProvider);
  final rules = await ref.read(librarySelectionRulesProvider.future);
  if (!rules.canSelectCurrent(session: session, location: target)) {
    return const Failure(ValidationException('当前创建位置不合法或已发生变化'));
  }

  Result<String> result;
  switch (draft.kind) {
    case LibraryContentKind.folder:
      result = await ref.read(folderRepositoryProvider).create(
        name: draft.name,
        parentId: target is LibraryFolderLocation ? target.folderId : null,
      );
    case LibraryContentKind.book:
      result = await ref.read(subjectRepositoryProvider).create(
        name: draft.name,
        level: 0,
        folderId: target is LibraryFolderLocation ? target.folderId : null,
      );
    case LibraryContentKind.chapter:
      result = await ref.read(subjectRepositoryProvider).create(
        name: draft.name,
        level: 1,
        parentId: (target as LibrarySubjectLocation).subjectId,
      );
    case LibraryContentKind.section:
      result = await ref.read(subjectRepositoryProvider).create(
        name: draft.name,
        level: 2,
        parentId: (target as LibrarySubjectLocation).subjectId,
      );
  }
  return switch (result) {
    Success<String>() => const Success(null),
    Failure<String>(:final exception) => Failure(exception),
  };
}
