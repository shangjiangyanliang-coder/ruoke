// 可搜索书章节范围树的默认展示、展开、搜索和会话重置测试。
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ruoke/src/data/database/app_database.dart';
import 'package:ruoke/src/features/notes/providers.dart';
import 'package:ruoke/src/features/notes/view/subject_scope_picker.dart';

void main() {
  testWidgets('默认只显示根书，书和章可逐级展开后选择节', (tester) async {
    final db = await _databaseWithTree();
    addTearDown(db.close);
    await _pumpHarness(tester, db);

    await tester.tap(find.text('打开范围'));
    await tester.pumpAndSettle();
    expect(find.text('数学'), findsOneWidget);
    expect(find.text('函数'), findsNothing);
    expect(find.text('一次函数'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('scope-expand-book')));
    await tester.pumpAndSettle();
    expect(find.text('函数'), findsOneWidget);
    expect(find.text('一次函数'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('scope-expand-chapter')));
    await tester.pumpAndSettle();
    expect(find.text('一次函数'), findsOneWidget);

    await tester.tap(find.text('一次函数'));
    await tester.pumpAndSettle();
    expect(find.text('已选：数学 > 函数 > 一次函数'), findsOneWidget);
  });

  testWidgets('按名称搜索章和节时显示所属书章节路径', (tester) async {
    final db = await _databaseWithTree();
    addTearDown(db.close);
    await _pumpHarness(tester, db);

    await tester.tap(find.text('打开范围'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('subject-scope-search')),
      '一次',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('一次函数'), findsOneWidget);
    expect(find.text('数学 > 函数'), findsOneWidget);
  });

  testWidgets('多个搜索结果会合并共同的书和章祖先', (tester) async {
    final db = await _databaseWithTree();
    addTearDown(db.close);
    await _insertSubject(
      db,
      id: 'theorem-a',
      parentId: 'chapter',
      name: '定理一',
      level: 2,
    );
    await _insertSubject(
      db,
      id: 'theorem-b',
      parentId: 'chapter',
      name: '定理二',
      level: 2,
    );
    await _pumpHarness(tester, db);

    await tester.tap(find.text('打开范围'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('subject-scope-search')),
      '定理',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('数学'), findsOneWidget);
    expect(find.text('函数'), findsOneWidget);
    expect(find.text('定理一'), findsOneWidget);
    expect(find.text('定理二'), findsOneWidget);
  });

  testWidgets('层级快捷入口可选择全部章', (tester) async {
    final db = await _databaseWithTree();
    addTearDown(db.close);
    await _pumpHarness(tester, db);

    await tester.tap(find.text('打开范围'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('选择全部或指定层级'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部章').last);
    await tester.pumpAndSettle();

    expect(find.text('已选：全部章'), findsOneWidget);
  });

  testWidgets('关闭重开会清空关键词和展开状态', (tester) async {
    final db = await _databaseWithTree();
    addTearDown(db.close);
    await _pumpHarness(tester, db);

    await tester.tap(find.text('打开范围'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scope-expand-book')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('subject-scope-search')),
      '函数',
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('打开范围'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('subject-scope-search')),
    );
    expect(field.controller?.text, isEmpty);
    expect(find.text('数学'), findsOneWidget);
    expect(find.text('函数'), findsNothing);
  });
}

Future<AppDatabase> _databaseWithTree() async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  await _insertSubject(db, id: 'book', name: '数学', level: 0);
  await _insertSubject(
    db,
    id: 'chapter',
    parentId: 'book',
    name: '函数',
    level: 1,
  );
  await _insertSubject(
    db,
    id: 'section',
    parentId: 'chapter',
    name: '一次函数',
    level: 2,
  );
  return db;
}

Future<void> _pumpHarness(WidgetTester tester, AppDatabase db) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: const MaterialApp(home: _PickerHarness()),
    ),
  );
}

class _PickerHarness extends StatefulWidget {
  const _PickerHarness();

  @override
  State<_PickerHarness> createState() => _PickerHarnessState();
}

class _PickerHarnessState extends State<_PickerHarness> {
  String? selected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          FilledButton(
            onPressed: () async {
              final result = await showSubjectScopePicker(context: context);
              if (result != null && mounted) {
                setState(() => selected = result.label);
              }
            },
            child: const Text('打开范围'),
          ),
          if (selected != null) Text('已选：$selected'),
        ],
      ),
    );
  }
}

Future<void> _insertSubject(
  AppDatabase db, {
  required String id,
  required String name,
  required int level,
  String? parentId,
}) {
  return db.subjectDao.insertSubject(
    SubjectsCompanion(
      id: Value(id),
      parentId: Value(parentId),
      name: Value(name),
      level: Value(level),
      createdAt: const Value(1),
      updatedAt: const Value(1),
    ),
  );
}
