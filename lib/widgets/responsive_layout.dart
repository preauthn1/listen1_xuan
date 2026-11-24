import 'package:flutter/widgets.dart';
import 'package:responsive_framework/responsive_framework.dart';

/// 全局断点（基于窗口宽度，单位逻辑像素）。
///
/// - MOBILE  0–599：手机竖屏
/// - TABLET  600–1023：平板、手机横屏、窄桌面窗口
/// - DESKTOP 1024–1599：常规桌面窗口
/// - 4K      1600+：宽屏/最大化
///
/// 需要按断点分支时用 `ResponsiveBreakpoints.of(context).largerThan(TABLET)` 等。
const List<Breakpoint> appBreakpoints = [
  Breakpoint(start: 0, end: 599, name: MOBILE),
  Breakpoint(start: 600, end: 1023, name: TABLET),
  Breakpoint(start: 1024, end: 1599, name: DESKTOP),
  Breakpoint(start: 1600, end: double.infinity, name: '4K'),
];

/// 在 [GetMaterialApp.builder] 里包一层，使所有页面都能读取断点。
Widget responsiveAppBuilder(BuildContext context, Widget child) =>
    ResponsiveBreakpoints.builder(child: child, breakpoints: appBreakpoints);

/// 阅读型内容（设置、说明文档、使用技巧、下载列表等）的最大宽度。
/// 宽屏下一行太长、开关离标题太远会很难读，居中限制宽度。
class ContentMaxWidth extends StatelessWidget {
  const ContentMaxWidth({super.key, required this.child, this.maxWidth = 880});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return MaxWidthBox(maxWidth: maxWidth, child: child);
  }
}

/// [ContentMaxWidth] 的 sliver 版本，用在 CustomScrollView 里：
/// 只限制内容宽度，滚动条仍贴在窗口右边。
class SliverContentMaxWidth extends StatelessWidget {
  const SliverContentMaxWidth({super.key, required this.sliver, this.maxWidth = 880});

  final Widget sliver;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final extra = constraints.crossAxisExtent - maxWidth;
        if (extra <= 0) return sliver;
        return SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: extra / 2),
          sliver: sliver,
        );
      },
    );
  }
}
