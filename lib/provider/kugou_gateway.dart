// 酷狗网关客户端：设备标识、请求签名、登录与账号相关接口。
//
// 接口路径、参数与请求头参考 MakcRe/KuGouMusicApi（MIT License,
// Copyright (c) MakcRe）的 module/ 与 util/request.js，用 Dart 重新实现，
// 直接请求酷狗官方服务器，不需要额外部署 Node 服务。
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:listen1_xuan/provider/kugou_sign.dart';

class KugouSession {
  const KugouSession({this.token = '', this.userid = '', this.dfid = '-'});

  final String token;
  final String userid;
  final String dfid;

  bool get loggedIn => token.isNotEmpty && userid.isNotEmpty && userid != '0';

  static KugouSession fromCookies(Map<String, String> c) => KugouSession(
        token: c['token'] ?? '',
        userid: c['userid'] ?? c['KugooID'] ?? '',
        dfid: (c['dfid'] ?? c['kg_dfid'] ?? '').isEmpty ? '-' : (c['dfid'] ?? c['kg_dfid'])!,
      );
}

class KugouQrCode {
  const KugouQrCode({required this.key, required this.imageDataUri});
  final String key;
  /// 官方接口返回的 data:image/png;base64,…，可直接显示，避免自行编码错误的扫码内容。
  final String imageDataUri;
}

/// 二维码登录状态：0 过期，1 等待扫码，2 已扫码待确认，4 成功。
class KugouQrStatus {
  const KugouQrStatus(this.code, {this.token, this.userid, this.nickname});
  final int code;
  final String? token;
  final String? userid;
  final String? nickname;
}

class KugouGateway {
  KugouGateway({required this.dio, required this.guid});

  final Dio dio;

  /// 每台设备固定的 GUID（存在设置里），mid 由它算出。
  final String guid;

  late final String mid = KugouSign.midFromGuid(guid);

  static const _ua = 'Android15-1070-11083-46-0-DiscoveryDRADProtocol-wifi';
  static const _gateway = 'https://gateway.kugou.com';
  static const _login = 'https://login-user.kugou.com';

  int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  Map<String, Object?> _defaults(KugouSession s, int t) => {
        'dfid': s.dfid,
        'mid': mid,
        'uuid': '-',
        'appid': KugouSign.appid,
        'clientver': KugouSign.clientver,
        'clienttime': t,
        if (s.token.isNotEmpty) 'token': s.token,
        if (s.loggedIn) 'userid': s.userid,
      };

  Map<String, String> _headers(KugouSession s, int t, [String? router]) => {
        'User-Agent': _ua,
        'dfid': s.dfid,
        'mid': mid,
        'clienttime': '$t',
        'kg-rc': '1',
        'kg-thash': '5d816a0',
        'kg-rec': '1',
        'kg-rf': 'B9EDA08A64250DEFFBCADDEE00F8F25F',
        if (router != null) 'x-router': router,
      };

  dynamic _decode(dynamic data) {
    if (data is String) return data.isEmpty ? null : jsonDecode(data);
    if (data is List<int>) return jsonDecode(utf8.decode(data));
    return data;
  }

  /// Android 签名的网关请求。返回解析后的 JSON；酷狗返回 status=0 / error_code≠0 时抛错。
  Future<Map<String, dynamic>> android(
    String path, {
    required KugouSession session,
    String? router,
    String method = 'GET',
    Map<String, Object?> params = const {},
    Map<String, Object?>? body,
    String base = _gateway,
  }) async {
    final t = _now();
    final query = {..._defaults(session, t), ...params};
    final raw = body == null ? '' : jsonEncode(body);
    query['signature'] = KugouSign.android(query, raw);
    final res = await dio.request<dynamic>(
      '$base$path',
      queryParameters: query.map((k, v) => MapEntry(k, v is Map || v is List ? jsonEncode(v) : '$v')),
      data: body == null ? null : raw,
      options: Options(
        method: method,
        headers: _headers(session, t, router),
        responseType: ResponseType.plain,
      ),
    );
    return _check(_decode(res.data));
  }

