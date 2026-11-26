import 'package:animated_digit/animated_digit.dart';
import 'controllers/feedback_unread_controller.dart';
import 'services/feedback/feedback_api.dart';
import 'widgets/feedback_unread_badge.dart';
import 'pages/feedback/feedback_push_navigation.dart';
import 'controllers/feedback_push_navigation_controller.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:toastification/toastification.dart';
import 'package:heroine/heroine.dart';
import 'package:iconify_flutter_plus/icons/ic.dart';
import 'package:listen1_xuan/controllers/controllers.dart';
import 'package:listen1_xuan/controllers/receiveSharingIntentController.dart';
import 'package:listen1_xuan/controllers/search_controller.dart';
import 'package:listen1_xuan/controllers/sleep_timer_controller.dart';
import 'package:listen1_xuan/funcs.dart';
import 'package:listen1_xuan/pages/lyric/lyric_page.dart';
import 'package:listen1_xuan/pages/playlist_info/playlist_info_page.dart';
import 'package:listen1_xuan/pages/playlist_info/playlist_info_binding.dart';
import 'package:listen1_xuan/pages/playlist_info/playlist_info_args.dart';
import 'package:listen1_xuan/provider/base.dart';
import 'package:listen1_xuan/provider/loweb.dart';
import 'package:listen1_xuan/router/image_toolbox_predictive_transitions.dart';
import 'package:listen1_xuan/widgets/draggable_toast/toast_overlay_manager.dart';
import 'package:listen1_xuan/widgets/ext/ext_widget.dart';
import 'package:listen1_xuan/widgets/native_file_drop_region.dart';
import 'widgets/keyboard_stable_player.dart';
import 'package:media_kit/media_kit.dart' show MediaKit;
import 'package:resizable_widget/resizable_widget.dart';
import 'controllers/HomeController.dart';
import 'controllers/upd_controller.dart';
import 'examples/websocket_server_example.dart';
import 'examples/websocket_client_example.dart';
import 'packages/circular_theme_reveal/src/circular_theme_reveal_overlay.dart';
import 'pages/download_page.dart';
import 'pages/track_downloads_page.dart';
import 'controllers/track_download_controller.dart';
import 'pages/nowPlaying_page.dart';
import 'pages/settings/settings_readme.dart';
import 'pages/settings/settings_tips_page.dart';
import 'pages/feedback/feedback_routes.dart';
import 'pages/feedback/feedback_route_observer.dart';
import 'pages/startup_page.dart';
import 'services/startup_tips_service.dart';
import 'services/app_log_file.dart';
import 'pages/settings/settings_supabase_login_page.dart';
import 'pages/settings/settings_supabase_password_login_page.dart';
import 'pages/settings/cache_naming_page.dart';
import 'pages/android_equalizer_page.dart';
import 'pages/songReplace_page.dart';
import 'settings.dart';
import 'bodys.dart';
import 'play.dart';
import 'global_settings_animations.dart';
import 'widgets.dart';
import 'widgets/priority_responsive_action_row.dart';
import 'widgets/responsive_layout.dart';
import 'dart:async';
import 'dart:io';
import 'package:preload_page_view/preload_page_view.dart';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:flutter/gestures.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:windows_taskbar/windows_taskbar.dart';
import 'package:smtc_windows/smtc_windows.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:adaptive_theme/adaptive_theme.dart';
import 'controllers/theme.dart';
import 'package:app_links/app_links.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:listen1_xuan/constants/network_defaults.dart';
import 'package:listen1_xuan/constants/supabase_proxy.dart';
part 'main_testBtn.dart';
part 'pages/main/main_widgets.dart';
part 'pages/main/main_utils.dart';

/// Supabase 项目默认地址（直连）
const String supabaseDefaultUrl = 'https://jtvxrwybwvgpqobyhaoy.supabase.co';

