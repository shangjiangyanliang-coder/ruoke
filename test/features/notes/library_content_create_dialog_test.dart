import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruoke/src/features/notes/models/library_navigation_state.dart';
import 'package:ruoke/src/features/notes/view/library_content_create_dialog.dart';

void main() {
  testWidgets('新建内容弹窗只返回类型和名称，不展示全局位置列表', (tester) async {
    LibraryContentDraft? draft;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async => draft = await showLibraryContentCreateDialog(context),
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('创建位置'), findsNothing);
    await tester.enterText(find.byType(TextField), '资料');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();

    expect(draft?.name, '资料');
  });
}
