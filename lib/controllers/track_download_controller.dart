import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:listen1_xuan/constants/network_defaults.dart';
import 'package:listen1_xuan/controllers/DioController.dart';
import 'package:listen1_xuan/controllers/cache_controller.dart';
import 'package:listen1_xuan/controllers/play_controller.dart';
import 'package:listen1_xuan/controllers/settings_controller.dart';
import 'package:listen1_xuan/funcs.dart';
import 'package:listen1_xuan/global_settings_animations.dart';
import 'package:listen1_xuan/models/Track.dart';
import 'package:listen1_xuan/models/bootStrapTrackRes.dart';
import 'package:listen1_xuan/provider/base.dart';
import 'package:listen1_xuan/provider/loweb.dart';
import 'package:listen1_xuan/services/app_logger.dart';
import 'package:listen1_xuan/services/track_download_naming.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

enum TrackDownloadState { queued, resolving, downloading, saving, done, failed, canceled }

class TrackDownloadTask {
  TrackDownloadTask(this.track);

  final Track track;
  final state = TrackDownloadState.queued.obs;
  final received = 0.obs;
  final total = 0.obs;
  final error = RxnString();

  /// 保存位置：Android 10+ 是 content:// URI，其他平台是文件路径。
  String? audioLocation;
  String? lyricLocation;
  CancelToken? cancelToken;

  double? get progress {
    final t = total.value;
    return t > 0 ? (received.value / t).clamp(0.0, 1.0) : null;
  }

  bool get isActive => const {
        TrackDownloadState.queued,
        TrackDownloadState.resolving,
        TrackDownloadState.downloading,
        TrackDownloadState.saving,
      }.contains(state.value);
}

/// 「下载到本地」：把歌曲（和歌词）保存为用户能在文件管理器、其他播放器里
/// 直接使用的文件。与播放缓存分开——缓存在应用专属目录、文件名带 id，
/// 随时可能被清理；下载文件放在公共的 Download/Listen1/Music（Android）
/// 或系统「下载」文件夹（桌面），以「歌手 - 歌名」命名。
class TrackDownloadController extends GetxController {
  static const _channel = MethodChannel('listen1_xuan/track_downloads');
  static const _concurrency = 2;
  static const _historyKey = 'track_download_history';
  static const _includeLyricKey = 'track_download_include_lyric';
  static const _maxHistory = 300;

  final _logger = createAppLogger();
  final tasks = <TrackDownloadTask>[].obs;

  /// 已完成的下载（trackId -> 记录），用于「已下载」标记和下载页的历史。
  final history = <String, Map<String, dynamic>>{}.obs;
  int _running = 0;
  int _batchTotal = 0;
  int _batchDone = 0;
  int _batchFailed = 0;

  SettingsController get _settings => Get.find<SettingsController>();

  bool get includeLyric => _settings.settings[_includeLyricKey] as bool? ?? true;
  set includeLyric(bool v) => _settings.settings[_includeLyricKey] = v;

  /// 在 Obx 中读取：settings 是 RxMap，读取即建立依赖。
  bool get includeLyricRx => includeLyric;

  int get activeCount => tasks.where((t) => t.isActive).length;

  String get locationHint {
    if (isAndroid) return 'Download/Listen1/Music';
    if (isIos) return '「文件」App › 我的 iPhone › Listen1 › Music';
    return '下载/Listen1/Music';
  }

