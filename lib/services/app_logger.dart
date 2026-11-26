import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

import 'app_log_file.dart';

enum AppLogLevel {
  trace(Level.trace, '全部'),
  debug(Level.debug, '调试'),
  info(Level.info, '信息'),
  warning(Level.warning, '警告'),
  error(Level.error, '错误'),
  fatal(Level.fatal, '严重错误'),
  off(Level.off, '关闭');

  const AppLogLevel(this.level, this.label);

  final Level level;
  final String label;

  static AppLogLevel get defaultLevel =>
      kDebugMode ? AppLogLevel.debug : AppLogLevel.warning;

  static AppLogLevel fromSetting(Object? value) =>
      values.where((level) => level.name == value).firstOrNull ?? defaultLevel;
}

/// Shared by every app logger, including instances created before settings load.
AppLogLevel appLogLevel = AppLogLevel.defaultLevel;

class _AppLogFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) =>
      appLogLevel != AppLogLevel.off && event.level >= appLogLevel.level;
}

/// 控制台照旧输出；同时把同一份内容写入 logs/app.log（发布版也写）。
class _AppLogOutput extends LogOutput {
  _AppLogOutput(this._console);
  final LogOutput _console;
  static final _ansi = RegExp(r'\x1B\[[0-9;]*m');

  @override
  void output(OutputEvent event) {
    _console.output(event);
    AppLogFile.instance.write(
      event.level.name.toUpperCase(),
      event.lines.map((l) => l.replaceAll(_ansi, '')).join('\n'),
    );
  }
}

/// Unlike DevelopmentFilter, this also emits selected levels in release builds.
Logger createAppLogger({LogOutput? output}) => Logger(
  filter: _AppLogFilter(),
  printer: PrettyPrinter(
    colors: kDebugMode,
    printEmojis: false,
    methodCount: 0,
    errorMethodCount: 8,
    dateTimeFormat: DateTimeFormat.dateAndTime,
  ),
  output: _AppLogOutput(output ?? ConsoleOutput()),
);
