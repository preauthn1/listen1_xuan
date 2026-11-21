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

  Future<void> startBroadcast(int port) async {
    // 当前控制面仅绑定 loopback，广播 LAN 地址会生成不可达配对入口。
    return;
  }

  Future<void> stopBroadcast() async {
    if (broadcast != null) {
      await broadcast!.stop();
    }
  }
}
