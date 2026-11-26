import 'package:listen1_xuan/widgets/page_scroll_to_top.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:listen1_xuan/provider/loweb.dart';
import 'package:listen1_xuan/widgets/ext/ext_widget.dart';
import 'package:super_sliver_list/super_sliver_list.dart';
import 'package:animated_reorderable_list/animated_reorderable_list.dart';
import '../bodys.dart';
import '../controllers/play_controller.dart';
import '../controllers/nowplaying_controller.dart';
import 'package:listen1_xuan/global_settings_animations.dart'
    show isDesktop;
import 'package:listen1_xuan/models/Track.dart';
import 'package:listen1_xuan/widgets/track_scrollbar.dart';

/// 播放列表行高。
///
/// 行高固定可以让 super_sliver_list 精确估算 extent（`extentEstimation` 返回同一个值），
/// 也支持用初始滚动偏移直接定位到当前播放项。
const double _kTrackRowHeight = 40;

/// 行内操作按钮（列表/删除）的总宽度：2 × (10 padding + 20 icon + 10 padding)。
/// 滚动时用同宽占位顶掉按钮，标题宽度不会跳。
const double _kTrackActionsWidth = 80;

/// 超过这个滚动速度就收起行内操作按钮（px/s）。
const double _kRowActionsHideSpeed = 1600;

/// 低于这个速度再显示回来（px/s）。与 hide 阈值构成滞回区间，
/// 避免速度上下拖动时反复重建。
const double _kRowActionsShowSpeed = 600;

/// 滚动停止（不再有滚动通知）后多久把按钮显示回来。
const int _kRowActionsSettleMs = 150;

/// 两次切换的最小间隔，避免速度跳动导致频繁 rebuild。
const int _kRowActionsFlipIntervalMs = 100;

/// 行文案（`标题 · 艺术家`）。在 itemBuilder 里算一次，行内不再拼字符串。
String _displayTextOf(Track track) =>
    '${track.title ?? '未知歌曲'} · ${track.artist ?? '未知艺术家'}';

class NowPlayingPage extends StatefulWidget {
  @override
  _NowPlayingPageState createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage>
    with SingleTickerProviderStateMixin {
  late NowPlayingPageController controller;
  late ScrollController scrollController;
  final ListController _listController = ListController();
  RxBool useReorderableList = false.obs;
  Worker? _searchQueryWorker;

  /// 当前播放曲目 id：单独广播给列表行，切歌时只重建状态真正变化的那一两行，
  /// 而不是让整个 `Obx`（含整份列表 widget）重建。
  late final ValueNotifier<String> _currentTrackId;
  Worker? _currentTrackIdWorker;

  /// 页面级唯一的标题浮层，替代“每行一个 [Tooltip]”。
  OverlayEntry? _titleTipEntry;
  Timer? _titleTipTimer;
  String? _titleTipText;
  Offset _titleTipAnchor = Offset.zero;

  /// 当前悬停的行（track id）。
  ///
  /// 行的 onEnter / onExit 先后顺序在不同 Flutter 版本/场景下并不保证，
  /// 用 id 做一次校验可以避免“新行的 enter 被旧行的 exit 取消”。
  String? _hoverTitleId;

  /// 行内操作按钮是否展开。
  ///
  /// 快速滚动时收起（只留 [_kTrackActionsWidth] 的同宽占位），
  /// 滚动变慢/停止后再淡入。两个按钮大约占一行成本的一半，而滚动过程中
  /// 几乎不可能去点它们，所以这一段是“白花”的。
  final ValueNotifier<bool> _rowActionsExpanded = ValueNotifier<bool>(true);

  /// 淡入用，所有行共享同一个动画（行内只是 FadeTransition，不会逐帧 rebuild）。
  late final AnimationController _rowActionsFade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    value: 1,
  );

  Timer? _rowActionsTimer;
  final Stopwatch _scrollClock = Stopwatch()..start();
  int _lastScrollMicros = 0;
  double _lastScrollPixels = 0;
  double _scrollSpeed = 0; // px/s（指数平滑）
  int _lastRowActionsFlipMicros = 0;

