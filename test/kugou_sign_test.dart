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

  test('raw RSA used by user detail', () {
    expect(
      KugouSign.rsaRaw('{"token":"abc","clienttime":1700000000}'),
      '6BC928FA835C5CD99CBE4BA97A59F469873874D25FB2C1CA2EFCC0C59316261C'
      'BEDE2FE04D648C2628F6AABD492F0401C9D4C7A180D0F1E2DFE55AEE7186BF8E'
      '18A270F1EDB8D7F4DB2F7A856AAE5FA6375186DBF4FFFFCF3B162EB9029A8E67'
      'D26754689C5F215BBCF9695141300A6FEB56AB862FFF1786A4D11AAC095B5269',
    );
  });
}
