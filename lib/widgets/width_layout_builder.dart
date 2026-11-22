import 'package:flutter/widgets.dart';

/// 仅在可用宽度变化时重建的 [LayoutBuilder]。
///
/// 普通的 [LayoutBuilder] 只要约束的任意维度发生变化（例如软键盘弹出、
/// 底部播放条收起导致高度变化）就会重新执行 `builder`，即使页面不在
/// 路由栈顶、已经设置了 `resizeToAvoidBottomInset: false` 也无法避免。
///
/// 此组件会缓存上一次构建的子树：
/// - 宽度变化时重新执行 `builder`；
/// - 父组件重建时重新执行 `builder`，保证外部状态（setState / Obx 等）
///   变化仍能刷新内容；
/// - 仅高度变化时直接复用缓存，不再重建子树。
class WidthLayoutBuilder extends StatefulWidget {
  const WidthLayoutBuilder({super.key, required this.builder});

  /// 构建回调，只暴露可用宽度。
  ///
  /// 不要在回调里直接读取 `MediaQuery` 等继承数据后再依赖它来构建，
  /// 因为高度变化导致的约束更新会复用缓存；这类数据请在返回的子组件
  /// 内部读取。
  final Widget Function(BuildContext context, double maxWidth) builder;

  @override
  State<WidthLayoutBuilder> createState() => _WidthLayoutBuilderState();
}

class _WidthLayoutBuilderState extends State<WidthLayoutBuilder> {
  double? _cachedWidth;
  Widget? _cachedChild;

  @override
  void didUpdateWidget(covariant WidthLayoutBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 父组件重建：丢弃缓存，让外部状态变化能刷新内容。
    _cachedChild = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 继承数据变化时同样需要重新构建，避免子组件读到旧值。
    _cachedChild = null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (_cachedChild == null || width != _cachedWidth) {
          _cachedWidth = width;
          _cachedChild = widget.builder(context, width);
        }
        return _cachedChild!;
      },
    );
  }
}
