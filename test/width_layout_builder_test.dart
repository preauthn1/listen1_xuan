import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listen1_xuan/widgets/width_layout_builder.dart';

void main() {
  testWidgets('仅高度变化时复用缓存，宽度变化时才重建', (tester) async {
    var buildCount = 0;
    double? lastWidth;
    var width = 300.0;
    var height = 400.0;
    late StateSetter setOuterState;
    final childKey = GlobalKey();

    // 复用同一个 widget 实例，模拟父级重建但 WidthLayoutBuilder 配置未变。
    final widthLayoutBuilder = WidthLayoutBuilder(
      builder: (context, maxWidth) {
        buildCount++;
        lastWidth = maxWidth;
        return SizedBox.expand(key: childKey);
      },
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, setState) {
            setOuterState = setState;
            return Center(
              child: SizedBox(
                width: width,
                height: height,
                child: widthLayoutBuilder,
              ),
            );
          },
        ),
      ),
    );

    expect(buildCount, 1);
    expect(lastWidth, 300);
    RenderBox childBox() =>
        childKey.currentContext!.findRenderObject()! as RenderBox;
    expect(childBox().size, const Size(300, 400));

    // 高度变化、宽度不变：不应重建，但仍需按新约束布局。
    setOuterState(() => height = 200);
    await tester.pump();
    expect(buildCount, 1);
    expect(childBox().size, const Size(300, 200));

    // 宽度变化：需要重建。
    setOuterState(() => width = 200);
    await tester.pump();
    expect(buildCount, 2);
    expect(lastWidth, 200);
  });
}
