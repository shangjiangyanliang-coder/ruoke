// 文件: lib/src/utils/id_generator.dart
// 作用: 全表主键用 UUID（字符串）的统一生成入口。
//       无账号纯本地阶段，UUID 天然唯一、跨设备不冲突，将来上多用户加列不破坏结构。
//       详见技术方案 B §一 设计总原则第 5 条。
import 'package:uuid/uuid.dart';

/// 全局唯一 UUID 生成器单例。
const _uuid = Uuid();

/// 生成一个新的 UUID v4 字符串，作为表主键。
String newId() => _uuid.v4();