  @override
  void initState() {
    super.initState();
    controller = Get.find<NowPlayingPageController>();
    _currentTrackId = ValueNotifier<String>(controller.currentTrackId);
    _currentTrackIdWorker = ever<Track?>(
      controller.playController.nowPlayingTrackRx,
      (_) => _currentTrackId.value = controller.currentTrackId,
    );
    // 首帧就按已知行高定位到当前播放项附近，避免先构建列表顶部的窗口、
    // 再通过 jumpToItem 跳转导致同一帧内构建两批列表项。
    scrollController = ScrollController(
      initialScrollOffset: _initialScrollOffset(),
    );
    scrollController.addListener(_onScroll);
    controller.scrollToCurrentTrack = scrollToCurrentTrack;
    // 搜索条件变化后结果列表会被整体替换，旧偏移量对新列表没有意义：
    // 一旦偏移量超过新列表的最大可滚动距离，列表会先渲染成空白，再回弹滑入。
    _searchQueryWorker = ever<String>(controller.searchQuery, (query) {
      // 列表内容变了，行可能已经不在了，标题浮层直接收起
      _hideTitleTip();
      // 清空搜索时列表会变长，旧偏移量仍然有效，不需要回顶。
      if (!mounted || query.isEmpty) return;
      _resetScrollToTop();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 此时列表已经在目标位置附近，这里只是精确居中对齐（微调，不会批量新建子项）
      scrollToCurrentTrack(animated: false);
      controller.showScrollButton.value = false; // 初始化时隐藏按钮
    });
  }

  /// 把列表滚动回顶部。
  ///
  /// 需要在查询变化时同步调用一次（此时旧列表还在，jumpTo 不会先按旧偏移量
  /// 布局出一帧空白），并在帧结束后再调用一次：搜索结果为空时列表会被空状态
  /// 替换、滚动位置随之销毁，重新出现结果时会按 `initialScrollOffset` 重建。
  void _resetScrollToTop() {
    void jumpToTop() {
      if (!mounted || !scrollController.hasClients) return;
      final position = scrollController.position;
      if (position.pixels != position.minScrollExtent) {
        scrollController.jumpTo(position.minScrollExtent);
      }
    }

    jumpToTop();
    WidgetsBinding.instance.addPostFrameCallback((_) => jumpToTop());
  }

  /// super_sliver_list 在列表内容变化时会在布局阶段修正滚动偏移，默认的
  /// [RangeMaintainingScrollPhysics] 会因此跳过边界约束，让越界的偏移量走回弹
  /// 动画（列表先空白再缓慢滑入）。包内提供的 [SuperRangeMaintainingScrollPhysics]
  /// 会把修正后的位置立即夹回有效范围。
  ScrollPhysics _listPhysics(BuildContext context) {
    return SuperRangeMaintainingScrollPhysics(
      parent: ScrollConfiguration.of(context).getScrollPhysics(context),
    );
  }

  /// 用固定行高估算当前播放项的位置，作为首帧的初始滚动偏移。
  double _initialScrollOffset() {
    final playingList = controller.filteredPlayingList;
    final index = playingList.indexWhere(
      (track) => track.id == controller.currentTrackId,
    );
    if (index <= 0) return 0;
    return index * _kTrackRowHeight;
  }

