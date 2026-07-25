// 文件: lib/main.dart
// 作用: 若可 Ruoke 程序入口。只做"装配"：加载 dotenv、
//       首启 seed 示例科目树、套 ProviderScope(Riverpod 接管依赖)、
//       MaterialApp.router 接 go_router、注册本地化委托(含 flutter_quill)、设定主题。
//       业务一律不写在这里，放各 features 的 view_model。
// 详见: jihua/ruoke-技术方案总集-20260716.md 启动初始化顺序(C 文档 §6.3)
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/data/database/app_database.dart';
import 'src/data/database/seed/subject_seed.dart';
import 'src/routing/app_router.dart';

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

  // 3. 首启 seed 示例科目树（表空才插，幂等）。
  //    用一个临时 AppDatabase 实例跑 seed 完关掉；ProviderScope 内会用 appDatabaseProvider
  //    新建另一个实例共享同一个 .sqlite 文件，Drift 支持多实例同库。
  //    （V2 阶段此处统一进启动初始化服务，见 C 文档 §6.3。）
  try {
    final seedDb = AppDatabase();
    await SubjectSeed(seedDb.subjectDao).runIfEmpty();
    await seedDb.close();
  } catch (e) {
    debugPrint('[ruoke] 科目 seed 失败(忽略,不打断启动): $e');
  }

  // 4. runApp + ProviderScope(Riverpod 接管所有依赖注入)
  runApp(const ProviderScope(child: RuokeApp()));
}

/// 应用根 Widget:用 MaterialApp.router 接管 go_router(见 A/C 文档路由)。
class RuokeApp extends StatelessWidget {
  const RuokeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '若可 Ruoke',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F2937)),
        useMaterial3: true,
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh'), Locale('en', 'US')],
      routerConfig: appRouter,
    );
  }
}