  Future<Map<String, dynamic>> _web(
    String path, {
    required KugouSession session,
    required Map<String, Object?> params,
  }) async {
    final t = _now();
    final query = {..._defaults(session, t), ...params};
    query['signature'] = KugouSign.web(query);
    final res = await dio.get<dynamic>(
      '$_login$path',
      queryParameters: query.map((k, v) => MapEntry(k, '$v')),
      options: Options(headers: _headers(session, t), responseType: ResponseType.plain),
    );
    return _check(_decode(res.data));
  }

  Map<String, dynamic> _check(dynamic json) {
    if (json is! Map) throw const FormatException('酷狗返回了无效数据');
    final map = Map<String, dynamic>.from(json);
    final err = map['error_code'];
    if (map['status'] == 0 || (err is int && err != 0)) {
      throw KugouApiException(err is int ? err : -1, '${map['error_msg'] ?? map['err_msg'] ?? map['data'] ?? ''}');
    }
    return map;
  }

  // ---- 登录 ----

  /// 申请二维码；图片由官方接口生成。
  Future<KugouQrCode> createQr() async {
    final res = await _web('/v2/qrcode', session: const KugouSession(), params: {
      'appid': 1001,
      'type': 1,
      'plat': 4,
      'qrcode_txt': 'https://h5.kugou.com/apps/loginQRCode/html/index.html?appid=${KugouSign.appid}&',
      'srcappid': KugouSign.srcappid,
    });
    final key = res['data']?['qrcode'] as String?;
    final image = res['data']?['qrcode_img'] as String?;
    if (key == null || key.isEmpty || image == null || image.isEmpty) {
      throw const FormatException('获取二维码失败');
    }
    return KugouQrCode(key: key, imageDataUri: image);
  }

  Future<KugouQrStatus> checkQr(String key, String dev) async {
    final res = await _web('/v2/get_userinfo_qrcode', session: const KugouSession(), params: {
      'plat': 4,
      'appid': KugouSign.appid,
      'srcappid': KugouSign.srcappid,
      'qrcode': key,
      'dev': dev,
    });
    final d = res['data'] as Map? ?? const {};
    final status = int.tryParse('${d['status']}') ?? -1;
    return KugouQrStatus(
      status,
      token: d['token'] as String?,
      userid: d['userid']?.toString(),
      nickname: d['nickname'] as String?,
    );
  }

  // ---- 账号 ----

  /// 用户信息（昵称、头像）。token 失效时抛 [KugouApiException]。
  Future<Map<String, dynamic>> userDetail(KugouSession s) async {
    final t = _now();
    final p = KugouSign.rsaRaw(jsonEncode({'token': s.token, 'clienttime': t}));
    final res = await android(
      '/v3/get_my_info',
      session: s,
      router: 'usercenter.kugou.com',
      method: 'POST',
      params: {'plat': 1},
      body: {'visit_time': t, 'usertype': 1, 'p': p, 'userid': int.tryParse(s.userid) ?? 0},
    );
    return Map<String, dynamic>.from(res['data'] as Map? ?? const {});
  }

