import 'pages/settings/totp_settings.dart';
import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:listen1_xuan/play.dart';
import 'package:animations/animations.dart';
import 'package:universal_io/io.dart' as universal_io;
import 'package:fluttertoast/fluttertoast.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:hotkey_manager/hotkey_manager.dart';
import 'constants/const.dart';
import 'controllers/settings_controller.dart';
import 'funcs.dart';
import 'settings.dart';
import 'package:window_manager/window_manager.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;
import 'package:expressive_loading_indicator/expressive_loading_indicator.dart';
import 'package:material_new_shapes/material_new_shapes.dart';

/// 无界面引擎（例如被系统媒体按键或车机绑定 MediaBrowserService 冷启动）
/// 下没有 FlutterView，也无法弹系统权限对话框
bool get isHeadlessEngine => ui.PlatformDispatcher.instance.views.isEmpty;

/// 存储权限已确认可用时跳过一次状态查询，避免每次取目录都走一趟平台通道
bool _storagePermissionConfirmed = false;

/// 本次运行是否已经弹过权限请求，避免连续取目录时反复弹窗
bool _storagePermissionRequested = false;

/// 确认存储权限。
/// 已授权时只查状态：permission_handler 的 checkPermissionStatus 走
/// application context，不需要 Activity，因此后台无界面冷启动也能正常取目录；
/// 只有确实未授权且存在界面时才弹窗请求（requestPermissions 必须有 Activity，
/// 否则会抛 PlatformException: Unable to detect current Android Activity）。
Future<bool> xuanEnsureStoragePermission() async {
  if (!isAndroid) return true;
  try {
    if (!_storagePermissionConfirmed &&
        (await Permission.manageExternalStorage.isGranted ||
            await Permission.storage.isGranted)) {
      _storagePermissionConfirmed = true;
    }
  } on PlatformException catch (e) {
    debugPrint('存储权限状态查询失败: $e');
  }
  if (_storagePermissionConfirmed) return true;
  if (isHeadlessEngine) {
    // 无界面时无法弹权限对话框，留待下次前台启动处理
    debugPrint('无界面引擎，跳过存储权限请求');
    return false;
  }
  if (_storagePermissionRequested) return false;
  _storagePermissionRequested = true;
  try {
    final granted =
        await Permission.manageExternalStorage.request().isGranted ||
        await Permission.storage.request().isGranted;
    _storagePermissionConfirmed = granted;
    return granted;
  } on PlatformException catch (e) {
    debugPrint('存储权限请求失败: $e');
    return false;
  }
}

Future<Directory> xuanGetdataDirectory() async {
  // 缓存与配置默认写在应用专属目录，不需要存储权限。
  // 只有用户把缓存目录改到公共路径时，才按原逻辑确认权限。
  final configuredPath = Get.isRegistered<SettingsController>()
      ? Get.find<SettingsController>().cacheDirectoryPath
      : '';
  if (isAndroid && configuredPath.isNotEmpty) {
    if (!await xuanEnsureStoragePermission()) {
      // 无界面引擎里没有可展示的提示，也不应阻塞播放流程
      if (!isHeadlessEngine) {
        showInfoSnackbar(
          '请务必授予存储权限以下载歌曲及读取配置文件等操作',
          '本应用不会访问您的个人数据',
        );
      }
      throw Exception('Storage permission not granted');
    }
  }

  if (configuredPath.isEmpty) {
    return await xuanGetdownloadDirectory();
  }

  final cacheDirectory = Directory(configuredPath);
  if (!await cacheDirectory.exists()) {
    await cacheDirectory.create(recursive: true);
  }
  return cacheDirectory;
}

Future<Directory> xuanGetDefaultCacheDirectory() async {
  return await xuanGetdownloadDirectory();
}

/// 旧版本固定使用的公共目录；已有缓存和安装包都在这里。
const String _legacyAndroidDownloadRoot = '/storage/emulated/0/Download';
Directory? _androidBaseDirectoryCache;

