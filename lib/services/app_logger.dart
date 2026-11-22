import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

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

/// Unlike DevelopmentFilter, this also emits selected levels in release builds.
Logger createAppLogger({LogOutput? output}) => Logger(
  filter: _AppLogFilter(),
  printer: PrettyPrinter(
    colors: kDebugMode,
    printEmojis: true,
    dateTimeFormat: DateTimeFormat.dateAndTime,
  ),
  output: output,
);
