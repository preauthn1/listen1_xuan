import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:get/get.dart';
import 'package:listen1_xuan/controllers/paste_controller.dart';
import 'package:path/path.dart' as p;
import 'package:listen1_xuan/funcs.dart';
import 'package:logger/logger.dart';
import 'package:listen1_xuan/services/app_logger.dart';
import 'package:listen1_xuan/models/Track.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../models/websocket_message.dart';
import '../settings.dart';
import 'BroadcastWsController.dart';
import 'play_controller.dart';
import '../play.dart';
import 'cache_controller.dart';
import '../services/websocket_listener.dart';
import '../services/paste_file_transfer.dart';

/// WebSocket 服务器控制器
/// 支持 IPv4/IPv6 配置，包含 ping/pong 心跳机制和资源释放
class WebSocketServerController extends GetxController {
  /// 将本地粘贴图片限制为和网络传输相同的预算。
  static const int maxPasteImageBytes = PasteFileTransfer.defaultMaxPartBytes;

  /// Largest WebSocket text message accepted or sent (clipboard text etc.).
  static const int maxMessageBytes = 8 * 1024 * 1024;

  static const String _tooLargeMessage = 'File too large';

  static const String _tag = 'WebSocketServerController';
  static const int _maxConnections = 8;
  static const int _maxMessageBytes = maxMessageBytes;
  static const int _maxHttpBodyBytes = PasteFileTransfer.maxBodyBytes;
  final Logger _logger = createAppLogger();
  HttpServer? _server;

  /// Shown to old (upstream) clients that connect without a pairing token.
  /// The protocol now requires the x-listen1-pairing-token header, which
  /// upstream builds never send; say so instead of a bare "Unauthorized".
  static const String missingTokenBody =
      'listen1_xuan: this server requires a pairing token '
      '(header x-listen1-pairing-token). Update the client and scan the '
      'pairing QR code. 此服务器需要配对令牌，请更新客户端后扫码配对。';

  /// Requests rejected because they carried no pairing token at all
  /// (typically an upstream client); shown in the server card.
  final RxInt _tokenlessRejections = 0.obs;
  int get tokenlessRejections => _tokenlessRejections.value;

  String _accessToken;

  /// Current pairing token required in the `x-listen1-pairing-token` header.
  String get accessToken => _accessToken;

  /// Generate a random 256-bit pairing token.
  static String generateAccessToken() => base64UrlEncode(
    List<int>.generate(32, (_) => Random.secure().nextInt(256)),
  );

  /// Replace the pairing token and drop every client paired with the old one.
  /// HTTP routes check the token per request, so they are invalidated at once.
  Future<void> rotateAccessToken(String token) async {
    if (token.isEmpty) throw ArgumentError('token must not be empty');
    _accessToken = token;
    await _closeAllConnections();
    _clientCount.value = 0;
  }

  /// 所有活跃的 WebSocket 连接
  final List<WebSocketConnection> _connections = <WebSocketConnection>[];
  int _pendingConnections = 0;

  /// 心跳定时器
  Timer? _pingTimer;
  DateTime? _serverStartedAt;
  final RxBool _isRunning = false.obs;

  /// 连接客户端数量
  final RxInt _clientCount = 0.obs;

  /// 当前粘贴的文件路径列表（供客户端通过 /getPasteFile 下载）
  List<String> nowPasteFiles = [];

  PasteImageSnapshot? _pasteImage;
  int _pasteImageGeneration = 0;
  int _transferGeneration = 0;

  /// Persist a new clipboard snapshot and release the old one after its readers.
  Future<bool> setPasteImage(List<int> bytes, String fileName) async {
    if (bytes.length > maxPasteImageBytes) {
      throw const FormatException('粘贴图片超过大小限制');
    }
    final generation = ++_pasteImageGeneration;
    final image = await PasteImageSnapshot.create(
      await getPasteFileDownloadDir(),
      bytes,
      fileName,
    );
    if (generation != _pasteImageGeneration || !isRunning) {
      await image.retire();
      return false;
    }
    final previous = _pasteImage;
    _pasteImage = image;
    await previous?.retire();
    return true;
  }

  /// 服务器配置
  late final String _host;
  late final int _port;
  final Duration _pingInterval;
  final Duration _pongTimeout;

  /// Getters
  bool get isRunning => _isRunning.value;
  int get clientCount => _clientCount.value;
  String get serverUrl => Uri(
    scheme: 'ws',
    host: _server?.address.address ?? _host,
    port: _port,
    path: '/ws',
  ).toString();

  WebSocketServerController({
    required String host,
    required int port,
    String? accessToken,
    InternetAddressType addressType = InternetAddressType.any,
    Duration pingInterval = const Duration(seconds: 30),
    Duration pongTimeout = const Duration(seconds: 5),
  }) : _host = host,
       _port = port,
       _accessToken = (accessToken == null || accessToken.isEmpty)
           ? generateAccessToken()
           : accessToken,
       _pingInterval = pingInterval,
       _pongTimeout = pongTimeout;

  @override
  void onInit() {
    super.onInit();
    _logger.i('$_tag 初始化完成');
  }

