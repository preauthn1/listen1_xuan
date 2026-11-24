import 'package:flutter_test/flutter_test.dart';
import 'package:listen1_xuan/provider/kugou_sign.dart';

/// 期望值由 KuGouMusicApi util/helper.js 的同名算法（标准版）在 Node 中算出，
/// 保证 Dart 实现逐字节一致。
void main() {
  const p = <String, Object?>{
    'dfid': '-',
    'mid': '123',
    'uuid': '-',
    'appid': 1005,
    'clientver': 20489,
    'clienttime': 1700000000,
    'platform': 'ios',
    'obj': {'a': 1},
  };

  test('android signature, with and without body', () {
    expect(KugouSign.android(p), '690fa0f94f7261f225662c681bbfd61b');
    expect(KugouSign.android(p, '{"x":1}'), '2622adc74c454142d01782406d624b8b');
  });

  test('web signature (QR login)', () {
    expect(
      KugouSign.web({
        'appid': 1001,
        'type': 1,
        'plat': 4,
        'srcappid': 2919,
        'qrcode_txt': 'https://h5.kugou.com/apps/loginQRCode/html/index.html?appid=1005&',
      }),
      '92696af811fed7cb60c301a3e39ba55a',
    );
  });

  test('track key, params key and mid', () {
    expect(KugouSign.trackKey('abcdef0123', '123', 42), 'bc3075aee94af8ebea9b8c5b66f2030e');
    expect(KugouSign.paramsKey(1700000000000), 'a16d61ca1308a00264f488e64029b29a');
    expect(
      KugouSign.midFromGuid('0f607264fc6318a92b9e13c65db7cd3c'),
      '78636283283860934464203133498772801020',
    );
  });
}
