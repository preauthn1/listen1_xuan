part of '../bodys.dart';

class MyPlaylist extends StatefulWidget {
  MyPlaylist({super.key});

  @override
  State<MyPlaylist> createState() => _MyPlaylistState();
}

class _MyPlaylistState extends State<MyPlaylist> {
  bool _isExpandedMy = true;
  bool _isExpandedFav = false;

  /// 平台一级分组（B 站 / 网易云 / QQ 音乐 / 酷狗音乐）的展开状态，key 为 provider.name。
  /// 没记录时：已登录展开，未登录收起。
  final Map<String, bool> _platformExpanded = {};

  @override
  void initState() {
    super.initState();
    // 平台的登录状态原本只在展开某个分组时才去查，所以「为你推荐」要先点一下平台才出现。
    // 有凭据的平台启动时就查一次；没有凭据的不发请求。
    for (final p in providers) {
      if (p.supportLogin &&
          p.token.isNotEmpty &&
          p.loginStatus.value == LoginStatus.noLogin) {
        unawaited(p.getUser());
      }
    }
  }

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
    bool? expanded,
  }) {
    final iconOnly = _isIconOnlyMode(availableWidth);
    // 可展开的分组在标题后显示展开箭头，否则看不出平台下面还有二级内容。
    final showChevron = expanded != null && !iconOnly;
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
                right: (_hasRoomForSectionTrailing(availableWidth) ? 40 : 0) +
                    (showChevron ? 24 : 0),
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
              if (showChevron)
                Positioned(
                  // 所有分组的箭头放在同一列：没有刷新按钮的分组也留出按钮宽度。
                  right: _hasRoomForSectionTrailing(availableWidth) ? 40 : 0,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: duration,
                      curve: Curves.easeInOut,
                      child: Icon(
                        Icons.expand_more_rounded,
                        size: 20,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
        throw const _SectionLoadError('未登录', needsLogin: true);
      }
      final playlists = await _fetchUserPlaylists(provider, type, user.userId);

      if (!mounted) return;
      setState(() {
        section.playlists = playlists;
        section.loaded = true;
        section.loading = false;
        section.error = null;
        section.errorNeedsLogin = false;
      });
    } catch (e) {
      logger.e('${_sectionTitleOf(provider, type)}加载失败', error: e);
      if (!mounted) return;
      setState(() {
        section.loading = false;
        section.error = e is _SectionLoadError ? e.message : '加载失败，请稍后重试';
        section.errorNeedsLogin = e is _SectionLoadError && e.needsLogin;
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

  /// 平台分组里的二级标题，如「我创建的」「追更合集」。
  String _subSectionTitleOf(BaseProvider provider, _UserPlaylistType type) =>
      _splitSectionTitle(_sectionTitleOf(provider, type)).$2;

  /// 二级分组不再重复平台图标，用列表图标区分「创建」与「收藏」。
  Widget _sectionLeadingOf(BaseProvider provider, _UserPlaylistType type) {
    return Icon(
      type == _UserPlaylistType.created
          ? Icons.queue_music_rounded
          : Icons.bookmark_border_rounded,
      size: 18,
    );
  }

  /// 分组为空时的一行说明，与分组标题文字左缘对齐。
  Widget _buildSectionHint(String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(48, 0, 12, 8),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildSectionError(
    String error,
    VoidCallback? onRetry, {
    bool needsLogin = false,
  }) {
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
          // 窄侧栏会隐藏分组标题的刷新按钮，这里保留一个就地入口：
          // 未登录时去设置页登录（重试不能解决），其它错误就地重试。
          if (needsLogin || onRetry != null)
            TextButton(
              onPressed: needsLogin
                  ? () => openInnerPage(RouteName.settingsPage)
                  : onRetry,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                textStyle: theme.textTheme.bodySmall,
              ),
              child: Text(needsLogin ? '去登录' : '重试'),
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
      title: _subSectionTitleOf(provider, type),
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
        needsLogin: section.errorNeedsLogin,
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
    Key? key,
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
      key: key,
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
              expanded: ExpandableController.of(context, required: true)!.expanded,
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

  /// 各平台登录后才有的推荐入口，放在平台分组里排在歌单前面。
  List<({IconData icon, String title, String subtitle, String id})> _recommendsOf(
    BaseProvider provider,
  ) {
    switch (provider.name) {
      case 'netease':
        return const [
          (icon: Icons.today_rounded, title: '每日推荐', subtitle: '每天 6 点更新', id: 'nedaily_today'),
          (icon: Icons.radio_rounded, title: '私人 FM', subtitle: '按口味连续推荐', id: 'nefm_personal'),
        ];
      case 'qq':
        return const [
          (icon: Icons.radar_rounded, title: '雷达推荐', subtitle: '按口味推荐的歌曲', id: 'qqradar_today'),
          (icon: Icons.radio_rounded, title: '个性电台', subtitle: '猜你喜欢，连续播放', id: 'qqradio_personal'),
        ];
      case 'kugou':
        return const [
          (icon: Icons.today_rounded, title: '每日推荐', subtitle: '每天更新', id: 'kgdaily_today'),
          (icon: Icons.radio_rounded, title: '私人 FM', subtitle: '按口味连续推荐', id: 'kgfm_personal'),
        ];
    }
    return const [];
  }

  /// 「网易云 · 我创建的」→ 平台名「网易云」与二级标题「我创建的」。
  static (String, String) _splitSectionTitle(String title) {
    final i = title.indexOf(' · ');
    if (i < 0) return (title, title);
    return (title.substring(0, i), title.substring(i + 3));
  }

  /// 二级内容的缩进；只显示图标的窄侧栏不缩进。
  double _childIndent(double width) =>
      _isIconOnlyMode(width) ? 0 : (_isCompactMode(width) ? 8 : 16);

  void _refreshPlatform(BaseProvider provider) {
    unawaited(provider.getUser());
    for (final type in _UserPlaylistType.values) {
      final section = _sectionOf(provider, type);
      if (section.loaded || section.isExpanded) {
        _refreshProviderPlaylists(provider, type);
      }
    }
  }

  /// 一级：平台。二级：推荐入口、我创建的、我收藏的（歌单分组可再展开）。
  Widget _buildPlatformGroup(BaseProvider provider, double availableWidth) {
    final platformName = _splitSectionTitle(
      provider.userCreatedPlaylistSectionTitle,
    ).$1;
    return Obx(() {
      final status = provider.loginStatus.value;
      final loggedIn = status == LoginStatus.loggedIn;
      final expanded = _platformExpanded[provider.name] ?? loggedIn;
      final indent = _childIndent(availableWidth);
      final Widget body;
      if (provider.supportLogin && status == LoginStatus.processing) {
        body = Center(child: globalLoadingAnime);
      } else if (provider.supportLogin && status == LoginStatus.failed) {
        body = _buildSectionError('登录状态获取失败', () => provider.getUser());
      } else if (provider.supportLogin && !loggedIn) {
        body = _buildSectionError('未登录', null, needsLogin: true);
      } else {
        body = Padding(
          padding: EdgeInsetsDirectional.only(start: indent),
          child: Column(
            children: [
              for (final r in _recommendsOf(provider))
                _buildShortcutTile(
                  icon: r.icon,
                  title: r.title,
                  subtitle: r.subtitle,
                  availableWidth: availableWidth - indent,
                  onTap: () => Ro.toArg(PlaylistInfoArgs(
                    playListInfo: PlayListInfo(id: r.id, title: r.title),
                    isMy: false,
                  )),
                ),
              if (provider.supportGetUserCreatedPlaylist)
                _buildProviderSection(
                  provider,
                  _UserPlaylistType.created,
                  availableWidth - indent,
                ),
              if (provider.supportGetUserFavoritePlaylist)
                _buildProviderSection(
                  provider,
                  _UserPlaylistType.favorite,
                  availableWidth - indent,
                ),
            ],
          ),
        );
      }
      return _buildExpandableSection(
        // 登录状态变化会改变默认展开状态，用 key 让展开控件跟着重建。
        key: ValueKey(
          'platform_${provider.name}_'
          '${_platformExpanded.containsKey(provider.name) ? 'user' : loggedIn}',
        ),
        leading: provider.userCreatedPlaylistSectionLeading,
        title: platformName,
        isExpanded: expanded,
        availableWidth: availableWidth,
        trailing: IconButton(
          icon: const Icon(Icons.refresh, size: 18),
          tooltip: '刷新',
          onPressed: () => _refreshPlatform(provider),
        ),
        onLongPress: () => _refreshPlatform(provider),
        onExpandedChanged: (value) {
          setState(() => _platformExpanded[provider.name] = value);
        },
        body: body,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final settingsController = Get.find<SettingsController>();
    final routeController = Get.find<RouteController>();

    return Obx(
      () => Scaffold(
        // 横屏布局（含桌面）里侧栏较窄，浮动按钮会压住平台行右侧的刷新按钮；
        // 此时由侧栏底部操作栏提供同一入口，浮动按钮只用于竖屏。
        // 桌面端窗口变窄进入竖屏布局时同理：浮动按钮会压住平台行右侧的刷新按钮，
        // 入口改到顶部栏（见 main_widgets.dart 竖屏头部）。手机竖屏保留可配置的浮动按钮。
        floatingActionButton: MediaQuery.orientationOf(context) == Orientation.landscape ||
                isDesktop
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
                          body: Obx(() {
                            final lists = Get.find<MyPlayListController>()
                                .playerlists
                                .values
                                .toList();
                            // 展开后没有内容时给一行说明，否则箭头翻转了却什么都没出现。
                            if (lists.isEmpty) {
                              return _buildSectionHint('还没有创建歌单');
                            }
                            return Column(
                              children: lists
                                  .map(
                                    (playlist) => _buildPlaylistTile(
                                      playlist: playlist,
                                      isMy: true,
                                      availableWidth: availableWidth,
                                    ),
                                  )
                                  .toList(),
                            );
                          }),
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
                          body: Obx(() {
                            final lists = Get.find<MyPlayListController>()
                                .favoriteplayerlists
                                .values
                                .toList();
                            if (lists.isEmpty) {
                              return _buildSectionHint('还没有收藏歌单');
                            }
                            return Column(
                              children: lists
                                  .map(
                                    (playlist) => _buildPlaylistTile(
                                      playlist: playlist,
                                      isMy: false,
                                      availableWidth: availableWidth,
                                    ),
                                  )
                                  .toList(),
                            );
                          }),
                        ),
                        for (final p in providers)
                          if (p.supportGetUserCreatedPlaylist ||
                              p.supportGetUserFavoritePlaylist)
                            _buildPlatformGroup(p, availableWidth),
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
  const _SectionLoadError(this.message, {this.needsLogin = false});
  final String message;
  final bool needsLogin;
  @override
  String toString() => message;
}

class _ProviderPlaylistSection {
  bool isExpanded = false;
  bool loaded = false;
  bool loading = false;
  String? error;
  bool errorNeedsLogin = false;
  List<PlayList> playlists = [];
}

enum _UserPlaylistType { created, favorite }
