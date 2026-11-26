import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../funcs.dart';
import '../services/app_log_file.dart';

/// 设置 › 杂项 › 运行日志：查看、复制、导出、打开目录、清空。
class AppLogFilesTile extends StatelessWidget {
  const AppLogFilesTile({super.key});

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.description_outlined),
    title: const Text('运行日志'),
    subtitle: const Text('出问题时把日志发给开发者，便于定位'),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _AppLogSheet(),
    ),
  );
}

class _AppLogSheet extends StatefulWidget {
  const _AppLogSheet();

  @override
  State<_AppLogSheet> createState() => _AppLogSheetState();
}

class _AppLogSheetState extends State<_AppLogSheet> {
  String _summary = '正在统计…';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final log = AppLogFile.instance;
    final files = await log.files();
    final bytes = await log.totalBytes();
    if (!mounted) return;
    setState(() {
      _summary = log.directory == null
          ? '日志未启用'
          : '${files.length} 个文件，共 ${(bytes / 1024).toStringAsFixed(0)} KB\n${log.directory!.path}';
    });
  }

  Future<void> _copyRecent() async {
    final text = await AppLogFile.instance.tail(lines: 400);
    await Clipboard.setData(ClipboardData(text: text));
    showSuccessSnackbar('已复制最近 400 行日志', null);
  }

  Future<void> _share() async {
    final files = await AppLogFile.instance.files();
    if (files.isEmpty) {
      showInfoSnackbar('还没有日志', null);
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        files: files.map((f) => XFile(f.path, mimeType: 'text/plain')).toList(),
        subject: 'Listen1 运行日志',
      ),
    );
  }

  Future<void> _openFolder() async {
    final dir = AppLogFile.instance.directory;
    if (dir == null) return;
    try {
      if (Platform.isWindows) {
        await Process.run('explorer', [dir.path], runInShell: true);
      } else if (Platform.isMacOS) {
        await Process.run('open', [dir.path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [dir.path]);
      } else {
        await _share();
      }
    } catch (e) {
      showErrorSnackbar('打开失败', e.toString());
    }
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空日志？'),
        content: const Text('删除全部运行日志和卡顿记录，无法恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('清空')),
        ],
      ),
    );
    if (ok != true) return;
    await AppLogFile.instance.clear();
    showSuccessSnackbar('日志已清空', null);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final desktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('运行日志', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            SelectableText(
              _summary,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '记录网络请求（不含 Cookie 与密钥）、错误和界面卡顿；单个文件满 2 MB 自动轮转，最多保留 5 个。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _copyRecent,
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('复制最近日志'),
                ),
                OutlinedButton.icon(
                  onPressed: _share,
                  icon: const Icon(Icons.ios_share),
                  label: const Text('导出日志文件'),
                ),
                if (desktop)
                  OutlinedButton.icon(
                    onPressed: _openFolder,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('打开日志目录'),
                  ),
                OutlinedButton.icon(
                  onPressed: _clear,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('清空'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
