import 'pages/settings/totp_settings.dart';
import 'package:listen1_xuan/widgets/page_scroll_to_top.dart';
import 'widgets/loudness_gain_input.dart';
import 'pages/feedback/feedback_route_args.dart';
import 'widgets/feedback_unread_badge.dart';
import 'controllers/feedback_push_controller.dart';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:animations/animations.dart';
import 'package:flutter/foundation.dart';
import 'package:listen1_xuan/widgets/ext/ext_widget.dart';
import 'package:wolt_modal_sheet/wolt_modal_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:listen1_xuan/controllers/controllers.dart';
import 'package:listen1_xuan/play.dart';
import 'services/app_logger.dart';
import 'widgets/app_log_level_tile.dart';
import 'controllers/search_controller.dart';
import 'controllers/upd_controller.dart';
import 'provider/base.dart';
import 'provider/loweb.dart' as music_providers;
import 'models/GitHubRelease.dart';
import 'models/SupabasePlaylist.dart' as PlaylistModel;
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import 'controllers/DioController.dart';
import 'controllers/cache_controller.dart';
import 'controllers/myPlaylist_controller.dart';
import 'controllers/play_controller.dart';
import 'controllers/settings_controller.dart';
import 'services/startup_tips_service.dart';
import 'services/ffmpeg_config.dart';
import 'services/app_version.dart';
import 'controllers/routeController.dart';
import 'controllers/supabase_auth_controller.dart';
import 'controllers/websocket_client_controller.dart';
import 'pages/settings/play_buttons_settings_page.dart';
import 'pages/settings/settings_password_dialog.dart';
import 'pages/settings/select_audio_quality_of_bl_dialog.dart';
import 'examples/websocket_client_example.dart';
import 'examples/websocket_server_example.dart';
import 'funcs.dart';
import 'models/websocket_message.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';
import 'dart:async';
import 'package:system_info3/system_info3.dart';
import 'global_settings_animations.dart';
import 'package:webview_windows/webview_windows.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:charset_converter/charset_converter.dart';
import 'package:get/get.dart' hide Response;
import 'package:adaptive_theme/adaptive_theme.dart';
import 'controllers/theme.dart';
import 'package:iconify_flutter_plus/iconify_flutter_plus.dart';
import 'package:iconify_flutter_plus/icons/octicon.dart';
import 'package:iconify_flutter_plus/icons/mdi.dart';
import 'package:iconify_flutter_plus/icons/fa_solid.dart';
import 'package:path/path.dart' as p;
import 'utils/curve_utils.dart';
import 'utils/platform_credentials.dart';
import 'widgets/curve_selector_dialog.dart';
import 'package:flutter/material.dart' hide SearchController;
import 'widgets/elevated_button_icon.dart';
part 'pages/settings/settings_utils.dart';
part 'pages/settings/settings_github.dart';
part 'pages/settings/settings_widgets.dart';
part 'pages/settings/settings_widgets_upd.dart';
part 'pages/settings/settings_widgets_settings.dart';
part 'pages/settings/supabase_playlist_utils.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

final logger = createAppLogger();

late String apkfile_name;
Future<void> init_apkfilepath() async {
  if (!isAndroid) return;
  // 确保路径存在
  switch (SysInfo.kernelArchitecture.name) {
    case "ARM64":
      apkfile_name = await xuanGetdownloadDirectory(
        path: 'app-arm64-v8a-release.apk',
      );
    case "ARM":
      apkfile_name = await xuanGetdownloadDirectory(
        path: 'app-armeabi-v7a-release.apk',
      );
    case "X86_64":
      apkfile_name = await xuanGetdownloadDirectory(
        path: 'app-x86_64-release.apk',
      );
    default:
      apkfile_name = await xuanGetdownloadDirectory(path: 'app-release.apk');
  }
}

class _SettingsPageState extends State<SettingsPage> {
  final FocusNode _focusNode2 = FocusNode();
  final FocusNode _focusNode3 = FocusNode();
  late final TextEditingController _windowsProxyAddrController;
  String _appVersion = '读取版本中';

