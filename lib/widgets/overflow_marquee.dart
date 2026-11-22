import 'package:flutter/material.dart';
import 'package:marquee/marquee.dart';

/// 文字放得下时静态显示（单行省略），放不下时才滚动。
///
/// 直接使用 [Marquee] 时，短标题也会在整行宽度内循环复制，
/// 出现「我喜欢的音乐 我喜欢的音乐 …」重复多遍的效果。
class OverflowMarquee extends StatelessWidget {
  const OverflowMarquee({
    super.key,
    required this.text,
    this.style,
    this.velocity = 40,
  });

  final String text;
  final TextStyle? style;
  final double velocity;

  @override
  Widget build(BuildContext context) {
    final effective = DefaultTextStyle.of(context).style.merge(style);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: effective),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final fits = !constraints.hasBoundedWidth ||
            painter.width <= constraints.maxWidth;
        painter.dispose();
        if (fits) {
          return Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              text,
              style: effective,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }
        return Marquee(
          text: text,
          style: effective,
          scrollAxis: Axis.horizontal,
          crossAxisAlignment: CrossAxisAlignment.center,
          blankSpace: 48,
          velocity: velocity,
          pauseAfterRound: const Duration(seconds: 2),
          startAfter: const Duration(seconds: 1),
          accelerationDuration: const Duration(milliseconds: 600),
          accelerationCurve: Curves.easeOut,
          decelerationDuration: const Duration(milliseconds: 400),
          decelerationCurve: Curves.easeOut,
        );
      },
    );
  }
}
