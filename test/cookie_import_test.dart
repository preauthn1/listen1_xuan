import 'package:flutter_test/flutter_test.dart';
import 'package:listen1_xuan/utils/cookie_import.dart';

void main() {
  const netease = ['https://music.163.com', 'https://interface3.music.163.com'];
  const bilibili = ['https://api.bilibili.com', 'https://www.bilibili.com'];

  Map<String, String> asMap(String input, List<String> domains) => {
        for (final c in CookieImport.parse(input, domains: domains)) c.name: c.value,
      };

  test('header string, with or without Cookie: prefix', () {
    expect(asMap('MUSIC_U=abc; __csrf=def', netease), {'MUSIC_U': 'abc', '__csrf': 'def'});
    expect(asMap('Cookie: MUSIC_U=abc; __csrf=def', netease), {'MUSIC_U': 'abc', '__csrf': 'def'});
  });

  test('picks the Cookie line out of a pasted request header block', () {
    const block = 'GET /api HTTP/1.1\nHost: music.163.com\nCookie: MUSIC_U=abc; __csrf=def\nAccept: */*';
    expect(asMap(block, netease), {'MUSIC_U': 'abc', '__csrf': 'def'});
  });

  test('browser-extension JSON keeps only the target site', () {
    const json = '''[
      {"domain": ".bilibili.com", "name": "SESSDATA", "value": "a%2Cb"},
      {"domain": "www.bilibili.com", "name": "bili_jct", "value": "x"},
      {"domain": ".example.com", "name": "other", "value": "y"}
    ]''';
    expect(asMap(json, bilibili), {'SESSDATA': 'a%2Cb', 'bili_jct': 'x'});
  });

  test('JSON object with a cookies array', () {
    expect(asMap('{"cookies": [{"domain": ".music.163.com", "name": "MUSIC_U", "value": "z"}]}', netease),
        {'MUSIC_U': 'z'});
  });

  test('Netscape cookies.txt including HttpOnly lines', () {
    const txt = '# Netscape HTTP Cookie File\n'
        '#HttpOnly_.music.163.com\tTRUE\t/\tTRUE\t0\tMUSIC_U\tabc\n'
        '.music.163.com\tTRUE\t/\tFALSE\t0\t__csrf\tdef\n'
        '.qq.com\tTRUE\t/\tFALSE\t0\tuin\to123\n';
    expect(asMap(txt, netease), {'MUSIC_U': 'abc', '__csrf': 'def'});
  });

  test('strips quotes and control characters, later duplicates win', () {
    expect(asMap('a="1"; b=2\r; a=3', const []), {'a': '3', 'b': '2'});
  });

  test('rejects invalid names and reports missing required cookies', () {
    final cookies = CookieImport.parse('bad name=1; __csrf=x', domains: netease);
    expect(cookies.map((c) => c.name), ['__csrf']);
    expect(CookieImport.missing(cookies, ['MUSIC_U', '__csrf']), ['MUSIC_U']);
  });

  test('rejects malformed JSON and oversized input', () {
    expect(() => CookieImport.parse('[{oops', domains: netease), throwsFormatException);
    expect(() => CookieImport.parse('a=${'x' * (CookieImport.maxInputLength + 1)}'), throwsFormatException);
  });
}
