import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';

import '../constants/network_defaults.dart';
import 'cache_audio_metadata.dart';

typedef BilibiliDownloadProgress =
    void Function(int receivedBytes, int totalBytes);
typedef BilibiliTranscodeProgress =
    void Function(int outputBytes, double speed);

class BilibiliMp3Transcoder {
  const BilibiliMp3Transcoder();

  static const int _maxOutputBytes = 64 * 1024 * 1024;
  static const Duration _maxDuration = Duration(minutes: 10);
  static const _maxErrorLength = 2000;
  Future<void> transcode({
    required Dio dio,
    required String sourceUrl,
    required String outputPath,
    required bool retainMetadata,
    CacheTrackMetadata? metadata,
    String? coverPath,
    BilibiliDownloadProgress? onDownloadProgress,
    BilibiliTranscodeProgress? onTranscodeProgress,
  }) async {
    final proxy = await _BilibiliAudioProxy.start(
      dio: dio,
      sourceUrl: sourceUrl,
      onProgress: onDownloadProgress,
    );

    final completedSession = Completer<FFmpegSession>();
    FFmpegSession? runningSession;
    Timer? timeoutTimer;
    Future<FFmpegSession>? executeFuture;
    try {
      timeoutTimer = Timer(_maxDuration, () {
        if (runningSession != null) {
          FFmpegKit.cancel();
        } else {
          // The native plugin may return its session only after completion;
          // the no-argument cancel is the only portable emergency fallback.
          FFmpegKit.cancel();
        }
        if (!completedSession.isCompleted) {
          completedSession.completeError(
            const BilibiliTranscodeException('FFmpeg 转码超时'),
          );
        }
      });
      executeFuture = FFmpegKit.executeWithArgumentsAsync(
        buildArguments(
          proxy.url.toString(),
          outputPath,
          retainMetadata: retainMetadata,
          metadata: metadata,
          coverPath: coverPath,
        ),
        (session) {
          runningSession = session;
          if (!completedSession.isCompleted) completedSession.complete(session);
        },
        null,
        (statistics) {
          onTranscodeProgress?.call(
            statistics.getSize(),
            statistics.getSpeed(),
          );
        },
      );
      await executeFuture;
      final session = await completedSession.future;
      if (runningSession == null) runningSession = session;

      final returnCode = await session.getReturnCode();
      if (!ReturnCode.isSuccess(returnCode)) {
        final output = await session.getOutput();
        throw BilibiliTranscodeException(_errorMessage(output));
      }
      final outputFile = File(outputPath);
      if (await outputFile.length() > _maxOutputBytes) {
        throw const BilibiliTranscodeException('输出音频超过大小限制');
      }
      await CacheAudioMetadata.validateAudioOutput(outputPath);
    } finally {
      timeoutTimer?.cancel();
      if (runningSession != null) {
        try {
          final returnCode = await runningSession!.getReturnCode();
          if (!ReturnCode.isSuccess(returnCode)) {
            // The session has already terminated or was cancelled.
          }
        } catch (_) {}
      }
      await proxy.close();
      if (await File(outputPath).exists() &&
          await File(outputPath).length() > _maxOutputBytes) {
        await File(outputPath).delete();
      }
    }
  }

  static List<String> buildArguments(
    String inputUrl,
    String outputPath, {
    bool retainMetadata = false,
    CacheTrackMetadata? metadata,
    String? coverPath,
  }) {
    final embedCover = CacheAudioMetadata.shouldEmbedCover(
      retainMetadata: retainMetadata,
      outputPath: outputPath,
      coverPath: coverPath,
    );
    return [
      '-hide_banner',
      '-nostdin',
      '-loglevel',
      'warning',
      '-reconnect',
      '1',
      '-reconnect_streamed',
      '1',
      '-reconnect_delay_max',
      '5',
      '-i',
      inputUrl,
      if (embedCover) ...['-i', coverPath!],
      '-map',
      '0:a:0',
      if (embedCover) ...['-map', '1:v:0'],
      if (!embedCover) '-vn',
      '-ac',
      '2',
      '-c:a',
      'libmp3lame',
      '-q:a',
      '2',
      '-compression_level',
      '9',
      '-threads',
      '0',
      if (embedCover) ...CacheAudioMetadata.coverOutputArguments(),
      ...CacheAudioMetadata.outputMetadataArguments(
        retainMetadata: retainMetadata,
        metadata: metadata,
        outputPath: outputPath,
      ),
      '-f',
      'mp3',
      '-y',
      outputPath,
    ];
  }

  static String _errorMessage(String? output) {
    final message = output?.trim() ?? '';
    if (message.isEmpty) return 'FFmpeg 转码失败';
    if (message.length <= _maxErrorLength) return message;
    return 'FFmpeg 输出过长，仅显示末尾：\n'
        '${message.substring(message.length - _maxErrorLength)}';
  }
}