  @override
  void dispose() {
    scrollController.removeListener(_onScroll);
    _searchQueryWorker?.dispose();
    _currentTrackIdWorker?.dispose();
    _currentTrackId.dispose();
    _hideTitleTip();
    _rowActionsTimer?.cancel();
    _rowActionsExpanded.dispose();
    _rowActionsFade.dispose();
    scrollController.dispose();
    controller.scrollToCurrentTrack = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 创建控制器实例
    // 获取主题
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: _buildScrollToCurrentButton(context, controller),
      body: Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor.withOpacity(0.95),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          children: [
            _buildHeader(context, controller),
            _buildSearchBar(context, controller),
            Expanded(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(physics: _listPhysics(context)),
                child: _buildPlayingList(context, controller),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onScroll() {
    // 滚动时行会移动，标题浮层不再跟随，直接收起
    if (_titleTipEntry != null || _titleTipTimer != null) _hideTitleTip();
    _trackScrollSpeed();
    // 使用 SuperSliverList 的 visibleRange API 判断当前播放歌曲是否在可视区域内
    if (scrollController.hasClients && _listController.isAttached) {
      final playingList = controller.filteredPlayingList;
      final currentTrackId = controller.currentTrackId;
      final currentIndex = playingList.indexWhere(
        (track) => track.id == currentTrackId,
      );

      if (currentIndex != -1) {
        final range = _listController.visibleRange;
        final isCurrentVisible =
            range != null &&
            currentIndex >= range.$1 &&
            currentIndex <= range.$2;

        controller.showScrollButton.value = !isCurrentVisible;
      }
    }
  }

  /// 估算滚动速度，并据此在“快速滚动”与“变慢”之间切换行内操作按钮。
  ///
  /// 带上滞回：超速立即收起，减速到 [_kRowActionsShowSpeed] 以下再显示；
  /// 彻底停下（不再有滚动通知）时由定时器兜底显示回来。
  void _trackScrollSpeed() {
    if (!scrollController.hasClients) return;
    final now = _scrollClock.elapsedMicroseconds;
    final pixels = scrollController.position.pixels;
    if (_lastScrollMicros != 0) {
      // 鼠标滚轮一档是瞬时跳变，把 dt 夹到 4ms 以上，避免算出天量速度
      final dt = math.max(
        (now - _lastScrollMicros) / Duration.microsecondsPerSecond,
        0.004,
      );
      final instant = (pixels - _lastScrollPixels).abs() / dt;
      _scrollSpeed = _scrollSpeed * 0.6 + instant * 0.4;
    }
    _lastScrollMicros = now;
    _lastScrollPixels = pixels;

    if (_scrollSpeed >= _kRowActionsHideSpeed) {
      _setRowActionsExpanded(false);
    } else if (_scrollSpeed <= _kRowActionsShowSpeed) {
      _setRowActionsExpanded(true);
    }

    _rowActionsTimer?.cancel();
    _rowActionsTimer = null;
    // 只有按钮处于收起状态才需要兜底定时器：滚动时每秒建 60 个 Timer 纯属浪费。
    if (!_rowActionsExpanded.value) {
      _rowActionsTimer = Timer(
        const Duration(milliseconds: _kRowActionsSettleMs),
        () {
          _scrollSpeed = 0;
          _rowActionsTimer = null;
          // 滚动已经停了，不会再有通知，这里绕过切换间隔限制，
          // 否则可能一直停在占位态。
          _lastRowActionsFlipMicros = 0;
          _setRowActionsExpanded(true);
        },
      );
    }
  }

  void _setRowActionsExpanded(bool expanded) {
    if (_rowActionsExpanded.value == expanded) return;
    final now = _scrollClock.elapsedMicroseconds;
    if (now - _lastRowActionsFlipMicros <
        _kRowActionsFlipIntervalMs * Duration.microsecondsPerMillisecond) {
      return;
    }
    _lastRowActionsFlipMicros = now;
    _rowActionsExpanded.value = expanded;
    if (expanded) {
      _rowActionsFade.forward(from: 0);
    } else {
      _rowActionsFade.value = 0;
    }
  }

  /// 鼠标进入/离开某一行（桌面端）时维护页面级唯一的标题浮层。
  ///
  /// 以前是每个列表行一个 [Tooltip]：每行都会建一个长按手势识别器、一个
  /// MouseRegion 和一个 Semantics 节点，滚动时这些对象要不断创建/销毁。
  void _onTrackHover(String id, String? text, Offset? globalPosition) {
    if (!isDesktop) return;
    if (text == null || globalPosition == null) {
      // 只响应当前行自己的离开事件
      if (_hoverTitleId == id) _hideTitleTip();
      return;
    }
    _hoverTitleId = id;
    _titleTipTimer?.cancel();
    _titleTipTimer = null;
    _titleTipText = text;
    _titleTipAnchor = globalPosition;
    // 与旧 Tooltip 的 waitDuration 保持一致
    _titleTipTimer = Timer(const Duration(milliseconds: 500), () {
      _titleTipTimer = null;
      if (!mounted || _titleTipText == null) return;
      _showTitleTip();
    });
  }

  void _showTitleTip() {
    if (_titleTipText == null) return;
    final entry = _titleTipEntry;
    if (entry != null) {
      entry.markNeedsBuild();
      return;
    }
    _titleTipEntry = OverlayEntry(builder: _buildTitleTip);
    Overlay.of(context, rootOverlay: true).insert(_titleTipEntry!);
  }

  Widget _buildTitleTip(BuildContext context) {
    final text = _titleTipText;
    if (text == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    const maxWidth = 420.0;
    final left = (_titleTipAnchor.dx + 12)
        .clamp(8.0, math.max(8.0, size.width - maxWidth - 8.0))
        .toDouble();
    final top = (_titleTipAnchor.dy + 20)
        .clamp(8.0, math.max(8.0, size.height - 56.0))
        .toDouble();
    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Container(
          constraints: const BoxConstraints(maxWidth: maxWidth),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.inverseSurface.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onInverseSurface,
            ),
          ),
        ),
      ),
    );
  }

  void _hideTitleTip() {
    _titleTipTimer?.cancel();
    _titleTipTimer = null;
    _titleTipText = null;
    _hoverTitleId = null;
    _titleTipEntry?.remove();
    _titleTipEntry = null;
  }

