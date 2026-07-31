// 作用：验证移动目标树的展开、搜索祖先保留、同名路径和选择限制。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ruoke/src/features/notes/models/library_organization.dart';
import 'package:ruoke/src/features/notes/view/library_move_target_tree.dart';

void main() {
  testWidgets('无关键词时按文件夹书章节逐层展开', (tester) async {
    LibraryMoveTarget? selected;
    await _pumpTree(tester, onSelected: (target) => selected = target);

    expect(find.text('资料 A'), findsOneWidget);
    expect(find.text('数学'), findsNothing);

    await tester.tap(find.text('资料 A'));
    await tester.pumpAndSettle();
    expect(find.text('数学'), findsOneWidget);

    await tester.tap(find.byKey(const Key('move-target-select-book-book-a')));
    expect(selected?.id, 'book-a');
  });

  testWidgets('搜索命中章时保留祖先并显示完整路径区分同名节点', (tester) async {
    await _pumpTree(tester, onSelected: (_) {});

    await tester.enterText(find.byKey(const Key('move-target-search')), '函数');
    await tester.pumpAndSettle();

    expect(find.text('资料 A'), findsOneWidget);
    expect(find.text('资料 B'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(ListView), matching: find.text('函数')),
      findsNWidgets(2),
    );
    expect(find.text('资料 A / 数学 / 函数'), findsOneWidget);
    expect(find.text('资料 B / 数学 / 函数'), findsOneWidget);
    expect(find.text('语文'), findsNothing);
  });

  testWidgets('不可选路径节点没有选择动作，可选节点正常回调', (tester) async {
    final selected = <String?>[];
    await _pumpTree(tester, onSelected: (target) => selected.add(target.id));

    expect(
      find.byKey(const Key('move-target-select-folder-folder-a')),
      findsNothing,
    );
    await tester.tap(find.text('资料 A'));
    await tester.pumpAndSettle();
    expect(selected, isEmpty);

    await tester.tap(find.byKey(const Key('move-target-select-book-book-a')));
    expect(selected, ['book-a']);
  });
}

Future<void> _pumpTree(
  WidgetTester tester, {
  required ValueChanged<LibraryMoveTarget> onSelected,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LibraryMoveTargetTree(targets: _targets, onSelected: onSelected),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _targets = [
  LibraryMoveTarget(
    kind: LibraryItemKind.folder,
    id: 'folder-a',
    parentId: null,
    label: '资料 A',
    pathLabels: ['资料 A'],
    canSelect: false,
  ),
  LibraryMoveTarget(
    kind: LibraryItemKind.book,
    id: 'book-a',
    parentId: 'folder-a',
    label: '数学',
    pathLabels: ['资料 A', '数学'],
    canSelect: true,
  ),
  LibraryMoveTarget(
    kind: LibraryItemKind.chapter,
    id: 'chapter-a',
    parentId: 'book-a',
    label: '函数',
    pathLabels: ['资料 A', '数学', '函数'],
    canSelect: false,
  ),
  LibraryMoveTarget(
    kind: LibraryItemKind.folder,
    id: 'folder-b',
    parentId: null,
    label: '资料 B',
    pathLabels: ['资料 B'],
    canSelect: false,
  ),
  LibraryMoveTarget(
    kind: LibraryItemKind.book,
    id: 'book-b',
    parentId: 'folder-b',
    label: '数学',
    pathLabels: ['资料 B', '数学'],
    canSelect: true,
  ),
  LibraryMoveTarget(
    kind: LibraryItemKind.chapter,
    id: 'chapter-b',
    parentId: 'book-b',
    label: '函数',
    pathLabels: ['资料 B', '数学', '函数'],
    canSelect: false,
  ),
  LibraryMoveTarget(
    kind: LibraryItemKind.book,
    id: 'book-root',
    parentId: null,
    label: '语文',
    pathLabels: ['未归类书籍', '语文'],
    canSelect: true,
  ),
];