/// Android 的默认根目录。
/// - 老用户：公共目录下已有 Listen1 文件夹且权限已授予，继续沿用，
///   避免缓存歌曲、歌词和安装包“消失”。只查询状态，不弹权限框。
/// - 新用户：使用应用专属外部目录（getExternalFilesDir），无需任何存储权限，
///   卸载时由系统清理。
Future<Directory?> _androidBaseDirectory() async {
  if (_androidBaseDirectoryCache != null) return _androidBaseDirectoryCache;
  Directory? result;
  try {
    final legacy = Directory(p.join(_legacyAndroidDownloadRoot, downDirName));
    final granted = await Permission.manageExternalStorage.isGranted ||
        await Permission.storage.isGranted;
    if (granted && await legacy.exists()) {
      result = Directory(_legacyAndroidDownloadRoot);
    }
  } catch (e) {
    debugPrint('检查旧缓存目录失败: $e');
  }
  result ??= await getExternalStorageDirectory();
  _androidBaseDirectoryCache = result;
  return result;
}

/// 旧版公共目录（/Download/Listen1）是否在用。
Future<bool> xuanIsUsingLegacyAndroidDirectory() async {
  if (!isAndroid) return false;
  final base = await _androidBaseDirectory();
  return base?.path == _legacyAndroidDownloadRoot;
}

/// 找回旧版缓存：存储权限被系统自动收回后，应用会改用专属目录，旧缓存看起来
/// 像「丢了」。这里重新申请权限，旧目录存在时切回旧目录。返回说明文字。
Future<String> xuanAdoptLegacyAndroidDirectory() async {
  if (!isAndroid) return '仅 Android 需要';
  _storagePermissionRequested = false;
  if (!await xuanEnsureStoragePermission()) {
    return '未获得存储权限，仍使用应用专属目录';
  }
  final legacy = Directory(p.join(_legacyAndroidDownloadRoot, downDirName));
  if (!await legacy.exists()) {
    return '没有找到旧版缓存目录（${legacy.path}）';
  }
  _androidBaseDirectoryCache = null;
  final base = await _androidBaseDirectory();
  return base?.path == _legacyAndroidDownloadRoot
      ? '已切回旧版缓存目录，重启应用后生效'
      : '切换失败，仍使用应用专属目录';
}

///若传入 path，则返回 dataDirectory/path 的字符串路径，否则返回 Directory 对象
Future<dynamic> xuanGetdownloadDirectory({String? path}) async {
  Directory? tempDir;
  if (isWindows) {
    tempDir = await getDownloadsDirectory();
  } else if (isMacOS) {
    tempDir = await getDownloadsDirectory();
  } else if (isAndroid) {
    tempDir = await _androidBaseDirectory();
  } else if (isIos) {
    // tempDir = await getdirectory
  }
  tempDir ??= await getApplicationDocumentsDirectory();
  // 检查是否存在 Listen1 文件夹
  var listen1Dir = isIos
      ? tempDir
      : Directory(p.join(tempDir.path, downDirName));
  if (!await listen1Dir.exists()) {
    // 如果不存在，则创建
    await listen1Dir.create(recursive: true);
  }
  // 更新 tempDir 为 Listen1 文件夹
  tempDir = listen1Dir;

  if (path != null) {
    // 检查是否存在指定的文件夹
    var customDir = p.join(tempDir.path, path);
    return customDir;
  }
  return tempDir;
}

final bool isWindows = universal_io.Platform.isWindows;
final bool isIos = universal_io.Platform.isIOS;
final bool isMacOS = universal_io.Platform.isMacOS;
final bool isAndroid = universal_io.Platform.isAndroid;
final bool isDesktop =
    universal_io.Platform.isWindows ||
    universal_io.Platform.isMacOS ||
    universal_io.Platform.isLinux;
final bool isMobile =
    universal_io.Platform.isIOS || universal_io.Platform.isAndroid;
void init_hotkeys() async {
  var settings = lengcyGetSettings();
  var hotskeys = settings["hotkeys"];
  if (hotskeys == null) {
    hotskeys = {
      "enable": false,
      "play_pause": null,
      "next": null,
      "previous": null,
      "show": null,
    };
    settings["hotkeys"] = hotskeys;
    Get.find<SettingsController>().setSettings(settings);
  }
  enable_hotkey = hotskeys["enable"];
  hotkeyEnabledNotifier.value = enable_hotkey == true;
  if (hotskeys['copy_totp'] != null) {
    set_hotkey(null, HotKey.fromJson(hotskeys['copy_totp']), 'copy_totp');
  }
  if (hotskeys["play_pause"] != null) {
    set_hotkey(null, HotKey.fromJson(hotskeys["play_pause"]), "play_pause");
  }
  if (hotskeys["next"] != null) {
    set_hotkey(null, HotKey.fromJson(hotskeys["next"]), "next");
  }
  if (hotskeys["previous"] != null) {
    set_hotkey(null, HotKey.fromJson(hotskeys["previous"]), "previous");
  }
  if (hotskeys["show"] != null) {
    set_hotkey(null, HotKey.fromJson(hotskeys["show"]), "show");
  }
}