/// Supabase 备用地址：自建的 Cloudflare Worker 透明反代，用于绕过受限网络。
/// 部署方式见 workers/supabase-proxy/README.md，部署后把这里改成实际域名。
/// 注意必须是 **一级** 子域，Cloudflare 免费版证书不覆盖多层子域。
/// 在「设置 - Supabase 账号 - 使用备用地址」开关切换，重启应用生效。
const String supabaseBackupUrl = 'https://sb.040905.xyz';

/// 实际使用的地址，在 main() 中按设置决定
String supabaseUrl = supabaseDefaultUrl;

String supabaseKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp0dnhyd3lid3ZncHFvYnloYW95Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjE5NjE5ODUsImV4cCI6MjA3NzUzNzk4NX0.lb4YhPlsyTinmoK85jv_15KCEv1QDr0JsUa1oI5P0Ko';

int last_dir = 0;
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void enableThumbnailToolbar() async {
  int retryCount = 0;
  const maxRetries = 10; // 最多重试10次

  while (retryCount < maxRetries) {
    try {
      await WindowsTaskbar.setThumbnailToolbar([
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon(
            'assets/images/audio_service_skip_previous.ico',
          ),
          '上一首',
          () {
            globalSkipToPrevious();
          },
        ),
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon('assets/images/audio_service_pause.ico'),
          '播放/暂停',
          () {
            globalPlayOrPause();
          },
        ),
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon(
            'assets/images/audio_service_skip_next.ico',
          ),
          '下一首',
          () {
            globalSkipToNext();
          },
        ),
      ]);
      debugPrint('任务栏缩略图工具栏设置成功');
      break;
    } catch (e) {
      retryCount++;
      debugPrint('设置任务栏缩略图工具栏失败 (尝试 $retryCount/$maxRetries): $e');
      if (retryCount < maxRetries) {
        await Future.delayed(Duration(seconds: 3)); // 注意这里添加了 await
      } else {
        debugPrint('已达到最大重试次数，放弃设置任务栏缩略图工具栏');
      }
    }
  }
}

Future<void> showStartupWindow(SettingsController? settingsController) async {
  if (!isDesktop) return;
  await Window.initialize();
  await windowManager.ensureInitialized();
  await hotKeyManager.unregisterAll();
  final rememberBounds =
      settingsController?.rememberWindowsSizeAndPosition ?? false;
  final bounds = rememberBounds
      ? settingsController!.windowsWindowBounds
      : const Rect.fromLTWH(0, 0, 1000, 700);
  final options = WindowOptions(
    size: Size(bounds.width, bounds.height),
    minimumSize: const Size(400, 700),
    center: settingsController?.centerWindowOnStart ?? true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );
  await windowManager.waitUntilReadyToShow(options);
  if (settingsController?.isWindowMaximized ?? false) {
    await windowManager.maximize();
  }
  await windowManager.setPreventClose(true);
  await windowManager.show();
}

bool _startupWindowConfigured = false;

Future<void> _initializeOptionalServices() async {
  try {
    final settingsController = Get.find<SettingsController>();
    if (settingsController.settingsPageExpansion.contains(0)) {
      unawaited(settingsController.refreshLoginData().catchError((Object error) {
        debugPrint('刷新登录信息失败: $error');
      }));
    }
  } catch (error) {
    debugPrint('启动后的可选服务初始化失败: $error');
  }
}

Future<SettingsController> _initializeSettingsAndTheme() async {
  MediaKit.ensureInitialized();
  SettingsController settingsController = Get.put(
    SettingsController(),
    permanent: true,
  );
  await settingsController.init();
  final themeController = createThemeController();
  await themeController.initialization;
  return settingsController;
}

