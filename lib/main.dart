// 文件: lib/main.dart
// 作用: 若可 Ruoke 程序入口(MVP 空壳阶段)。
//       只做"装配":加载 dotenv、套 ProviderScope(Riverpod 接管依赖)、
//       用 go_router 接管路由、显示一个 Hello 落地页。
//       业务一律不写在这里,放各 features 的 view_model。
// 详见: jihua/ruoke-技术方案总集-20260716.md 启动初始化顺序(C 文档 §6.3)

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

Future<void> main() async {
  // 1. Flutter 绑定初始化(async 之前必加)
  WidgetsFlutterBinding.ensureInitialized();

  // 2. 加载 .env(密钥)。容错:没 .env 也照常跑(空壳阶段没有真 Key)
  //    真实 .env 不进 git;这里只是把有的就读进来,没有就走默认。
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    // 开发期未配 .env 属正常,忽略;release 阶段密钥走 secure_storage(见技术方案 C)
    debugPrint('[ruoke] 未加载 .env(忽略): $e');
  }

  // 3.(V2 阶段在此打开数据库 / 首次种子数据,见 C 文档 §6.3;
  //    MVP 空壳暂不连数据库,只验骨架可跑通。)

  // 4. runApp + ProviderScope(Riverpod 接管所有依赖注入)
  runApp(const ProviderScope(child: RuokeApp()));
}

/// 应用根 Widget:用 MaterialApp.router 接管 go_router(见 A/C 文档路由)。
class RuokeApp extends StatelessWidget {
  const RuokeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const HelloPage(),
        ),
      ],
    );

    return MaterialApp.router(
      title: '若可 Ruoke',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F2937)),
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}

/// 空壳落地页:验证骨架能跑、依赖能解析、路由能进。
class HelloPage extends StatelessWidget {
  const HelloPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('若可 Ruoke')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '若可 Ruoke',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '骨架跑通 ✅ (Flutter + Riverpod + go_router)',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'dotenv: ${dotenv.isInitialized ? "已加载" : "未加载(忽略)"}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