Map<String, HotKey> inapp_hotkeys = {
  "space": HotKey(key: PhysicalKeyboardKey.space, scope: HotKeyScope.inapp),
  "arrowLeft": HotKey(key: PhysicalKeyboardKey.keyA, scope: HotKeyScope.inapp),
  "arrowRight": HotKey(key: PhysicalKeyboardKey.keyD, scope: HotKeyScope.inapp),
  "arrowUp": HotKey(key: PhysicalKeyboardKey.keyW, scope: HotKeyScope.inapp),
  "arrowDown": HotKey(key: PhysicalKeyboardKey.keyS, scope: HotKeyScope.inapp),
  "next": HotKey(key: PhysicalKeyboardKey.keyE, scope: HotKeyScope.inapp),
  "previous": HotKey(key: PhysicalKeyboardKey.keyQ, scope: HotKeyScope.inapp),
};
Map<LogicalKeyboardKey, dynamic> inappShortcuts = {
  LogicalKeyboardKey.space: globalPlayOrPause,
  LogicalKeyboardKey.keyA: globalSeekToPrevious,
  LogicalKeyboardKey.keyD: globalSeekToNext,
  LogicalKeyboardKey.keyW: globalVolumeUp,
  LogicalKeyboardKey.keyS: globalVolumeDown,
  LogicalKeyboardKey.keyE: globalSkipToNext,
  LogicalKeyboardKey.keyQ: globalSkipToPrevious,
  LogicalKeyboardKey.arrowLeft: globalSeekToPrevious,
  LogicalKeyboardKey.arrowRight: globalSeekToNext,
  LogicalKeyboardKey.arrowUp: globalVolumeUp,
  LogicalKeyboardKey.arrowDown: globalVolumeDown,
  // ","
  LogicalKeyboardKey.comma: globalSkipToPrevious,
  // "."
  LogicalKeyboardKey.period: globalSkipToNext,
};
bool enable_inapp_hotkey = true;
void setInAppHotKeyEnable(enable) {
  enable_inapp_hotkey = enable;
}

Future<void> set_hotkey(s_hotkey, hotkey, name) async {
  if (s_hotkey != null) {
    await hotKeyManager.unregister(s_hotkey);
  }
  if (hotkey != null) {
    switch (name) {
      case 'copy_totp':
        await hotKeyManager.register(hotkey, keyDownHandler: (_) async {
          if (enable_hotkey) await copyTotpCode();
        });
        break;
      case "play_pause":
        await hotKeyManager.register(
          hotkey,
          keyDownHandler: (hotKey) async {
            // 处理播放/暂停的逻辑
            if (enable_hotkey) globalPlayOrPause();
          },
        );
        break;
      case "next":
        await hotKeyManager.register(
          hotkey,
          keyDownHandler: (hotKey) async {
            // 处理下一首的逻辑
            if (enable_hotkey) globalSkipToNext();
          },
        );
        break;
      case "previous":
        await hotKeyManager.register(
          hotkey,
          keyDownHandler: (hotKey) async {
            // 处理上一首的逻辑
            if (enable_hotkey) globalSkipToPrevious();
          },
        );
        break;
      case "show":
        await hotKeyManager.register(
          hotkey,
          keyDownHandler: (hotKey) async {
            // 处理显示的逻辑
            if (enable_hotkey) {
              windowManager.show();
              windowManager.setSkipTaskbar(false);
              windowManager.setAlwaysOnTop(true);
              windowManager.setAlwaysOnTop(false);
            }
          },
        );
        break;
    }
  }
}

var enable_hotkey_setstate;
var enable_hotkey;
/// 热键总开关的可监听副本，用于在关闭时禁用各快捷键按钮。
final ValueNotifier<bool> hotkeyEnabledNotifier = ValueNotifier<bool>(false);

