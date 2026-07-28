// 标签搜索页：标签名称匹配、多标签并集、科目范围和排序。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/note.dart';
import '../models/note_search_query.dart';
import '../models/search_match_mode.dart';
import '../models/subject_scope.dart';
import '../models/tag.dart';
import '../view_model/tag_search_view_model.dart';
import '../view_model/view_model_providers.dart';
import 'subject_scope_picker.dart';

/// 主界面的标签搜索入口。保留旧类名以维持路由兼容。
class TagManagementView extends ConsumerStatefulWidget {
  const TagManagementView({super.key});

  @override
  ConsumerState<TagManagementView> createState() => _TagSearchViewState();
}

class _TagSearchViewState extends ConsumerState<TagManagementView> {
  final TextEditingController _keywordController = TextEditingController();
  final Map<String, Tag> _selectedTags = {};
  Timer? _debounce;
  SearchMatchMode _matchMode = SearchMatchMode.contains;
  SubjectScope _subjectScope = const SubjectScope.all();
  String _subjectScopeLabel = '全部笔记';
  NoteSortOrder _sortOrder = NoteSortOrder.updatedDesc;

  @override
  void dispose() {
    _debounce?.cancel();
    _keywordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(tagSearchVmProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('标签搜索')),
      body: search.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('加载失败：$error')),
        data: _buildContent,
      ),
    );
  }

  Widget _buildContent(TagSearchState state) {
    final visibleTags = <String, Tag>{
      ..._selectedTags,
      for (final tag in state.matchedTags) tag.id: tag,
    };
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            key: const ValueKey('tag-search-keyword'),
            controller: _keywordController,
            textInputAction: TextInputAction.search,
            onChanged: _scheduleSearch,
            onSubmitted: (_) => _searchNow(),
            decoration: InputDecoration(
              labelText: '搜索标签名称',
              prefixIcon: const Icon(Icons.sell_outlined),
              suffixIcon: IconButton(
                tooltip: '执行标签搜索',
                onPressed: _searchNow,
                icon: const Icon(Icons.search),
              ),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<SearchMatchMode>(
                value: _matchMode,
                items: const [
                  DropdownMenuItem(
                    value: SearchMatchMode.contains,
                    child: Text('部分匹配'),
                  ),
                  DropdownMenuItem(
                    value: SearchMatchMode.exact,
                    child: Text('完全匹配'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _matchMode = value);
                  ref.read(tagSearchVmProvider.notifier).setTagMatchMode(value);
                },
              ),
              Tooltip(
                message: '选择标签搜索范围',
                child: OutlinedButton.icon(
                  onPressed: _pickSubjectScope,
                  icon: const Icon(Icons.account_tree_outlined),
                  label: Text(_subjectScopeLabel),
                ),
              ),
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
                  ref.read(tagSearchVmProvider.notifier).setSortOrder(value);
                },
              ),
            ],
          ),
        ),
        if (state.searchingTags) const LinearProgressIndicator(),
        if (visibleTags.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                for (final tag in visibleTags.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FilterChip(
                      label: Text(tag.name),
                      selected: state.selectedTagIds.contains(tag.id),
                      onSelected: (_) => _toggleTag(tag),
                    ),
                  ),
              ],
            ),
          )
        else
          const SizedBox(height: 8),
        if (state.tagSearchError != null)
          MaterialBanner(
            content: Text(state.tagSearchError!.userMessage),
            actions: [
              TextButton(
                onPressed: () =>
                    ref.read(tagSearchVmProvider.notifier).retryTagSearch(),
                child: const Text('重试标签'),
              ),
            ],
          ),
        if (state.noteSearchError != null)
          MaterialBanner(
            content: Text(state.noteSearchError!.userMessage),
            actions: [
              TextButton(
                onPressed: () =>
                    ref.read(tagSearchVmProvider.notifier).retryNoteSearch(),
                child: const Text('重试笔记'),
              ),
            ],
          ),
        const Divider(height: 1),
        Expanded(child: _buildResults(state)),
      ],
    );
  }

  Widget _buildResults(TagSearchState state) {
    if (state.selectedTagIds.isEmpty) {
      return const Center(child: Text('请先搜索并选择标签'));
    }
    if (state.searchingNotes) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.results.isEmpty) {
      return const Center(child: Text('没有匹配的笔记'));
    }
    return ListView.builder(
      itemCount: state.results.length,
      itemBuilder: (_, index) => _TagSearchResultTile(
        note: state.results[index],
        onReturn: () => ref.read(tagSearchVmProvider.notifier).refresh(),
      ),
    );
  }

  void _scheduleSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _searchNow);
  }

  void _searchNow() {
    _debounce?.cancel();
    ref
        .read(tagSearchVmProvider.notifier)
        .setTagKeyword(_keywordController.text);
  }

  void _toggleTag(Tag tag) {
    final ids = Set<String>.from(
      ref.read(tagSearchVmProvider).value?.selectedTagIds ?? const {},
    );
    setState(() {
      if (ids.remove(tag.id)) {
        _selectedTags.remove(tag.id);
      } else {
        ids.add(tag.id);
        _selectedTags[tag.id] = tag;
      }
    });
    ref.read(tagSearchVmProvider.notifier).setSelectedTagIds(ids);
  }

  Future<void> _pickSubjectScope() async {
    final selection = await showSubjectScopePicker(context: context);
    if (selection == null || !mounted) return;
    setState(() {
      _subjectScope = selection.scope;
      _subjectScopeLabel = selection.label;
    });
    await ref.read(tagSearchVmProvider.notifier).setSubjectScope(_subjectScope);
  }
}

class _TagSearchResultTile extends StatelessWidget {
  final Note note;
  final Future<void> Function() onReturn;

  const _TagSearchResultTile({required this.note, required this.onReturn});

  @override
  Widget build(BuildContext context) {
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
        if (context.mounted) await onReturn();
      },
    );
  }
}
