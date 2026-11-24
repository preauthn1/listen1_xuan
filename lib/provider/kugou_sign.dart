// 酷狗网关请求与签名。
//
// 协议与常量参考 MakcRe/KuGouMusicApi（MIT License, Copyright (c) MakcRe）
// 的 util/helper.js、util/request.js、util/util.js，用 Dart 重新实现；
// 只用标准版（appid 1005）身份，不含概念版领 VIP 之类的接口。
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

class KugouSign {
  KugouSign._();

  static const int appid = 1005;
  static const int clientver = 20489;
  static const int srcappid = 2919;

  static const _androidSalt = 'OIlwieks28dk2k092lksi2UIkp';
  static const _webSalt = 'NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt';
  static const _keySalt = '57ae12eb6890223e355ccfcb74edf70d';

  static String md5Hex(String s) => md5.convert(utf8.encode(s)).toString();

  static String _value(Object? v) => v is Map || v is List ? jsonEncode(v) : '$v';

  /// Android 签名：MD5(盐 + 按 key 排序的 key=value 串 + 请求体 + 盐)。
  static String android(Map<String, Object?> params, [String body = '']) {
    final keys = params.keys.toList()..sort();
    final joined = keys.map((k) => '$k=${_value(params[k])}').join();
    return md5Hex('$_androidSalt$joined$body$_androidSalt');
  }

  /// Web 签名：MD5(盐 + 按「key=value」字符串排序后的串 + 请求体 + 盐)。
  static String web(Map<String, Object?> params, [String body = '']) {
    final pairs = params.keys.map((k) => '$k=${params[k]}').toList()..sort();
    return md5Hex('$_webSalt${pairs.join()}$body$_webSalt');
  }

  /// 取播放地址用的 key：MD5(hash + 盐 + appid + mid + userid)。
  static String trackKey(String hash, String mid, Object? userid) =>
      md5Hex('$hash$_keySalt$appid$mid${userid ?? 0}');

  /// 私人 FM 等接口的参数签名：MD5(appid + 盐 + clientver + data)。
  static String paramsKey(Object data) => md5Hex('$appid$_androidSalt$clientver$data');

  /// 由设备 GUID 计算 mid：把 MD5 十六进制串当作一个大整数，输出十进制。
  static String midFromGuid(String guid) =>
      BigInt.parse(md5Hex(guid), radix: 16).toString();

  static String randomGuid([Random? rnd]) {
    final r = rnd ?? Random.secure();
    String e() => (65536 * (1 + r.nextDouble())).floor().toRadixString(16).substring(1);
    return '${e()}${e()}-${e()}-${e()}-${e()}-${e()}${e()}${e()}';
  }

  // 标准版 RSA 公钥（KuGouMusicApi util/crypto.js 的 publicRasKey）。
  static final BigInt _rsaN = BigInt.parse(
    'c8006ed03842d2628209bd314984ca5ed6cfe06e30c95f9d4704d9c49791d7a9'
    '35ba950ecb0bc8ebf5f5994f0bac927a7eb151b3c1de343303fa539c83136ecc'
    'fd7d7e511e2dbce18eaa9f784c9b50d443e75865979e0a5e216e46c684066a8d'
    '6b998580bbaa22d73f5790286bb14742e83244e44db6d707ffe162c5c7002d45',
    radix: 16,
  );
  static final BigInt _rsaE = BigInt.from(0x10001);

  /// 酷狗的「无填充」RSA：明文右侧补零到 128 字节后直接 modPow，输出大写十六进制。
  static String rsaRaw(String plain) {
    final bytes = utf8.encode(plain);
    if (bytes.length > 128) throw ArgumentError('RSA 明文超过 128 字节');
    final padded = List<int>.filled(128, 0)..setRange(0, bytes.length, bytes);
    final m = BigInt.parse(padded.map((b) => b.toRadixString(16).padLeft(2, '0')).join(), radix: 16);
    return m.modPow(_rsaE, _rsaN).toRadixString(16).padLeft(256, '0').toUpperCase();
  }

  static String randomString(int len, [Random? rnd]) {
    const chars = '1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final r = rnd ?? Random.secure();
    return List.generate(len, (_) => chars[r.nextInt(chars.length)]).join();
  }
}
