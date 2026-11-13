/// 配置加载或校验失败时抛出的统一异常。
///
/// 规格第 12 节要求「配置校验失败：启动报错页」，因此这里把**所有**问题一次性收集
/// 到 [issues] 里，而不是遇到第一个错误就返回，方便一次修完。
class ConfigException implements Exception {
  const ConfigException(this.message, {this.issues = const <String>[]});

  /// 人类可读的错误摘要。
  final String message;

  /// 逐条问题描述，可能为空。
  final List<String> issues;

  @override
  String toString() {
    if (issues.isEmpty) {
      return 'ConfigException: $message';
    }
    final buffer = StringBuffer('ConfigException: $message');
    for (final issue in issues) {
      buffer.write('\n  - $issue');
    }
    return buffer.toString();
  }
}
