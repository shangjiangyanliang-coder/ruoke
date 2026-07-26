// 文件: test/widget_test.dart
// 作用: 验证当前路由应用能在内存数据库和 ProviderScope 下挂载。

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ruoke/main.dart';
import 'package:ruoke/src/data/database/app_database.dart';
import 'package:ruoke/src/features/notes/providers.dart';

void main() {
  testWidgets('RuokeApp 能挂载笔记导航页', (WidgetTester tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const RuokeApp(),
      ),
    );
    await tester.pump();

    expect(find.text('笔记'), findsWidgets);
  });
}
