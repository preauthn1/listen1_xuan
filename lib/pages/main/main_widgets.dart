part of '../../main.dart';

String _searchHintText(String? tip) => startupTipsService.searchHintText(
  showTips: Get.find<SettingsController>().showSomeTips,
  tip: tip,
);

Widget _leftBarTitleDragArea(Widget child) =>
    isWindows || isMacOS ? DragToMoveArea(child: child) : child;

class _WindowsTitleBar extends StatefulWidget {
  const _WindowsTitleBar();

  @override
  State<_WindowsTitleBar> createState() => _WindowsTitleBarState();
}

class _WindowsTitleBarState extends State<_WindowsTitleBar> {
  bool _isPinned = false;

  @override
  void initState() {
    super.initState();
    windowManager.isAlwaysOnTop().then((value) {
      if (mounted) setState(() => _isPinned = value);
    });
  }

  Future<void> _togglePinned() async {
    final next = !_isPinned;
    await windowManager.setAlwaysOnTop(next);
    if (mounted) setState(() => _isPinned = next);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final routeName =
          top_routeWithName.isEmpty ? null : top_routeWithName.last.name;
      final settingsRoute = routeName == RouteName.settingsPage;
      // 其它子页面自带 AppBar（返回 + 标题），标题栏不再重复显示。
      final canGoBack = settingsRoute;
      final title = settingsRoute ? '设置' : '';
      final settings = Get.find<SettingsController>();
      return Material(
        color: Theme.of(context).colorScheme.surface,
        child: SizedBox(
        height: 32,
        child: DragToMoveArea(
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: canGoBack
                    ? IconButton(
                        tooltip: '返回',
                        padding: EdgeInsets.zero,
                        iconSize: 15,
                        onPressed: routerPop,
                        icon: const Icon(LucideIcons.chevronLeft),
                      )
                    : null,
              ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              if (settingsRoute) ...[
                WebSocketHelper.buildReactiveButton(
                  tooltip: 'WebSocket 服务器',
                  iconSize: 15,
                  padding: EdgeInsets.zero,
                ),
                WebSocketClientHelper.buildReactiveButton(
                  tooltip: 'WebSocket 客户端',
                  iconSize: 15,
                  padding: EdgeInsets.zero,
                ),
              ],
              if (settingsRoute)
                const SizedBox(
                  height: 16,
                  child: VerticalDivider(width: 17, thickness: 1),
                ),
              IconButton(
                tooltip: _isPinned ? '取消置顶' : '窗口置顶',
                padding: EdgeInsets.zero,
                iconSize: 15,
                color: _isPinned ? Theme.of(context).colorScheme.primary : null,
                onPressed: _togglePinned,
                icon: Icon(_isPinned ? LucideIcons.pinOff : LucideIcons.pin),
              ),
              IconButton(
                tooltip: '最小化',
                padding: EdgeInsets.zero,
                iconSize: 15,
                onPressed: () async {
                  await windowManager.minimize();
                  await windowManager.setSkipTaskbar(false);
                },
                icon: const Icon(LucideIcons.minus),
              ),
              FutureBuilder<bool>(
                future: windowManager.isMaximized(),
                builder: (context, snapshot) {
                  final maximized = snapshot.data == true;
                  return IconButton(
                    tooltip: maximized ? '还原窗口' : '最大化',
                    padding: EdgeInsets.zero,
                    iconSize: 15,
                    onPressed: () async {
                      if (await windowManager.isMaximized()) {
                        await windowManager.unmaximize();
                      } else {
                        await windowManager.maximize();
                      }
                      if (mounted) setState(() {});
                    },
                    icon: Icon(maximized ? LucideIcons.copy : LucideIcons.square),
                  );
                },
              ),
              IconButton(
                tooltip: settings.windowsCloseBtnCloseOrHideApp != false ? '关闭' : '隐藏到托盘',
                padding: EdgeInsets.zero,
                iconSize: 15,
                onPressed: _clickCloseBtn,
                icon: const Icon(LucideIcons.x),
              ),
            ],
          ),
        ),
        ),
      );
    });
  }
}

