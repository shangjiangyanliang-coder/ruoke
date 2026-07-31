// 文件: lib/src/routing/settings_view.dart
// 作用: "我的" tab 设置页。当前第3批含：学科管理入口、占位条目（复习设置/AI隐私/备份）。
//       后续批逐次填充。点击条目跳对应子页。
import 'package:flutter/material.dart';

/// "我的" tab 设置页。
class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('复习设置'),
            subtitle: const Text('每日题数 · 间隔（待开发）'),
            trailing: const Icon(Icons.chevron_right),
            enabled: false,
            onTap: null,
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('AI 隐私'),
            subtitle: const Text('章/笔记级 AI不可见（待开发）'),
            trailing: const Icon(Icons.chevron_right),
            enabled: false,
            onTap: null,
          ),
          ListTile(
            leading: const Icon(Icons.cloud_upload_outlined),
            title: const Text('备份与恢复'),
            subtitle: const Text('本地备份 · 云端加密（待开发）'),
            trailing: const Icon(Icons.chevron_right),
            enabled: false,
            onTap: null,
          ),
        ],
      ),
    );
  }
}
