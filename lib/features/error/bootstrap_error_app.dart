import 'package:flutter/material.dart';

import '../../config/config_exception.dart';
import '../../core/theme/app_theme.dart';

/// 启动失败页。
///
/// 规格第 12 节：配置校验失败时不要白屏，要显示到底哪里错了。
class BootstrapErrorApp extends StatelessWidget {
  const BootstrapErrorApp({
    required this.title,
    required this.details,
    super.key,
  });

  final String title;
  final String details;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            const Text(
              '应用暂时无法启动，请检查配置后重新打开。',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            SelectableText(
              details,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 把 [ConfigException] 展开成可读文本，逐条列出问题。
String describeConfigException(ConfigException exception) {
  final buffer = StringBuffer(exception.message);
  for (final issue in exception.issues) {
    buffer.write('\n\n• $issue');
  }
  return buffer.toString();
}