Widget get _leftBar => Scaffold(
  resizeToAvoidBottomInset: false,
  body: Column(
    children: [
      16.sbh,
      isDesktop
          ? _leftBarTitleDragArea(
              Listener(
                onPointerDown: (event) {
                  if (event.kind == PointerDeviceKind.mouse &&
                      event.buttons == kSecondaryMouseButton) {
                    windowManager.hide();
                    windowManager.setSkipTaskbar(true);
                  }
                  if (event.kind == PointerDeviceKind.mouse &&
                      event.buttons == kMiddleMouseButton) {
                    closeApp();
                  }
                },
                child: Tooltip(
                  message: '右键以最小化,中键以关闭',
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Listen1', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                    ),
                  ).sbwh(double.infinity, 34),
                ),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                return FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Listen1', style: TextStyle(fontSize: 24)),
                );
              },
            ).sbwh(double.infinity, 34),
      LayoutBuilder(
        builder: (context, constraints) {
          final searchController = Get.find<XSearchController>();
          final searchSettings = Get.find<SettingsController>();
          bool useFocusNode = !searchController.showSearchArea.value;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            searchController.leftBarWidth.value = constraints.maxWidth;
          });
          if (constraints.maxWidth > searchSettings.showSearchAreaWidth) {
            if (searchController.showSearchArea.value) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                searchController.showSearchArea.value = false;
              });
            }
          } else {
            if (!searchController.showSearchArea.value) {
              useFocusNode = false;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                searchController.showSearchArea.value = true;
              });
            }
          }
          final inputFontSize = (constraints.maxWidth / 6)
              .clamp(12.0, 16.0)
              .toDouble();
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ValueListenableBuilder<String?>(
              valueListenable: startupTipsService.searchHint,
              builder: (context, tip, _) => Obx(
                () => TextField(
                  focusNode: useFocusNode ? searchController.focusNode : null,
                  decoration: InputDecoration(
                    hintText: _searchHintText(tip),
                    hintStyle: TextStyle(fontSize: inputFontSize),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  ),
                  style: TextStyle(fontSize: inputFontSize),
                  controller: input_text_Controller,
                  readOnly: searchController.showSearchArea.value,
                  onSubmitted: (_) => searchController.onSubmitted(),
                  onTap: searchController.showSearchArea.value
                      ? () async {
                          Get.toNamed(RouteName.searchPage, id: 1);
                        }
                      : null,
                ),
              ),
            ),
          );
        },
      ).sbh(64),
      Expanded(child: MyPlaylist()),

      // SizedBox(),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Align(
          alignment: Alignment.center,
          child: PriorityResponsiveActionRow(
            // 窄时依次隐藏：WS 客户端、WS 服务器、主题、歌曲替换、更新提示；设置最后保留。
            hidePriority: const [2, 1, 0, 3, 4, 5],
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
          ThemeToggleButton(iconSize: 24.0, padding: EdgeInsets.all(0)),
          WebSocketHelper.buildReactiveButton(
            tooltip: "WebSocket 服务器",
            inMainPage: true,
          ),
          WebSocketClientHelper.buildReactiveButton(
            tooltip: "WebSocket 客户端",
            inMainPage: true,
          ),
          IconButton(
              tooltip: '歌曲替换列表',
              icon: const Icon(Icons.find_replace_rounded),
              onPressed: () {
                final routeController = Get.find<RouteController>();
                if (routeController.inSongReplacePage.value) {
                  Get.back(id: 1);
                  return;
                }
                Get.toNamed(RouteName.songReplacePage, id: 1);
              },
            ),
          Obx(() {
            final pending = Get.find<UpdController>().pendingUpdate.value;
            if (pending == null) return const SizedBox.shrink();
            return IconButton(
              tooltip: '发现新版本 ${pending.$1.tagName}',
              color: Get.theme.colorScheme.primary,
              icon: const Badge(
                smallSize: 8,
                child: Icon(Icons.system_update_rounded),
              ),
              onPressed: Get.find<UpdController>().reopenPendingUpdate,
            );
          }),
          IconButton(
            tooltip: "设置",
            icon: const FeedbackUnreadBadge(child: Icon(Icons.settings)),
            onPressed: () {
              Get.toNamed(RouteName.settingsPage, id: 1);
            },
          ),
        ],
        ),
        ),
      ),
    ],
  ),
);

final heroineController = HeroineController();

final innerKey = Get.nestedKey(1);

