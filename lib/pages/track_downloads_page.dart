import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:listen1_xuan/controllers/routeController.dart';
import 'package:listen1_xuan/controllers/track_download_controller.dart';
import 'package:listen1_xuan/funcs.dart';
import 'package:listen1_xuan/widgets/responsive_layout.dart';

/// 「下载」页：进行中/失败的任务和已下载的歌曲。
class TrackDownloadsPage extends StatelessWidget {
  const TrackDownloadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<TrackDownloadController>();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('下载'),
        leading: BackButton(onPressed: routerPop),
        actions: [
          Obx(() => c.activeCount > 0
              ? TextButton(onPressed: c.cancelAll, child: const Text('全部取消'))
              : const SizedBox.shrink()),
          IconButton(
            tooltip: '打开下载文件夹',
            icon: const Icon(Icons.folder_open_rounded),
            onPressed: c.openFolder,
          ),
        ],
      ),
      body: Obx(() {
        final tasks = c.tasks.toList();
        final history = c.history.entries.toList()
          ..sort((a, b) => (b.value['at'] as int? ?? 0).compareTo(a.value['at'] as int? ?? 0));
        final hasFinished = tasks.any((t) => !t.isActive);
        return CustomScrollView(
          slivers: [
            for (final sliver in <Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '保存在 ${c.locationHint}',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Obx(() => SwitchListTile(
                    title: const Text('同时下载歌词'),
                    subtitle: const Text('保存为同名 .lrc，有翻译时合并成双语'),
                    value: c.includeLyricRx,
                    onChanged: (v) => c.includeLyric = v,
                  )),
            ),
            if (tasks.isNotEmpty) ...[
              _header(context, '任务', trailing: hasFinished
                  ? TextButton(onPressed: c.clearFinished, child: const Text('清除已结束'))
                  : null),
              SliverList.builder(
                itemCount: tasks.length,
                itemBuilder: (context, i) => _TaskTile(task: tasks[i]),
              ),
            ],
            _header(context, '已下载（${history.length}）'),
            if (history.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
                  child: Column(
                    children: [
                      Icon(Icons.download_for_offline_outlined, size: 48, color: theme.colorScheme.outline),
                      const SizedBox(height: 12),
                      Text('还没有下载过歌曲', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        '在歌曲菜单里选择「下载」，或在歌单页点「下载全部」',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverList.builder(
                itemCount: history.length,
                itemBuilder: (context, i) {
                  final e = history[i];
                  final v = e.value;
                  final audio = v['audio'] as String?;
                  return ListTile(
                    title: Text(v['title'] as String? ?? v['file'] as String? ?? e.key,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      [v['artist'], if (v['lyric'] != null) '含歌词'].whereType<String>().join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: audio == null ? null : () => c.reveal(audio),
                    trailing: IconButton(
                      tooltip: '从列表中移除（不删除文件）',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => c.forget(e.key),
                    ),
                  );
                },
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ]) SliverContentMaxWidth(maxWidth: 760, sliver: sliver),
          ],
        );
      }),
    );
  }

  Widget _header(BuildContext context, String text, {Widget? trailing}) {
    final theme = Theme.of(context);
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(text, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task});
  final TrackDownloadTask task;

  @override
  Widget build(BuildContext context) {
    final c = Get.find<TrackDownloadController>();
    final theme = Theme.of(context);
    return Obx(() {
      final state = task.state.value;
      final err = task.error.value;
      final (String label, Color? color) = switch (state) {
        TrackDownloadState.queued => ('等待中', null),
        TrackDownloadState.resolving => ('获取地址…', null),
        TrackDownloadState.downloading => (
            task.total.value > 0
                ? '${_bytes(task.received.value)} / ${_bytes(task.total.value)}'
                : '下载中…',
            null
          ),
        TrackDownloadState.saving => ('保存中…', null),
        TrackDownloadState.done => ('已完成', theme.colorScheme.primary),
        TrackDownloadState.failed => (err ?? '下载失败', theme.colorScheme.error),
        TrackDownloadState.canceled => ('已取消', theme.colorScheme.outline),
      };
      final active = task.isActive;
      return ListTile(
        title: Text(task.track.title ?? task.track.id, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              [task.track.artist, label].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: color == null ? null : TextStyle(color: color),
            ),
            if (active) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  value: state == TrackDownloadState.downloading ? task.progress : null,
                ),
              ),
            ],
          ],
        ),
        onTap: state == TrackDownloadState.done && task.audioLocation != null
            ? () => c.reveal(task.audioLocation!)
            : null,
        // 与「已下载」行一致：右侧统一是 48px 的按钮位。
        trailing: active
            ? IconButton(tooltip: '取消', icon: const Icon(Icons.close_rounded), onPressed: () => c.cancel(task))
            : state == TrackDownloadState.failed || state == TrackDownloadState.canceled
                ? IconButton(tooltip: '重试', icon: const Icon(Icons.refresh_rounded), onPressed: () => c.retry(task))
                : SizedBox.square(
                    dimension: 48,
                    child: Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary),
                  ),
      );
    });
  }

  static String _bytes(int b) {
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

/// 歌曲菜单里的「下载」行：显示下载中/已下载状态。
class TrackDownloadMenuTile extends StatelessWidget {
  const TrackDownloadMenuTile({super.key, required this.trackFor});

  /// 延迟取曲目，便于菜单在曲目变化时复用。
  final dynamic Function() trackFor;

  @override
  Widget build(BuildContext context) {
    final c = Get.find<TrackDownloadController>();
    final track = trackFor();
    return Obx(() {
      final task = c.taskOf(track.id);
      final done = c.isDownloaded(track.id);
      // 与菜单里其他行保持同样的左对齐：不放 leading 图标，状态写在标题里。
      return ListTile(
        title: Text(task != null ? '下载中…' : done ? '重新下载' : '下载'),
        subtitle: Text(done && task == null ? '已保存到 ${c.locationHint}' : c.includeLyricRx ? '歌曲和歌词' : '仅歌曲'),
        onTap: task != null
            ? () => Get.toNamed(RouteName.trackDownloadsPage, id: 1)
            : () async {
                Navigator.of(context).pop();
                final n = await c.enqueue([track]);
                if (n > 0) {
                  showInfoSnackbar('已加入下载', track.title, onTap: () => Get.toNamed(RouteName.trackDownloadsPage, id: 1));
                }
              },
      );
    });
  }
}

/// 歌曲行标题后的小标记：下载中显示进度圈，已下载显示勾。
class TrackDownloadBadge extends StatelessWidget {
  const TrackDownloadBadge({super.key, required this.trackId});
  final String trackId;

  @override
  Widget build(BuildContext context) {
    final c = Get.find<TrackDownloadController>();
    final color = Theme.of(context).colorScheme.primary;
    return Obx(() {
      final task = c.taskOf(trackId);
      if (task != null) {
        return Padding(
          padding: const EdgeInsets.only(left: 6),
          child: SizedBox.square(
            dimension: 12,
            child: CircularProgressIndicator(strokeWidth: 1.5, value: task.progress, color: color),
          ),
        );
      }
      if (!c.isDownloaded(trackId)) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Tooltip(
          message: '已下载',
          child: Icon(Icons.download_done_rounded, size: 14, color: color),
        ),
      );
    });
  }
}