  @override
  void onInit() {
    super.onInit();
    try {
      final raw = _settings.settings[_historyKey];
      if (raw is String && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final e in decoded.entries) {
            if (e.value is Map) history[e.key as String] = Map<String, dynamic>.from(e.value as Map);
          }
        }
      }
    } catch (e) {
      _logger.w('读取下载记录失败', error: e);
    }
    debounce(history, (_) => _saveHistory(), time: const Duration(seconds: 1));
  }

  void _saveHistory() {
    var entries = history.entries.toList();
    if (entries.length > _maxHistory) {
      entries.sort((a, b) => (a.value['at'] as int? ?? 0).compareTo(b.value['at'] as int? ?? 0));
      entries = entries.sublist(entries.length - _maxHistory);
    }
    _settings.settings[_historyKey] = jsonEncode(Map.fromEntries(entries));
  }

  bool isDownloaded(String trackId) => history.containsKey(trackId);

  TrackDownloadTask? taskOf(String trackId) =>
      tasks.firstWhereOrNull((t) => t.track.id == trackId && t.isActive);

  /// 加入下载队列。已在队列中的歌曲会跳过；返回实际加入的数量。
  Future<int> enqueue(Iterable<Track> tracks) async {
    if (isAndroid && !await _ensureLegacyPermission()) {
      showErrorSnackbar('无法下载', '需要存储权限才能把歌曲保存到「下载」文件夹');
      return 0;
    }
    if (isAndroid) unawaited(Permission.notification.request());
    var added = 0;
    for (final track in tracks) {
      if (track.id.isEmpty || taskOf(track.id) != null) continue;
      tasks.removeWhere((t) => t.track.id == track.id && !t.isActive);
      tasks.add(TrackDownloadTask(track));
      added++;
    }
    if (added > 0) {
      if (_running == 0) {
        _batchTotal = 0;
        _batchDone = 0;
        _batchFailed = 0;
      }
      _batchTotal += added;
      _pump();
    }
    return added;
  }

  void cancel(TrackDownloadTask task) {
    if (!task.isActive) return;
    task.cancelToken?.cancel('用户取消');
    if (task.state.value == TrackDownloadState.queued) {
      task.state.value = TrackDownloadState.canceled;
      _batchTotal = (_batchTotal - 1).clamp(0, 1 << 30);
    }
  }

  void cancelAll() {
    for (final t in tasks.toList()) {
      cancel(t);
    }
  }

  void retry(TrackDownloadTask task) {
    if (task.isActive) return;
    tasks.remove(task);
    enqueue([task.track]);
  }

  void clearFinished() => tasks.removeWhere((t) => !t.isActive);

  void forget(String trackId) => history.remove(trackId);

  void _pump() {
    while (_running < _concurrency) {
      final next = tasks.firstWhereOrNull((t) => t.state.value == TrackDownloadState.queued);
      if (next == null) break;
      _running++;
      unawaited(_run(next).whenComplete(() {
        _running--;
        _pump();
        if (_running == 0) _notifyFinish();
      }));
    }
  }

  Future<void> _run(TrackDownloadTask task) async {
    final track = task.track;
    File? tmp;
    try {
      task.state.value = TrackDownloadState.resolving;
      task.cancelToken = CancelToken();
      final res = await _resolve(track);
      if (task.cancelToken!.isCancelled) throw const _Canceled();

      final ext = TrackDownloadNaming.audioExtension(res.url);
      final base = TrackDownloadNaming.baseName(track);
      tmp = File(p.join((await getTemporaryDirectory()).path,
          'dl_${DateTime.now().microsecondsSinceEpoch}$ext'));

      // 已缓存的歌曲直接复制，省流量；在线地址或替换后的歌曲才重新下载。
      final cached = await _cachedFile(track.id);
      if (cached != null && p.extension(cached.path).toLowerCase() == ext) {
        task.state.value = TrackDownloadState.downloading;
        await cached.copy(tmp.path);
      } else {
        task.state.value = TrackDownloadState.downloading;
        final isBilibili = res.platform == provider.bilibili.name;
        await dioWithCookieManager.download(
          res.url,
          tmp.path,
          cancelToken: task.cancelToken,
          options: isBilibili ? Options(headers: kBilibiliPlayHeader) : null,
          onReceiveProgress: (r, t) {
            task.received.value = r;
            task.total.value = t;
          },
        );
      }
      if (!await tmp.exists() || await tmp.length() == 0) {
        throw const FormatException('下载的文件为空');
      }

      task.state.value = TrackDownloadState.saving;
      task.audioLocation = await _publish(tmp, '$base$ext');

      if (includeLyric) {
        try {
          final lrc = await _lyricFor(track);
          if (lrc != null && lrc.trim().isNotEmpty) {
            final lrcFile = File('${tmp.path}.lrc');
            await lrcFile.writeAsString(lrc);
            try {
              task.lyricLocation = await _publish(lrcFile, '$base.lrc');
            } finally {
              if (await lrcFile.exists()) await lrcFile.delete();
            }
          }
        } catch (e) {
          // 歌词失败不影响歌曲本身。
          _logger.w('歌词下载失败: ${track.id}', error: e);
        }
      }

      history[track.id] = {
        'title': track.title,
        'artist': track.artist,
        'file': '$base$ext',
        'audio': task.audioLocation,
        if (task.lyricLocation != null) 'lyric': task.lyricLocation,
        'at': DateTime.now().millisecondsSinceEpoch,
      };
      task.state.value = TrackDownloadState.done;
      _batchDone++;
    } catch (e) {
      final canceled = e is _Canceled || (e is DioException && CancelToken.isCancel(e));
      task.state.value = canceled ? TrackDownloadState.canceled : TrackDownloadState.failed;
      if (!canceled) {
        _batchFailed++;
        task.error.value = _describe(e);
        _logger.w('下载失败: ${track.id}', error: e);
      } else {
        _batchTotal = (_batchTotal - 1).clamp(0, 1 << 30);
      }
    } finally {
      if (tmp != null && await tmp.exists()) {
        try {
          await tmp.delete();
        } catch (_) {}
      }
      _notifyProgress(task);
    }
  }

  String _describe(Object e) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      if (code == 403 || code == 401) return '没有权限下载（可能需要登录或会员）';
      if (code != null) return '服务器返回 $code';
      return '网络错误，请检查网络后重试';
    }
    if (e is PlatformException) return e.message ?? '保存失败';
    if (e is FormatException) return e.message;
    final s = e.toString();
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }

  /// 走与播放相同的解析流程（包括「歌曲替换」），拿到音频地址。
  Future<BootSuccessRes> _resolve(Track track) async {
    final playController = Get.find<PlayController>();
    final rep = playController.songReplaceSettings.value.getReplacedTrack(track.id);
    final target = rep ?? track;
    BaseProvider? source;
    try {
      source = provider.tryGetProviderByName(provider.getProviderNameByItemId(target.id));
    } catch (_) {}
    source ??= provider.tryGetProviderByName(target.source ?? '');
    if (source == null) throw const FormatException('不支持下载此来源的歌曲');

    final completer = Completer<BootSuccessRes>();
    await source.bootStrapTrack(
      target,
      (res, _) {
        if (!completer.isCompleted) completer.complete(res);
      },
      (_, error) {
        if (!completer.isCompleted) {
          completer.completeError(error ?? const FormatException('无法获取播放地址'));
        }
      },
    );
    final res = await completer.future.timeout(const Duration(seconds: 30));
    if (res.url.isEmpty) throw const FormatException('无法获取播放地址（可能需要会员）');
    return res;
  }

  Future<File?> _cachedFile(String trackId) async {
    try {
      final cache = Get.find<CacheController>();
      if (cache.isOnlineCache(trackId)) return null;
      final path = await cache.getLocalCache(trackId);
      if (path.isEmpty || path.startsWith('http')) return null;
      final f = File(path);
      return await f.exists() ? f : null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _lyricFor(Track track) async {
    final playController = Get.find<PlayController>();
    final rep = playController.songReplaceSettings.value.getReplacedTrack(track.id);
    final target = rep ?? track;
    BaseProvider? source;
    try {
      source = provider.getProviderByItemId(target.id);
    } catch (_) {
      return null;
    }
    if (source.supportLyric) {
      final res = await source.lyric(target);
      if (res != null && res.$1.trim().isNotEmpty) {
        return TrackDownloadNaming.mergeTranslation(res.$1, res.$2);
      }
    }
    // 平台没有歌词接口（如 B 站）时，用已经生成/缓存过的歌词：
    // 弹幕或字幕转成的歌词存在 lyricBox，普通歌词缓存是同目录的 .lrc。
    return _cachedLyric(track.id) ?? _cachedLyric(target.id) ?? await _cachedLyricFile(target.id);
  }

  String? _cachedLyric(String id) {
    final lyric = _settings.getLyricBoxString('${id}_lyric');
    if (lyric == null || lyric.trim().isEmpty) return null;
    return TrackDownloadNaming.mergeTranslation(lyric, _settings.getLyricBoxString('${id}_tlyric'));
  }

  Future<String?> _cachedLyricFile(String id) async {
    try {
      final dir = await xuanGetdataDirectory();
      final f = File(p.join(dir.path, '${id}_lyric.lrc'));
      if (!await f.exists()) return null;
      final t = File(p.join(dir.path, '${id}_tlyric.lrc'));
      return TrackDownloadNaming.mergeTranslation(
        await f.readAsString(),
        await t.exists() ? await t.readAsString() : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// 把临时文件放到最终位置，返回保存位置。
  Future<String> _publish(File file, String name) async {
    final mime = TrackDownloadNaming.mimeForExtension(p.extension(name));
    if (isAndroid) {
      final location = await _channel.invokeMethod<String>('save', {
        'path': file.path,
        'name': name,
        'mime': mime,
        'subdir': 'Listen1/Music',
      });
      if (location == null) throw const FormatException('保存失败');
      return location;
    }
    final dir = await musicDirectory();
    final out = File(p.join(dir.path, name));
    if (await out.exists()) await out.delete();
    await file.copy(out.path);
    return out.path;
  }

  /// 桌面和 iOS 的下载目录。iOS 放在 Documents 下，「文件」App 里可见。
  Future<Directory> musicDirectory() async {
    Directory? base;
    if (isIos) {
      base = await getApplicationDocumentsDirectory();
    } else {
      base = await getDownloadsDirectory();
    }
    base ??= await getApplicationDocumentsDirectory();
    final dir = Directory(isIos
        ? p.join(base.path, 'Listen1', 'Music')
        : p.join(base.path, 'Listen1', 'Music'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<bool> _ensureLegacyPermission() async {
    try {
      final legacy = await _channel.invokeMethod<bool>('needsLegacyPermission') ?? false;
      if (!legacy) return true;
      return await Permission.storage.request().isGranted;
    } catch (_) {
      return true;
    }
  }

  /// 打开下载好的文件（Android 用系统播放器打开；桌面在文件夹中定位）。
  Future<void> reveal(String location) async {
    try {
      if (isAndroid) {
        final ok = await _channel.invokeMethod<bool>('open', {
          'location': location,
          'mime': location.endsWith('.lrc') ? 'text/plain' : 'audio/*',
        });
        if (ok != true) showInfoSnackbar('文件在 $locationHint', null);
        return;
      }
      if (isWindows) {
        await Process.run('explorer', ['/select,', location], runInShell: true);
      } else if (isMacOS) {
        await Process.run('open', ['-R', location]);
      } else {
        showInfoSnackbar('文件在 $locationHint', null);
      }
    } catch (e) {
      showErrorSnackbar('打开失败', e.toString());
    }
  }

  Future<void> openFolder() async {
    if (isWindows || isMacOS) {
      final dir = await musicDirectory();
      await Process.run(isWindows ? 'explorer' : 'open', [dir.path],
          runInShell: isWindows);
    } else {
      showInfoSnackbar('下载的歌曲在 $locationHint', null);
    }
  }

  void _notifyProgress(TrackDownloadTask last) {
    if (!isAndroid) return;
    final finished = _batchDone + _batchFailed;
    if (finished >= _batchTotal) return;
    unawaited(_channel.invokeMethod('progress', {
      'done': finished,
      'total': _batchTotal,
      'title': last.track.title ?? '',
    }).catchError((_) {}));
  }

  void _notifyFinish() {
    if (_batchTotal == 0) return;
    if (isAndroid) {
      unawaited(_channel.invokeMethod('finish', {
        'done': _batchDone,
        'failed': _batchFailed,
      }).catchError((_) {}));
    }
    if (_batchFailed > 0) {
      showWarningSnackbar('下载结束', '完成 $_batchDone 首，失败 $_batchFailed 首，可在「下载」页重试');
    } else if (_batchDone > 0) {
      showSuccessSnackbar(
        _batchDone == 1 ? '已下载' : '已下载 $_batchDone 首',
        '保存在 $locationHint',
      );
    }
    if (kDebugMode) debugPrint('download batch done=$_batchDone failed=$_batchFailed');
  }
}

class _Canceled implements Exception {
  const _Canceled();
}
