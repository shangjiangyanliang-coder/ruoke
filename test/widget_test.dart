// 文件: test/widget_test.dart
// 作用: 若可 Ruoke 空壳阶段的冒烟测试,验证 RuokeApp 能挂载、Hello 页能渲染。
//       随功能增多再各 features 补测试(见开发规范7.9)。

import 'package:flutter_test/flutter_test.dart';

import 'package:ruoke/main.dart';

void main() {
  testWidgets('RuokeApp 能挂载并显示 Hello 页', (WidgetTester tester) async {
    await tester.pumpWidget(const RuokeApp());

    // 顶栏标题
    expect(find.text('若可 Ruoke'), findsWidgets);

    // Hello 落地页主标
    expect(find.text('若可 Ruoke'), findsWidgets);

    // 骨架跑通提示字样(至少一处出现)
    expect(find.textContaining('骨架跑通'), findsOneWidget);
  });
}