  void scrollToCurrentTrack({bool animated = true}) async {
    final playingList = controller.filteredPlayingList; // 使用过滤后的列表
    final currentTrackId = controller.currentTrackId;

    // 找到当前播放歌曲的索引
    final currentIndex = playingList.indexWhere(
      (track) => track.id == currentTrackId,
    );

    if (currentIndex != -1 &&
        scrollController.hasClients &&
        _listController.isAttached) {
      if (animated) {
        _listController.animateToItem(
          index: () => currentIndex,
          scrollController: scrollController,
          alignment: 0.5,
          duration: (_) => Duration(milliseconds: 500),
          curve: (_) => Curves.easeInOutSine,
          teleport: true,
          teleportThreshold: 1.2,
          approachFactor: 1.2,
          precalculateTargetItemCount: true,
        );
      } else {
        _listController.jumpToItem(
          index: currentIndex,
          scrollController: scrollController,
          alignment: 0.5,
        );
      }

      // 添加震动反馈
      HapticFeedback.lightImpact();
    }
  }

  Widget _buildHeader(
    BuildContext context,
    NowPlayingPageController controller,
  ) {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 16,
        left: 16,
        right: 16,
        bottom: 16,
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              Icons.keyboard_arrow_down,
              color: theme.textTheme.bodyLarge?.color,
              size: 28,
            ),
            onPressed: () {
              Get.back(id: 1);
            },
          ),
          Expanded(
            child: Obx(() {
              final playingList = controller.filteredPlayingList; // 使用过滤后的列表
              final totalCount = controller.currentPlayingList.length;
              final filteredCount = playingList.length;

              return Text(
                controller.isSearching.value &&
                        controller.searchQuery.value.isNotEmpty
                    ? '搜索结果 ($filteredCount/$totalCount)'
                    : '当前播放 ($totalCount)',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              );
            }),
          ),
          IconButton(
            tooltip: controller.isSearching.value ? '关闭搜索' : '搜索',
            icon: Obx(
              () => Icon(
                controller.isSearching.value ? Icons.search_off : Icons.search,
                color: theme.textTheme.bodyLarge?.color,
              ),
            ),
            onPressed: () {
              controller.toggleSearch();
            },
          ),
          Tooltip(
            message: '排序',
            child: IconButton(
              onPressed: () {
                useReorderableList.value = !useReorderableList.value;
              },
              icon: Transform.rotate(
                angle: -math.pi / 2.0,
                child: Obx(
                  () => Icon(
                    Icons.compare_arrows_rounded,
                    color: useReorderableList.value
                        ? theme.colorScheme.primary
                        : null,
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: '清空播放列表',
            icon: Icon(
              Icons.clear_all,
              color: theme.textTheme.bodyLarge?.color,
            ),
            onPressed: () {
              _showClearDialog(context, controller);
            },
          ),
          IconButton(
            tooltip: '添加当前列表到歌单',
            icon: Icon(
              Icons.add_to_photos_outlined,
              color: theme.textTheme.bodyLarge?.color,
            ),
            onPressed: () {
              provider.myplaylist.Add_to_my_playlist(
                null,
                Get.find<PlayController>().current_playing,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(
    BuildContext context,
    NowPlayingPageController controller,
  ) {
    final theme = Theme.of(context);

    return Obx(() {
      if (!controller.isSearching.value) {
        return SizedBox.shrink();
      }

      return AnimatedContainer(
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withOpacity(0.8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outline.withOpacity(0.3),
            ),
          ),
          child: TextField(
            controller: controller.searchController,
            autofocus: false,
            focusNode: controller.searchFocusNode,
            decoration: InputDecoration(
              hintText: '搜索歌曲、艺术家或专辑...',
              hintStyle: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
              ),
              prefixIcon: Icon(
                Icons.search,
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
                size: 20,
              ),
              suffixIcon: Obx(() {
                if (controller.searchQuery.value.isEmpty) {
                  return SizedBox.shrink();
                }
                return IconButton(
                  icon: Icon(
                    Icons.clear,
                    color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
                    size: 20,
                  ),
                  onPressed: controller.clearSearch,
                  splashRadius: 16,
                );
              }),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            style: theme.textTheme.bodyMedium,
            onChanged: (value) {
              // 搜索逻辑已经在 controller 中通过监听器处理
            },
          ),
        ),
      );
    });
  }

  Widget _buildPlayingList(
    BuildContext context,
    NowPlayingPageController controller,
  ) {
    return Obx(() {
      final playingList = controller.filteredPlayingList; // 使用过滤后的列表
      // 在这里统一订阅搜索状态，替代原先每个列表项内部的 Obx
      final isSearching = controller.isSearching.value;
      // 关键字只处理一次：行内不再 toLowerCase
      final query = controller.searchQuery.value.toLowerCase().trim();
      // 行样式只算一次：行内不再 copyWith
      final styles = _RowStyles.fromTheme(Theme.of(context));

      if (playingList.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                controller.isSearching.value &&
                        controller.searchQuery.value.isNotEmpty
                    ? Icons.search_off
                    : Icons.queue_music,
                size: 64,
                color: Theme.of(
                  context,
                ).textTheme.bodyMedium?.color?.withOpacity(0.5),
              ),
              16.sbh,
              Text(
                controller.isSearching.value &&
                        controller.searchQuery.value.isNotEmpty
                    ? '没有找到匹配的歌曲'
                    : '播放队列为空',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.color?.withOpacity(0.7),
                ),
              ),
            ],
          ),
        );
      }

      final canReorder = useReorderableList.value && !isSearching;

      if (canReorder) {
        return TrackScrollbar(
          controller: scrollController,
          child: PageScrollToTop(scrollController: scrollController, builder: (context, pageScrollController, pageListController) => AnimatedReorderableListView(
            onReorder: (oldIndex, newIndex) {
              controller.reorderPlaylist(oldIndex, newIndex);
            },
            isSameItem: (trackA, trackB) => trackA.id == trackB.id,
            controller: pageScrollController,
            items: playingList,
            longPressDraggable: true,
            buildDefaultDragHandles: false,
            enterTransition: [SlideInDown()],
            exitTransition: [SlideInUp()],
            insertDuration: const Duration(milliseconds: 250),
            removeDuration: const Duration(milliseconds: 250),
            dragStartDelay: const Duration(milliseconds: 200),
            padding: EdgeInsets.symmetric(horizontal: 16),
            itemBuilder: (context, index) {
              final track = playingList[index];
              return _TrackTile(
                key: ValueKey(track.id),
                track: track,
                displayText: _displayTextOf(track),
                currentTrackId: _currentTrackId,
                rowActionsExpanded: _rowActionsExpanded,
                rowActionsFade: _rowActionsFade,
                reorderEnabled: true,
                query: query,
                styles: styles,
                controller: controller,
                onHoverTitle: _onTrackHover,
              );
            },
          )),
        );
      }

      return TrackScrollbar(
        controller: scrollController,
        child: PageScrollToTop(scrollController: scrollController, listController: _listController, superList: true, builder: (context, pageScrollController, pageListController) => SuperListView.builder(
          controller: pageScrollController,
          listController: pageListController,
          itemCount: playingList.length,
          padding: EdgeInsets.symmetric(horizontal: 16),
          // 行内容没有需要保活的状态，去掉每项的 AutomaticKeepAlive 包装
          addAutomaticKeepAlives: false,
          // 行高固定：让 jumpToItem / 初始偏移的估算精确
          extentEstimation: (_, __) => _kTrackRowHeight,
          // cache 区的子项延迟到后续帧填充，避免首帧一次性物化过多列表项
          delayPopulatingCacheArea: true,
          itemBuilder: (context, index) {
            final track = playingList[index];
            return _TrackTile(
              key: ValueKey(track.id),
              track: track,
              displayText: _displayTextOf(track),
              currentTrackId: _currentTrackId,
              rowActionsExpanded: _rowActionsExpanded,
              rowActionsFade: _rowActionsFade,
              reorderEnabled: false,
              query: query,
              styles: styles,
              controller: controller,
              onHoverTitle: _onTrackHover,
            );
          },
        )),
      );
    });
  }

  void _showClearDialog(
    BuildContext context,
    NowPlayingPageController controller,
  ) {
    Get.defaultDialog(
      title: '清空播放列表',
      middleText: '确定要清空整个播放列表吗？',
      textCancel: '取消',
      textConfirm: '确认',
      confirmTextColor: Get.theme.colorScheme.onError,
      buttonColor: Get.theme.colorScheme.error,
      onConfirm: () {
        controller.clearPlaylist();
        Get.back();
      },
      onCancel: () {
        Get.back();
      },
    );
  }

  Widget _buildScrollToCurrentButton(
    BuildContext context,
    NowPlayingPageController controller,
  ) {
    return Obx(() {
      // 在搜索状态下，只有当前播放歌曲在搜索结果中时才显示浮动按钮
      final shouldShow = controller.shouldShowFloatingButton;
      final isCurrentInFilteredList = controller.filteredPlayingList.any(
        (track) => track.id == controller.currentTrackId,
      );

      if (!shouldShow || !isCurrentInFilteredList || useReorderableList.value) {
        return SizedBox.shrink();
      }

      return AnimatedScale(
        scale: controller.showScrollButton.value ? 1.0 : 0.0,
        duration: Duration(milliseconds: 200),
        child: FloatingActionButton.small(
          onPressed: scrollToCurrentTrack,
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
          tooltip: '定位到当前播放',
          child: Icon(Icons.my_location, size: 20),
        ),
      );
    });
  }
}

