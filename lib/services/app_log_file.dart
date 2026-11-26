import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 写到磁盘的应用日志：按大小轮转，保留最近几个文件。
///
/// 所有 Logger（见 app_logger.dart）、debugPrint、print、未捕获异常和网络请求
/// 都汇总到这里。日志目录：应用支持目录下的 `logs/`。
class AppLogFile {
  AppLogFile._();
  static final AppLogFile instance = AppLogFile._();

  static const latestName = 'app.log';
  static const hangLogName = 'ui_hang.log';
  static const maxFileBytes = 2 * 1024 * 1024;
  static const keepRotated = 4;
  static const _maxPending = 2000;

  Directory? _dir;
  IOSink? _sink;
  int _size = 0;
  bool _rotating = false;
  final Queue<String> _pending = Queue<String>();
  Future<void>? _init;

  Directory? get directory => _dir;
  File? get latestFile => _dir == null ? null : File(p.join(_dir!.path, latestName));

  Future<void> init() => _init ??= _open();

  Future<void> _open() async {
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory(p.join(base.path, 'logs'));
      await dir.create(recursive: true);
      _dir = dir;
      final file = File(p.join(dir.path, latestName));
      _size = await file.exists() ? await file.length() : 0;
      _sink = file.openWrite(mode: FileMode.append);
      while (_pending.isNotEmpty) {
        _writeRaw(_pending.removeFirst());
      }
    } catch (e) {
      // 日志本身失败不能影响启动。
      debugPrintSynchronously('打开日志文件失败: $e');
    }
  }

  /// 写一行（或多行）日志。在 init 完成前先缓存在内存里。
  void write(String level, String message) {
    final now = DateTime.now().toIso8601String();
    final text = message.replaceAll('\r\n', '\n');
    final line = '$now [$level] $text\n';
    if (_sink == null) {
      _pending.add(line);
      while (_pending.length > _maxPending) {
        _pending.removeFirst();
      }
      return;
    }
    _writeRaw(line);
  }

  void _writeRaw(String line) {
    final sink = _sink;
    if (sink == null) return;
    sink.write(line);
    _size += line.length * 3; // 按 UTF-8 最坏情况估算，避免每行统计字节数
    if (_size > maxFileBytes && !_rotating) unawaited(_rotate());
  }

  Future<void> _rotate() async {
    final dir = _dir;
    final sink = _sink;
    if (dir == null || sink == null) return;
    _rotating = true;
    _sink = null;
    try {
      await sink.flush();
      await sink.close();
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final latest = File(p.join(dir.path, latestName));
      if (await latest.exists()) {
        await latest.rename(p.join(dir.path, 'app-$stamp.log'));
      }
      final rotated = await dir
          .list()
          .where((e) => e is File && p.basename(e.path).startsWith('app-'))
          .cast<File>()
          .toList();
      rotated.sort((a, b) => b.path.compareTo(a.path));
      for (final old in rotated.skip(keepRotated)) {
        try {
          await old.delete();
        } catch (_) {}
      }
    } catch (e) {
      debugPrintSynchronously('轮转日志失败: $e');
    } finally {
      _size = 0;
      _sink = File(p.join(dir.path, latestName)).openWrite(mode: FileMode.append);
      _rotating = false;
      while (_pending.isNotEmpty) {
        _writeRaw(_pending.removeFirst());
      }
    }
  }

  Future<void> flush() async {
    try {
      await _sink?.flush();
    } catch (_) {}
  }

  /// 日志目录下的全部日志文件，最新的在前。
  Future<List<File>> files() async {
    final dir = _dir;
    if (dir == null || !await dir.exists()) return const [];
    await flush();
    final list = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.log'))
        .cast<File>()
        .toList();
    list.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return list;
  }

  Future<int> totalBytes() async {
    var total = 0;
    for (final f in await files()) {
      try {
        total += await f.length();
      } catch (_) {}
    }
    return total;
  }

  /// 最近 [lines] 行（只读当前文件尾部）。
  Future<String> tail({int lines = 300}) async {
    final file = latestFile;
    if (file == null || !await file.exists()) return '';
    await flush();
    final length = await file.length();
    const window = 256 * 1024;
    final raf = await file.open();
    try {
      final start = length > window ? length - window : 0;
      await raf.setPosition(start);
      final bytes = await raf.read(length - start);
      final text = utf8.decode(bytes, allowMalformed: true);
      final all = const LineSplitter().convert(text);
      final from = all.length > lines ? all.length - lines : 0;
      return all.sublist(from).join('\n');
    } finally {
      await raf.close();
    }
  }

  Future<void> clear() async {
    final dir = _dir;
    if (dir == null) return;
    final sink = _sink;
    _sink = null;
    try {
      await sink?.flush();
      await sink?.close();
    } catch (_) {}
    for (final f in await dir.list().where((e) => e is File).cast<File>().toList()) {
      try {
        await f.delete();
      } catch (_) {}
    }
    _size = 0;
    _sink = File(p.join(dir.path, latestName)).openWrite(mode: FileMode.append);
  }
}

