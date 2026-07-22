// 文件: lib/src/data/errors/result.dart
// 作用: Result<T> 成功/失败包装。Repository 方法返回 Future<Result<T>>，
//       把底层异常翻译成 AppException 放进 Failure，不让异常抛到 ViewModel。
//       详见技术方案 A §6.2。
import 'app_exception.dart';

/// 通用结果包装：成功带数据，失败带领域异常。
sealed class Result<T> {
  const Result();
}

/// 成功，value 即数据。
final class Success<T> extends Result<T> {
  final T value;
  const Success(this.value);
}

/// 失败，exception 是翻译后的领域异常（AppException 子类）。
final class Failure<T> extends Result<T> {
  final AppException exception;
  const Failure(this.exception);
}

/// 便捷：把底层抛异常的动作包成 Result。失败时翻译为指定异常。
///
/// 例：
/// ```dart
/// return guard(() async => await noteDao.list(),
///   orElse: (e) => const Failure(DatabaseException('读取笔记失败')));
/// ```
Future<Result<T>> guard<T>(
  Future<T> Function() action, {
  required Failure<T> Function(Object error) orElse,
}) async {
  try {
    return Success(await action());
  } catch (e) {
    return orElse(e);
  }
}