  /// 用户的全部歌单（自建 + 收藏），每项含 listid / global_collection_id / name / pic 等。
  Future<List<Map<String, dynamic>>> userPlaylists(KugouSession s) async {
    final out = <Map<String, dynamic>>[];
    for (var page = 1; page <= 10; page++) {
      final res = await android(
        '/v7/get_all_list',
        session: s,
        router: 'cloudlist.service.kugou.com',
        method: 'POST',
        params: {'plat': 1, 'userid': int.tryParse(s.userid) ?? 0, 'token': s.token},
        body: {
          'userid': int.tryParse(s.userid) ?? 0,
          'token': s.token,
          'total_ver': 979,
          'type': 2,
          'page': page,
          'pagesize': 30,
        },
      );
      final info = (res['data']?['info'] as List?) ?? const [];
      out.addAll(info.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
      if (info.length < 30) break;
    }
    return out;
  }

  /// 歌单曲目（按 global_collection_id，自建和收藏通用）。
  Future<List<Map<String, dynamic>>> playlistTracks(KugouSession s, String gid) async {
    final out = <Map<String, dynamic>>[];
    for (var page = 1; page <= 20; page++) {
      final res = await android(
        '/pubsongs/v2/get_other_list_file_nofilt',
        session: s,
        params: {
          'area_code': 1,
          'begin_idx': (page - 1) * 300,
          'plat': 1,
          'type': 1,
          'mode': 1,
          'personal_switch': 1,
          'extend_fields': 'abtags,hot_cmt,popularization',
          'pagesize': 300,
          'global_collection_id': gid,
        },
      );
      final songs = (res['data']?['songs'] as List?) ?? const [];
      out.addAll(songs.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
      if (songs.length < 300) break;
    }
    return out;
  }

  /// 每日推荐（未登录时为通用推荐，登录后按口味）。
  Future<List<Map<String, dynamic>>> dailyRecommend(KugouSession s) async {
    final res = await android(
      '/everyday_song_recommend',
      session: s,
      router: 'everydayrec.service.kugou.com',
      method: 'POST',
      params: {'platform': 'ios'},
    );
    return ((res['data']?['song_list'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// 私人 FM：每次返回 5 首左右。
  Future<List<Map<String, dynamic>>> personalFm(KugouSession s, {String? lastHash}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final res = await android(
      '/v2/personal_recommend',
      session: s,
      router: 'persnfm.service.kugou.com',
      method: 'POST',
      body: {
        'appid': KugouSign.appid,
        'clienttime': now,
        'mid': mid,
        'action': 'play',
        'recommend_source_locked': 0,
        'song_pool_id': 0,
        'callerid': 0,
        'm_type': 1,
        'platform': 'ios',
        'area_code': 1,
        'remain_songcnt': 0,
        'clientver': KugouSign.clientver,
        'is_overplay': 0,
        'mode': 'normal',
        'fakem': 'ca981cfc583a4c37f28d2d49000013c16a0a',
        'key': KugouSign.paramsKey(now),
        if (s.loggedIn) ...{'userid': s.userid, 'kguid': s.userid, 'token': s.token},
        if (lastHash != null) 'hash': lastHash,
      },
    );
    return ((res['data']?['song_list'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// 登录后的播放地址（会员歌曲需要登录）。
  Future<(String url, int bitrate)?> songUrl(
    KugouSession s,
    String hash, {
    int albumId = 0,
    int albumAudioId = 0,
  }) async {
    final h = hash.toLowerCase();
    final res = await android(
      '/v5/url',
      session: s,
      router: 'trackercdn.kugou.com',
      params: {
        'album_id': albumId,
        'area_code': 1,
        'hash': h,
        'ssa_flag': 'is_fromtrack',
        'version': 11430,
        'page_id': 151369488,
        'quality': 128,
        'album_audio_id': albumAudioId,
        'behavior': 'play',
        'pid': 2,
        'cmd': 26,
        'pidversion': 3001,
        'IsFreePart': 0,
        'ppage_id': '463467626,350369493,788954147',
        'cdnBackup': 1,
        'module': '',
        'clientver': 11430,
        'key': KugouSign.trackKey(h, mid, s.loggedIn ? s.userid : 0),
      },
    );
    final urls = res['url'];
    final url = urls is List && urls.isNotEmpty ? '${urls.first}' : null;
    if (url == null || url.isEmpty) return null;
    return (url, int.tryParse('${res['bitRate'] ?? 128000}') ?? 128000);
  }
}

class KugouApiException implements Exception {
  const KugouApiException(this.code, this.message);
  final int code;
  final String message;

  /// 20018 / 30768 / 20017 等为登录失效。
  bool get isAuthError => const {20017, 20018, 30768, 51002}.contains(code);

  @override
  String toString() => '酷狗接口错误 $code${message.isEmpty ? '' : '：$message'}';
}