/// UI 卡死检测：独立 isolate 每秒检查主线程心跳；主线程超过 [threshold]
/// 没有心跳时写入 ui_hang.log（主线程卡住时它自己什么都写不了），恢复后再记一条。
class UiHangWatchdog {
  UiHangWatchdog._();
  static bool _started = false;

  /// 只在桌面端启用：移动端切到后台时系统会暂停引擎，会被误报成卡死。
  static Future<void> start({Duration threshold = const Duration(seconds: 5)}) async {
    final desktop = defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
    if (_started || kIsWeb || !desktop) return;
    final dir = AppLogFile.instance.directory;
    if (dir == null) return;
    _started = true;
    try {
      final ready = ReceivePort();
      await Isolate.spawn<List<Object>>(
        _watch,
        [ready.sendPort, p.join(dir.path, AppLogFile.hangLogName), threshold.inMilliseconds],
        debugName: 'ui-hang-watchdog',
        errorsAreFatal: false,
      );
      final heartbeat = await ready.first as SendPort;
      Timer.periodic(const Duration(seconds: 1), (_) {
        heartbeat.send(DateTime.now().millisecondsSinceEpoch);
      });
      _watchFrames();
    } catch (e) {
      AppLogFile.instance.write('W', '启动卡死检测失败: $e');
    }
  }

  /// 单帧耗时超过 1 秒也记一条，便于定位「卡一下」。
  static void _watchFrames() {
    SchedulerBinding.instance.addTimingsCallback((timings) {
      for (final t in timings) {
        final total = t.totalSpan;
        if (total > const Duration(seconds: 1)) {
          AppLogFile.instance.write(
            'W',
            '慢帧 ${total.inMilliseconds} ms（构建 ${t.buildDuration.inMilliseconds} ms，'
                '绘制 ${t.rasterDuration.inMilliseconds} ms）',
          );
        }
      }
    });
  }

  static void _watch(List<Object> args) {
    final ready = args[0] as SendPort;
    final path = args[1] as String;
    final thresholdMs = args[2] as int;
    final port = ReceivePort();
    ready.send(port.sendPort);
    var last = DateTime.now().millisecondsSinceEpoch;
    var stalledSince = 0;
    void log(String message) {
      try {
        File(path).writeAsStringSync(
          '${DateTime.now().toIso8601String()} $message\n',
          mode: FileMode.append,
          flush: true,
        );
      } catch (_) {}
    }

    port.listen((dynamic _) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (stalledSince != 0) {
        log('界面线程恢复响应，阻塞约 ${((now - stalledSince) / 1000).toStringAsFixed(1)} 秒');
        stalledSince = 0;
      }
      last = now;
    });
    Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (stalledSince == 0 && now - last > thresholdMs) {
        stalledSince = last;
        log('界面线程已 ${((now - last) / 1000).round()} 秒无响应（最后心跳 '
            '${DateTime.fromMillisecondsSinceEpoch(last).toIso8601String()}）');
      }
    });
  }
}
