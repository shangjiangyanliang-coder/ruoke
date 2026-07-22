// 文件: lib/src/data/errors/app_exception.dart
// 作用: 统一异常基类与子类。Repository 把底层(SQL/dio/校验)异常翻译成这些领域异常，
//       不让技术异常泄漏到 ViewModel。详见技术方案 A §6.1。
/// 应用统一异常基类。所有可向 UI 暴露的异常都继承它。
sealed class AppException implements Exception {
  /// 给用户看的一句话（通俗，无堆栈）。
  final String userMessage;

  /// 给开发者的技术原因（不显示给用户，可入日志）。
  final String? techDetail;

  const AppException(this.userMessage, {this.techDetail});

  @override
  String toString() =>
      techDetail == null ? userMessage : '$userMessage ($techDetail)';
}

/// 数据库相关异常（SQL 失败、迁移失败、约束冲突等）。
class DatabaseException extends AppException {
  const DatabaseException(super.userMessage, {super.techDetail});
}

/// 网络相关异常（调 AI/云端 OCR 联网失败）。
class NetworkException extends AppException {
  const NetworkException(super.userMessage, {super.techDetail});
}

/// AI 服务异常。reason 区分三种不可用状态（对应 AiAvailability）。
class AiServiceException extends AppException {
  /// notConfigured / offline / disabledByPrivacy / failed
  final String reason;

  const AiServiceException(super.userMessage, {required this.reason, super.techDetail});
}

/// OCR 引擎异常。
class OcrException extends AppException {
  const OcrException(super.userMessage, {super.techDetail});
}

/// 数据校验异常（如标题超长、UUID 为空等）。
class ValidationException extends AppException {
  const ValidationException(super.userMessage, {super.techDetail});
}
