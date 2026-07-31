// 作用：验证同级拖拽排序页的草稿、保存、取消和失败重试行为。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:ruoke/src/data/errors/app_exception.dart';
import 'package:ruoke/src/data/errors/result.dart';
import 'package:ruoke/src/features/notes/models/library_organization.dart';
import 'package:ruoke/src/features/notes/view/library_reorder_view.dart';
import 'package:ruoke/src/features/notes/view_model/library_organization_controller.dart';

void main() {
  late _MockOrganizationController controller;

  setUpAll(() {
    registerFallbackValue(_request);
  });

  setUp(() {
    controller = _MockOrganizationController();
    when(() => controller.loadSiblings(any())).thenAnswer(
      (_) async => const Success([
        LibraryOrderItem(id: 'a', label: '第一项'),
        LibraryOrderItem(id: 'b', label: '第二项'),
        LibraryOrderItem(id: 'c', label: '第三项'),
      ]),
    );
    when(
      () => controller.saveOrder(any(), any()),
    ).thenAnswer((_) async => const Success<void>(null));
  });

  testWidgets('加载后拖拽只改变页面草稿，不立即保存', (tester) async {
    await _pumpView(tester, controller);

    await tester.drag(
      find.byKey(const ValueKey('reorder-handle-a')),
      const Offset(0, 180),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('第一项')).dy,
      greaterThan(tester.getTopLeft(find.text('第三项')).dy),
    );
    verifyNever(() => controller.saveOrder(any(), any()));
  });

  testWidgets('保存提交完整 id 列表并返回 true', (tester) async {
    bool? result;
    await _pumpLauncher(
      tester,
      controller,
      onResult: (value) => result = value,
    );
    await tester.tap(find.byKey(const Key('open-reorder-view')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('reorder-handle-a')),
      const Offset(0, 180),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('reorder-save')));
    await tester.pumpAndSettle();

    final captured =
        verify(() => controller.saveOrder(any(), captureAny())).captured.single
            as List<String>;
    expect(captured, ['b', 'c', 'a']);
    expect(result, isTrue);
  });

  testWidgets('取消关闭页面且不保存', (tester) async {
    bool? result;
    await _pumpLauncher(
      tester,
      controller,
      onResult: (value) => result = value,
    );
    await tester.tap(find.byKey(const Key('open-reorder-view')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('reorder-cancel')));
    await tester.pumpAndSettle();

    verifyNever(() => controller.saveOrder(any(), any()));
    expect(result, isFalse);
  });

  testWidgets('保存中按钮禁用', (tester) async {
    final pending = Completer<Result<void>>();
    when(
      () => controller.saveOrder(any(), any()),
    ).thenAnswer((_) => pending.future);
    await _pumpView(tester, controller);

    await tester.tap(find.byKey(const Key('reorder-save')));
    await tester.pump();

    final saveButton = tester.widget<TextButton>(
      find.byKey(const Key('reorder-save')),
    );
    expect(saveButton.onPressed, isNull);

    pending.complete(const Failure(DatabaseException('模拟保存失败')));
    await tester.pumpAndSettle();
  });

  testWidgets('保存失败保留草稿顺序并显示错误，重试成功后关闭', (tester) async {
    var saveCount = 0;
    when(() => controller.saveOrder(any(), any())).thenAnswer((_) async {
      saveCount++;
      return saveCount == 1
          ? const Failure(DatabaseException('列表已变化，请重试'))
          : const Success<void>(null);
    });
    bool? result;
    await _pumpLauncher(
      tester,
      controller,
      onResult: (value) => result = value,
    );
    await tester.tap(find.byKey(const Key('open-reorder-view')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('reorder-handle-a')),
      const Offset(0, 180),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('reorder-save')));
    await tester.pumpAndSettle();

    expect(find.text('列表已变化，请重试'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('第一项')).dy,
      greaterThan(tester.getTopLeft(find.text('第三项')).dy),
    );

    await tester.tap(find.byKey(const Key('reorder-save')));
    await tester.pumpAndSettle();

    expect(result, isTrue);
    verify(() => controller.saveOrder(any(), any())).called(2);
  });
}

const _request = LibraryReorderRequest(
  kind: LibraryItemKind.folder,
  parentId: null,
  title: '调整文件夹顺序',
);

class _MockOrganizationController extends Mock
    implements LibraryOrganizationController {}

Future<void> _pumpView(
  WidgetTester tester,
  LibraryOrganizationController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: LibraryReorderView(request: _request, controller: controller),
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
            key: const Key('open-reorder-view'),
            onPressed: () async {
              final result = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => LibraryReorderView(
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