/// 单个播放列表项（滚动性能敏感：一帧里可能同时新建好几行）。
///
/// 改动前先读这几条约束：
/// - **不要再换回 [ListTile]**。它会额外引入 InkWell 的手势/hover/语义层、
///   3 个 [Semantics] 节点和两层 [Padding]，一行的 RenderObject 数量翻倍；
/// - 行高由 [SizedBox] 固定为 [_kTrackRowHeight]，与 `extentEstimation` 完全一致，
///   super_sliver_list 不需要再实测高度，也就不会反复修正滚动偏移；
/// - **不要每行建 [Tooltip]**（每行 = 一个长按识别器 + 一个 MouseRegion +
///   一个 Semantics，滚动时反复创建销毁）。完整标题用页面级唯一的浮层，
///   见 `_NowPlayingPageState._onTrackHover`；
/// - 文案、TextStyle 都由列表层算好传进来，行内不做字符串拼接和 `copyWith`；
/// - “是否当前播放”由 [currentTrackId] 这个 [ValueListenable] 驱动，
///   切歌只重建状态真正变化的那一两行（见 [_CurrentTrackBuilder]）。
class _TrackTile extends StatefulWidget {
  const _TrackTile({
    super.key,
    required this.track,
    required this.displayText,
    required this.currentTrackId,
    required this.rowActionsExpanded,
    required this.rowActionsFade,
    required this.reorderEnabled,
    required this.query,
    required this.styles,
    required this.controller,
    required this.onHoverTitle,
  });

