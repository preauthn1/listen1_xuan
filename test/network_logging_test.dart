import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listen1_xuan/services/network_logging.dart';

void main() {
  test('redact masks tokens, signatures and codes in query values', () {
    final uri = Uri.parse(
      'https://api.example.com/x?keyword=abc&access_token=SECRET&w_rid=deadbeef&code=123&page=2',
    );
    final out = NetworkLogInterceptor.redact(uri);
    expect(out, contains('keyword=abc'));
    expect(out, contains('page=2'));
    expect(out, isNot(contains('SECRET')));
    expect(out, isNot(contains('deadbeef')));
    expect(out, contains('access_token=***'));
    expect(out, contains('code=***'));
  });

  test('412 from bilibili is described as risk control, not raw Dio text', () {
    final options = RequestOptions(path: 'https://api.bilibili.com/x/web-interface/search/type');
    final err = DioException.badResponse(
      statusCode: 412,
      requestOptions: options,
      response: Response(requestOptions: options, statusCode: 412),
    );
    final text = describeNetworkError(err);
    expect(text, contains('412'));
    expect(text, isNot(contains('DioException')));
  });

  test('timeouts get a short Chinese message', () {
    final options = RequestOptions(path: 'https://example.com');
    expect(
      describeNetworkError(DioException.connectionTimeout(timeout: kConnectTimeout, requestOptions: options)),
      '连接超时，请检查网络',
    );
  });

  test('risk-control business codes are recognised', () {
    expect(BilibiliRiskRetryInterceptor.isRiskCode({'code': -352}), isTrue);
    expect(BilibiliRiskRetryInterceptor.isRiskCode({'code': 0}), isFalse);
    expect(BilibiliRiskRetryInterceptor.isBilibili(Uri.parse('https://api.bilibili.com/x')), isTrue);
    expect(BilibiliRiskRetryInterceptor.isBilibili(Uri.parse('https://music.163.com/x')), isFalse);
  });
}