List<Widget> create_hotkey_btns(context) {
  if (!(isWindows || isMacOS)) return [];
  var s_hotkeys = [
    {"name": "播放/暂停", "hotkey": "play_pause"},
    {"name": "下一首", "hotkey": "next"},
    {"name": "上一首", "hotkey": "previous"},
    {"name": "显示窗口", "hotkey": "show"},
    {"name": "复制一次性验证码", "hotkey": "copy_totp"},
  ];
  return <Widget>[
    StatefulBuilder(
      builder: (BuildContext context, StateSetter setState) {
        enable_hotkey_setstate = setState;
        return SwitchListTile(
          title: const Text('启用快捷键'),
          value: enable_hotkey,
          onChanged: (bool value) async {
            enable_hotkey = value;
            hotkeyEnabledNotifier.value = value == true;
            var settings = lengcyGetSettings();
            var hotkeys = settings['hotkeys'];
            hotkeys['enable'] = value;
            settings['hotkeys'] = hotkeys;
            Get.find<SettingsController>().setSettings(settings);
            try {
              setState(() {
                enable_hotkey = value;
              });
            } catch (e) {}
          },
        );
      },
    ),
    ...s_hotkeys.map((_hotkey) {
      return ValueListenableBuilder<bool>(
        valueListenable: hotkeyEnabledNotifier,
        builder: (context, enabled, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: OutlinedButton(
        onPressed: !enabled ? null : () async {
          var settings = lengcyGetSettings();
          var hotkeys = settings['hotkeys'];
          var hotkeyData = hotkeys[_hotkey['hotkey']];
          var hotkey = hotkeyData == null ? null : HotKey.fromJson(hotkeyData);
          var s_hotkey = hotkey;
          showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: Text('设置${_hotkey['name']}快捷键'),
                content: HotKeyRecorder(
                  initalHotKey: hotkey,
                  onHotKeyRecorded: (hotKey) {
                    print(hotKey.toJson());
                    hotkey = hotKey;
                  },
                ),
                actions: <Widget>[
                  TextButton(
                    child: const Text('确定'),
                    onPressed: () async {
                      if (hotkey == null) {
                        // _msg('请设置热键', 1.0);
                        showWarningSnackbar('请先按下要设置的快捷键', null);
                        return;
                      }
                      hotkeys[_hotkey['hotkey']] = hotkey!.toJson();
                      settings['hotkeys'] = hotkeys;
                      Get.find<SettingsController>().setSettings(settings);
                      await set_hotkey(s_hotkey, hotkey, _hotkey['hotkey']);
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              );
            },
          );
        },
        child: Text('设置“${_hotkey['name']}”快捷键'),
      ),
      ),
      );
    }).toList(),
  ];
}

Widget get globalLoadingAnime => ExpressiveLoadingIndicator(
  // Custom size constraints
  constraints: BoxConstraints(
    minWidth: 64.0,
    minHeight: 64.0,
    maxWidth: 64.0,
    maxHeight: 64.0,
  ),

  // Custom polygon shapes
  polygons: [
    MaterialShapes.softBurst,
    MaterialShapes.pentagon,
    MaterialShapes.pill,
    MaterialShapes.pentagon,
    MaterialShapes.square,
  ],

  // Accessibility
  semanticsLabel: 'Loading',
  semanticsValue: 'In progress',
);

Widget get globalLoadingAnimeOfExtendedImage =>
    Center(child: globalLoadingAnime);
Widget? loadStateChanged(ExtendedImageState state) {
  if (state.extendedImageLoadState == LoadState.loading) {
    return globalLoadingAnimeOfExtendedImage;
  }

  return null;
}

Widget search_Animation({
  required Animation<double> animation,
  required Animation<double> secondaryAnimation,
  required Widget child,
  Axis axis = Axis.vertical,
}) {
  const curve = Curves.easeInOut;

  var curvedAnimation = CurvedAnimation(parent: animation, curve: curve);

  var alignmentTween = Tween<Alignment>(
    // begin: Alignment.topCenter, // 从顶部开始
    begin: axis == Axis.vertical ? Alignment.topCenter : Alignment.topRight,
    end: Alignment.center, // 到达中心
  ).animate(curvedAnimation);

  // return AlignTransition(
  //   alignment: alignmentTween, // 使用动态的 Alignment 动画
  //   child: SizeTransition(
  //     sizeFactor: curvedAnimation, // 控制高度从 0 到 1 的变化
  //     axis: axis, // 垂直方向展开
  //     child: FadeTransition(
  //       opacity: curvedAnimation, // 添加淡入淡出效果
  //       child: child,
  //     ),
  //   ),
  // );
  return SharedAxisTransition(
    animation: animation,
    secondaryAnimation: secondaryAnimation,
    transitionType: SharedAxisTransitionType.vertical,
    child: child,
  );
}
