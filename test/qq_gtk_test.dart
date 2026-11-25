import 'package:flutter_test/flutter_test.dart';
import 'package:listen1_xuan/provider/qq.dart';

/// 期望值按 QQ 音乐网页端的 hash33（初值 5381，结果与 0x7fffffff 取与）
/// 用 Python 独立计算得出。
void main() {
  test('g_tk defaults to 5381 without a music key', () {
    expect(QQ.qqGtk(null), 5381);
    expect(QQ.qqGtk(''), 5381);
  });

  test('g_tk hashes the music key', () {
    expect(QQ.qqGtk('Q_H_L_5abc'), 1924269666);
  });
}
