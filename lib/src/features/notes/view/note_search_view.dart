// 笔记搜索页：关键词、标签并集筛选、三种排序和结果导航。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/note.dart';
import '../models/note_search_query.dart';
import '../view_model/view_model_providers.dart';

/// 笔记搜索与筛选结果页。
class NoteSearchView extends ConsumerStatefulWidget {
  final Set<String> initialTagIds;

  const NoteSearchView({super.key, this.initialTagIds = const {}});

  @override
  ConsumerState<NoteSearchView> createState() => _NoteSearchViewState();
}

class _NoteSearchViewState extends ConsumerState<NoteSearchView> {
  late final TextEditingController _keywordController;
  late Set<String> _selectedTagIds;
  NoteSortOrder _sortOrder = NoteSortOrder.updatedDesc;

  @override
  void initState() {
    super.initState();
    final searchNotifier = ref.read(noteSearchVmProvider.notifier);
    final preservedQuery =
        ref.read(noteSearchVmProvider).value?.query ??
        searchNotifier.currentQuery;
    _keywordController = TextEditingController(text: preservedQuery.keyword);
    _selectedTagIds = widget.initialTagIds.isNotEmpty
        ? Set.of(widget.initialTagIds)
        : Set.of(preservedQuery.tagIds);
    _sortOrder = preservedQuery.sortOrder;
    if (widget.initialTagIds.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(noteSearchVmProvider.notifier).setTagIds(_selectedTagIds);
        }
      });
    }
  }

  @override
  void dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(noteSearchVmProvider);
    final tags = ref.watch(tagManagementVmProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('搜索笔记')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _keywordController,
              textInputAction: TextInputAction.search,
              onSubmitted: _searchKeyword,
              decoration: InputDecoration(
                labelText: '搜索标题或正文',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: '执行搜索',
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: () => _searchKeyword(_keywordController.text),
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text('排序：'),
                const SizedBox(width: 8),
                DropdownButton<NoteSortOrder>(
                  value: _sortOrder,
                  items: const [
                    DropdownMenuItem(
                      value: NoteSortOrder.updatedDesc,
                      child: Text('最近更新'),
                    ),
                    DropdownMenuItem(
                      value: NoteSortOrder.updatedAsc,
                      child: Text('最早更新'),
                    ),
                    DropdownMenuItem(
                      value: NoteSortOrder.titleAsc,
                      child: Text('标题升序'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _sortOrder = value);
                    ref.read(noteSearchVmProvider.notifier).setSortOrder(value);
                  },
                ),
              ],
            ),
          ),
          tags.when(
            loading: () => const LinearProgressIndicator(),
            error: (error, _) => Padding(
              padding: const EdgeInsets.all(8),
              child: Text('标签加载失败：$error'),
            ),
            data: (state) => state.tags.isEmpty
                ? const SizedBox(height: 8)
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        for (final tag in state.tags)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: FilterChip(
                              label: Text(tag.name),
                              selected: _selectedTagIds.contains(tag.id),
                              onSelected: (_) => _toggleTag(tag.id),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
          const Divider(height: 1),
          Expanded(
            child: search.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('搜索失败：$error')),
              data: (state) => state.results.isEmpty
                  ? const Center(child: Text('没有匹配的笔记'))
                  : ListView.builder(
                      itemCount: state.results.length,
                      itemBuilder: (_, index) =>
                          _SearchResultTile(note: state.results[index]),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  void _searchKeyword(String keyword) {
    ref.read(noteSearchVmProvider.notifier).setKeyword(keyword);
  }

  void _toggleTag(String tagId) {
    setState(() {
      if (!_selectedTagIds.add(tagId)) {
        _selectedTagIds.remove(tagId);
      }
    });
    ref
        .read(noteSearchVmProvider.notifier)
        .setTagIds(Set.unmodifiable(_selectedTagIds));
  }
}

class _SearchResultTile extends ConsumerWidget {
  final Note note;

  const _SearchResultTile({required this.note});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(Icons.description_outlined),
      title: Text(note.displayTitle),
      subtitle: Text(
        note.summary,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () async {
        await context.push('/notes/editor/${note.id}');
        if (context.mounted) {
          await ref.read(noteSearchVmProvider.notifier).refresh();
        }
      },
    );
  }
}
