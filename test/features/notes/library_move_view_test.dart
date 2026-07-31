// 作用：验证两步移动页的目标选择、精确插入、返回取消和失败重试。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:ruoke/src/data/errors/app_exception.dart';
import 'package:ruoke/src/data/errors/result.dart';
import 'package:ruoke/src/features/notes/models/library_organization.dart';
import 'package:ruoke/src/features/notes/view/library_move_view.dart';
import 'package:ruoke/src/features/notes/view_model/library_organization_controller.dart';

void main() {
  late _MockOrganizationController controller;

  setUpAll(() {
    registerFallbackValue(_request);
    registerFallbackValue(_bookTarget);
  });

  setUp(() {
    controller = _MockOrganizationController();
    when(
      () => controller.loadTargets(any()),
    ).thenAnswer((_) async => const Success(_targets));
    when(() => controller.loadTargetSiblings(any(), any())).thenAnswer(
      (_) async => const Success([
        LibraryOrderItem(id: 'a', label: '原有 A'),
        LibraryOrderItem(id: 'b', label: '原有 B'),
      ]),
    );
    when(
      () => controller.move(any(), any(), any()),
    ).thenAnswer((_) async => const Success<void>(null));
  });

  testWidgets('选择目标后拖到精确位置并保存最终索引', (tester) async {
    bool? result;
    await _pumpLauncher(
      tester,
      controller,
      onResult: (value) => result = value,
    );
    await tester.tap(find.byKey(const Key('open-move-view')));
    await tester.pumpAndSettle();
    await _selectBookTarget(tester);

    expect(find.byKey(const Key('move-position-step')), findsOneWidget);
    expect(find.text('正在移动：待移动章'), findsOneWidget);
    await _dragMovingItemUpOne(tester);

    await tester.tap(find.byKey(const Key('move-save')));
    await tester.pumpAndSettle();

    final captured =
        verify(
              () => controller.move(any(), any(), captureAny()),
            ).captured.single
            as int;
    expect(captured, 1);
    expect(result, isTrue);
  });

  testWidgets('空目标列表会以索引 0 插入待移动项', (tester) async {
    when(
      () => controller.loadTargetSiblings(any(), any()),
    ).thenAnswer((_) async => const Success([]));
    await _pumpView(tester, controller);
    await _selectBookTarget(tester);

    await tester.tap(find.byKey(const Key('move-save')));
    await tester.pump();

    verify(() => controller.move(any(), any(), 0)).called(1);
  });

  testWidgets('返回上一步后取消不会写入', (tester) async {
    bool? result;
    await _pumpLauncher(
      tester,
      controller,
      onResult: (value) => result = value,
    );
    await tester.tap(find.byKey(const Key('open-move-view')));
    await tester.pumpAndSettle();
    await _selectBookTarget(tester);

    await tester.tap(find.byKey(const Key('move-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('move-target-step')), findsOneWidget);

    await tester.tap(find.byKey(const Key('move-cancel')));
    await tester.pumpAndSettle();

    verifyNever(() => controller.move(any(), any(), any()));
    expect(result, isFalse);
  });

  testWidgets('保存失败保留位置草稿并可重试成功', (tester) async {
    var saveCount = 0;
    when(() => controller.move(any(), any(), any())).thenAnswer((_) async {
      saveCount++;
      return saveCount == 1
          ? const Failure(DatabaseException('目标列表已变化'))
          : const Success<void>(null);
    });
    bool? result;
    await _pumpLauncher(
      tester,
      controller,
      onResult: (value) => result = value,
    );
    await tester.tap(find.byKey(const Key('open-move-view')));
    await tester.pumpAndSettle();
    await _selectBookTarget(tester);
    await _dragMovingItemUpOne(tester);

    await tester.tap(find.byKey(const Key('move-save')));
    await tester.pumpAndSettle();

    expect(find.text('目标列表已变化'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('正在移动：待移动章')).dy,
      lessThan(tester.getTopLeft(find.text('原有 B')).dy),
    );

    await tester.tap(find.byKey(const Key('move-save')));
    await tester.pumpAndSettle();

    expect(result, isTrue);
    verify(() => controller.move(any(), any(), any())).called(2);
  });
}

const _request = LibraryMoveRequest(
  kind: LibraryItemKind.chapter,
  itemId: 'chapter-moving',
  itemName: '待移动章',
);

const _bookTarget = LibraryMoveTarget(
  kind: LibraryItemKind.book,
  id: 'book-a',
  parentId: 'folder-a',
  label: '数学',
  pathLabels: ['资料 A', '数学'],
  canSelect: true,
);

const _targets = [
  LibraryMoveTarget(
    kind: LibraryItemKind.folder,
    id: 'folder-a',
    parentId: null,
    label: '资料 A',
    pathLabels: ['资料 A'],
    canSelect: false,
  ),
  _bookTarget,
];

class _MockOrganizationController extends Mock
    implements LibraryOrganizationController {}

Future<void> _dragMovingItemUpOne(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    tester.getCenter(
      find.byKey(const Key('move-position-handle-chapter-moving')),
    ),
  );
  await gesture.moveBy(const Offset(0, -40));
  await tester.pump(const Duration(milliseconds: 250));
  await gesture.moveBy(const Offset(0, -40));
  await tester.pump(const Duration(milliseconds: 250));
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> _selectBookTarget(WidgetTester tester) async {
  await tester.tap(find.text('资料 A'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('move-target-select-book-book-a')));
  await tester.pumpAndSettle();
}

Future<void> _pumpView(
  WidgetTester tester,
  LibraryOrganizationController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: LibraryMoveView(request: _request, controller: controller),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpLauncher(
  WidgetTester tester,
  LibraryOrganizationController controller, {
  required ValueChanged<bool?> onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            key: const Key('open-move-view'),
            onPressed: () async {
              final result = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => LibraryMoveView(
                    request: _request,
                    controller: controller,
                  ),
                ),
              );
              onResult(result);
            },
            child: const Text('打开'),
          ),
        ),
      ),
    ),
  );
}
