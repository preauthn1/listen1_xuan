part of '../bodys.dart';

class MyPlaylist extends StatefulWidget {
  MyPlaylist({super.key});

  @override
  State<MyPlaylist> createState() => _MyPlaylistState();
}

class _MyPlaylistState extends State<MyPlaylist> {
  bool _isExpandedMy = true;
  bool _isExpandedFav = false;
  bool _isExpandedRecommend = true;
  bool _isExpandedKugouRecommend = true;
  bool _isExpandedQQRecommend = true;

  /// 各平台“我的歌单”分组的加载状态，key 为 provider.name。
  final Map<String, _ProviderPlaylistSection> _providerSections = {};

  bool _isIconOnlyMode(double width) => width <= 90;

  bool _isCompactMode(double width) => width <= 220;

  /// 宽度至少达到该值时，分组标题栏才有空间放下右侧的刷新按钮。
  static const double _minWidthForSectionTrailing = 150;

  bool _hasRoomForSectionTrailing(double width) =>
      width >= _minWidthForSectionTrailing;

  double _coverSize(double width) {
    return 50;
  }

  Widget _buildCoverFallbackText(String text, double size) {
    final content = text.trim().isEmpty ? '歌单' : text;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      padding: EdgeInsets.all(size <= 34 ? 2 : 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        content,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: size <= 34 ? 8 : 10,
          height: 1.1,
          color: Colors.grey.shade800,
        ),
      ),
    );
  }

  Widget _buildPlaylistCover({
    required PlayList playList,
    required String title,
    required String? coverUrl,
    required double size,
  }) {
    if (coverUrl == null || coverUrl.isEmpty) {
      return _buildCoverFallbackText(title, size);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: ExtendedImage.network(
        coverUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cache: true,
        loadStateChanged: (state) {
          if (state.extendedImageLoadState == LoadState.loading) {
            return globalLoadingAnimeOfExtendedImage;
          }
          if (state.extendedImageLoadState == LoadState.failed) {
            return _buildCoverFallbackText(title, size);
          }
          return null;
        },
      ).hero4playlistItemImg(playList.info),
    );
  }

  Future<void> _openPlaylist(PlayList playlist, {required bool isMy}) async {
    await Ro.toArg(PlaylistInfoArgs(playListInfo: playlist.info, isMy: isMy));
  }

  Widget _buildPlaylistTile({
    required PlayList playlist,
    required bool isMy,
    required double availableWidth,
  }) {
    final iconOnly = _isIconOnlyMode(availableWidth);
    final compact = _isCompactMode(availableWidth);
    final title = playlist.info.title ?? '';
    final cover = _buildPlaylistCover(
      playList: playlist,
      title: title,
      coverUrl: playlist.info.cover_img_url,
      size: _coverSize(availableWidth),
    );

    const sizeHeight = 56.0;
    final horizontalPadding = compact ? 8.0 : 12.0;
    final spacing = compact ? 8.0 : 12.0;
    const duration = Duration(milliseconds: 220);

    return Tooltip(
      message: title,
      child: InkWell(
        onTap: () => _openPlaylist(playlist, isMy: isMy),
        child: AnimatedPadding(
          duration: duration,
          curve: Curves.easeInOut,
          padding: EdgeInsets.symmetric(
            horizontal: iconOnly ? 0.0 : horizontalPadding,
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedAlign(
                  duration: duration,
                  curve: Curves.easeInOut,
                  alignment: iconOnly ? Alignment.center : Alignment.centerLeft,
                  child: Center(child: cover).sbw(sizeHeight),
                ),
              ),
              Positioned.fill(
                left: sizeHeight + spacing,
                child: IgnorePointer(
                  ignoring: iconOnly,
                  child: AnimatedOpacity(
                    duration: duration,
                    curve: Curves.easeInOut,
                    opacity: iconOnly ? 0.0 : 1.0,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ).sbh(sizeHeight),
      ),
    );
  }

  /// 「为你推荐」里的入口行：与歌单行同高，用图标块代替封面。
  Widget _buildShortcutTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required double availableWidth,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final iconOnly = _isIconOnlyMode(availableWidth);
    final compact = _isCompactMode(availableWidth);
    final size = _coverSize(availableWidth);
    const sizeHeight = 56.0;
    final badge = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, size: 24, color: theme.colorScheme.onPrimaryContainer),
    );
    return Tooltip(
      message: title,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: iconOnly ? 0.0 : (compact ? 8.0 : 12.0),
          ),
          child: iconOnly
              ? Center(child: badge)
              : Row(
                  children: [
                    SizedBox(width: sizeHeight, child: Center(child: badge)),
                    SizedBox(width: compact ? 8.0 : 12.0),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          if (!compact)
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
        ).sbh(sizeHeight),
      ),
    );
  }

  Widget _buildSectionHeader({
    required Widget leading,
    required String title,
    required VoidCallback onTap,
    required double availableWidth,
    bool centerLeadingWhenIconOnly = false,
    Widget? trailing,
    VoidCallback? onLongPress,
  }) {
    final iconOnly = _isIconOnlyMode(availableWidth);
    final compact = _isCompactMode(availableWidth);
    // 页面过窄时隐藏刷新按钮，此时可长按整条标题栏刷新。
    final showTrailing =
        trailing != null && _hasRoomForSectionTrailing(availableWidth);
    final shouldCenterLeading = iconOnly && centerLeadingWhenIconOnly;
    final horizontalPadding = shouldCenterLeading
        ? 0.0
        : (iconOnly ? 6.0 : (compact ? 8.0 : 12.0));
    final leadingWidth = iconOnly ? 18.0 : 24.0;
    final spacing = compact ? 8.0 : 12.0;
    const duration = Duration(milliseconds: 220);

    return Tooltip(
      // 窄屏时刷新按钮会被隐藏，这里顺便提示长按可刷新。
      message: onLongPress == null ? title : '$title（长按刷新）',
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedPadding(
          duration: duration,
          curve: Curves.easeInOut,
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedAlign(
                  duration: duration,
                  curve: Curves.easeInOut,
                  alignment: shouldCenterLeading
                      ? Alignment.center
                      : Alignment.centerLeft,
                  child: Center(child: leading).sbw(leadingWidth),
                ),
              ),
              Positioned.fill(
                left: leadingWidth + spacing,
                right: showTrailing ? 40 : 0,
                child: IgnorePointer(
                  ignoring: iconOnly,
                  child: AnimatedOpacity(
                    duration: duration,
                    curve: Curves.easeInOut,
                    opacity: iconOnly ? 0.0 : 1.0,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 14 : 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (showTrailing)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: Center(child: trailing),
                ),
            ],
          ),
        ).sbh(compact ? 44 : 48),
      ),
    );
  }

  _ProviderPlaylistSection _sectionOf(
    BaseProvider provider,
    _UserPlaylistType type,
  ) {
    return _providerSections.putIfAbsent(
      '${provider.name}_${type.name}',
      () => _ProviderPlaylistSection(),
    );
  }

  Future<List<PlayList>> _fetchUserPlaylists(
    BaseProvider provider,
    _UserPlaylistType type,
    String userId,
  ) async {
    final future = type == _UserPlaylistType.created
        ? provider.getUserCreatedPlaylist(userId)
        : provider.getUserFavoritePlaylist(userId);
    if (future == null) {
      throw const _SectionLoadError('该平台暂不支持此歌单');
    }
    return future;
  }

  Future<void> _loadProviderPlaylists(
    BaseProvider provider,
    _UserPlaylistType type, {
    bool force = false,
  }) async {
    final section = _sectionOf(provider, type);
    if (section.loading) return;
    if (section.loaded && !force) return;

    setState(() {
      section.loading = true;
      section.error = null;
    });

    try {
      final user = await provider.getUser();
      if (user == null) {
        throw const _SectionLoadError('未登录，可在设置中登录');
      }
      final playlists = await _fetchUserPlaylists(provider, type, user.userId);

      if (!mounted) return;
      setState(() {
        section.playlists = playlists;
        section.loaded = true;
        section.loading = false;
        section.error = null;
      });
    } catch (e) {
      logger.e('${_sectionTitleOf(provider, type)}加载失败', error: e);
      if (!mounted) return;
      setState(() {
        section.loading = false;
        section.error = e is _SectionLoadError ? e.message : '加载失败，请稍后重试';
      });
    }
  }

  void _refreshProviderPlaylists(
    BaseProvider provider,
    _UserPlaylistType type,
  ) {
    _loadProviderPlaylists(provider, type, force: true);
  }

  String _sectionTitleOf(BaseProvider provider, _UserPlaylistType type) {
    return type == _UserPlaylistType.created
        ? provider.userCreatedPlaylistSectionTitle
        : provider.userFavoritePlaylistSectionTitle;
  }

  Widget _sectionLeadingOf(BaseProvider provider, _UserPlaylistType type) {
    return type == _UserPlaylistType.created
        ? provider.userCreatedPlaylistSectionLeading
        : provider.userFavoritePlaylistSectionLeading;
  }

  Widget _buildSectionError(String error, VoidCallback? onRetry) {
    final theme = Theme.of(context);
    // 与分组标题文字左缘对齐（12 + 24 图标 + 12 间距），不再居中打断列表节奏。
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(48, 0, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              error,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          // 窄侧栏会隐藏分组标题的刷新按钮，这里保留一个就地重试入口。
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                textStyle: theme.textTheme.bodySmall,
              ),
              child: const Text('重试'),
            ),
        ],
      ),
    );
  }

  Widget _buildProviderSection(
    BaseProvider provider,
    _UserPlaylistType type,
    double availableWidth,
  ) {
    final section = _sectionOf(provider, type);
    return _buildExpandableSection(
      leading: _sectionLeadingOf(provider, type),
      title: _sectionTitleOf(provider, type),
      isExpanded: section.isExpanded,
      availableWidth: availableWidth,
      trailing: IconButton(
        icon: const Icon(Icons.refresh, size: 18),
        tooltip: '刷新',
        onPressed: () => _refreshProviderPlaylists(provider, type),
      ),
      // 长按整条标题栏会展开并刷新（页面过窄时按钮会被隐藏）。
      onLongPress: () => _refreshProviderPlaylists(provider, type),
      onExpandedChanged: (expanded) {
        setState(() {
          section.isExpanded = expanded;
        });
        if (expanded) {
          _loadProviderPlaylists(provider, type);
        }
      },
      body: _buildProviderSectionBody(section, availableWidth, provider, type),
    );
  }

  Widget _buildProviderSectionBody(
    _ProviderPlaylistSection section,
    double availableWidth,
    BaseProvider provider,
    _UserPlaylistType type,
  ) {
    if (section.loading) {
      return Center(child: globalLoadingAnime);
    }
    if (section.error != null) {
      return _buildSectionError(
        section.error!,
        () => _refreshProviderPlaylists(provider, type),
      );
    }
    return Column(
      children: section.playlists
          .map(
            (playlist) => _buildPlaylistTile(
              playlist: playlist,
              isMy: false,
              availableWidth: availableWidth,
            ),
          )
          .toList(),
    );
  }

  /// 长按标题栏：先展开（若未展开），再执行刷新。
  void _handleSectionLongPress(
    ExpandableController controller,
    ValueChanged<bool> onExpandedChanged,
    VoidCallback onRefresh,
  ) {
    if (!controller.expanded) {
      controller.expanded = true;
      // 这里只是展开，真正的加载交给紧随其后的强制刷新。
      onExpandedChanged(true);
    }
    onRefresh();
  }

  Widget _buildExpandableSection({
    required Widget leading,
    required String title,
    required bool isExpanded,
    required double availableWidth,
    required Widget body,
    required ValueChanged<bool> onExpandedChanged,
    Widget? trailing,
    VoidCallback? onLongPress,
  }) {
    final controller = ExpandableController(initialExpanded: isExpanded);
    final onRefresh = onLongPress;
    return ExpandableNotifier(
      controller: controller,
      child: Builder(
        builder: (context) {
          return ExpandablePanel(
            theme: const ExpandableThemeData(
              hasIcon: false,
              tapHeaderToExpand: false,
              tapBodyToCollapse: false,
              tapBodyToExpand: false,
              animationDuration: Duration(milliseconds: 180),
            ),
            header: _buildSectionHeader(
              leading: leading,
              title: title,
              availableWidth: availableWidth,
              centerLeadingWhenIconOnly: true,
              trailing: trailing,
              onLongPress: onRefresh == null
                  ? null
                  : () => _handleSectionLongPress(
                      controller,
                      onExpandedChanged,
                      onRefresh,
                    ),
              onTap: () {
                final nextExpanded = !controller.expanded;
                controller.expanded = nextExpanded;
                onExpandedChanged(nextExpanded);
              },
            ),
            collapsed: SizedBox.shrink(),
            expanded: body,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsController = Get.find<SettingsController>();
    final routeController = Get.find<RouteController>();

    return Obx(
      () => Scaffold(
        // 横屏布局（含桌面）里侧栏较窄，浮动按钮会压住平台行右侧的刷新按钮；
        // 此时由侧栏底部操作栏提供同一入口，浮动按钮只用于竖屏。
        floatingActionButton: MediaQuery.orientationOf(context) == Orientation.landscape
            ? null
            : FloatingActionButton(
          heroTag: HeroTags.songReplaceFab,
          mini: (isWindows &&
                  !settingsController.settings
                      .containsKey(SettingsController.songReplaceFabLocationKey)) ||
              settingsController.songReplaceFabMiniRx.value,
          onPressed: () {
            if (routeController.inSongReplacePage.value) {
              Get.back(id: 1);
              return;
            }
            Get.toNamed(RouteName.songReplacePage, id: 1);
          },
          tooltip: '歌曲替换列表',
          child: Icon(Icons.find_replace_rounded),
        ),
        // Windows 默认放在侧栏右下角并缩小，列表底部留白保证不压住最后一行。
        floatingActionButtonLocation: isWindows &&
                !settingsController.settings.containsKey(SettingsController.songReplaceFabLocationKey)
            ? FloatingActionButtonLocation.miniEndFloat
            : settingsController.songReplaceFabMiniRx.value
            ? settingsController.songReplaceFabLocation.fabMiniLocation
            : settingsController.songReplaceFabLocation.fabLocation,
        resizeToAvoidBottomInset: false,
        body: WidthLayoutBuilder(
          builder: (context, availableWidth) {
            return PageScrollToTop(
              builder: (context, pageScrollController, pageListController) =>
                  SingleChildScrollView(
                    controller: pageScrollController,
                    child: Column(
                      children: [
                        _buildExpandableSection(
                          leading: const Icon(Icons.library_music, size: 18),
                          title: '我创建的歌单',
                          isExpanded: _isExpandedMy,
                          availableWidth: availableWidth,
                          onExpandedChanged: (expanded) {
                            setState(() {
                              _isExpandedMy = expanded;
                            });
                          },
                          body: Obx(
                            () => Column(
                              children: Get.find<MyPlayListController>()
                                  .playerlists
                                  .values
                                  .toList()
                                  .map(
                                    (playlist) => _buildPlaylistTile(
                                      playlist: playlist,
                                      isMy: true,
                                      availableWidth: availableWidth,
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ),
                        _buildExpandableSection(
                          leading: const Icon(Icons.star, size: 18),
                          title: '我收藏的歌单',
                          isExpanded: _isExpandedFav,
                          availableWidth: availableWidth,
                          onExpandedChanged: (expanded) {
                            setState(() {
                              _isExpandedFav = expanded;
                            });
                          },
                          body: Obx(
                            () => Column(
                              children: Get.find<MyPlayListController>()
                                  .favoriteplayerlists
                                  .values
                                  .map(
                                    (playlist) => _buildPlaylistTile(
                                      playlist: playlist,
                                      isMy: false,
                                      availableWidth: availableWidth,
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ),
                        Obx(() {
                          final netease = providers.firstWhereOrNull(
                            (p) => p.name == 'netease',
                          );
                          if (netease == null ||
                              netease.loginStatus.value != LoginStatus.loggedIn) {
                            return const SizedBox.shrink();
                          }
                          return _buildExpandableSection(
                            leading: const Icon(Icons.auto_awesome_rounded, size: 18),
                            title: '网易云 · 为你推荐',
                            isExpanded: _isExpandedRecommend,
                            availableWidth: availableWidth,
                            onExpandedChanged: (expanded) {
                              setState(() => _isExpandedRecommend = expanded);
                            },
                            body: Column(
                              children: [
                                _buildShortcutTile(
                                  icon: Icons.today_rounded,
                                  title: '每日推荐',
                                  subtitle: '每天 6 点更新',
                                  availableWidth: availableWidth,
                                  onTap: () => Ro.toArg(PlaylistInfoArgs(
                                    playListInfo: PlayListInfo(
                                      id: 'nedaily_today',
                                      title: '每日推荐',
                                    ),
                                    isMy: false,
                                  )),
                                ),
                                _buildShortcutTile(
                                  icon: Icons.radio_rounded,
                                  title: '私人 FM',
                                  subtitle: '按口味连续推荐',
                                  availableWidth: availableWidth,
                                  onTap: () => Ro.toArg(PlaylistInfoArgs(
                                    playListInfo: PlayListInfo(
                                      id: 'nefm_personal',
                                      title: '私人 FM',
                                    ),
                                    isMy: false,
                                  )),
                                ),
                              ],
                            ),
                          );
                        }),
                        Obx(() {
                          final qq = providers.firstWhereOrNull(
                            (p) => p.name == 'qq',
                          );
                          if (qq == null ||
                              qq.loginStatus.value != LoginStatus.loggedIn) {
                            return const SizedBox.shrink();
                          }
                          return _buildExpandableSection(
                            leading: qq.loginIcon,
                            title: 'QQ 音乐 · 为你推荐',
                            isExpanded: _isExpandedQQRecommend,
                            availableWidth: availableWidth,
                            onExpandedChanged: (expanded) {
                              setState(() => _isExpandedQQRecommend = expanded);
                            },
                            body: Column(
                              children: [
                                _buildShortcutTile(
                                  icon: Icons.radar_rounded,
                                  title: '雷达推荐',
                                  subtitle: '按口味推荐的歌曲',
                                  availableWidth: availableWidth,
                                  onTap: () => Ro.toArg(PlaylistInfoArgs(
                                    playListInfo: PlayListInfo(
                                      id: 'qqradar_today',
                                      title: '雷达推荐',
                                    ),
                                    isMy: false,
                                  )),
                                ),
                                _buildShortcutTile(
                                  icon: Icons.radio_rounded,
                                  title: '个性电台',
                                  subtitle: '猜你喜欢，连续播放',
                                  availableWidth: availableWidth,
                                  onTap: () => Ro.toArg(PlaylistInfoArgs(
                                    playListInfo: PlayListInfo(
                                      id: 'qqradio_personal',
                                      title: '个性电台',
                                    ),
                                    isMy: false,
                                  )),
                                ),
                              ],
                            ),
                          );
                        }),
                        Obx(() {
                          final kugou = providers.firstWhereOrNull(
                            (p) => p.name == 'kugou',
                          );
                          if (kugou == null ||
                              kugou.loginStatus.value != LoginStatus.loggedIn) {
                            return const SizedBox.shrink();
                          }
                          return _buildExpandableSection(
                            leading: kugou.loginIcon,
                            title: '酷狗音乐 · 为你推荐',
                            isExpanded: _isExpandedKugouRecommend,
                            availableWidth: availableWidth,
                            onExpandedChanged: (expanded) {
                              setState(() => _isExpandedKugouRecommend = expanded);
                            },
                            body: Column(
                              children: [
                                _buildShortcutTile(
                                  icon: Icons.today_rounded,
                                  title: '每日推荐',
                                  subtitle: '每天更新',
                                  availableWidth: availableWidth,
                                  onTap: () => Ro.toArg(PlaylistInfoArgs(
                                    playListInfo: PlayListInfo(
                                      id: 'kgdaily_today',
                                      title: '每日推荐',
                                    ),
                                    isMy: false,
                                  )),
                                ),
                                _buildShortcutTile(
                                  icon: Icons.radio_rounded,
                                  title: '私人 FM',
                                  subtitle: '按口味连续推荐',
                                  availableWidth: availableWidth,
                                  onTap: () => Ro.toArg(PlaylistInfoArgs(
                                    playListInfo: PlayListInfo(
                                      id: 'kgfm_personal',
                                      title: '私人 FM',
                                    ),
                                    isMy: false,
                                  )),
                                ),
                              ],
                            ),
                          );
                        }),
                        ...providers.expand(
                          (p) => [
                            if (p.supportGetUserCreatedPlaylist)
                              _buildProviderSection(
                                p,
                                _UserPlaylistType.created,
                                availableWidth,
                              ),
                            if (p.supportGetUserFavoritePlaylist)
                              _buildProviderSection(
                                p,
                                _UserPlaylistType.favorite,
                                availableWidth,
                              ),
                          ],
                        ),
                        // 预留底部浮动按钮的位置，最后一个分组不会被遮住。
                        const SizedBox(height: 72),
                      ],
                    ),
                  ),
            );
          },
        ),
      ),
    );
  }
}

class _SectionLoadError implements Exception {
  const _SectionLoadError(this.message);
  final String message;
  @override
  String toString() => message;
}

class _ProviderPlaylistSection {
  bool isExpanded = false;
  bool loaded = false;
  bool loading = false;
  String? error;
  List<PlayList> playlists = [];
}

enum _UserPlaylistType { created, favorite }
