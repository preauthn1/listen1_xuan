import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hyper_thread_downloader/hyper_thread_downloader.dart';
import 'package:listen1_xuan/widgets/ext/ext_widget.dart';

import 'settings_controller.dart';

/// 下载进度信息
class DownloadProgressInfo {
  final double progress;
  final double speed;
  final double remainTime;
  final int currentCount;
  final int totalCount;

  DownloadProgressInfo({
    required this.progress,
    required this.speed,
    required this.remainTime,
    required this.currentCount,
    required this.totalCount,
  });
}

class HyperDownloadController extends GetxController {
  final isDownloading = false.obs;
  final downloadProgress = 0.0.obs;
  final downloadSpeed = 0.0.obs;
  final remainTime = 0.0.obs;
  final currentCount = 0.obs;
  final totalCount = 0.obs;
  int _currentTaskId = -1;
  bool _dialogShown = false;
  late HyperDownload _hyperDownload;

  @override
  void onInit() {
    super.onInit();
    _hyperDownload = HyperDownload();
  }

  /// 开始下载文件
  /// [url] 下载链接
  /// [savePath] 保存路径
  /// [context] BuildContext，仅在 [showDialog] 为 true 时需要
  /// [threadCount] 线程数
  /// [showDialog] 是否显示下载进度对话框，默认为 true
  /// [onComplete] 下载完成回调
  /// [onFailed] 下载失败回调
  /// [onProgress] 下载进度回调，返回进度信息
  Future<void> downloadFile({
    required String url,
    required String savePath,
    BuildContext? context,
    int threadCount = 8,
    bool showDialog = true,
    Future<void> Function()? onComplete,
    Function(String)? onFailed,
    Function(DownloadProgressInfo)? onProgress,
  }) async {
    // onFailed 只报告一次：下载失败、完成处理失败、异常只会走其中一条。
    var failureReported = false;
    void reportFailure(String reason) {
      isDownloading.value = false;
      _closeDownloadDialog();
      if (failureReported) return;
      failureReported = true;
      onFailed?.call(reason);
    }

    try {
      // 重置下载状态
      _resetDownloadState();
      if (File(savePath).existsSync()) {
        await File(savePath).delete();
      }
      isDownloading.value = true;

      // 如果需要显示对话框，则显示下载进度对话框
      if (showDialog && context != null) {
        _showDownloadDialog();
      }

      // 默认直连，不把签名地址交给第三方。用户主动开启镜像后先走镜像、失败再
      // 直连；镜像下载的文件同样要过调用方 onComplete 里的 SHA-256 校验。
      final mirrorUrl = useDownloadMirror ? mirroredUrl(url) : null;
      String? failure;
      if (mirrorUrl != null) {
        failure = await _runDownload(
          url: mirrorUrl,
          savePath: savePath,
          threadCount: threadCount,
          onProgress: onProgress,
        );
        if (!isDownloading.value) return; // 用户已取消
        if (failure != null) {
          debugPrint('Mirror download failed, retrying direct: $failure');
          _resetDownloadState();
          try {
            if (File(savePath).existsSync()) await File(savePath).delete();
          } catch (_) {}
        }
      }
      if (mirrorUrl == null || failure != null) {
        failure = await _runDownload(
          url: url,
          savePath: savePath,
          threadCount: threadCount,
          onProgress: onProgress,
        );
      }
      if (!isDownloading.value) return; // 用户已取消
      if (failure != null) {
        reportFailure('下载失败: $failure');
        return;
      }

      // 字节已下载完：先关掉带「取消」按钮的进度框，再做校验、解压、安装，
      // 否则进度框会在 100% 时一直挡着（安卓上直到系统安装器返回）。
      _closeDownloadDialog();
      try {
        await onComplete?.call();
      } catch (error) {
        reportFailure('下载完成处理失败: $error');
        return;
      }
      isDownloading.value = false;
    } catch (e) {
      debugPrint('Download error: $e');
      reportFailure(e.toString());
    }
  }

  static const String _mirrorPrefix = 'https://h3.040905.xyz/default/https/';

  /// 设置里的「使用下载镜像」，默认关闭。
  static bool get useDownloadMirror =>
      Get.isRegistered<SettingsController>() &&
      Get.find<SettingsController>().useDownloadMirror;