  final Track track;

  /// 已经拼好的 `标题 · 艺术家`，行内不再做字符串插值。
  final String displayText;

  /// 当前播放曲目 id。
  final ValueListenable<String> currentTrackId;

  /// 行内操作按钮当前是否应该展开（快速滚动时为 false，只留同宽占位）。
  final ValueListenable<bool> rowActionsExpanded;

  /// 展开时共享的淡入动画（所有行共用一个 AnimationController）。
  final Animation<double> rowActionsFade;

  final bool reorderEnabled;

  /// 已 `toLowerCase().trim()` 的搜索关键字；空串表示不需要高亮。
  final String query;
  final _RowStyles styles;
  final NowPlayingPageController controller;

  /// 鼠标进入/离开某一行时把完整标题交给页面级浮层（text 为 null 表示离开）。
  final void Function(String id, String? text, Offset? globalPosition)?
  onHoverTitle;

  @override
  State<_TrackTile> createState() => _TrackTileState();
}

/// 行样式在列表层算一次，行内直接复用（避免每行 `copyWith`）。
class _RowStyles {
  const _RowStyles({
    required this.title,
    required this.titleCurrent,
    required this.highlight,
    required this.highlightCurrent,
    required this.currentBackground,
    required this.hoverBackground,
    required this.pressedBackground,
    required this.accent,
    required this.deleteIcon,
    required this.iconDisabled,
  });

  final TextStyle? title;
  final TextStyle? titleCurrent;
  final TextStyle? highlight;
  final TextStyle? highlightCurrent;
  final Color currentBackground;
  final Color hoverBackground;
  final Color pressedBackground;
  final Color accent;
  final Color deleteIcon;
  final Color iconDisabled;

  factory _RowStyles.fromTheme(ThemeData theme) {
    final body = theme.textTheme.bodyMedium;
    final title = body?.copyWith(
      color: theme.textTheme.bodyLarge?.color,
      fontWeight: FontWeight.normal,
    );
    final titleCurrent = body?.copyWith(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w600,
    );
    final highlightBackground = theme.colorScheme.secondary.withValues(
      alpha: 0.3,
    );
    return _RowStyles(
      title: title,
      titleCurrent: titleCurrent,
      highlight: title?.copyWith(
        backgroundColor: highlightBackground,
        fontWeight: FontWeight.bold,
      ),
      highlightCurrent: titleCurrent?.copyWith(
        backgroundColor: highlightBackground,
        fontWeight: FontWeight.bold,
      ),
      currentBackground: theme.colorScheme.primary.withValues(alpha: 0.1),
      hoverBackground: theme.colorScheme.primary.withValues(alpha: 0.06),
      pressedBackground: theme.colorScheme.primary.withValues(alpha: 0.16),
      accent: theme.colorScheme.primary,
      deleteIcon: theme.colorScheme.error.withValues(alpha: 0.7),
      iconDisabled: theme.disabledColor.withValues(alpha: 0.6),
    );
  }
}

