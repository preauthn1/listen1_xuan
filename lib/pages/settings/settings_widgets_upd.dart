part of '../../settings.dart';

UpdController updController = Get.find<UpdController>();
Widget updSettingsTile(BuildContext context) {
  return Wrap(
    alignment: WrapAlignment.start,
    children: [
      ...[
        ElevatedButton(
          onPressed: updController.downloadArtifact,
          child: const Text('下载最新开发版'),
        ),
        ElevatedButton(
          onPressed: () {
            g_launchURL(
              Uri.parse('https://github.com/HBWuChang/listen1_xuan/releases'),
            );
          },
          child: const Text('打开 GitHub 发布页'),
        ),
        if (!kDebugMode && (isAndroid || isWindows || isMacOS))
          ElevatedButton(
            onPressed: updController.switchFfmpegVariant,
            child: Text(isFfmpegEnabled ? '切换到不含 FFmpeg 版' : '切换到含 FFmpeg 版'),
          ),
        ElevatedButton(
          onPressed: () => openInnerPage(RouteName.settingsChangelogPage),
          child: const Text('查看更新日志'),
        ),
        if (isAndroid)
          ElevatedButton(
            onPressed: updController.delAndroidApkCache,
            child: const Text('清除安装包缓存'),
          ),
        if (isMacOS)
          ElevatedButton(
            onPressed: () async {
              try {
                Directory tempPath = await xuanGetdownloadDirectory();
                final filelist = tempPath
                    .listSync()
                    .where(
                      (element) =>
                          element is File &&
                          (p.basename(element.path) == 'canary.zip' ||
                              p.basename(element.path) ==
                                  'update_macos.command'),
                    )
                    .toList();

                // 同时清理canary文件夹
                final canaryDir = Directory(p.join(tempPath.path, 'canary'));
                if (await canaryDir.exists()) {
                  filelist.add(canaryDir);
                }

                if (filelist.isEmpty) {
                  showWarningSnackbar('没有找到安装包缓存', null);
                  return;
                }

                for (var file in filelist) {
                  try {
                    if (file is Directory) {
                      await file.delete(recursive: true);
                    } else {
                      await file.delete();
                    }
                  } catch (e) {
                    debugPrint('删除文件失败: $e');
                  }
                }
                showSuccessSnackbar('清理成功', null);
              } catch (e) {
                showErrorSnackbar('清理失败', e.toString());
              }
            },
            child: const Text('清除安装包缓存'),
          ),
        Obx(
          () => SwitchListTile(
            title: const Text('接收预发布版本'),
            subtitle: const Text('提前体验新功能，可能不够稳定'),
            value: Get.find<SettingsController>().getPreRelease,
            onChanged: (value) {
              Get.find<SettingsController>().getPreRelease = value;
            },
          ),
        ),
      ].map((e) => e is Obx
          ? SizedBox(width: double.infinity, child: e)
          : Padding(padding: const EdgeInsets.fromLTRB(16, 8, 0, 8), child: e)),
    ],
  );
}