/// 歌单分类（筛选）按钮。
///
/// 注意：任何状态下都不要返回 [SizedBox.shrink] 之类没有内容的子组件。
/// 该按钮的显隐完全交给外层动画（横屏用 [AnimatedOpacity]、竖屏用 [AnimatedSize]）控制，
/// 而「隐藏」和 `empty` 状态是同一时刻发生的；一旦子组件在这里先变成零尺寸，
/// 淡出动画就没有内容可淡，视觉上就成了「瞬间消失」。
Widget get filterButton => Builder(
  builder: (context) => TextButton(
    onPressed: homeController.canFilterClick
        ? () {
            _showFilterSelection(context);
          }
        : null,
    child: Obx(
      () => switch (homeController.playlistFiltersLoadingStatus) {
        PlaylistFiltersLoadingStatus.loading => globalLoadingAnime,
        PlaylistFiltersLoadingStatus.failed => Icon(
          Icons.error,
          color: Colors.red,
        ),
        // loaded / empty / notLoaded 都显示当前分类名（默认「全部」）。
        _ => Text(
          homeController.currentProvider.nowSelectedPlaylistFilter.value.name,
        ),
      },
    ),
  ),
);
void Function(PointerDownEvent)? onMainPointerDown(PointerDownEvent event) {
  if (event.kind == PointerDeviceKind.mouse &&
      event.buttons == kSecondaryMouseButton) {
    routerPop();
  }
  if (event.kind == PointerDeviceKind.mouse &&
      event.buttons == kMiddleMouseButton) {
    switch (Get.find<SettingsController>().hideOrMinimize) {
      case false:
        windowManager.hide();
        windowManager.setSkipTaskbar(true);
        break;
      case true:
        windowManager.minimize();
        windowManager.setSkipTaskbar(false);
        break;
    }
  }
  return null;
}