Future<void> _initializeAppForHome(SettingsController settingsController) async {
  if (isDesktop) {
    await showStartupWindow(settingsController);
    _startupWindowConfigured = true;
  }
  // 读取「使用备用地址」开关后，才能确定要连哪个 Supabase 地址
  // 没有中转令牌的构建（fork、本地构建）即使开关曾被打开也回退到直连，
  // 不在启动时抛错导致应用打不开。
  final useBackupUrl =
      settingsController.supabaseUseBackupUrl && supabaseProxyToken.isNotEmpty;
  if (settingsController.supabaseUseBackupUrl && !useBackupUrl) {
    debugPrint('未配置 SUPABASE_PROXY_TOKEN，已回退到 Supabase 直连地址');
  }
  supabaseUrl = useBackupUrl ? supabaseBackupUrl : supabaseDefaultUrl;
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseKey,
    headers: useBackupUrl
        ? {'x-proxy-token': supabaseProxyToken}
        : const {},
    authOptions: FlutterAuthClientOptions(
      localStorage: SharedPreferencesLocalStorage(
        persistSessionKey: 'sb-jtvxrwybwvgpqobyhaoy-auth-token',
      ),
    ),
  );
  Get.put(RouteController(), permanent: true);
  Get.put(SleepTimerController(), permanent: true);
  DioController dioController = Get.put(DioController(), permanent: true);
  await dioController.loadConfig();
  settingsController.completeDioInit();
  CacheController cacheController = Get.put(CacheController(), permanent: true);
  final playController = Get.put(PlayController(), permanent: true);
  settingsController.bindPlaybackSettings(playController);
  Get.put(Provider(), permanent: true);
  cacheController.loadLocalCacheList();
  Get.find<PlayController>().loadDatas();
  Get.put(MyPlayListController(), permanent: true);
  Get.find<MyPlayListController>().loadDatas();
  Get.put(AudioHandlerController(), permanent: true);
  Get.put(XLyricController(), permanent: true);
  Get.put(NowPlayingPageController(), permanent: true);
  Get.put(BroadcastWsController(), permanent: true);
  Get.put(ScanBroadcastController(), permanent: true);
  Get.put(WsDownloadController(), permanent: true);
  Get.put(TrackDownloadController(), permanent: true);
  Get.put(Applinkscontroller(), permanent: true);
  Get.put(SupabaseAuthController(), permanent: true);
  Get.put(FeedbackUnreadController(FeedbackApi(Supabase.instance.client)), permanent: true);
  initializeFeedbackPush();
  Get.put(XSearchController(), permanent: true);
  Get.put(UpdController(), permanent: true);
  Get.put(HomeController(), permanent: true);
  Get.put(PasteController(), permanent: true);
  if (isAndroid) Get.put(ReceiveSharingIntentController(), permanent: true);
  init_apkfilepath();
  if (isWindows) SMTCWindows.initialize();
  // 初始化WebSocket控制器并加载配置
  WebSocketCardController wsController = Get.put(
    WebSocketCardController(),
    permanent: true,
  );
  wsController.loadWebSocketSettings();
  // 如果设置了自动启动，则启动WebSocket服务器
  wsController.autoStartServerIfNeeded();

  // 初始化WebSocket客户端控制器并加载配置
  WebSocketClientController wsClientController = Get.put(
    WebSocketClientController(),
    permanent: true,
  );
  wsClientController.loadWebSocketClientSettings();
  // 如果设置了自动连接，则连接WebSocket服务器
  wsClientController.autoConnectIfNeeded();

  final settings = lengcyGetSettings();
  settings.remove('useHttpOverrides');
  HttpOverrides.global = MyHttpOverrides(
    trustBadCertificates: false,
    userAgent: kGlobalDefaultUserAgent,
  );

  initDeepLinks();
}

void main() {
  // 所有 print / 未捕获的异步异常都经过这个 Zone，写入 logs/app.log。
  runZonedGuarded(
    _main,
    (error, stack) => AppLogFile.instance.write('FATAL', '未捕获异常: $error\n$stack'),
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        AppLogFile.instance.write('PRINT', line);
        parent.print(zone, line);
      },
    ),
  );
}