  /// 镜像地址；只处理 https 地址，其它情况返回 null（直连）。
  static String? mirroredUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return '$_mirrorPrefix${url.substring('https://'.length)}';
  }

  Completer<String?>? _activeAttempt;

  /// 运行一次下载；成功返回 null，失败返回原因。取消时返回「已取消」。
  Future<String?> _runDownload({
    required String url,
    required String savePath,
    required int threadCount,
    Function(DownloadProgressInfo)? onProgress,
  }) async {
    final completer = Completer<String?>();
    _activeAttempt = completer;
    try {
      _hyperDownload.startDownload(
        url: url,
        savePath: savePath,
        threadCount: threadCount,
        downloadProgress:
            ({
              required double progress,
              required double speed,
              required double remainTime,
              required int count,
              required int total,
            }) {
              downloadProgress.value = progress;
              downloadSpeed.value = speed;
              this.remainTime.value = remainTime;
              currentCount.value = count;
              totalCount.value = total;
              // 调用进度回调
              onProgress?.call(
                DownloadProgressInfo(
                  progress: progress,
                  speed: speed,
                  remainTime: remainTime,
                  currentCount: count,
                  totalCount: total,
                ),
              );
            },
        downloadComplete: () {
          debugPrint('Download completed');
          if (!completer.isCompleted) completer.complete(null);
        },
        downloadFailed: (String reason) {
          debugPrint('Download failed: $reason');
          if (!completer.isCompleted) completer.complete(reason);
        },
        downloadTaskId: (int id) {
          debugPrint('Download task id: $id');
          _currentTaskId = id;
        },
        prepareWorking: (bool ret) {
          debugPrint('Prepare working: $ret');
        },
        downloadingLog: (String log) {
          debugPrint('Downloading log: $log');
        },
        workingMerge: (bool ret) {
          debugPrint('Working merge: $ret');
        },
      );
    } catch (e) {
      debugPrint('Download error: $e');
      if (!completer.isCompleted) completer.complete(e.toString());
    }
    try {
      return await completer.future;
    } finally {
      if (identical(_activeAttempt, completer)) _activeAttempt = null;
    }
  }

  /// 显示不可关闭的下载进度对话框
  void _showDownloadDialog() {
    _dialogShown = true;
    Get.dialog(
      barrierDismissible: false,
      AlertDialog(
        title: const Text('文件下载中'),
        content: Obx(
          () => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: downloadProgress.value),
                16.sbh,
                Text(
                  '进度: ${(downloadProgress.value * 100).toStringAsFixed(2)}%',
                ),
                8.sbh,
                Text('速度: ${_formatSpeed(downloadSpeed.value)}'),
                8.sbh,
                Text('剩余时间: ${_formatTime(remainTime.value)}'),
                8.sbh,
                Text('已下载: ${currentCount.value} / ${totalCount.value}'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await cancelDownload();
            },
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  /// 关闭下载对话框
  void _closeDownloadDialog() {
    // 只关自己弹出的进度框，不误关其它对话框。
    if (!_dialogShown) return;
    _dialogShown = false;
    try {
      if (Get.isDialogOpen ?? false) {
        Get.back();
      }
    } catch (e) {
      debugPrint('Close download dialog error: $e');
    }
  }

  /// 格式化速度显示
  String _formatSpeed(double speed) {
    if (speed < 1024) {
      return '${speed.toStringAsFixed(2)} B/s';
    } else if (speed < 1024 * 1024) {
      return '${(speed / 1024).toStringAsFixed(2)} KB/s';
    } else {
      return '${(speed / 1024 / 1024).toStringAsFixed(2)} MB/s';
    }
  }

  /// 格式化时间显示
  String _formatTime(double seconds) {
    if (seconds < 0) {
      return '计算中...';
    }
    final int hours = seconds.toInt() ~/ 3600;
    final int minutes = (seconds.toInt() % 3600) ~/ 60;
    final int secs = seconds.toInt() % 60;

    if (hours > 0) {
      return '$hours小时$minutes分$secs秒';
    } else if (minutes > 0) {
      return '$minutes分$secs秒';
    } else {
      return '${secs}秒';
    }
  }

  /// 取消下载任务
  Future<void> cancelDownload() async {
    if (_currentTaskId != -1) {
      debugPrint('Cancelling download task: $_currentTaskId');
      try {
        // 取消下载任务
        _hyperDownload.stopDownload(id: _currentTaskId);
      } catch (e) {
        debugPrint('Stop download error: $e');
      }
    }
    isDownloading.value = false;
    _closeDownloadDialog();
    _currentTaskId = -1;
    final attempt = _activeAttempt;
    if (attempt != null && !attempt.isCompleted) attempt.complete('已取消');
  }

  /// 重置下载状态
  void _resetDownloadState() {
    downloadProgress.value = 0.0;
    downloadSpeed.value = 0.0;
    remainTime.value = 0.0;
    currentCount.value = 0;
    totalCount.value = 0;
    _currentTaskId = -1;
  }

  @override
  void onClose() {
    isDownloading.value = false;
    super.onClose();
  }
}
