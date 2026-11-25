import 'package:bonsoir/bonsoir.dart';
import 'package:get/get.dart';
import 'package:listen1_xuan/funcs.dart';
import 'package:uuid/uuid.dart';
import 'settings_controller.dart';

String broadcastType = '_listen1xuan._tcp';

class BroadcastWsController extends GetxController {
  late String deviceId;
  BonsoirBroadcast? broadcast;
  @override
  void onInit() {
    super.onInit();
    loadConfig();
  }

  void loadConfig() {
    if (isEmpty(Get.find<SettingsController>().settings['deviceId'])) {
      deviceId = Uuid().v4();
      Get.find<SettingsController>().settings['deviceId'] = deviceId;
    } else {
      deviceId = Get.find<SettingsController>().settings['deviceId'];
    }
  }

  /// Advertise the server over mDNS. Callers must only invoke this when the
  /// user opted in to LAN access. Only the port is published: the pairing
  /// token must never be broadcast.
  Future<void> startBroadcast(int port) async {
    try {
      await stopBroadcast();
      BonsoirService service = BonsoirService(
        name: deviceId,
        type: broadcastType,
        port: 3030,
        attributes: {'port': port.toString()},
      );

      broadcast = BonsoirBroadcast(service: service);
      await broadcast!.initialize();
      await broadcast!.start();
    } catch (e) {
      showErrorSnackbar('启动地址广播失败', e.toString());
    }
  }

  Future<void> stopBroadcast() async {
    final current = broadcast;
    broadcast = null;
    if (current != null) {
      await current.stop();
    }
  }
}