Future<void> _main() async {
  // Supabase 的初始化被移到了读取设置之后，见下方 settingsController.init()
  await WidgetsFlutterBinding.ensureInitialized(); // 确保 Flutter框架已初始化
  await AppLogFile.instance.init();
  _installErrorLogging();
  AppLogFile.instance.write('I', '启动 ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent, // 设置导航栏背景色为透明
      systemNavigationBarDividerColor: Colors.transparent, // 设置导航栏分割线为透明
      // 透明导航栏上不强制系统加半透明遮罩，手势条区域与播放栏背景一致。
      systemNavigationBarContrastEnforced: false,
    ),
  );
  // 无界面音频启动后再挂载 Activity 时，重新注册 Android 返回手势处理。
  if (isAndroid) {
    WidgetsBinding.instance.addObserver(frameworkHandlesBackRestorer);
  }
  final startupFailure = ValueNotifier<StartupFailure?>(null);
  final startupPage = StartupPage(
    tipsService: startupTipsService,
    failure: startupFailure,
  );
  var startupPageShown = false;
  unawaited(startupTipsService.load());
  try {
    final settingsController = await _initializeSettingsAndTheme();
    runApp(StartupApp(
      themeController: Get.find<ThemeController>(),
      home: startupPage,
    ));
    startupPageShown = true;
    await _initializeAppForHome(settingsController);
  } catch (error, stackTrace) {
    if (isHeadlessEngine) Error.throwWithStackTrace(error, stackTrace);
    if (isDesktop && !_startupWindowConfigured) {
      try {
        await showStartupWindow(null);
      } catch (windowError) {
        debugPrint('显示启动错误窗口失败: $windowError');
      }
    }
    startupFailure.value = StartupFailure.fromError(error, stackTrace);
    if (!startupPageShown) {
      runApp(MaterialApp(home: startupPage));
    }
    return;
  }
  runApp(MyApp());
  if (!isHeadlessEngine) {
    unawaited(UiHangWatchdog.start());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initializeOptionalServices());
      unawaited(startupTipsService.refreshIfDue(dioWithProxyAdapter));
    });
  } else {
    unawaited(_initializeOptionalServices());
  }
}

/// 把 Flutter 框架错误、平台异常和 debugPrint 都写入日志文件。
void _installErrorLogging() {
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    AppLogFile.instance.write(
      'E',
      'Flutter 错误: ${details.exceptionAsString()}\n${details.stack ?? ''}',
    );
    previousOnError?.call(details);
  };
  final previousPlatformError = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogFile.instance.write('FATAL', '平台异常: $error\n$stack');
    return previousPlatformError?.call(error, stack) ?? false;
  };
  final previousDebugPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) AppLogFile.instance.write('DEBUG', message);
    previousDebugPrint(message, wrapWidth: wrapWidth);
  };
}

/// 修复「系统先无界面拉起引擎、Activity 之后才挂上」时安卓返回手势失效的问题，
/// 详见 main() 里的调用处注释
class FrameworkHandlesBackRestorer with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!isAndroid) return;
    if (state != AppLifecycleState.resumed) return;
    SystemNavigator.setFrameworkHandlesBack(true);
  }
}

final frameworkHandlesBackRestorer = FrameworkHandlesBackRestorer();

Future<void> initDeepLinks() async {
  AppLinks().uriLinkStream.listen((uri) {
    debugPrint('Received app link: $uri');
    Get.find<Applinkscontroller>().appLink.value = uri;
  });
}

