// 作用：验证五类目录项目统一三点菜单的动作集合与回调。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ruoke/src/features/notes/models/library_organization.dart';
import 'package:ruoke/src/features/notes/view/library_item_action_menu.dart';

void main() {
  testWidgets('文件夹菜单包含安全解散，其他四类只包含通用动作', (tester) async {
    for (final kind in LibraryItemKind.values) {
      await _pumpMenu(tester, kind: kind, onSelected: (_) {});
      await tester.tap(find.byKey(const Key('item-menu')));
      await tester.pumpAndSettle();

      expect(find.text('重命名'), findsOneWidget);
      expect(find.text('移动'), findsOneWidget);
      expect(find.text('调整顺序'), findsOneWidget);
      expect(
        find.text('安全解散'),
        kind == LibraryItemKind.folder ? findsOneWidget : findsNothing,
      );

      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
    }
  });

  testWidgets('选择菜单项会回传对应动作且不会触发外层点击', (tester) async {
    LibraryItemAction? selected;
    var outerTapCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InkWell(
            onTap: () => outerTapCount++,
            child: LibraryItemActionMenu(
              key: const Key('item-menu'),
              kind: LibraryItemKind.note,
              onSelected: (action) => selected = action,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('item-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移动'));
    await tester.pumpAndSettle();

    expect(selected, LibraryItemAction.move);
    expect(outerTapCount, 0);
  });
}

Future<void> _pumpMenu(
  WidgetTester tester, {
  required LibraryItemKind kind,
  required ValueChanged<LibraryItemAction> onSelected,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: LibraryItemActionMenu(
        key: const Key('item-menu'),
        kind: kind,
        onSelected: onSelected,
      ),
    ),
  ),
);