  /// 启动 WebSocket 服务器
  Future<bool> startServer() async {
    if (_isRunning.value) {
      _logger.w('$_tag 服务器已在运行');
      return true;
    }

    try {
      // 创建 HTTP 服务器
      _server = await bindWebSocketServer(_host, _port);
      if (_host == '::' && _server!.address.type == InternetAddressType.IPv4) {
        _logger.w('$_tag IPv6 监听失败，已回退到 IPv4');
      }

      _isRunning.value = true;
      _serverStartedAt = DateTime.now();
      // 仅在用户开启局域网访问（非回环监听）时广播，广播内容不含配对令牌。
      if (!_server!.address.isLoopback) {
        unawaited(Get.find<BroadcastWsController>().startBroadcast(_port));
      }
      // 监听请求
      _server!.listen((HttpRequest request) async {
        // 只接受本机和局域网（私有网段）来源；公网来源在校验令牌前直接拒绝。
        final peer = request.connectionInfo?.remoteAddress;
        if (peer == null || !isPrivateNetworkAddress(peer)) {
          request.response
            ..statusCode = HttpStatus.forbidden
            ..write('Forbidden');
          await request.response.close();
          return;
        }
        final authorized = _isAuthorizedRequest(request);
        final connectionSlot = _connections.length + _pendingConnections;
        if (WebSocketTransformer.isUpgradeRequest(request) &&
            authorized &&
            connectionSlot < _maxConnections) {
          _pendingConnections++;
          try {
            final webSocket = await WebSocketTransformer.upgrade(request);
            _handleNewConnection(webSocket);
          } finally {
            _pendingConnections--;
          }
          return;
        }
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          if (!authorized) {
            _rejectUnauthorized(request);
            return;
          }
          request.response
            ..statusCode = HttpStatus.serviceUnavailable
            ..write('Connection limit reached');
          await request.response.close();
          return;
        }
        // 处理普通 HTTP 请求
        _handleHttpRequest(request);
      });

      // 启动心跳检测
      _startPingTimer();

      return true;
    } catch (e, stackTrace) {
      _logger.e('$_tag 启动服务器失败', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  /// 停止 WebSocket 服务器
  Future<void> stopServer() async {
    ++_transferGeneration;
    ++_pasteImageGeneration;
    final image = _pasteImage;
    _pasteImage = null;
    nowPasteFiles = [];
    await image?.retire();
    try {
      Get.find<BroadcastWsController>().stopBroadcast();
    } catch (e) {
      showErrorSnackbar('停止地址广播失败', e.toString());
    }
    if (!_isRunning.value) {
      return;
    }

    try {
      // 停止心跳检测
      _stopPingTimer();

      // 关闭所有连接
      await _closeAllConnections();
      await _server?.close(force: true);
      _server = null;

      _isRunning.value = false;
      _clientCount.value = 0;
      _serverStartedAt = null;
    } catch (e, stackTrace) {
      _logger.e('$_tag 停止服务器时出错', error: e, stackTrace: stackTrace);
    }
  }

  /// 处理新的 WebSocket 连接
  void _handleNewConnection(WebSocket webSocket) {
    final connection = WebSocketConnection(
      webSocket: webSocket,
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      connectedAt: DateTime.now(),
    );

    _connections.add(connection);
    _clientCount.value = _connections.length;

    _logger.i('$_tag 新客户端连接: ${connection.id}, 总连接数: ${_connections.length}');

    // 发送欢迎消息
    final welcomeMessage = WebSocketMessageBuilder.createWelcomeMessage(
      connection.id,
    );
    _sendMessage(connection, welcomeMessage);
    // 监听消息
    webSocket.listen(
      (data) => _handleMessage(connection, data),
      onDone: () => _handleConnectionClosed(connection),
      onError: (error) => _handleConnectionError(connection, error),
    );
  }

  /// 处理收到的消息
  Future<void> _handleMessage(
    WebSocketConnection connection,
    dynamic data,
  ) async {
    final raw = data is String ? data : data.toString();
    final rawBytes = utf8.encode(raw);
    if (rawBytes.length > _maxMessageBytes) {
      // 只拒绝这条消息并告知发送方，不断开整个连接（避免客户端重连循环）。
      _logger.w('$_tag 拒绝超大消息: ${rawBytes.length} bytes from ${connection.id}');
      _sendMessage(
        connection,
        WebSocketMessageBuilder.createErrorMessage(
          '消息过大（超过 ${_maxMessageBytes ~/ (1024 * 1024)} MiB），未处理',
        ),
      );
      return;
    }
    try {
      // 尝试解析为新的 WebSocketMessage 格式
      WebSocketMessage message;
      try {
        message = WebSocketMessage.fromJsonString(raw);
      } catch (e) {
        // 如果解析失败，尝试解析为旧格式
        final oldMessage = json.decode(raw);
        final messageType = oldMessage['type'] ?? 'unknown';

        // 转换为新格式
        message = WebSocketMessage(
          type: messageType,
          content: json.encode(oldMessage),
        );
      }

      _logger.d('$_tag 收到消息: ${message.type} from ${connection.id}');

      switch (message.type) {
        case WebSocketMessageType.getStatus:
          _handleGetStatusRequest(connection);
          break;
        case WebSocketMessageType.ctrl:
          await _handleControlMessage(connection, message);
          break;
        case WebSocketMessageType.track:
          _handleTrackMessage(connection, message);
          break;
        case WebSocketMessageType.trackNext:
          _handleTrackNextMessage(connection, message);
          break;
        case WebSocketMessageType.pong:
          connection.lastPong = DateTime.now();
          _logger.d('$_tag 收到 pong from ${connection.id}');
          break;
        case WebSocketMessageType.ping:
          // 响应客户端的 ping
          final pongMessage = WebSocketMessageBuilder.createPongMessage();
          _sendMessage(connection, pongMessage);
          break;
        case WebSocketMessageType.broadcast:
          // 广播消息给所有客户端
          final contentMap = message.parseContentAsMap();
          final broadcastMessage = contentMap?['message'] ?? message.content;
          final broadcastMsg = WebSocketMessageBuilder.createBroadcastMessage(
            broadcastMessage,
            from: connection.id,
          );
          _broadcastMessage(broadcastMsg, excludeClient: connection.id);
          break;
        case WebSocketMessageType.sendPasteText:
          unawaited(
            Get.find<PasteController>().onReceivedPasteText(message.content),
          );

          break;
        case WebSocketMessageType.getCookie:
          Set<String> toOpr = {};
          if (message.content == PlantformCodes.all) {
            toOpr.addAll(PlantformCodes.values);
          } else if (PlantformCodes.values.contains(message.content)) {
            toOpr.add(message.content);
          }
          Map<String, String> cookiesMap = {};
          for (var k in toOpr) {
            final token = await outputPlatformToken(k);
            if (token != null) {
              cookiesMap[k] = token;
            }
          }
          _sendMessage(
            connection,
            WebSocketMessage(
              type: WebSocketMessageType.setCookie,
              content: jsonEncode(cookiesMap),
            ),
          );
          break;

        case WebSocketMessageType.message:
          // 处理普通消息（可以根据需要添加逻辑）
          _logger.d('$_tag 收到普通消息: ${message.content}');
          break;
        default:
          _logger.d('$_tag 未知消息类型: ${message.type}');
      }
    } catch (e) {
      _logger.e('$_tag 处理消息失败', error: e);
      // 发送错误消息给客户端
      final errorMessage = WebSocketMessageBuilder.createErrorMessage(
        _safeExternalError('消息处理失败'),
      );
      _sendMessage(connection, errorMessage);
    }
  }

  /// 处理获取状态请求
  void _handleGetStatusRequest(WebSocketConnection connection) {
    try {
      // 获取 PlayController 实例
      final playController = Get.find<PlayController>();

      // 创建状态数据
      final statusData = PlayStatusData.fromPlayController(playController);

      // 创建状态响应消息
      final statusMessage = WebSocketMessageBuilder.createStatusResponse(
        statusData,
      );

      // 发送状态消息给请求的客户端
      _sendMessage(connection, statusMessage);

      _logger.i(
        '$_tag 发送播放状态给客户端 ${connection.id}: isPlaying=${statusData.isPlaying}, track=${statusData.currentTrack?.title ?? "None"}',
      );
    } catch (e) {
      _logger.e('$_tag 处理获取状态请求失败', error: e);

      // 发送错误消息
      final errorMessage = WebSocketMessageBuilder.createErrorMessage(
        _safeExternalError('无法获取播放状态'),
      );
      _sendMessage(connection, errorMessage);
    }
  }

  /// 处理播放控制消息
  Future<void> _handleControlMessage(
    WebSocketConnection connection,
    WebSocketMessage message,
  ) async {
    try {
      final command = message.content.trim();
      _logger.i('$_tag 收到播放控制命令: $command from ${connection.id}');

      switch (command) {
        case PlayControlCommands.play:
          globalPlay();
          _logger.i('$_tag 执行播放命令');
          break;
        case PlayControlCommands.pause:
        case PlayControlCommands.stop:
          globalPause();
          _logger.i('$_tag 执行暂停命令');
          break;
        case PlayControlCommands.next:
          globalSkipToNext();
          _logger.i('$_tag 执行下一首命令');
          break;
        case PlayControlCommands.previous:
          globalSkipToPrevious();
          _logger.i('$_tag 执行上一首命令');
          break;
        default:
          // 检查是否为changePlayMode命令
          if (command == 'changePlayMode') {
            try {
              final newPlayMode = await globalChangePlayMode();
              _logger.i('$_tag 播放模式已切换为: $newPlayMode');

              // 发送成功响应
              final successMessage = WebSocketMessageBuilder.createMessage(
                '播放模式已切换: ${_getPlayModeText(newPlayMode)}',
              );
              _sendMessage(connection, successMessage);
              return;
            } catch (e) {
              _logger.e('$_tag 切换播放模式失败', error: e);
              final errorMessage = WebSocketMessageBuilder.createErrorMessage(
                _safeExternalError('切换播放模式失败'),
              );
              _sendMessage(connection, errorMessage);
              return;
            }
          }
          if (command.startsWith('process_')) {
            final processValue = double.tryParse(command.substring(8));
            if (processValue != null &&
                processValue >= 0.0 &&
                processValue <= 1.0) {
              // 这是进度控制命令
              _logger.i('$_tag 收到进度控制命令: $processValue');
              try {
                globalSeek(null, process: processValue);
                return;
              } catch (e) {
                _logger.e('$_tag 进度控制失败', error: e);
                final errorMessage = WebSocketMessageBuilder.createErrorMessage(
                  _safeExternalError('设置进度失败'),
                );
                _sendMessage(connection, errorMessage);
                return;
              }
            }
          }
          // 尝试解析为音量控制命令
          final volumeValue = double.tryParse(command);
          if (volumeValue != null &&
              volumeValue >= 0.0 &&
              volumeValue <= 100.0) {
            // 这是音量控制命令
            try {
              final playController = Get.find<PlayController>();
              playController.currentVolume = volumeValue;
              _logger.i('$_tag 设置音量: ${volumeValue.toInt()}%');

              // 发送成功响应
              final successMessage = WebSocketMessageBuilder.createMessage(
                '音量已设置为: ${volumeValue.toInt()}%',
              );
              _sendMessage(connection, successMessage);
              return;
            } catch (e) {
              _logger.e('$_tag 设置音量失败', error: e);
              final errorMessage = WebSocketMessageBuilder.createErrorMessage(
                _safeExternalError('设置音量失败'),
              );
              _sendMessage(connection, errorMessage);
              return;
            }
          }

          _logger.w('$_tag 未知播放控制命令: $command');
          final errorMessage = WebSocketMessageBuilder.createErrorMessage(
            '未知播放控制命令: $command',
          );
          _sendMessage(connection, errorMessage);
          return;
      }

      // 发送成功响应
      final successMessage = WebSocketMessageBuilder.createMessage(
        '播放控制命令已执行: $command',
      );
      _sendMessage(connection, successMessage);
    } catch (e) {
      _logger.e('$_tag 处理播放控制消息失败', error: e);
      final errorMessage = WebSocketMessageBuilder.createErrorMessage(
        _safeExternalError('播放控制失败'),
      );
      _sendMessage(connection, errorMessage);
    }
  }

  /// 处理播放指定歌曲消息
  void _handleTrackMessage(
    WebSocketConnection connection,
    WebSocketMessage message,
  ) {
    try {
      _logger.i('$_tag 收到播放歌曲请求 from ${connection.id}');

      // 解析歌曲数据
      final trackData = json.decode(message.content);

      // 将Map转换为Track对象
      final track = Track.fromJson(trackData);

      _logger.i('$_tag 准备播放歌曲: ${track.title} - ${track.artist}');

      // 调用playsong方法播放歌曲
      try {
        playsong(track, isByClick: true);

        // 发送成功响应
        final successMessage = WebSocketMessageBuilder.createMessage(
          '开始播放歌曲: ${track.title} - ${track.artist}',
        );
        _sendMessage(connection, successMessage);

        _logger.i('$_tag 播放歌曲命令已执行: ${track.title}');
      } catch (e) {
        _logger.e('$_tag 播放歌曲执行失败', error: e);
        final errorMessage = WebSocketMessageBuilder.createErrorMessage(
          _safeExternalError('播放歌曲失败'),
        );
        _sendMessage(connection, errorMessage);
      }
    } catch (e) {
      _logger.e('$_tag 处理播放歌曲消息失败 (解析阶段)', error: e);
      final errorMessage = WebSocketMessageBuilder.createErrorMessage(
        _safeExternalError('解析歌曲数据失败'),
      );
      _sendMessage(connection, errorMessage);
    }
  }

  void _handleTrackNextMessage(
    WebSocketConnection connection,
    WebSocketMessage message,
  ) {
    try {
      _logger.i('$_tag 收到播放下一首请求 from ${connection.id}');

      // 解析歌曲数据
      final trackData = json.decode(message.content);

      // 将Map转换为Track对象
      final track = Track.fromJson(trackData);

      _logger.i('$_tag 准备设置下一首歌曲: ${track.title} - ${track.artist}');

      try {
        Get.find<PlayController>().nextTrack = track;
        _logger.i('$_tag 下一首歌曲已设置: ${track.title}');

        // 发送成功响应
        final successMessage = WebSocketMessageBuilder.createMessage(
          '下一首已设置: ${track.title} - ${track.artist}',
        );
        _sendMessage(connection, successMessage);
      } catch (e) {
        _logger.e('$_tag 设置下一首歌曲失败', error: e);
        final errorMessage = WebSocketMessageBuilder.createErrorMessage(
          _safeExternalError('设置下一首歌曲失败'),
        );
        _sendMessage(connection, errorMessage);
      }
    } catch (e) {
      _logger.e('$_tag 处理播放下一首消息失败 (解析阶段)', error: e);
      final errorMessage = WebSocketMessageBuilder.createErrorMessage(
        _safeExternalError('解析歌曲数据失败'),
      );
      _sendMessage(connection, errorMessage);
    }
  }

  /// 广播播放状态给所有连接的客户端
  void broadcastStatus() {
    if (_connections.isEmpty) {
      _logger.d('$_tag 没有连接的客户端，跳过状态广播');
      return;
    }

    try {
      // 获取 PlayController 实例
      final playController = Get.find<PlayController>();

      // 创建状态数据
      final statusData = PlayStatusData.fromPlayController(playController);

      // 创建状态响应消息
      final statusMessage = WebSocketMessageBuilder.createStatusResponse(
        statusData,
      );

      // 广播状态消息给所有客户端
      _broadcastMessage(statusMessage);

      _logger.i(
        '$_tag 向 ${_connections.length} 个客户端广播播放状态: isPlaying=${statusData.isPlaying}, track=${statusData.currentTrack?.title ?? "None"}',
      );
    } catch (e) {
      _logger.e('$_tag 广播播放状态失败', error: e);
    }
  }

  /// 处理连接关闭
  void _handleConnectionClosed(WebSocketConnection connection) {
    _connections.remove(connection);
    _clientCount.value = _connections.length;
    _logger.i('$_tag 客户端断开连接: ${connection.id}, 剩余连接数: ${_connections.length}');
  }

  /// 处理连接错误
  void _handleConnectionError(WebSocketConnection connection, dynamic error) {
    _logger.e('$_tag WebSocket 连接错误 ${connection.id}', error: error);
    _connections.remove(connection);
    _clientCount.value = _connections.length;
  }

  /// 启动 ping 定时器
  void _startPingTimer() {
    _pingTimer = Timer.periodic(_pingInterval, (timer) {
      _sendPingToAllClients();
      _checkPongTimeout();
    });
  }

  /// 停止 ping 定时器
  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  /// 向所有客户端发送 ping
  void _sendPingToAllClients() {
    final pingMessage = WebSocketMessageBuilder.createPingMessage();

    for (final connection in List<WebSocketConnection>.from(_connections)) {
      connection.lastPing = DateTime.now();
      _sendMessage(connection, pingMessage);
    }

    if (_connections.isNotEmpty) {
      _logger.d('$_tag 向 ${_connections.length} 个客户端发送 ping');
    }
  }

  /// 检查 pong 超时
  void _checkPongTimeout() {
    final now = DateTime.now();
    final timeoutConnections = <WebSocketConnection>[];

    for (final connection in _connections) {
      if (connection.lastPing != null &&
          (connection.lastPong == null ||
              connection.lastPong!.isBefore(connection.lastPing!))) {
        final timeSincePing = now.difference(connection.lastPing!);
        if (timeSincePing > _pongTimeout) {
          timeoutConnections.add(connection);
        }
      }
    }

    // 移除超时的连接
    for (final connection in timeoutConnections) {
      _logger.w('$_tag 客户端 ${connection.id} pong 超时，移除连接');
      try {
        connection.webSocket.close();
      } catch (e) {
        _logger.e('$_tag 关闭超时连接失败', error: e);
      }
      _connections.remove(connection);
    }

    if (timeoutConnections.isNotEmpty) {
      _clientCount.value = _connections.length;
    }
  }

  /// 向指定客户端发送消息
  void _sendMessage(WebSocketConnection connection, dynamic message) {
    try {
      String messageJson;
      if (message is WebSocketMessage) {
        messageJson = message.toJsonString();
      } else if (message is Map<String, dynamic>) {
        messageJson = json.encode(message);
      } else if (message is String) {
        messageJson = message;
      } else {
        messageJson = message.toString();
      }
      if (utf8.encode(messageJson).length > _maxMessageBytes) {
        _logger.w('$_tag 拒绝发送超大消息');
        return;
      }
      connection.webSocket.add(messageJson);
    } catch (e) {
      _logger.e('$_tag 发送消息失败 to ${connection.id}', error: e);
      _connections.remove(connection);
      _clientCount.value = _connections.length;
    }
  }

  /// 广播消息给所有客户端；消息超过大小限制时返回 false。
  bool _broadcastMessage(dynamic message, {String? excludeClient}) {
    String messageJson;
    if (message is WebSocketMessage) {
      messageJson = message.toJsonString();
    } else if (message is Map<String, dynamic>) {
      messageJson = json.encode(message);
    } else if (message is String) {
      messageJson = message;
    } else {
      messageJson = message.toString();
    }

    if (utf8.encode(messageJson).length > _maxMessageBytes) {
      _logger.w('$_tag 拒绝广播超大消息');
      return false;
    }

    final connectionsToRemove = <WebSocketConnection>[];

    for (final connection in _connections) {
      if (excludeClient != null && connection.id == excludeClient) {
        continue;
      }

      try {
        connection.webSocket.add(messageJson);
      } catch (e) {
        _logger.e('$_tag 广播消息失败 to ${connection.id}', error: e);
        connectionsToRemove.add(connection);
      }
    }

    // 移除失败的连接
    for (final connection in connectionsToRemove) {
      _connections.remove(connection);
    }

    if (connectionsToRemove.isNotEmpty) {
      _clientCount.value = _connections.length;
    }
    return true;
  }

  /// 公开的广播方法；消息超过大小限制时返回 false（未发送）。
  bool broadcastMessage(dynamic message) {
    if (message is Map<String, dynamic>) {
      message['timestamp'] = DateTime.now().millisecondsSinceEpoch;
    }
    return _broadcastMessage(message);
  }

  /// 关闭所有连接
  Future<void> _closeAllConnections() async {
    final List<Future> closeFutures = [];

    for (final connection in _connections) {
      try {
        closeFutures.add(connection.webSocket.close());
      } catch (e) {
        _logger.e('$_tag 关闭连接失败 ${connection.id}', error: e);
      }
    }

    await Future.wait(closeFutures);
    _connections.clear();
  }

  bool _isAuthorizedRequest(HttpRequest request) {
    final candidate = request.headers.value('x-listen1-pairing-token');
    return candidate != null &&
        candidate.isNotEmpty &&
        _constantTimeEquals(candidate, accessToken);
  }

  bool _constantTimeEquals(String left, String right) {
    final a = utf8.encode(left);
    final b = utf8.encode(right);
    var result = a.length ^ b.length;
    final length = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }

  void _rejectUnauthorized(HttpRequest request) {
    final candidate = request.headers.value('x-listen1-pairing-token');
    final missing = candidate == null || candidate.isEmpty;
    if (missing) {
      _tokenlessRejections.value++;
      _logger.w(
        '$_tag 拒绝了不带配对令牌的请求（可能是旧版客户端）: '
        '${request.method} ${request.uri.path}',
      );
    }
    request.response
      ..statusCode = HttpStatus.unauthorized
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({
        'error': missing ? 'PairingTokenRequired' : 'Unauthorized',
        if (missing) 'message': missingTokenBody,
      }));
    unawaited(request.response.close());
  }

  static String _safeExternalError(String fallback) => fallback;

  Future<void> _rejectTooLarge(HttpRequest request) async {
    request.response
      ..statusCode = HttpStatus.requestEntityTooLarge
      ..headers.contentType = ContentType.json
      ..write(json.encode({'error': _tooLargeMessage}));
    await request.response.close();
  }

  /// 处理 HTTP 请求（根路径）
  void _handleHttpRequest(HttpRequest request) async {
    if (!_isAuthorizedRequest(request)) {
      _rejectUnauthorized(request);
      return;
    }
    final body = request.contentLength;
    if (body > _maxHttpBodyBytes) {
      await _rejectTooLarge(request);
      return;
    }
    final uri = request.uri.path;

    // 检查是否为 /downloadById/{id} 路由
    if (uri.startsWith('/downloadById/')) {
      if (request.method != 'GET') {
        request.response
          ..statusCode = HttpStatus.methodNotAllowed
          ..write('Method Not Allowed');
        await request.response.close();
        return;
      }
      final id = uri.substring('/downloadById/'.length);
      if (id.isEmpty || id.contains('/') || id.contains('\\')) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..write('Invalid cache ID');
        await request.response.close();
        return;
      }
      await _handleDownloadById(request, id);
      return;
    }

    switch (uri) {
      case '/':
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.text
          ..write('WebSocket Server is running\nConnect to: $serverUrl');
        break;
      case '/status':
        final status = {
          'running': _isRunning.value,
          'clientCount': _clientCount.value,
          'uptime': _serverStartedAt == null
              ? Duration.zero.inSeconds
              : DateTime.now().difference(_serverStartedAt!).inSeconds,
        };
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(json.encode(status));
        break;
      case '/allCacheList':
        try {
          // 获取 CacheController 实例
          final cacheController = Get.find<CacheController>();

          // 获取所有缓存项的 key 列表
          final cacheKeys = await cacheController.localCacheList();

          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(json.encode(cacheKeys));

          _logger.i('$_tag 返回缓存列表: ${cacheKeys.length} 个项目');
        } catch (e) {
          _logger.e('$_tag 获取缓存列表失败', error: e);
          request.response
            ..statusCode = HttpStatus.internalServerError
            ..headers.contentType = ContentType.json
            ..write(
              json.encode({
                'error': 'Internal server error',
                'message': _safeExternalError('Failed to get cache list'),
              }),
            );
        }
        break;
      case '/onPasteFile':
        await _handleOnPasteFile(request);
        return;
      case '/getPasteFile':
        await _handleGetPasteFile(request);
        return;
      case '/onPasteImage':
        await _handleOnPasteImage(request);
        return;
      case '/getPasteImage':
        await _handleGetPasteImage(request);
        return;
      default:
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('Not Found');
    }

    request.response.close();
  }