class BilibiliTranscodeException implements Exception {
  const BilibiliTranscodeException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _BilibiliAudioProxy {
  static const int _maxInputBytes = 256 * 1024 * 1024;
  static const Duration _maxDuration = Duration(minutes: 10);
  static const int _maxOutputBytes = 64 * 1024 * 1024;
  _BilibiliAudioProxy._({
    required this.server,
    required this.url,
    required this.dio,
    required this.sourceUrl,
    required this.onProgress,
  });

  final HttpServer server;
  final Uri url;
  final Dio dio;
  final String sourceUrl;
  final BilibiliDownloadProgress? onProgress;
  final Set<CancelToken> _cancelTokens = {};
  StreamSubscription<HttpRequest>? _subscription;

  static Future<_BilibiliAudioProxy> start({
    required Dio dio,
    required String sourceUrl,
    BilibiliDownloadProgress? onProgress,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final token = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final proxy = _BilibiliAudioProxy._(
      server: server,
      url: Uri.parse('http://127.0.0.1:${server.port}/$token/audio'),
      dio: dio,
      sourceUrl: sourceUrl,
      onProgress: onProgress,
    );
    proxy._subscription = server.listen(proxy._handleRequest);
    return proxy;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    response.bufferOutput = false;
    if (request.uri.path != url.path || request.method != 'GET') {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }

    final cancelToken = CancelToken();
    _cancelTokens.add(cancelToken);
    var responseStarted = false;
    try {
      final headers = Map<String, String>.from(kBilibiliPlayHeader)
        ..remove(HttpHeaders.rangeHeader);
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null && range.isNotEmpty) {
        headers[HttpHeaders.rangeHeader] = range;
      }

      final upstream = await dio.get<ResponseBody>(
        sourceUrl,
        cancelToken: cancelToken,
        options: Options(
          headers: headers,
          responseType: ResponseType.stream,
          validateStatus: (status) => status != null && status < 400,
        ),
      );
      final body = upstream.data;
      if (body == null) {
        throw const BilibiliTranscodeException('Bilibili 音频响应为空');
      }

      response.statusCode = upstream.statusCode ?? HttpStatus.ok;
      _copyHeader(upstream, response, HttpHeaders.acceptRangesHeader);
      _copyHeader(upstream, response, HttpHeaders.contentRangeHeader);
      _copyHeader(upstream, response, HttpHeaders.contentTypeHeader);
      final contentLength = int.tryParse(
        upstream.headers.value(HttpHeaders.contentLengthHeader) ?? '',
      );
      if (contentLength != null && contentLength > _maxInputBytes) {
        throw const BilibiliTranscodeException('输入音频超过大小限制');
      }
      if (contentLength != null && contentLength >= 0) {
        response.contentLength = contentLength;
      }
      responseStarted = true;

      final rangeStart = _rangeStart(
        upstream.headers.value(HttpHeaders.contentRangeHeader),
      );
      final total = _totalLength(
        upstream.headers.value(HttpHeaders.contentRangeHeader),
        contentLength,
      );
      var received = 0;
      var outputBytes = 0;
      final stream = body.stream.map((chunk) {
        received += chunk.length;
        outputBytes += chunk.length;
        if (received > _maxInputBytes || outputBytes > _maxOutputBytes) {
          throw const BilibiliTranscodeException('音频传输超过大小限制');
        }
        onProgress?.call(rangeStart + received, total);
        return chunk;
      });
      await response.addStream(stream).timeout(_maxDuration);
    } catch (_) {
      if (!responseStarted) response.statusCode = HttpStatus.badGateway;
    } finally {
      _cancelTokens.remove(cancelToken);
      try {
        await response.close();
      } catch (_) {}
    }
  }

  static void _copyHeader(
    Response<ResponseBody> upstream,
    HttpResponse response,
    String name,
  ) {
    final value = upstream.headers.value(name);
    if (value != null && value.isNotEmpty) response.headers.set(name, value);
  }

  static int _rangeStart(String? contentRange) {
    final match = RegExp(r'^bytes\s+(\d+)-').firstMatch(contentRange ?? '');
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  static int _totalLength(String? contentRange, int? contentLength) {
    final match = RegExp(r'/(\d+)$').firstMatch(contentRange ?? '');
    return int.tryParse(match?.group(1) ?? '') ?? contentLength ?? -1;
  }

  Future<void> close() async {
    for (final token in _cancelTokens) {
      if (!token.isCancelled) token.cancel('Bilibili 转码已结束');
    }
    _cancelTokens.clear();
    await _subscription?.cancel();
    await server.close(force: true);
  }
}
