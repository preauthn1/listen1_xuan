import 'package:flutter_test/flutter_test.dart';
import 'package:listen1_xuan/funcs.dart';

void main() {
  test('dio 412 text becomes a short risk-control message', () {
    const raw = 'DioException [bad response]: This exception was thrown because the response has a status code of 412 and RequestOptions.validateStatus was configured to throw for this status code.';
    expect(userFacingMessage(raw), '请求被平台风控拦截（412），请稍后再试');
  });

  test('dart exception prefixes and extra lines are removed', () {
    expect(userFacingMessage('Bad state: 有歌曲正在缓存\n#0 main'), '有歌曲正在缓存');
    expect(userFacingMessage('Exception: 备份文件地址不受信任'), '备份文件地址不受信任');
    expect(userFacingMessage('FormatException: 需要先登录 QQ 音乐'), '需要先登录 QQ 音乐');
  });

  test('plain Chinese messages are kept', () {
    expect(userFacingMessage('文件已存在'), '文件已存在');
    expect(userFacingMessage(''), '请稍后重试');
  });

  test('timeouts and socket errors are explained', () {
    expect(userFacingMessage('DioException [connection timeout]: ...'), '连接超时，请检查网络');
    expect(userFacingMessage('SocketException: Failed host lookup'), '网络连接失败，请检查网络后重试');
  });
}