Listener _mainContent() => Listener(
  onPointerDown: onMainPointerDown,
  child: Scaffold(
    resizeToAvoidBottomInset: false,
    body: Column(
      children: [
        if (isWindows) const _WindowsTitleBar(),
        Expanded(
          // 防止页面内容/转场绘制溢出到标题栏区域。
          child: ClipRect(
          child: Navigator(
            key: innerKey,
            initialRoute: RouteName.defaultPage,
            observers: [heroineController, feedbackRouteObserver],
            onGenerateRoute: (RouteSettings settings) {
              final feedbackRoute = buildFeedbackRoute(settings);
              if (feedbackRoute != null) return feedbackRoute;
              WidgetBuilder builder;
              switch (settings.name) {
                case RouteName.defaultPage:
                  // 在函数内部定义默认页面
                  if (globalHorizon) {
                    builder = (context_in_1) {
                      return Scaffold(
                        body: OverHeroineScope(
                          child: Column(
                            children: [
                              OverHeroine(
                                keepDir: KeepDir.bottom,
                                child: Container(
                                  height: 40,
                                  child: Stack(
                                    children: [
                                      Positioned(
                                        top: 0,
                                        right: 100,
                                        left: 0,
                                        child: Container(
                                          height: 40,
                                          child: AnimatedTabBarWidget(
                                            pageController: homeController
                                                .pageControllerHorizon,
                                            tabLabels:
                                                supportShowPlaylistProvidersH
                                                    .map(
                                                      (platform) => TextSpan(
                                                        text: platform
                                                            .shortDisplayName,
                                                      ),
                                                    )
                                                    .toList(),
                                            containerHeight: 40,
                                            spacing: 0,
                                          ),
                                        ),
                                      ),

                                      Positioned(
                                        top: 0,
                                        bottom: 0,
                                        right: 20,
                                        child: Center(
                                          child: Obx(
                                          // filterButton 隐藏时仍会保留内容，
                                          // 这样淡出才有东西可以淡（见 filterButton 注释）。
                                          () => AnimatedOpacity(
                                            opacity: homeController.showFilter
                                                ? 1.0
                                                : 0.0,
                                            duration: const Duration(
                                              milliseconds: 300,
                                            ),
                                            child: filterButton,
                                          ),
                                        ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Expanded(
                                child: PreloadPageView.builder(
                                  physics: BouncingScrollPhysics(),
                                  controller: homeController
                                      .pageControllerHorizon, // 使用 PageController
                                  itemCount: supportShowPlaylistProvidersH
                                      .length, // 页面数量
                                  preloadPagesCount:
                                      supportShowPlaylistProvidersH.length,

                                  itemBuilder: (context, index) {
                                    // 其他页面：动态生成
                                    return Obx(() {
                                      return PlaylistPage(
                                        source:
                                            supportShowPlaylistProvidersH[index],
                                        key: ValueKey(
                                          '${supportShowPlaylistProvidersH[index].name}${supportShowPlaylistProvidersH[index].nowSelectedPlaylistFilter.value.id}',
                                        ),
                                      );
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    };
                    break;
                  } else {
                    //竖屏
                    builder = (context_in_1) {
                      return Scaffold(
                        appBar: AppBar(
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Listen1'),
                              10.sbw,
                              Expanded(
                                child: ValueListenableBuilder<String?>(
                                  valueListenable:
                                      startupTipsService.searchHint,
                                  builder: (context, tip, _) => Obx(
                                    () => TextField(
                                      decoration: InputDecoration(
                                        hintText: _searchHintText(tip),
                                        border: InputBorder.none,
                                      ),
                                      controller: input_text_Controller,
                                      readOnly: true,
                                      onTap: () async {
                                        Get.toNamed(
                                          RouteName.searchPage,
                                          id: 1,
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                              WebSocketHelper.buildReactiveButton(
                                tooltip: "WebSocket服务器",
                                inMainPage: true,
                              ),
                              WebSocketClientHelper.buildReactiveButton(
                                tooltip: "WebSocket客户端",
                                inMainPage: true,
                              ),
                              IconButton(
                                tooltip: "设置",
                                icon: const FeedbackUnreadBadge(child: Icon(Icons.settings)),
                                onPressed: () {
                                  Get.toNamed(RouteName.settingsPage, id: 1);
                                },
                              ),
                            ],
                          ),
                        ),
                        body: OverHeroineScope(
                          child: Column(
                            children: [
                              SizedBox(
                                height: 45,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: AnimatedTabBarWidget(
                                        pageController: homeController
                                            .pageControllerPortrait,
                                        tabLabels: supportShowPlaylistProviders
                                            .map(
                                              (provider) => TextSpan(
                                                text: provider.shortDisplayName,
                                              ),
                                            )
                                            .toList(),
                                        containerHeight: 45,
                                        spacing: 0,
                                      ),
                                    ),
                                    Obx(
                                      () => AnimatedSize(
                                        // 不要加 key：状态一变 key 就变，
                                        // State 会被重建，尺寸动画会退化成瞬间跳变。
                                        duration: const Duration(
                                          milliseconds: 300,
                                        ),
                                        // 贴住右边缘，收起/展开时像是从右侧滑出。
                                        alignment: Alignment.centerRight,
                                        // 必须能在隐藏时真的收成 0 宽度，否则占位不会变化。
                                        child: homeController.showFilter
                                            ? filterButton
                                            : const SizedBox.shrink(),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // 长灰色细分割线
                              OverHeroine(
                                keepDir: KeepDir.bottom,
                                child: Divider(
                                  height: 1,
                                  color: Colors.grey[300],
                                ),
                              ),
                              Expanded(
                                child: PreloadPageView.builder(
                                  physics: BouncingScrollPhysics(),
                                  controller: homeController
                                      .pageControllerPortrait, // 使用 PageController
                                  itemCount: supportShowPlaylistProviders
                                      .length, // 页面数量
                                  preloadPagesCount:
                                      supportShowPlaylistProviders.length,

                                  itemBuilder: (context, index) {
                                    final provider =
                                        supportShowPlaylistProviders[index];
                                    if (provider.isLocal) {
                                      return MyPlaylist();
                                    } else {
                                      return PlaylistPage(
                                        source: provider,
                                        key: Key(provider.name),
                                      );
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    };
                    break;
                  }
                case RouteName.searchPage:
                  var route = ThemedGetPageRoute(
                    settings: settings,
                    page: () => Searchlistinfo(),
                    transition: Transition.upToDown,
                    middlewares: [ListenPopMiddleware()],
                  );
                  addAndCleanReapeatRoute(route, RouteName.searchPage);
                  return route;
                case RouteName.settingsPage:
                  var route = ThemedGetPageRoute(
                    settings: settings,
                    page: () => SettingsPage(),
                    middlewares: [ListenPopMiddleware()],
                  );
                  addAndCleanReapeatRoute(route, RouteName.settingsPage);
                  return route;
                case RouteName.nowPlayingPage:
                  var route = ThemedGetPageRoute(
                    settings: settings,
                    transition: Transition.downToUp,
                    // Transition.noTransition,
                    page: () => NowPlayingPage(),
                    middlewares: [ListenPopMiddleware()],
                  );
                  addAndCleanReapeatRoute(route, RouteName.nowPlayingPage);
                  return route;
                case RouteName.lyricPage:
                  var route = ThemedGetPageRoute(
                    settings: settings,
                    transition: Transition.downToUp,
                    page: () => LyricPage(),
                    middlewares: [ListenPopMiddleware()],
                  );
                  addAndCleanReapeatRoute(route, RouteName.lyricPage);
                  return route;
                case RouteName.settingsChangelogPage:
                  var route = ThemedGetPageRoute(
                    settings: settings,
                    transition: Transition.rightToLeftWithFade,
                    page: () => const SettingsChangelogPage(),
                    middlewares: [ListenPopMiddleware()],
                  );
                  addAndCleanReapeatRoute(route, RouteName.settingsChangelogPage);
                  return route;
                case RouteName.settingsReadmePage:
                  var route = ThemedGetPageRoute(
                    settings: settings,
                    transition: Transition.rightToLeftWithFade,
                    page: () => SettingsReadmePage(),
                    middlewares: [ListenPopMiddleware()],
                  );
                  addAndCleanReapeatRoute(route, RouteName.settingsReadmePage);
                  return route;
                case RouteName.settingsTipsPage:
                  var route = ThemedGetPageRoute(
                    settings: settings,
                    transition: Transition.rightToLeftWithFade,
                    page: () => const SettingsTipsPage(),
                    middlewares: [ListenPopMiddleware()],
                  );
                  addAndCleanReapeatRoute(route, RouteName.settingsTipsPage);
                  return route;
                case RouteName.downloadPage:
                  var route = ThemedGetPageRoute(
                    settings: settings,
                    transition: Transition.rightToLeftWithFade,
                    page: () => DownloadPage(),
                    middlewares: [ListenPopMiddleware()],
                  );
                  addAndCleanReapeatRoute(route, RouteName.downloadPage);
                  return route;
                case RouteName.supabaseLoginPage:
                  var route = ThemedGetPageRoute(
                    settings: settings,
                    transition: Transition.rightToLeftWithFade,
                    page: () => SupabaseLoginPage(),
                    middlewares: [ListenPopMiddleware()],
                  );
                  addAndCleanReapeatRoute(route, RouteName.supabaseLoginPage);
                  return route;
                case RouteName.supabasePasswordLoginPage:
                  var route = ThemedGetPageRoute(
                    settings: settings,
                    transition: Transition.rightToLeftWithFade,
                    page: () => SupabasePasswordLoginPage(),
                    middlewares: [ListenPopMiddleware()],
                  );
                  addAndCleanReapeatRoute(
                    route,
                    RouteName.supabasePasswordLoginPage,
                  );
                  return route;
                case RouteName.cacheNamingPage:
                  var route = ThemedGetPageRoute(
                    settings: settings,
                    transition: Transition.rightToLeftWithFade,
                    page: () => CacheNamingPage(),
                    middlewares: [ListenPopMiddleware()],
                  );
                  addAndCleanReapeatRoute(route, RouteName.cacheNamingPage);
                  return route;
                case RouteName.equalizerPage:
                  var route = ThemedGetPageRoute(
                    settings: settings,
                    transition: Transition.rightToLeftWithFade,
                    page: () => AndroidEqualizerPage(),
                    middlewares: [ListenPopMiddleware()],
                  );
                  addAndCleanReapeatRoute(route, RouteName.equalizerPage);
                  return route;
                case RouteName.songReplacePage:
                  var route = ThemedGetPageRoute(
                    settings: settings,
                    page: () => SongReplacePage(),
                    middlewares: [ListenPopMiddleware()],
                  );
                  addAndCleanReapeatRoute(route, RouteName.songReplacePage);
                  return route;
                default:
                  final args = settings.arguments is PlaylistInfoArgs
                      ? settings.arguments as PlaylistInfoArgs
                      : null;
                  if (args == null) throw 'unknown route $settings';
                  var route = ThemedGetPageRoute(
                    settings: settings,
                    binding: PlaylistInfoBinding(args: args),
                    page: () => PlaylistInfoPage(args: args),
                    middlewares: [ListenPopMiddleware()],
                  );
                  addAndCleanReapeatRoute(route, settings.name!);
                  return route;
              }
              return MaterialPageRoute(
                builder: (context) => PopScope(
                  // The default route must stay in the nested navigator. This
                  // passive scope also keeps Android back dispatch in Flutter
                  // so the root scope can forward it to routerPop().
                  canPop: false,
                  child: builder(context),
                ),
              );
            },
          ),
          ),
        ),
      ],
    ),
  ),
);