  Future<void> _loadAppVersion() async {
    try {
      final version = await loadAppVersion();
      if (mounted) setState(() => _appVersion = version);
    } catch (error, stackTrace) {
      logger.w('读取应用版本失败', error: error, stackTrace: stackTrace);
      if (mounted) setState(() => _appVersion = '版本未知');
    }
  }

  @override
  void dispose() {
    _focusNode2.dispose(); // 释放 FocusNode
    _focusNode3.dispose(); // 释放 FocusNode
    _windowsProxyAddrController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    _windowsProxyAddrController = TextEditingController(
      text: Get.find<SettingsController>().windowsProxyAddr,
    );
    // 监听焦点变化
    _focusNode2.addListener(() {
      if (_focusNode2.hasFocus) {
        setInAppHotKeyEnable(false);
      } else {
        setInAppHotKeyEnable(true);
      }
    });
    _focusNode3.addListener(() {
      if (_focusNode3.hasFocus) {
        setInAppHotKeyEnable(false);
      } else {
        setInAppHotKeyEnable(true);
      }
    });
  }

  SettingsController settingsController = Get.find<SettingsController>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageScrollToTop(
        builder: (context, pageScrollController, pageListController) => CustomScrollView(
          controller: pageScrollController,
          slivers: [
            if (!isWindows)
              SliverAppBar(
                floating: true,
                pinned: true,
                toolbarHeight: 56,
                expandedHeight: 56,
                leading: BackButton(onPressed: routerPop),
                title: const Text('设置'),
                centerTitle: false,
                actions: [
                  WebSocketHelper.buildReactiveButton(tooltip: "WebSocket 服务器"),
                  WebSocketClientHelper.buildReactiveButton(
                    tooltip: "WebSocket 客户端",
                  ),
                ],
              ),
            SliverToBoxAdapter(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  Obx(
                    () => ExpansionPanelList(
                      elevation: 0,
                      materialGapSize: 12,
                      dividerColor: Theme.of(context).colorScheme.outlineVariant,
                      expandedHeaderPadding: EdgeInsets.zero,
                      expansionCallback: (int index, bool isExpanded) {
                        if (isExpanded) {
                          settingsController.settingsPageExpansion.add(index);
                        } else {
                          settingsController.settingsPageExpansion.remove(
                            index,
                          );
                        }
                      },
                      children: [
                        // Supabase 登录面板
                        ExpansionPanel(
                          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
                          headerBuilder:
                              (BuildContext context, bool isExpanded) {
                                return ListTile(
                                  leading: Icon(Icons.person),
                                  title: const Text('Supabase 账号'),
                                  trailing: IconButton(
                                    onPressed: () async {
                                      Get.find<SupabaseAuthController>()
                                          .refreshUserProfile();
                                    },
                                    icon: Icon(Icons.refresh),
                                  ),
                                );
                              },
                          canTapOnHeader: true,
                          isExpanded: settingsController.settingsPageExpansion
                              .contains(0),
                          body: _buildSupabasePanel(),
                        ),
                        ExpansionPanel(
                          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
                          headerBuilder:
                              (BuildContext context, bool isExpanded) {
                                return ListTile(
                                  leading: Icon(Icons.login),
                                  title: const Text('第三方平台登录'),
                                  trailing: IconButton(
                                    onPressed: () async {
                                      settingsController.refreshLoginData();
                                    },
                                    icon: Icon(Icons.refresh),
                                  ),
                                );
                              },
                          canTapOnHeader: true,
                          isExpanded: settingsController.settingsPageExpansion
                              .contains(1),
                          body: _buildThirdPartyLoginPanel(context),
                        ),
                        ExpansionPanel(
                          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
                          headerBuilder:
                              (BuildContext context, bool isExpanded) {
                                return ListTile(
                                  leading: Icon(Icons.save),
                                  title: const Text('歌单/配置文件'),
                                );
                              },
                          canTapOnHeader: true,
                          isExpanded: settingsController.settingsPageExpansion
                              .contains(2),
                          body: settingsWidget(context),
                        ),
                        ExpansionPanel(
                          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
                          headerBuilder:
                              (BuildContext context, bool isExpanded) {
                                final theme = Theme.of(context);
                                final resolvedIconColor =
                                    ListTileTheme.of(context).iconColor ??
                                    theme.listTileTheme.iconColor ??
                                    theme.colorScheme.onSurfaceVariant;
                                final resolvedIconSize =
                                    IconTheme.of(context).size ?? 24.0;
                                return ListTile(
                                  leading: Iconify(
                                    Octicon.cache_16,
                                    color: resolvedIconColor,
                                    size: resolvedIconSize,
                                  ),
                                  title: Text('缓存'),
                                );
                              },
                          canTapOnHeader: true,
                          isExpanded: settingsController.settingsPageExpansion
                              .contains(3),
                          body: Wrap(
                            alignment: WrapAlignment.start,
                            spacing: 12,
                            runSpacing: 8,
                            children: [...cacheSettingsTiles],
                          ),
                        ),
                        ExpansionPanel(
                          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
                          headerBuilder:
                              (BuildContext context, bool isExpanded) {
                                return ListTile(
                                  leading: Icon(
                                    isDesktop
                                        ? Icons.keyboard_alt
                                        : isAndroid
                                        ? Icons.notifications
                                        : Icons.device_unknown,
                                  ),
                                  title: Text(
                                    isDesktop
                                        ? '桌面端：热键、代理与窗口'
                                        : isAndroid
                                        ? "安卓通知设置"
                                        : "未知平台设置",
                                  ),
                                );
                              },
                          canTapOnHeader: true,
                          isExpanded: settingsController.settingsPageExpansion
                              .contains(4),
                          body: isDesktop
                              ? desktopSettingsTiles(
                                  context,
                                  _focusNode2,
                                  _focusNode3,
                                  _windowsProxyAddrController,
                                )
                              : isAndroid
                              ? androidSettingsTiles
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: notificationSettingsTiles,
                                ),
                        ),
                        ExpansionPanel(
                          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
                          headerBuilder: (BuildContext context, bool isExpanded) {
                            return ListTile(
                              leading: const Icon(Icons.system_update),
                              title: const Text('更新版本'),
                              subtitle: Text(
                                '$_appVersion · ${isFfmpegEnabled ? '含 FFmpeg' : '不含 FFmpeg'} · ${UpdController.buildGitHash}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () {
                                if (settingsController.settingsPageExpansion
                                    .contains(5)) {
                                  settingsController.settingsPageExpansion
                                      .remove(5);
                                } else {
                                  settingsController.settingsPageExpansion.add(
                                    5,
                                  );
                                }
                              },
                              onLongPress: () {
                                showInfoSnackbar(
                                  '@DustDot',
                                  'https://github.com/HBWuChang/listen1_xuan/pull/43',
                                  onTap: () {
                                    g_launchURL(
                                      Uri.parse(
                                        'https://github.com/HBWuChang/listen1_xuan/pull/43',
                                      ),
                                    );
                                  },
                                );
                              },
                            );
                          },
                          canTapOnHeader: true,
                          isExpanded: settingsController.settingsPageExpansion
                              .contains(5),
                          body: updSettingsTile(context),
                        ),
                        ExpansionPanel(
                          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
                          headerBuilder:
                              (BuildContext context, bool isExpanded) {
                                final theme = Theme.of(context);
                                final resolvedIconColor =
                                    ListTileTheme.of(context).iconColor ??
                                    theme.listTileTheme.iconColor ??
                                    theme.colorScheme.onSurfaceVariant;

                                return ListTile(
                                  leading: Iconify(
                                    FaSolid.tshirt,
                                    color: resolvedIconColor,
                                    size: 18,
                                  ),
                                  title: Text('外观设置'),
                                );
                              },
                          canTapOnHeader: true,
                          isExpanded: settingsController.settingsPageExpansion
                              .contains(6),
                          body: themeSettingsTiles,
                        ),
                        ExpansionPanel(
                          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
                          headerBuilder:
                              (BuildContext context, bool isExpanded) {
                                return ListTile(
                                  leading: Icon(Icons.play_circle_fill_rounded),
                                  title: Text('播放设置'),
                                );
                              },
                          canTapOnHeader: true,
                          isExpanded: settingsController.settingsPageExpansion
                              .contains(7),
                          body: Column(
                            children: [
                              ListTile(
                                leading: Icon(Icons.equalizer),
                                title: const Text('均衡器设置'),
                                trailing: Icon(Icons.chevron_right),
                                onTap: () =>
                                    Get.toNamed(RouteName.equalizerPage, id: 1),
                              ),
                              ListTile(
                                leading: Icon(Icons.audiotrack),
                                title: const Text('默认音频质量'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => DefaultQualitySettingsSheet.show(),
                              ),
                              Obx(
                                () => SwitchListTile(
                                  title: const Text('响度均衡'),
                                  subtitle: const Text(
                                    '会降低整体音量；哔哩哔哩按响度均衡，其他平台使用固定音量补偿',
                                  ),
                                  value:
                                      settingsController.loudnessNormalization,
                                  onChanged: (value) async {
                                    settingsController.loudnessNormalization =
                                        value;
                                    await Get.find<PlayController>()
                                        .applyPlaybackVolume();
                                    if (value) {
                                      unawaited(
                                        Get.find<PlayController>()
                                            .refreshCurrentLoudness(),
                                      );
                                    }
                                  },
                                ),
                              ),
                              Obx(
                                () => settingsController.loudnessNormalization
                                    ? LoudnessGainInput(
                                        value: settingsController
                                            .otherPlatformLoudnessGain,
                                        onChanged: (value) {
                                          settingsController
                                                  .otherPlatformLoudnessGain =
                                              value;
                                          unawaited(
                                            Get.find<PlayController>()
                                                .applyPlaybackVolume(),
                                          );
                                        },
                                      )
                                    : const SizedBox.shrink(),
                              ),
                              Obx(
                                () => SwitchListTile(
                                  title: const Text('音量跟随系统'),
                                  value: Get.find<SettingsController>()
                                      .volumnFollowSystem,
                                  onChanged:
                                      Get.find<SettingsController>()
                                          .volumnFollowSystemChanging
                                          .value
                                      ? null
                                      : (bool value) async {
                                          Get.find<SettingsController>()
                                                  .volumnFollowSystemChanging
                                                  .value =
                                              true;
                                          Get.find<SettingsController>()
                                                  .volumnFollowSystem =
                                              value;
                                          await Get.find<PlayController>()
                                              .updSysVolAndSet();
                                          Get.find<SettingsController>()
                                                  .volumnFollowSystemChanging
                                                  .value =
                                              false;
                                        },
                                ),
                              ),
                              Obx(
                                () => SwitchListTile(
                                  title: const Text('下一首播放模式'),
                                  subtitle: Obx(
                                    () => setSubTitleTextAniSwi(
                                      Text(
                                        Get.find<SettingsController>()
                                                .nextTrackQueueOrStackMethod
                                            ? '队列：先添加的曲目将先播放'
                                            : '栈：后添加的曲目将先播放',
                                        key: ValueKey<bool>(
                                          Get.find<SettingsController>()
                                              .nextTrackQueueOrStackMethod,
                                        ),
                                      ),
                                    ),
                                  ),
                                  value: Get.find<SettingsController>()
                                      .nextTrackQueueOrStackMethod,
                                  onChanged: (bool value) {
                                    Get.find<SettingsController>()
                                            .nextTrackQueueOrStackMethod =
                                        value;
                                  },
                                ),
                              ),
                              Obx(
                                () => SwitchListTile(
                                  title: const Text('在“循环播放”模式下列表播放完成时停止播放'),

                                  value: Get.find<SettingsController>()
                                      .stopOnPlayListEnd,
                                  onChanged: (bool value) {
                                    Get.find<SettingsController>()
                                            .stopOnPlayListEnd =
                                        value;
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        ExpansionPanel(
                          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
                          headerBuilder:
                              (BuildContext context, bool isExpanded) {
                                return ListTile(
                                  leading: Icon(Icons.miscellaneous_services),
                                  title: Text('杂项'),
                                );
                              },
                          canTapOnHeader: true,
                          isExpanded: settingsController.settingsPageExpansion
                              .contains(8),
                          body: Column(
                            children: [
                              Obx(
                                () => AppLogLevelTile(
                                  value: settingsController.logLevel,
                                  onChanged: (level) =>
                                      settingsController.logLevel = level,
                                ),
                              ),
                              ListTile(
                                leading: const Icon(Icons.password),
                                title: const Text('一次性验证码'),
                                subtitle: const Text('点击复制一次性验证码'),
                                onTap: copyTotpCode,
                                onLongPress: showTotpHelpDialog(),
                                trailing: IconButton(
                                  tooltip: '设置一次性验证码',
                                  icon: const Icon(Icons.settings),
                                  onPressed: () => showTotpSettings(context),
                                ),
                              ),

                              Obx(
                                () => SwitchListTile(
                                  secondary: const Icon(Icons.tips_and_updates_outlined),
                                  title: const Text('显示使用提示'),
                                  subtitle: const Text('在搜索框等位置显示操作提示'),
                                  value: settingsController.showSomeTips,
                                  onChanged: (value) {
                                    settingsController.showSomeTips = value;
                                    if (value)
                                      startupTipsService.updateSearchHint();
                                  },
                                ),
                              ),
                              ListTile(
                                leading: const Icon(Icons.width_normal),
                                title: const Text('侧栏较宽时隐藏搜索页的搜索框'),
                                subtitle: Obx(
                                  () => setSubTitleTextAniSwi(
                                    Text(
                                      '侧栏宽于 ${Get.find<SettingsController>().showSearchAreaWidth.round()} px 时，搜索页不再重复显示搜索框（当前 ${Get.find<XSearchController>().leftBarWidth.value.round()} px）',
                                      key: ValueKey<double>(
                                        Get.find<XSearchController>()
                                            .leftBarWidth
                                            .value,
                                      ),
                                    ),
                                  ),
                                ),
                                onTap: showShowSearchAreaWidthInputDialog,
                                onLongPress: () => showInfoSnackbar(
                                  '@zhiquanchi',
                                  'https://github.com/HBWuChang/listen1_xuan/issues/33',
                                ),
                              ),

                              Obx(
                                () => SwitchListTile(
                                  secondary: const Icon(Icons.manage_search),
                                  title: const Text('记忆上次搜索源'),
                                  subtitle: Obx(
                                    () => setSubTitleTextAniSwi(
                                      Text(
                                        Get.find<SettingsController>()
                                                .searchUseLastSource
                                            ? '打开搜索时使用上次的平台'
                                            : '打开搜索时使用默认平台',
                                        key: ValueKey<bool>(
                                          Get.find<SettingsController>()
                                              .searchUseLastSource,
                                        ),
                                      ),
                                    ),
                                  ),
                                  value: Get.find<SettingsController>()
                                      .searchUseLastSource,
                                  onChanged: (bool value) {
                                    Get.find<SettingsController>()
                                            .searchUseLastSource =
                                        value;
                                  },
                                ),
                              ),
                              Obx(
                                () => SwitchListTile(
                                  secondary: const Icon(Icons.content_copy_outlined),
                                  title: const Text('出错时复制错误信息'),
                                  subtitle: const Text('便于反馈问题时粘贴'),
                                  value: Get.find<SettingsController>()
                                      .copyErrorMessage,
                                  onChanged: (bool value) {
                                    Get.find<SettingsController>()
                                            .copyErrorMessage =
                                        value;
                                  },
                                ),
                              ),
                              AnimatedSize(
                                duration: Duration(milliseconds: 300),
                                child: Obx(
                                  () =>
                                      Get.find<SettingsController>()
                                          .searchUseLastSource
                                      ? SizedBox.shrink()
                                      : ListTile(
                                          leading: Icon(Icons.search),
                                          title: const Text('选择默认搜索源'),
                                          trailing: DropdownButton<BaseProvider>(
                                            value: Get.find<XSearchController>()
                                                .providerFromNameOrAlias(
                                                  Get.find<SettingsController>()
                                                      .searchLastSource,
                                                ),
                                            icon: Icon(Icons.arrow_downward),
                                            onChanged:
                                                (BaseProvider? newValue) {
                                                  if (newValue == null) return;
                                                  setState(() {
                                                    Get.find<
                                                              SettingsController
                                                            >()
                                                            .searchLastSource =
                                                        newValue.name;
                                                  });
                                                },
                                            items: Get.find<XSearchController>()
                                                .searchProviders
                                                .map<
                                                  DropdownMenuItem<BaseProvider>
                                                >((BaseProvider provider) {
                                                  return DropdownMenuItem<
                                                    BaseProvider
                                                  >(
                                                    value: provider,
                                                    child: Text(
                                                      provider.shortDisplayName,
                                                    ),
                                                  );
                                                })
                                                .toList(),
                                          ),
                                        ),
                                ),
                              ),

                              const ListTile(
                                leading: Icon(Icons.verified_user_outlined),
                                title: Text('始终校验 SSL 证书'),
                                subtitle: Text('出于安全考虑，证书校验无法关闭'),
                              ),
                              Obx(
                                () => SwitchListTile(
                                  secondary: const Icon(Icons.bug_report_outlined),
                                  title: const Text('显示调试提示'),
                                  value: Get.find<SettingsController>()
                                      .useDebugMode,
                                  onChanged: (bool value) {
                                    Get.find<SettingsController>()
                                            .useDebugMode =
                                        value;
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 导航类条目与上方分组卡片使用同一表面色，保持一个节奏。
                  12.sbh,
                  Material(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    child: Column(
                      children: [
                      ListTile(
                        leading: const FeedbackUnreadBadge(child: Icon(Icons.forum_outlined)),
                        title: const Text('在线反馈'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () =>
                            Get.toNamed(RouteName.onlineFeedbackPage, id: 1),
                      ),
                      if (Get.isRegistered<FeedbackPushController>() && Get.find<FeedbackPushController>().supported)
                        GetBuilder<FeedbackPushController>(
                          autoRemove: false,
                          builder: (push) => SwitchListTile(
                            secondary: const Icon(Icons.notifications_outlined),
                            title: const Text('反馈消息推送'),
                            subtitle: Text(push.error ?? (push.enabled
                                ? '按问题的未读红点设置接收系统通知'
                                : '开启后可接收关注问题的新消息通知')),
                            value: push.enabled,
                            onChanged: push.busy ? null : push.setEnabled,
                          ),
                        ),
                      ListTile(
                        leading: const Icon(Icons.lightbulb_outline),
                        title: const Text('使用技巧'),
                        trailing: Icon(Icons.chevron_right),
                        onTap: () {
                          Get.toNamed(RouteName.settingsTipsPage, id: 1);
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.menu_book_outlined),
                        title: const Text('说明文档'),
                        trailing: Icon(Icons.chevron_right),
                        onTap: () {
                          Get.toNamed(RouteName.settingsReadmePage, id: 1);
                        },
                      ),
                      ],
                    ),
                  ),
                  // 预留右下角浮动提示的位置，最后一行不会被遮住。
                  88.sbh,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
