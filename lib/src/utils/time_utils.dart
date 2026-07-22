// 文件: lib/src/utils/time_utils.dart
// 作用: 时间戳与时间转换小工具。
//       所有表的 created_at / updated_at 一律存毫秒时间戳（INT），
//       供上云同步比对版本用（见 B 文档 §一 第 6 条）。
//       真机/仓里禁用 Date.now()/new DateTime.now() 的场合一律走这里，便于将来注入。
/// 当前时间戳（毫秒，自 epoch）。
int nowMs() => DateTime.now().millisecondsSinceEpoch;

/// 毫秒时间戳 → DateTime。
DateTime fromMs(int ms) =>
    DateTime.fromMillisecondsSinceEpoch(ms, isUtc: false);
