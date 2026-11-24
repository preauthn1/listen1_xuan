import 'dart:math' as math;

import 'package:animated_reorderable_list/animated_reorderable_list.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:listen1_xuan/bodys.dart';
import 'package:listen1_xuan/controllers/routeController.dart';
import 'package:listen1_xuan/controllers/track_download_controller.dart';
import 'package:listen1_xuan/pages/track_downloads_page.dart';
import 'package:listen1_xuan/funcs.dart';
import 'package:listen1_xuan/global_settings_animations.dart';
import 'package:listen1_xuan/models/Track.dart';
import 'package:listen1_xuan/play.dart';
import 'package:listen1_xuan/provider/loweb.dart';
import 'package:listen1_xuan/widgets/ext/ext_hero.dart';
import 'package:listen1_xuan/widgets/ext/ext_widget.dart';
import 'package:listen1_xuan/widgets/page_scroll_to_top.dart';
import 'package:listen1_xuan/widgets/overflow_marquee.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:super_sliver_list/super_sliver_list.dart';
import 'package:url_launcher/url_launcher.dart';

import 'playlist_info_args.dart';
import 'playlist_info_controller.dart';

class PlaylistInfoPage extends StatelessWidget {
  final PlaylistInfoArgs args;

  const PlaylistInfoPage({super.key, required this.args});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<PlaylistInfoController>(
      tag: args.controllerTag,
    );
    return Scaffold(
      body: Center(
        child: PageScrollToTop(
          scrollController: controller.scrollController,
          builder: (context, scrollController, listController) =>
              CustomScrollView(
                controller: scrollController,
                scrollBehavior: ScrollConfiguration.of(
                  context,
                ).copyWith(scrollbars: false),
                slivers: [
                  SliverAppBar(
                    expandedHeight: 280.0,
                    pinned: true,
                    leading: IconButton(
                      icon: Icon(Icons.arrow_back),
                      onPressed: () => routerPop(),
                    ),
                    title: Obx(
                      () => Skeletonizer(
                        enabled: controller.loading.value,
                        child: SizedBox(
                          height: 48,
                          child: OverflowMarquee(
                            text: controller.loadFailed.value
                                ? '加载失败'
                                : controller.result.info.title ?? "加载失败",
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                    ),
                    titleSpacing: 0,
                    flexibleSpace: FlexibleSpaceBar(
                      collapseMode: CollapseMode.parallax,
                      background: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Obx(
                            () => Skeletonizer(
                              enabled: controller.loading.value,
                              child: ExtendedImage.network(
                                controller.result.info.cover_img_url ?? '',
                                width: 150,
                                height: 150,
                                fit: BoxFit.cover,
                                cache: true,
                                loadStateChanged: (state) {
                                  if (state.extendedImageLoadState ==
                                      LoadState.failed) {
                                    return Icon(Icons.error);
                                  }
                                  if (state.extendedImageLoadState ==
                                      LoadState.loading) {
                                    return globalLoadingAnimeOfExtendedImage;
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ).hero4playlistItemImg(args.playListInfo),
                          8.sbh,
                          Obx(
                            () => Padding(
                              // 右侧留出与左侧相同的边距，搜索框不再贴着窗口边缘。
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  Expanded(
                                    flex: 5,
                                    child: ElevatedButton(
                                      onPressed: () async {
                                        if (controller.tracks.isEmpty) {
                                          return;
                                        }
                                        List<Track> trackList =
                                            List<Track>.from(controller.tracks);
                                        set_current_playing(trackList);
                                        // 私人 FM 是电台：队列快播完时自动续上
                                        personalFmActive.value =
                                            controller.listId.startsWith('nefm_');
                                        playsong(
                                          controller.tracks[0],
                                          isByClick: true,
                                        );
                                      },
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          '播放全部（共${controller.tracks.length}首）',
                                          maxLines: 1,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: IconButton(
                                      onPressed: () async {
                                        List<Track> trackList =
                                            List<Track>.from(controller.tracks);
                                        add_current_playing(trackList);
                                        showSuccessSnackbar('已添加到当前播放列表', null);
                                      },
                                      icon: Icon(Icons.add_box_outlined),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 4,
                                    child: TextField(
                                      focusNode: controller.searchFocusNode,
                                      controller: controller.searchController,
                                      decoration: InputDecoration(
                                        hintText: '搜索',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    actions: _buildActions(context, controller),
                  ),
                  Obx(() {
                    if (controller.loading.value ||
                        controller.loadFailed.value) {
                      return SliverFillRemaining(
                        hasScrollBody: false,
                        child: controller.loading.value
                            ? globalLoadingAnime.center
                            : _buildErrorView(context, controller),
                      );
                    }
                    return controller.useReorderableList.value
                        ? _buildReorderableList(context, controller)
                        : _buildNormalList(context, controller);
                  }),
                ],
              ),
        ),
      ),
    );
  }

  List<Widget> _buildActions(
    BuildContext context,
    PlaylistInfoController controller,
  ) {
    // 每日推荐、私人 FM 每次内容都不同，收藏没有意义；改为提供「换一批」。
    final isDynamic =
        controller.listId.startsWith('nedaily_') ||
        controller.listId.startsWith('nefm_') ||
        controller.listId.startsWith('kgdaily_') ||
        controller.listId.startsWith('kgfm_');
    final isFm = controller.listId.startsWith('nefm_') || controller.listId.startsWith('kgfm_');
    return [
      if (isFm)
        IconButton(
          tooltip: '换一批',
          icon: const Icon(Icons.shuffle_rounded),
          onPressed: () => controller.loadData(),
        ),
      IconButton(
        tooltip: '下载全部',
        icon: const Icon(Icons.download_rounded),
        onPressed: () async {
          final tracks = List<Track>.from(controller.tracks);
          if (tracks.isEmpty) return;
          final dl = Get.find<TrackDownloadController>();
          final pending = tracks.where((t) => !dl.isDownloaded(t.id)).toList();
          final skip = tracks.length - pending.length;
          final ok = await showConfirmDialog(
            skip > 0
                ? '共 ${tracks.length} 首，其中 $skip 首已下载过将跳过。\n保存到 ${dl.locationHint}'
                : '共 ${tracks.length} 首，保存到 ${dl.locationHint}',
            '下载全部歌曲？',
            confirmText: '下载 ${pending.length} 首',
          );
          if (!ok || pending.isEmpty) return;
          final n = await dl.enqueue(pending);
          if (n > 0) {
            showInfoSnackbar('已加入下载 $n 首', '可在「下载」页查看进度',
                onTap: () => Get.toNamed(RouteName.trackDownloadsPage, id: 1));
          }
        },
      ),
      IconButton(
        tooltip: '保存为我的歌单',
        icon: Icon(Icons.add),
        onPressed: () async {
          try {
            await provider.myplaylist.Add_to_my_playlist(
              context,
              List<Track>.from(controller.tracks),
              controller.result.info.title,
              controller.result.info.cover_img_url,
            );
            Get.back(result: {"refresh": true}, id: 1);
          } catch (e) {
            showErrorSnackbar('添加失败', e.toString());
          }
        },
      ),
      controller.isMy
          ? IconButton(
              tooltip: '删除歌单',
              icon: Icon(Icons.delete),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (BuildContext contextDialog) {
                    return AlertDialog(
                      title: Text('删除歌单'),
                      content: Text('确定要删除这个歌单吗？'),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Navigator.of(contextDialog).pop();
                          },
                          child: Text('取消'),
                        ),
                        TextButton(
                          onPressed: () async {
                            provider.myplaylist.removeMyPlaylist(
                              'my',
                              controller.listId,
                            );
                            Navigator.of(contextDialog).pop();
                            Get.back(result: {"refresh": true}, id: 1);
                          },
                          child: Text('确定'),
                        ),
                      ],
                    );
                  },
                );
              },
            )
          : isDynamic
          ? const SizedBox.shrink()
          : IconButton(
              tooltip: '在浏览器中打开',
              icon: Icon(Icons.link),
              onPressed: () {
                final sourceUrl = controller.result.info.source_url;
                if (sourceUrl == null || sourceUrl.isEmpty) {
                  showErrorSnackbar('没有可打开的链接', null);
                  return;
                }
                launchUrl(Uri.parse(sourceUrl));
              },
            ),
      controller.isMy
          ? IconButton(
              tooltip: '编辑歌单',
              icon: Icon(Icons.edit),
              onPressed: () async {
                setInAppHotKeyEnable(false);
                await showDialog(
                  context: context,
                  builder: (BuildContext contextDialog) {
                    final TextEditingController titleCtrl =
                        TextEditingController(
                          text: controller.result.info.title,
                        );
                    final TextEditingController coverCtrl =
                        TextEditingController(
                          text: controller.result.info.cover_img_url,
                        );
                    return AlertDialog(
                      title: Text('编辑歌单'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: titleCtrl,
                            decoration: InputDecoration(labelText: '歌单标题'),
                          ),
                          TextField(
                            controller: coverCtrl,
                            decoration: InputDecoration(labelText: '封面图片链接'),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Navigator.of(contextDialog).pop();
                          },
                          child: Text('取消'),
                        ),
                        TextButton(
                          onPressed: () async {
                            provider.myplaylist.editMyPlaylist(
                              controller.listId,
                              titleCtrl.text,
                              coverCtrl.text,
                            );
                            showSuccessSnackbar('编辑成功', null);
                            Navigator.of(contextDialog).pop();
                            Get.back(result: {"refresh": true}, id: 1);
                          },
                          child: Text('确定'),
                        ),
                      ],
                    );
                  },
                );
                setInAppHotKeyEnable(true);
              },
            )
          : isDynamic
          ? const SizedBox.shrink()
          : Obx(
              () => IconButton(
                tooltip: controller.isFav.value ? '取消收藏' : '收藏歌单',
                icon: controller.isFav.value
                    ? Icon(Icons.star)
                    : Icon(Icons.star_border),
                onPressed: () async {
                  if (controller.isFav.value) {
                    provider.myplaylist.removeMyPlaylist(
                      'favorite',
                      controller.listId,
                    );
                    controller.checkFav();
                    showInfoSnackbar('已取消收藏', null);
                  } else {
                    provider.myplaylist.saveMyPlaylist(
                      'favorite',
                      controller.result,
                    );
                    controller.checkFav();
                    showSuccessSnackbar('已添加到我的收藏', null);
                  }
                },
              ),
            ),
      if (controller.isMy)
        Tooltip(
          message: '排序',
          child: IconButton(
            onPressed: () {
              controller.useReorderableList.value =
                  !controller.useReorderableList.value;
            },
            icon: Transform.rotate(
              angle: -math.pi / 2.0,
              child: Obx(
                () => Icon(
                  Icons.compare_arrows_rounded,
                  color: controller.useReorderableList.value
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
              ),
            ),
          ),
        ),
    ];
  }

  Widget _buildErrorView(
    BuildContext context,
    PlaylistInfoController controller,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            const Text(
              '加载失败',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SelectableText(
              controller.loadError.value,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => controller.loadData(),
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReorderableList(
    BuildContext context,
    PlaylistInfoController controller,
  ) {
    return ReorderableAnimatedListImpl<Track>(
      scrollDirection: Axis.vertical,
      onReorder: controller.onReorder,
      isSameItem: (trackA, trackB) => trackA.id == trackB.id,
      items: controller.tracks.toList(),
      enterTransition: [SlideInDown()],
      exitTransition: [SlideInUp()],
      insertDuration: const Duration(milliseconds: 300),
      removeDuration: const Duration(milliseconds: 300),
      dragStartDelay: const Duration(milliseconds: 300),
      buildDefaultDragHandles: false,
      longPressDraggable: false,
      itemBuilder: (context, index) {
        final track = controller.tracks[index];
        final key = ValueKey(track.id);
        return ListTile(
          key: key,
          title: Row(
            children: [
              Flexible(
                child: Text(
                  track.title ?? '未知标题',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TrackDownloadBadge(trackId: track.id),
            ],
          ),
          subtitle: Text(
            '${track.artist ?? '未知艺术家'} - ${track.album ?? '未知专辑'}',
          ),
          trailing: Builder(
            builder: (iconContext) => IconButton(
              tooltip: '更多',
              icon: Icon(Icons.more_vert),
              onPressed: () async {
                await _onTrackMore(context, iconContext, track, controller);
              },
            ),
          ),
          onTap: () {
            playsong(track, isByClick: true);
          },
        );
      },
    );
  }

  Widget _buildNormalList(
    BuildContext context,
    PlaylistInfoController controller,
  ) {
    return SuperSliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final track = controller.tracks[index];
        final key = ValueKey(track.id);
        return ListTile(
          key: key,
          title: Row(
            children: [
              Flexible(
                child: Text(
                  track.title ?? '未知标题',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TrackDownloadBadge(trackId: track.id),
            ],
          ),
          subtitle: Text(
            '${track.artist} - ${track.album}${track.totalDurMsg != null ? ' | ${track.totalDurMsg}' : ''}',
          ),
          trailing: Builder(
            builder: (iconContext) => IconButton(
              tooltip: '更多',
              icon: Icon(Icons.more_vert),
              onPressed: () async {
                await _onTrackMore(context, iconContext, track, controller);
              },
            ),
          ),
          onTap: () {
            playsong(track, isByClick: true);
          },
        );
      }, childCount: controller.tracks.length),
    );
  }

  Future<void> _onTrackMore(
    BuildContext context,
    BuildContext iconContext,
    Track track,
    PlaylistInfoController controller,
  ) async {
    final renderObject = iconContext.findRenderObject();
    final iconDy = renderObject is RenderBox
        ? renderObject.localToGlobal(Offset.zero).dy
        : 0.0;
    await song_dialog(
      context,
      track,
      is_my: controller.isMy,
      nowplaylistinfo: controller.result.info,
      deltrack: controller.delTrack,
      position: Offset(MediaQuery.of(context).size.width, iconDy),
    );
  }
}