  /// 处理 /onPasteFile POST 请求 - 接收客户端粘贴的文件并保存到下载目录
  Future<void> _handleOnPasteFile(HttpRequest request) async {
    final generation = _transferGeneration;
    try {
      if (request.method != 'POST') {
        request.response
          ..statusCode = HttpStatus.methodNotAllowed
          ..write('Method Not Allowed');
        await request.response.close();
        return;
      }
      final body = request.contentLength;
      if (body < 0) {
        request.response
          ..statusCode = HttpStatus.lengthRequired
          ..write('Length Required');
        await request.response.close();
        return;
      }
      if (body > _maxHttpBodyBytes) {
        await _rejectTooLarge(request);
        return;
      }
      final contentType = request.headers.contentType;
      if (contentType == null ||
          contentType.mimeType != 'multipart/form-data') {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..write('Expected multipart/form-data');
        request.response.close();
        return;
      }

      final boundary = contentType.parameters['boundary'];
      if (boundary == null) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..write('Missing boundary');
        request.response.close();
        return;
      }

      // 获取下载目录
      final downloadDir = await getPasteFileDownloadDir();

      final savedFiles = await PasteFileTransfer.receive(
        stream: request,
        isCancelled: () => generation != _transferGeneration,
        saveDir: downloadDir,
        boundary: boundary,
        expectedLength: body,
      );

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(json.encode({'saved': savedFiles.length}));
      request.response.close();
      if (savedFiles.isNotEmpty) {
        showSuccessSnackbar('收到 ${savedFiles.length} 个粘贴文件', '已保存到下载目录');
        SharePlus.instance.share(
          ShareParams(files: savedFiles.map((f) => XFile(f)).toList()),
        );
      }
    } on PasteTransferLimitException catch (e) {
      _logger.w('$_tag /onPasteFile 超过大小限制: ${e.message}');
      try {
        await _rejectTooLarge(request);
      } catch (_) {}
    } catch (e) {
      _logger.e('$_tag 处理 /onPasteFile 请求失败', error: e);
      try {
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..write('Internal Server Error');
        request.response.close();
      } catch (_) {}
    }
  }

  /// 处理 /getPasteFile GET 请求 - 将 nowPasteFiles 中的文件以 multipart/mixed 方式流式返回
  Future<void> _handleGetPasteFile(HttpRequest request) async {
    if (request.method != 'GET') {
      request.response
        ..statusCode = HttpStatus.methodNotAllowed
        ..write('Method Not Allowed');
      await request.response.close();
      return;
    }
    var responseStarted = false;
    try {
      // 先只检查文件数量和大小（不读入内存），超限时在发送前返回 413。
      final files = <(File, String, int)>[];
      var totalBytes = 0;
      for (final filePath in List<String>.of(nowPasteFiles)) {
        final file = File(filePath);
        if (!await file.exists()) continue;
        if (files.length >= PasteFileTransfer.defaultMaxFiles) {
          throw const PasteTransferLimitException('粘贴文件数量超过限制');
        }
        final size = await file.length();
        if (size > PasteFileTransfer.defaultMaxPartBytes ||
            totalBytes + size > PasteFileTransfer.defaultMaxTotalBytes) {
          throw const PasteTransferLimitException('粘贴文件总大小超过限制');
        }
        totalBytes += size;
        files.add((file, p.basename(filePath), size));
      }
      if (files.isEmpty) {
        request.response
          ..statusCode = HttpStatus.notFound
          ..headers.contentType = ContentType.json
          ..write(json.encode({'error': 'No paste files available'}));
        await request.response.close();
        return;
      }

      final boundary = '----Listen1Paste${const Uuid().v4()}';
      request.response.statusCode = HttpStatus.ok;
      responseStarted = true;
      request.response.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/mixed; boundary=$boundary',
      );

      for (final (file, fileName, fileSize) in files) {
        final encodedFileName = Uri.encodeComponent(fileName);
        request.response.write('--$boundary\r\n');
        request.response.write(
          'Content-Disposition: attachment; filename*=UTF-8\'\'$encodedFileName\r\n',
        );
        request.response.write('Content-Type: application/octet-stream\r\n');
        request.response.write('Content-Length: $fileSize\r\n');
        request.response.write('\r\n');
        // 只发送校验过的长度；文件若在此期间变短，客户端会按 Content-Length 判定不完整。
        await request.response.addStream(file.openRead(0, fileSize));
        request.response.write('\r\n');
      }

      // 结束 boundary
      request.response.write('--$boundary--\r\n');
      await request.response.close();

      _logger.i('$_tag 返回 ${files.length} 个粘贴文件');
    } on PasteTransferLimitException catch (e) {
      _logger.w('$_tag /getPasteFile 超过大小限制: ${e.message}');
      try {
        await _rejectTooLarge(request);
      } catch (_) {}
    } catch (e) {
      _logger.e('$_tag 处理 /getPasteFile 请求失败', error: e);
      if (responseStarted) {
        try {
          await request.response.close();
        } catch (_) {}
      } else {
        try {
          request.response
            ..statusCode = HttpStatus.internalServerError
            ..write('Internal Server Error');
          await request.response.close();
        } catch (_) {}
      }
    }
  }

  /// 处理 /onPasteImage POST 请求 - 接收客户端粘贴的图片并保存到下载目录
  Future<void> _handleOnPasteImage(HttpRequest request) async {
    final generation = _transferGeneration;
    try {
      if (request.method != 'POST') {
        request.response
          ..statusCode = HttpStatus.methodNotAllowed
          ..write('Method Not Allowed');
        await request.response.close();
        return;
      }
      final body = request.contentLength;
      if (body < 0) {
        request.response
          ..statusCode = HttpStatus.lengthRequired
          ..write('Length Required');
        await request.response.close();
        return;
      }
      if (body > PasteFileTransfer.defaultMaxPartBytes) {
        await _rejectTooLarge(request);
        return;
      }

      // 从请求头中获取文件名
      final fileName =
          request.headers.value('x-filename') ??
          'paste_image_${DateTime.now().millisecondsSinceEpoch}.png';
      final decodedFileName = Uri.decodeComponent(fileName);

      final savedFiles = await PasteFileTransfer.receive(
        stream: request,
        isCancelled: () => generation != _transferGeneration,
        saveDir: await getPasteFileDownloadDir(),
        fileName: decodedFileName,
        expectedLength: body,
      );
      final savePath = savedFiles.single;

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(json.encode({'saved': 1, 'fileName': p.basename(savePath)}));
      request.response.close();

      showSuccessSnackbar('收到粘贴图片', '已保存到 ${p.basename(savePath)}');
      _logger.i('$_tag 保存粘贴图片: $savePath');
    } on PasteTransferLimitException catch (e) {
      _logger.w('$_tag /onPasteImage 超过大小限制: ${e.message}');
      try {
        await _rejectTooLarge(request);
      } catch (_) {}
    } catch (e) {
      _logger.e('$_tag 处理 /onPasteImage 请求失败', error: e);
      try {
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..write('Internal Server Error');
        request.response.close();
      } catch (_) {}
    }
  }

  /// 处理 /getPasteImage GET 请求 - 流式返回磁盘中的图片快照
  Future<void> _handleGetPasteImage(HttpRequest request) async {
    if (request.method != 'GET') {
      request.response
        ..statusCode = HttpStatus.methodNotAllowed
        ..write('Method Not Allowed');
      await request.response.close();
      return;
    }
    try {
      final image = _pasteImage;
      if (image == null) {
        request.response
          ..statusCode = HttpStatus.notFound
          ..headers.contentType = ContentType.json
          ..write(json.encode({'error': 'No paste image available'}));
        request.response.close();
        return;
      }

      await image.send((file) async {
        final encodedFileName = Uri.encodeComponent(image.name);
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.set(
            HttpHeaders.contentTypeHeader,
            'application/octet-stream',
          )
          ..headers.contentLength = await file.length()
          ..headers.set(
            'content-disposition',
            "attachment; filename*=UTF-8''$encodedFileName",
          );
        await request.response.addStream(file.openRead());
        await request.response.close();
      });
      _logger.i('$_tag 返回粘贴图片: ${image.name}');
    } catch (e) {
      _logger.e('$_tag 处理 /getPasteImage 请求失败', error: e);
      try {
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..write('Internal Server Error');
        request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _sendNotFound(HttpRequest request) async {
    request.response
      ..statusCode = HttpStatus.notFound
      ..headers.contentType = ContentType.json
      ..write(json.encode({'error': 'File not found'}));
    await request.response.close();
  }

  /// 处理根据 ID 下载文件的请求
  Future<void> _handleDownloadById(HttpRequest request, String id) async {
    try {
      // 获取 CacheController 实例
      final cacheController = Get.find<CacheController>();

      // 从缓存中获取文件路径
      final filePath = await cacheController.getLocalCache(id);

      if (filePath.isEmpty) {
        await _sendNotFound(request);
        return;
      }

      final file = File(filePath);
      if (!await file.exists()) {
        await _sendNotFound(request);
        return;
      }

      // 获取文件信息
      final fileStats = await file.stat();
      final fileName = file.path.split(Platform.pathSeparator).last;

      // 对文件名进行URL编码以支持非ASCII字符
      final encodedFileName = Uri.encodeComponent(fileName);

      // 设置响应头
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.set(HttpHeaders.contentTypeHeader, 'application/octet-stream')
        ..headers.set(
          HttpHeaders.contentLengthHeader,
          fileStats.size.toString(),
        )
        ..headers.set(
          'content-disposition',
          'attachment; filename*=UTF-8\'\'$encodedFileName',
        );

      // 读取并发送文件内容
      final fileStream = file.openRead();
      await fileStream.pipe(request.response);

      _logger.i('$_tag 成功处理文件下载请求: 文件=$fileName');
    } catch (e, stackTrace) {
      _logger.e('$_tag 处理文件下载请求失败', error: e, stackTrace: stackTrace);

      try {
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..headers.contentType = ContentType.json
          ..write(
            json.encode({
              'error': 'Internal server error',
              'message': _safeExternalError('Failed to process download request'),
            }),
          );
        request.response.close();
      } catch (closeError) {
        _logger.e('$_tag 关闭错误响应失败', error: closeError);
      }
    }
  }

  /// 获取播放模式文本描述
  String _getPlayModeText(int playMode) {
    switch (playMode) {
      case 0:
        return '循环播放';
      case 1:
        return '随机播放';
      case 2:
        return '单曲循环';
      default:
        return '未知模式';
    }
  }

  @override
  void onClose() {
    _logger.i('$_tag 控制器销毁中...');

    // 停止服务器（这会自动清理所有资源）
    stopServer()
        .then((_) {
          _logger.i('$_tag 控制器已销毁');
        })
        .catchError((error) {
          _logger.e('$_tag 销毁时出错', error: error);
        });

    super.onClose();
  }
}

/// WebSocket 连接信息类
class WebSocketConnection {
  final WebSocket webSocket;
  final String id;
  final DateTime connectedAt;
  DateTime? lastPing;
  DateTime? lastPong;

  WebSocketConnection({
    required this.webSocket,
    required this.id,
    required this.connectedAt,
  });
}