class MyApp extends StatelessWidget {
  MyApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    final themeController = Get.find<ThemeController>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      themeController.didChangePlatformBrightnessOrManual();
    });

    return ScreenUtilInit(
      designSize: const Size(1200, 2670),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return ToastificationWrapper(
          child: AdaptiveTheme(
          light: themeController.lightTheme,
          dark: themeController.darkTheme,
          initial: themeController.themeMode.value,
          builder: (theme, darkTheme) => GetMaterialApp(
            title: 'Listen1',
            builder: (context, widget) {
              widget = CircularThemeRevealOverlay(
                child: widget ?? SizedBox.shrink(),
              );
              widget = FToastBuilder()(context, widget);
              // 全局断点：页面可用 ResponsiveBreakpoints.of(context) 判断布局档位。
              widget = responsiveAppBuilder(context, widget);
              // 处理 MediaQuery 异常问题，特别是小米澎湃系统
              MediaQueryData mediaQuery = MediaQuery.of(context);
              double safeTop = mediaQuery.padding.top;

              // 如果出现异常值，使用默认值替代
              if (safeTop > 80 || safeTop < 0) {
                debugPrint(
                  'Detected abnormal top padding: $safeTop, using fallback.',
                );
                safeTop = 24.0; // 合理默认值
              }

              // 然后应用 MediaQuery 设置
              return MediaQuery(
                // Desktop chrome keeps a stable density. Mobile follows the
                // user's text scale but clamped to 1.0–1.3: the ScreenUtil
                // fixed-size layouts (play bar, list rows) overflow beyond it.
                data: mediaQuery.copyWith(
                  textScaler: isDesktop
                      ? const TextScaler.linear(1.0)
                      : mediaQuery.textScaler.clamp(
                          minScaleFactor: 1.0,
                          maxScaleFactor: 1.3,
                        ),
                  padding: mediaQuery.padding.copyWith(top: safeTop),
                ),
                child: widget,
              );
            },
            navigatorKey: navigatorKey,
            theme: theme.copyWith(
              pageTransitionsTheme: imageToolboxPageTransitionsTheme,
            ),
            darkTheme: darkTheme.copyWith(
              pageTransitionsTheme: imageToolboxPageTransitionsTheme,
            ),
            localizationsDelegates: [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            scrollBehavior: const MaterialScrollBehavior().copyWith(
              dragDevices: {
                PointerDeviceKind.mouse, // 添加鼠标拖动
                PointerDeviceKind.touch,
                PointerDeviceKind.stylus,
                PointerDeviceKind.invertedStylus,
                PointerDeviceKind.trackpad,
              },
            ),
            supportedLocales: [
              const Locale('zh', 'CN'), // 中文简体
              // 其他支持的语言
            ],
            locale: const Locale('zh', 'CN'), // 设置默认语言为中文
            home: MyHomePage(),
          ),
          ),
        );
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

RxBool _globalHorizon = false.obs;
bool get globalHorizon => _globalHorizon.value;
set globalHorizon(bool value) => _globalHorizon.value = value;

HomeController get homeController => Get.find<HomeController>();

TextEditingController get input_text_Controller =>
    Get.find<XSearchController>().searchTextController;

class _MyHomePageState extends State<MyHomePage>
    with TrayListener, WindowListener, WidgetsBindingObserver {
  FocusNode _focusNode = FocusNode();
  FocusNode _focusNode2 = FocusNode();
  bool _wasInactive = false;
  bool _wasUnfocused = false;
  bool _hasBeenResumed = false;

  void _refreshSearchHint() {
    if (Get.find<SettingsController>().showSomeTips) {
      startupTipsService.updateSearchHint();
    }
  }

  @override
  void initState() {
    super.initState();
    _hasBeenResumed =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    trayManager.addListener(this);
    homeController.updatePageControllers();
    if (isDesktop) {
      _initTrayManager();
      init_hotkeys();
      windowManager.addListener(this);
    }
    Get.find<Applinkscontroller>().xshow = xshow;

    fToast = FToast();
    // if you want to use context from globally instead of content we need to pass navigatorKey.currentContext!
    fToast.init(navigatorKey.currentContext!);

    draggableToastManager = ToastOverlayManager.instance;
    draggableToastManager.init(navigatorKey.currentContext!);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && Get.isRegistered<FeedbackPushNavigationController>()) {
        Get.find<FeedbackPushNavigationController>().setReady();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (isDesktop) {
      Get.find<ThemeController>().stateAppLifecycleStateResumed.value =
          state == AppLifecycleState.resumed;
      return;
    }
    if (state == AppLifecycleState.resumed) {
      if (_wasInactive && _hasBeenResumed) _refreshSearchHint();
      _wasInactive = false;
      _hasBeenResumed = true;
    } else {
      _wasInactive = true;
    }
  }

  void _initTrayManager() async {
    await trayManager.setIcon('assets/images/app_icon.ico');
    await trayManager.setToolTip('Listen1_xuan');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show_window', label: '显示窗口'),
          MenuItem(key: 'exit_app', label: '退出应用'),
        ],
      ),
    );
  }

  @override
  void onTrayIconMouseDown() {
    print('onTrayIconMouseDown');
    // do something, for example pop up the menu
    xshow();
  }

  Future<void> xshow() async {
    await windowManager.show();
    windowManager.setSkipTaskbar(false);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setBackgroundColor(Colors.transparent);
    createThemeController().didChangePlatformBrightnessOrManual();
  }

  @override
  void onTrayIconRightMouseDown() {
    print('onTrayIconRightMouseDown');
    // do something, for example pop up the menu
    trayManager.popUpContextMenu(bringAppToFront: true);
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    print('onTrayMenuItemClick: ${menuItem.key}');
    if (menuItem.key == 'show_window') {
      xshow();
    } else if (menuItem.key == 'exit_app') {
      // do something
      closeApp();
    }
  }

  @override
  void onWindowClose() {
    _clickCloseBtn();
  }

  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    Get.find<ThemeController>().didChangePlatformBrightnessOrManual();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (isDesktop) {
      trayManager.removeListener(this);
      windowManager.removeListener(this);
    }
    _focusNode.dispose();
    _focusNode2.dispose();
    homeController.pageControllerHorizon?.dispose(); // 销毁 PageController
    homeController.pageControllerPortrait?.dispose();

    super.dispose();
  }

  List<double> horPartPercentages =
      Get.find<SettingsController>().horPartPercentages;
  @override
  Widget build(BuildContext main_context) {
    // appLinks
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Get.find<Applinkscontroller>().processAppLink();
    });
    return Focus(
      autofocus: true,
      onKeyEvent: (FocusNode node, KeyEvent event) {
        // 动态判断是否启用热键
        if (!enable_inapp_hotkey) {
          return KeyEventResult.ignored; // 将按键事件传递给下一个处理器
        }
        // 处理粘贴快捷键 (仅Desktop)
        if (isDesktop &&
            Get.isRegistered<PasteController>() &&
            Get.find<PasteController>().handleKeyEvent(event)) {
          return KeyEventResult.handled;
        }

        bool flag = false;
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          inappShortcuts.forEach((key, value) {
            if (event.logicalKey == key) {
              value();
              flag = true;
            }
          });
        }
        if (flag) return KeyEventResult.handled;
        return KeyEventResult.ignored;
      },
      child: NativeFileDropRegion(
        enabled: isDesktop,
        onFilesDropped: Get.find<UpdController>().processFileUpdate,
        onTextDropped: Get.find<PasteController>().onTextPasted,
        onDropEnter: () => showInfoSnackbar('松开以确认', null),
        child: OrientationBuilder(
          builder: (context, orientation) {
            globalHorizon = orientation == Orientation.landscape;
            final newDir = globalHorizon ? 2 : 1;
            // OrientationBuilder 会随任意父级重建（键盘弹出、换主题等）重跑。
            // 只在方向真正变化（或首次构建）时才重置首页标签和系统栏模式，
            // 否则竖屏下选中的标签会被意外切回第一个平台。
            final orientationChanged = last_dir != newDir;
            final flag = last_dir != 0 && orientationChanged;
            if (orientationChanged) {
              if (globalHorizon) {
                homeController.selectedIndex.value = provider.indexOfFirstOnH;
                SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
              } else {
                homeController.selectedIndex.value = provider.indexOfFirstOnV;
                if (!Get.find<XSearchController>().showSearchArea.value) {
                  Get.find<XSearchController>().showSearchArea.value = true;
                }
                SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
              }
              last_dir = newDir;
            }
            if (flag) {
              Get.offAllNamed('/', id: 1);
              homeController.updatePageControllers();
            }
            Widget _play = Play(horizon: globalHorizon);
            Scaffold con() => Scaffold(
              extendBody: true,
              resizeToAvoidBottomInset: false,
              backgroundColor:
                  createThemeController().playHBackgroundColor.value,
              // 手机横屏时左右可能有挖孔/圆角，内容整体避开，背景色铺满。
              body: SafeArea(
                top: false,
                bottom: false,
                left: isMobile,
                right: isMobile,
                child: Stack(
                children: [
                  Positioned.fill(
                    child: Column(
                      children: <Widget>[
                        Expanded(
                          child: globalHorizon
                              ? ResizableWidget(
                                  isHorizontalSeparator: false,
                                  isDisabledSmartHide: false,
                                  separatorColor: AdaptiveTheme.of(
                                    Get.context!,
                                  ).theme.colorScheme.secondaryContainer,
                                  separatorSize: 2,
                                  percentages: horPartPercentages,
                                  minWidths: [60, 500],
                                  keepWidthWhenExtended: {0},
                                  onResized: (infoList) {
                                    Get.find<SettingsController>()
                                        .horPartPercentages = infoList
                                        .map((e) => e.percentage)
                                        .toList();
                                  },
                                  children: [
                                    // required
                                    _leftBar,
                                    _mainContent(),
                                  ],
                                )
                              : _mainContent(),
                        ),
                        KeyboardPlayerSpacer(
                          height: globalHorizon ? 60 : 256.w,
                          includeBottomSafeArea: !globalHorizon,
                        ),
                      ],
                    ),
                  ),

                  ///测试按钮
                  if (kDebugMode && !testBtnoff) testBtn,

                  /// The desktop workspace uses the rail/topbar action instead
                  /// of a mobile FAB, which otherwise floats over the player.
                  /// Mobile keeps the FAB in both orientations (upstream offsets).
                  if (!isDesktop)
                    Positioned.fill(
                      child: SafeArea(
                        top: false,
                        maintainBottomViewPadding: true,
                        child: Align(
                          alignment: Alignment.bottomRight,
                          child: Padding(
                            padding: EdgeInsets.only(
                              bottom: globalHorizon ? 76 : 300.w,
                              right: globalHorizon ? 16 : 40.w,
                            ),
                            child: WebSocketClientControlPanel.floatingActionButton,
                          ),
                        ),
                      ),
                    ),

                  // Windows desktop keeps the player above all workspace content.
                  /// 播放控制栏
                  Positioned.fill(
                    child: KeyboardStablePlayer(child: globalHorizon
                        ? Align(alignment: Alignment.bottomCenter, child: _play)
                        : SafeArea(top: false, child: _play)),

                    // 竖屏状态下添加额外的占位空间
                  ),
                ],
              ),
              ),
              // floatingActionButton:
              // FloatingActionButton(
              //   onPressed: () {
              //     Get.find<Applinkscontroller>().processAppLink();
              //   },
              // ),
              // WebSocketClientControlPanel.floatingActionButton,
            );

            return PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, result) => routerPop(),
              child: isDesktop && globalHorizon ? Obx(() => con()) : con(),
            );
          },
        ),
      ),
    );
  }

  bool _windowManagerOnce = false;
  @override
  void onWindowBlur() {
    _wasUnfocused = true;
  }

  @override
  void onWindowFocus() {
    if (_windowManagerOnce && _wasUnfocused) _refreshSearchHint();
    _wasUnfocused = false;
    // 确保只调用一次
    if (!_windowManagerOnce) {
      _windowManagerOnce = true;
      if (isWindows) {
        enableThumbnailToolbar();
      }
      // if (isDesktop) {
      //   Get.find<ThemeController>().didChangePlatformBrightnessOrManual();
      // }
      setState(() {});
      // 做些什么
    }
  }

  @override
  void onWindowResized() {
    Get.find<SettingsController>().saveWindowsSizeAndPosition();
  }

  @override
  void onWindowMaximize() {
    Get.find<SettingsController>().onWindowMaximize();
    if (mounted) setState(() {});
  }

  @override
  void onWindowUnmaximize() {
    Get.find<SettingsController>().onWindowUnmaximize();
    if (mounted) setState(() {});
  }
}
