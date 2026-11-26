import 'dart:async';

import 'package:dio/dio.dart';

import 'app_log_file.dart';

/// 应用内所有共享 Dio 的默认超时。
///
/// receiveTimeout 只限制「等到首个响应字节」和「两次收到数据之间」的间隔，
/// 不是整次下载的总时长，所以大文件下载不受影响。
/// sendTimeout 是上传整个请求体的时限，给大的 Gist 备份留足时间。
const Duration kConnectTimeout = Duration(seconds: 15);
const Duration kReceiveTimeout = Duration(seconds: 30);
const Duration kSendTimeout = Duration(minutes: 2);

void applyNetworkTimeouts(Dio dio) {
  dio.options
    ..connectTimeout = kConnectTimeout
    ..receiveTimeout = kReceiveTimeout
    ..sendTimeout = kSendTimeout;
}

/// 把每个请求的方法、地址（去掉查询串里的敏感值）、状态码、耗时写进日志；
/// 失败时记录错误类型，便于事后排查。不记录请求/响应正文和 Cookie。
class NetworkLogInterceptor extends Interceptor {
  static const _startKey = '_log_start';
  static final _sensitive = RegExp(
    r'(access_token|token|key|sign|w_rid|password|cookie|csrf|code)=([^&]+)',
    caseSensitive: false,
  );

  static String redact(Uri uri) {
    final s = uri.toString();
    final cut = s.length > 300 ? '${s.substring(0, 300)}…' : s;
    return cut.replaceAllMapped(_sensitive, (m) => '${m[1]}=***');
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startKey] = DateTime.now().millisecondsSinceEpoch;
    handler.next(options);
  }

  int _elapsed(RequestOptions o) {
    final start = o.extra[_startKey];
    return start is int ? DateTime.now().millisecondsSinceEpoch - start : -1;
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final o = response.requestOptions;
    final code = response.statusCode ?? 0;
    AppLogFile.instance.write(
      code >= 400 ? 'W' : 'NET',
      '${o.method} ${redact(o.uri)} → $code (${_elapsed(o)} ms)',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final o = err.requestOptions;
    final code = err.response?.statusCode;
    AppLogFile.instance.write(
      'E',
      '${o.method} ${redact(o.uri)} ✗ ${err.type.name}'
      '${code == null ? '' : ' $code'} (${_elapsed(o)} ms)'
      '${err.message == null ? '' : ': ${err.message!.split('\n').first}'}',
    );
    handler.next(err);
  }
}

/// B 站风控（HTTP 412 / 业务码 -352）多为偶发：换一组 buvid 后重试。
/// 只重试 GET，最多 [maxRetries] 次，间隔递增。
class BilibiliRiskRetryInterceptor extends Interceptor {
  BilibiliRiskRetryInterceptor(this._dio, {this.onRiskControl, this.maxRetries = 2});

  final Dio _dio;
  final Future<void> Function()? onRiskControl;
  final int maxRetries;
  static const _attemptKey = '_bili_retry';

  static bool isBilibili(Uri uri) =>
      uri.host == 'api.bilibili.com' || uri.host.endsWith('.bilibili.com');

  static bool isRiskCode(Object? data) =>
      data is Map && (data['code'] == -352 || data['code'] == -412);

  bool _canRetry(RequestOptions o) =>
      o.method.toUpperCase() == 'GET' &&
      isBilibili(o.uri) &&
      ((o.extra[_attemptKey] as int?) ?? 0) < maxRetries;

  Future<Response<dynamic>> _retry(RequestOptions o) async {
    final attempt = ((o.extra[_attemptKey] as int?) ?? 0) + 1;
    o.extra[_attemptKey] = attempt;
    AppLogFile.instance.write('W', 'B 站风控，第 $attempt 次重试: ${NetworkLogInterceptor.redact(o.uri)}');
    try {
      await onRiskControl?.call();
    } catch (e) {
      AppLogFile.instance.write('W', '刷新 B 站 buvid 失败: $e');
    }
    await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
    // 同一个 RequestOptions 再走一遍拦截器：CookieManager 会认出上次自己拼的
    // Cookie 头，还原调用方原本传入的部分（如登录 Cookie），再合并 Cookie 库里的新 buvid。
    return _dio.fetch<dynamic>(o);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    final o = response.requestOptions;
    if (isRiskCode(response.data) && _canRetry(o)) {
      try {
        handler.resolve(await _retry(o));
      } on DioException catch (e) {
        handler.reject(e);
      }
      return;
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final o = err.requestOptions;
    if (err.response?.statusCode == 412 && _canRetry(o)) {
      try {
        handler.resolve(await _retry(o));
      } on DioException catch (e) {
        handler.next(e);
      }
      return;
    }
    handler.next(err);
  }
}

/// 给用户看的网络错误说明，替代 DioException 的长篇英文。
String describeNetworkError(Object error) {
  if (error is DioException) {
    final code = error.response?.statusCode;
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
        return '连接超时，请检查网络';
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return '服务器响应超时，请稍后重试';
      case DioExceptionType.connectionError:
        return '网络连接失败，请检查网络';
      case DioExceptionType.badCertificate:
        return '证书校验失败';
      case DioExceptionType.cancel:
        return '请求已取消';
      case DioExceptionType.badResponse:
        if (code == 412) return '请求被平台风控拦截（412），已自动重试仍失败，请稍后再试';
        if (code == 429) return '请求过于频繁（429），请稍后再试';
        if (code != null && code >= 500) return '平台服务器出错（$code），请稍后再试';
        return '请求失败（HTTP $code）';
      case DioExceptionType.unknown:
        break;
    }
  }
  if (error is TimeoutException) return '请求超时，请稍后重试';
  final text = error.toString();
  return text.length > 120 ? '${text.substring(0, 120)}…' : text;
}
