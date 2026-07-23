// 文件: lib/src/routing/placeholder_page.dart
// 作用: 未开发标签的占位页。后续阶段分别替换为真实页面。
import 'package:flutter/material.dart';

/// 占位页：只显示标题与"待开发"提示。
class PlaceholderPage extends StatelessWidget {
  final String title;
  final String hint;
  const PlaceholderPage({super.key, required this.title, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text(
          hint,
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