/// 只在“这一行是不是当前播放项”真的变化时才重建。
///
/// 直接用 [ValueListenableBuilder] 的话，切歌时所有可见行都会重新 build 一遍；
/// 这里记住上次的状态，未变化的行直接跳过。
class _CurrentTrackBuilder extends StatefulWidget {
  const _CurrentTrackBuilder({
    required this.listenable,
    required this.trackId,
    required this.builder,
  });

  final ValueListenable<String> listenable;
  final String trackId;
  final Widget Function(BuildContext context, bool isCurrent) builder;

  @override
  State<_CurrentTrackBuilder> createState() => _CurrentTrackBuilderState();
}

class _CurrentTrackBuilderState extends State<_CurrentTrackBuilder> {
  late bool _isCurrent = _compute();

  bool _compute() => widget.trackId == widget.listenable.value;

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_handleChanged);
  }

  @override
  void didUpdateWidget(covariant _CurrentTrackBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listenable != widget.listenable) {
      oldWidget.listenable.removeListener(_handleChanged);
      widget.listenable.addListener(_handleChanged);
    }
    // build 紧接在其后，直接同步状态即可，这里不能 setState。
    _isCurrent = _compute();
  }

  void _handleChanged() {
    if (!mounted) return;
    final next = _compute();
    if (next != _isCurrent) setState(() => _isCurrent = next);
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_handleChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _isCurrent);
}

class _TrackTileState extends State<_TrackTile> {
  bool _hovered = false;
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!mounted || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final row = _CurrentTrackBuilder(
      listenable: widget.currentTrackId,
      trackId: widget.track.id,
      builder: _buildRow,
    );
    // 移动端没有指针：连 MouseRegion 都不建。
    if (!isDesktop) return row;
    return MouseRegion(
      onEnter: (event) {
        if (_hovered) return;
        setState(() => _hovered = true);
        widget.onHoverTitle?.call(
          widget.track.id,
          widget.displayText,
          event.position,
        );
      },
      onExit: (_) {
        if (!_hovered) return;
        setState(() => _hovered = false);
        widget.onHoverTitle?.call(widget.track.id, null, null);
      },
      child: row,
    );
  }

  Widget _buildRow(BuildContext context, bool isCurrent) {
    final styles = widget.styles;
    // 桌面端只在 hover / 当前播放项上构建操作按钮
    final showActions = !isDesktop || _hovered || isCurrent;

    // 背景色优先级：按压 > 当前播放 > hover（都是常数，行内不新算颜色）
    final Color? background = _pressed
        ? styles.pressedBackground
        : isCurrent
        ? styles.currentBackground
        : _hovered
        ? styles.hoverBackground
        : null;

    // 用 GestureDetector 而不是 InkWell：
    // InkWell/InkResponse 每个都会展开 Actions → Focus → FocusInherited →
    // Semantics → MouseRegion → Builder → DefaultSelectionStyle → Semantics →
    // GestureDetector → RawGestureDetector → Listener（~12 个 Element），
    // 而一行里有 1 个 InkWell + 2 个 InkResponse。反馈改用上面那层背景色。
    final row = SizedBox(
      height: _kTrackRowHeight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.controller.playTrack(widget.track),
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              // 固定宽度占位，保证有/无播放图标时标题都对齐
              SizedBox(
                width: 20,
                child: isCurrent
                    ? Icon(Icons.graphic_eq, size: 20, color: styles.accent)
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildHighlightedText(
                  widget.displayText,
                  widget.query,
                  isCurrent ? styles.titleCurrent : styles.title,
                  isCurrent ? styles.highlightCurrent : styles.highlight,
                ),
              ),
              if (showActions)
                _RowActionsSlot(
                  expanded: widget.rowActionsExpanded,
                  opacity: widget.rowActionsFade,
                  builder: (context) => _buildActions(styles, isCurrent),
                ),
            ],
          ),
        ),
      ),
    );

    // 只有需要背景时（当前播放 / hover / 按压）才多一层绘制节点。
    if (background == null) return row;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: row,
    );
  }

  Widget _buildActions(_RowStyles styles, bool isCurrent) {
    final track = widget.track;
    Offset? songDialogPosition;
    return Row(
      mainAxisSize: MainAxisSize.min, // 确保按钮在行内对齐
      children: [
        _TrackActionIcon(
          icon: Icons.list,
          disabledColor: styles.iconDisabled,
          onTapDown: (details) {
            songDialogPosition = details.globalPosition;
          },
          onTapCancel: () {
            songDialogPosition = null;
          },
          onTap: () {
            final position = songDialogPosition;
            songDialogPosition = null;
            song_dialog(context, track, position: position);
          },
        ),
        _TrackActionIcon(
          icon: Icons.delete,
          color: styles.deleteIcon,
          disabledColor: styles.iconDisabled,
          onTap: isCurrent
              ? null
              : () {
                  widget.controller.removeTrackFromList(track);
                },
        ),
      ],
    );
  }
}

