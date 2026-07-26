// 文件: lib/src/routing/app_router.dart
// 作用: go_router 路由表。StatefulShellRoute.indexedStack 承载 5 标签底栏
//       （首页/笔记/题库/学习/我的），各 tab 独立 Navigator 保状态。
//       笔记编辑器(/notes/editor/:noteId)作沉浸页挂 shell 外（隐藏底栏）。
//       第2批只有"笔记"tab接真页，其余tab放占位页，后续阶段替换。
//       详见技术方案 C §1 路由设计。
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/notes/view/note_editor_view.dart';
import '../features/notes/view/note_list_view.dart';
import '../features/notes/view/note_search_view.dart';
import '../features/notes/view/note_version_list_view.dart';
import '../features/notes/view/subject_manage_view.dart';
import '../features/notes/view/tag_management_view.dart';
import 'placeholder_page.dart';
import 'settings_view.dart';

/// 全局路由配置。由 main.dart 或 ProviderScope 注入 MaterialApp.router。
final GoRouter appRouter = GoRouter(
  initialLocation: '/notes',
  routes: [
    // 沉浸页：编辑器（不在 shell 内，隐藏底栏）
    // 可选 query: ?subjectId=xxx 用于"新建"时一键定级（FAB 定级窗选完带过来）
    GoRoute(
      path: '/notes/editor/:noteId',
      builder: (context, state) {
        final noteId = state.pathParameters['noteId']!;
        final subjectId = state.uri.queryParameters['subjectId'];
        return NoteEditorView(noteId: noteId, subjectId: subjectId);
      },
    ),
    GoRoute(
      path: '/notes/editor/:noteId/versions',
      builder: (context, state) =>
          NoteVersionListView(noteId: state.pathParameters['noteId']!),
    ),
    GoRoute(
      path: '/notes/tags',
      builder: (context, state) => const TagManagementView(),
    ),
    GoRoute(
      path: '/notes/search',
      builder: (context, state) {
        final rawTagIds = state.uri.queryParameters['tagIds'];
        final tagIds = rawTagIds == null || rawTagIds.isEmpty
            ? const <String>{}
            : rawTagIds.split(',').where((id) => id.isNotEmpty).toSet();
        return NoteSearchView(initialTagIds: tagIds);
      },
    ),
    // 底部 5 标签导航 shell
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return ScaffoldWithNavBar(navigationShell: navigationShell);
      },
      branches: [
        // tab0 首页（占位）
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) =>
                  const PlaceholderPage(title: '首页', hint: '学习仪表盘（待开发）'),
            ),
          ],
        ),
        // tab1 笔记（已实现）
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/notes',
              builder: (context, state) => const NoteListView(),
            ),
          ],
        ),
        // tab2 题库（占位）
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/quiz',
              builder: (context, state) =>
                  const PlaceholderPage(title: '题库', hint: '题库浏览（待开发）'),
            ),
          ],
        ),
        // tab3 学习（占位）
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/study',
              builder: (context, state) =>
                  const PlaceholderPage(title: '学习', hint: '每日清单（待开发）'),
            ),
          ],
        ),
        // tab4 我的（设置，含学科管理入口）
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsView(),
              routes: [
                GoRoute(
                  path: 'subjects',
                  builder: (context, state) => const SubjectManageView(),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);

/// 带 5 标签底栏的 Scaffold 外壳。
class ScaffoldWithNavBar extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const ScaffoldWithNavBar({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (i) => navigationShell.goBranch(
          i,
          initialLocation: i == navigationShell.currentIndex,
        ),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.book_outlined),
            selectedIcon: Icon(Icons.book),
            label: '笔记',
          ),
          NavigationDestination(
            icon: Icon(Icons.quiz_outlined),
            selectedIcon: Icon(Icons.quiz),
            label: '题库',
          ),
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school),
            label: '学习',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