/// 行内操作按钮的占位/淡入容器。
///
/// 快速滚动时只留同宽的空白（不建两个按钮，标题宽度也不会跳），
/// 滚动变慢后再淡入真正的按钮。滚动状态变化时**只有这个小组件重建**，
/// 行内其余内容（标题、图标）都不会重新 build。
class _RowActionsSlot extends StatefulWidget {
  const _RowActionsSlot({
    required this.expanded,
    required this.opacity,
    required this.builder,
  });

  final ValueListenable<bool> expanded;
  final Animation<double> opacity;
  final WidgetBuilder builder;

  @override
  State<_RowActionsSlot> createState() => _RowActionsSlotState();
}

class _RowActionsSlotState extends State<_RowActionsSlot> {
  late bool _expanded = widget.expanded.value;

  @override
  void initState() {
    super.initState();
    widget.expanded.addListener(_handleChanged);
  }

  @override
  void didUpdateWidget(covariant _RowActionsSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expanded != widget.expanded) {
      oldWidget.expanded.removeListener(_handleChanged);
      widget.expanded.addListener(_handleChanged);
    }
    _expanded = widget.expanded.value;
  }

  void _handleChanged() {
    if (!mounted) return;
    final next = widget.expanded.value;
    if (next != _expanded) setState(() => _expanded = next);
  }

  @override
  void dispose() {
    widget.expanded.removeListener(_handleChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_expanded) {
      // 占位：宽度一致，标题不会因为按钮消失而重排
      return const SizedBox(width: _kTrackActionsWidth);
    }
    return FadeTransition(
      opacity: widget.opacity,
      child: SizedBox(
        width: _kTrackActionsWidth,
        child: widget.builder(context),
      ),
    );
  }
}

/// 轻量的行内操作按钮：GestureDetector + Icon，替换昂贵的 IconButton/InkResponse。
///
/// InkResponse 会展开一整套 Actions/Focus/Semantics/Gesture 栈（~12 个 Element），
/// 而这里只需要命中 40×40 的点击热区。桌面端才包 MouseRegion
/// （移动端没有指针，不需要设置 cursor）。
class _TrackActionIcon extends StatelessWidget {
  const _TrackActionIcon({
    required this.icon,
    required this.disabledColor,
    this.onTap,
    this.onTapDown,
    this.onTapCancel,
    this.color,
  });

  final IconData icon;
  final Color disabledColor;
  final VoidCallback? onTap;
  final ValueChanged<TapDownDetails>? onTapDown;
  final VoidCallback? onTapCancel;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onTapDown: enabled ? onTapDown : null,
      onTapCancel: enabled ? onTapCancel : null,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Icon(icon, size: 20, color: enabled ? color : disabledColor),
      ),
    );
    if (!isDesktop) return button;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      child: button,
    );
  }
}

/// 高亮搜索关键字（用 [Text]/[Text.rich]，避免每行创建 SelectableText 的编辑栈）。
///
/// [query] 已由列表层 `toLowerCase().trim()`；[highlightStyle] 也已预计算，
/// 不再为每个关键词片段做 `copyWith`。
Widget _buildHighlightedText(
  String text,
  String query,
  TextStyle? style,
  TextStyle? highlightStyle,
) {
  if (query.isEmpty) {
    return Text(
      text,
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  final lowerText = text.toLowerCase();
  final spans = <TextSpan>[];

  int start = 0;
  int index = lowerText.indexOf(query);

  while (index != -1) {
    // 添加高亮前的文本
    if (index > start) {
      spans.add(TextSpan(text: text.substring(start, index)));
    }

    // 添加高亮文本（长度做上界保护：个别字符 toLowerCase 后长度会变）
    final end = math.min(index + query.length, text.length);
    spans.add(
      TextSpan(text: text.substring(index, end), style: highlightStyle),
    );

    start = end;
    index = lowerText.indexOf(query, start);
  }

  // 添加剩余文本
  if (start < text.length) {
    spans.add(TextSpan(text: text.substring(start)));
  }

  return Text.rich(
    // 基础样式放在父 span 上，子 span 直接继承
    TextSpan(style: style, children: spans),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
}
