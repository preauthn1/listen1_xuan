part of '../../settings.dart';

class Github {
  static const String OAUTH_URL = 'https://github.com/login/oauth';
  static const String API_URL = 'https://api.github.com';

  static const String clientId = 'e099a4803bb1e2e773a3';

  static final RxInt status = 0.obs;
  static String username = '';
  static bool usedefault = false;

  static Future<Response<dynamic>> _postGithub(
    String url,
    Map<String, dynamic> data,
  ) async {
    final options = Options(
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      responseType: ResponseType.json,
      validateStatus: (status) => status != null && status < 500,
    );
    try {
      return await dioWithProxyAdapter.post(url, data: data, options: options);
    } catch (_) {
      return Dio().post(url, data: data, options: options);
    }
  }

  static Map<String, dynamic> _asJsonMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const FormatException('GitHub 返回数据格式无效');
  }

  static Future<Map<String, dynamic>> _requestDeviceCode() async {
    final response = await _postGithub('$OAUTH_URL/device/code', {
      'client_id': clientId,
      'scope': 'gist',
    });
    final data = _asJsonMap(response.data);
    if (response.statusCode != 200) {
      throw FormatException(data['error_description'] ?? data['error'] ?? '设备授权不可用');
    }
    for (final key in ['device_code', 'user_code', 'verification_uri']) {
      if (data[key] is! String || (data[key] as String).isEmpty) {
        throw const FormatException('GitHub 设备授权响应缺少必要字段');
      }
    }
    return data;
  }

  static Future<Map<String, dynamic>> _pollDeviceToken(
    String deviceCode,
  ) async {
    final response = await _postGithub('$OAUTH_URL/access_token', {
      'client_id': clientId,
      'device_code': deviceCode,
      'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
    });
    if (response.statusCode != 200 && response.statusCode != 400) {
      throw const HttpException('GitHub 设备授权请求失败');
    }
    return _asJsonMap(response.data);
  }

  static Future<void> _completeDeviceAuthorization(
    String accessToken, {
    VoidCallback? onCompleted,
  }) async {
    if (accessToken.trim().isEmpty) {
      throw const FormatException('GitHub 未返回访问令牌');
    }
    final s = Get.find<SettingsController>();
    await s.setString('githubOauthAccessKey', accessToken.trim());
    final verifiedStatus = await updateStatus();
    if (verifiedStatus != 2) {
      await s.remove(key: 'githubOauthAccessKey');
      throw const FormatException('GitHub 令牌验证失败');
    }
    status.value = 2;
    showInfoSnackbar('设置成功', null);
    onCompleted?.call();
  }

  static String? _pkceVerifier;
  static String? _oauthState;

  static String _randomUrlSafe(int length) {
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  static String _pkceChallenge(String verifier) {
    return base64UrlEncode(sha256.convert(utf8.encode(verifier)).bytes)
        .replaceAll('=', '');
  }

  static String _openWebAuthUrl() {
    final verifier = _randomUrlSafe(64);
    final state = _randomUrlSafe(32);
    _pkceVerifier = verifier;
    _oauthState = state;
    final uri = Uri.https('github.com', '/login/oauth/authorize', {
      'client_id': clientId,
      'scope': 'gist',
      'state': state,
      'code_challenge': _pkceChallenge(verifier),
      'code_challenge_method': 'S256',
    });
    return uri.toString();
  }

  static Future<void> handleCallback(
    String callbackUrl, {
    VoidCallback? onCompleted,
  }) async {
    try {
      final uri = Uri.tryParse(callbackUrl);
      final code = uri?.queryParameters['code'];
      final state = uri?.queryParameters['state'];
      if (code == null || state == null || state != _oauthState) {
        throw const FormatException('授权回调无效');
      }
      final verifier = _pkceVerifier;
      if (verifier == null) throw const FormatException('授权会话已过期');
      final response = await _postGithub('$OAUTH_URL/access_token', {
        'client_id': clientId,
        'code': code,
        'state': state,
        'code_verifier': verifier,
      });
      final data = _asJsonMap(response.data);
      final token = data['access_token'];
      if (response.statusCode != 200 || token is! String) {
        throw const FormatException('GitHub 授权失败');
      }
      await _completeDeviceAuthorization(token, onCompleted: onCompleted);
    } catch (e, stackTrace) {
      status.value = 0;
      debugPrint('GitHub 网页授权失败: ${e.runtimeType}\\n$stackTrace');
      showErrorSnackbar('登录失败', 'GitHub 授权未完成，请重新尝试');
    } finally {
      _pkceVerifier = null;
      _oauthState = null;
    }
  }
  static Future<void> openAuthUrl() async {
    status.value = 1;
    try {
      final device = await _requestDeviceCode();
      Get.dialog(
        GithubDeviceAuthDialog(
          deviceCode: device['device_code'] as String,
          userCode: device['user_code'] as String,
          verificationUri: (device['verification_uri'] ??
                  device['verification_uri_complete']) as String,
          expiresIn: (device['expires_in'] as num?)?.toInt() ?? 900,
          interval: (device['interval'] as num?)?.toInt() ?? 5,
        ),
      );
    } catch (_) {
      status.value = 0;
      showErrorSnackbar('登录失败', 'GitHub 设备授权不可用，请稍后重试');
    }
  }

  static int getStatus() => status.value;

  static String getStatusText() {
    switch (status.value) {
      case 0:
        return '未连接';
      case 1:
        return '连接中';
      case 2:
        return '$username已登录';
      default:
        return '???';
    }
  }

  static Future<int> updateStatus() async {
    // final accessToken = localStorage.getItem('githubOauthAccessKey');
    // final accessToken = null; // Replace with actual access token retrieval
    final s = Get.find<SettingsController>();

    final accessToken = await s.getString('githubOauthAccessKey');
    if (accessToken == null) {
      status.value = 0;
    } else {
      var response;
      try {
        response = await dioWithProxyAdapter.get(
          '$API_URL/user',
          options: Options(
            headers: {
              'Authorization': 'Bearer $accessToken',
              'Accept': 'application/json',
            },
          ),
        );
      } catch (e) {
        usedefault = true;
        try {
          response = await Dio().get(
            '$API_URL/user',
            options: Options(
              headers: {
                'Authorization': 'Bearer $accessToken',
                'Accept': 'application/json',
              },
            ),
          );
        } catch (e) {
          status.value = 0;
          return status.value;
        }
      }

      final data = _asJsonMap(response.data);
      if (data['login'] == null || response.statusCode != 200) {
        await s.remove(key: 'githubOauthAccessKey');
        status.value = 0;
      } else {
        status.value = 2;
        username = data['login'];
      }
    }
    return status.value;
  }

  static Future<void> logout() async {
    final s = Get.find<SettingsController>();
    await s.remove(key: 'githubOauthAccessKey');
    status.value = 0;
    username = '';
  }

  static Map<String, dynamic> json2gist(Map<String, dynamic> jsonObject) {
    final result = <String, dynamic>{};

    result['listen1_backup.json'] = {'content': json.encode(jsonObject)};

    final playlistIds = jsonObject['playerlists'];
    final songsCount = playlistIds.fold<int>(0, (count, playlistId) {
      final playlist = jsonObject[playlistId];
      final cover =
          '<img src="${playlist['info']['cover_img_url']}" width="140" height="140"><br/>';
      final title = playlist['info']['title'];
      var tableHeader = '\n| 音乐标题 | 歌手 | 专辑 |\n';
      tableHeader += '| --- | --- | --- |\n';
      final tableBody = playlist['tracks'].fold<String>('', (r, track) {
        return '$r | ${track['title']} | ${track['artist']} | ${track['album']} | \n';
      });
      final content =
          '<details>\n  <summary>$cover   $title</summary><p>\n$tableHeader$tableBody</p></details>';
      final filename = 'listen1_$playlistId.md';
      result[filename] = {'content': content};
      return (count as int) + (playlist['tracks'].length as int);
    });
    final summary =
        '本歌单由[listen1_xuan](https://github.com/HBWuChang/listen1_xuan)创建, 歌曲数：$songsCount，歌单数：${playlistIds.length}，点击查看更多';
    result['listen1_aha_playlist.md'] = {'content': summary};

    return result;
  }

  static Future<Map<String, dynamic>> gist2json(
    Map<String, dynamic> gistFiles,
  ) async {
    final backup = gistFiles['listen1_backup.json'];
    if (backup is! Map) throw const FormatException('Gist 备份文件缺失');
    if (backup['truncated'] != true) {
      final jsonString = backup['content'];
      if (jsonString is! String || jsonString.length > 4 * 1024 * 1024) {
        throw const FormatException('Gist 备份内容无效或过大');
      }
      return json.decode(jsonString);
    } else {
      final url = backup['raw_url'];
      final uri = Uri.tryParse(url);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host != 'raw.githubusercontent.com' &&
          uri.host != 'gist.githubusercontent.com' ||
          uri.userInfo.isNotEmpty ||
          uri.hasPort ||
          uri.hasQuery ||
          uri.hasFragment ||
          !uri.path.startsWith('/HBWuChang/')) {
        throw const FormatException('备份文件地址不受信任');
      }
      final response = await (usedefault ? Dio() : dioWithProxyAdapter).get(
        uri.toString(),
        options: Options(
          headers: {
            'Accept': 'application/json',
            if (!usedefault) 'Authorization': 'Bearer ${await Get.find<SettingsController>().getString('githubOauthAccessKey')}',
          },
          validateStatus: (status) => status != null && status < 400,
        ),
      );
      if (response.data is! String && response.data is! List<int>) {
        throw const FormatException('Gist 备份响应格式无效');
      }
      final raw = response.data is String
          ? response.data as String
          : utf8.decode(response.data as List<int>);
      if (raw.length > 4 * 1024 * 1024) {
        throw const FormatException('Gist 备份超过大小限制');
      }
      return json.decode(raw);
    }
  }

  static Future<List<dynamic>> listExistBackup() async {
    final s = Get.find<SettingsController>();
    final accessToken = await s.getString('githubOauthAccessKey');
    final response = await (usedefault ? Dio() : dioWithProxyAdapter).get(
      '$API_URL/gists',
      options: Options(
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/vnd.github.v3+json',
        },
      ),
    );
    final result = response.data;
    return result.where((backupObject) {
      return backupObject['description'] != null &&
          backupObject['description'].startsWith('updated by Listen1');
    }).toList();
  }

  static Future<void> backupMySettings2Gist(
    Map<String, dynamic> files,
    String? gistId,
    bool isPublic,
  ) async {
    String method;
    String url;
    if (gistId != null) {
      method = 'patch';
      url = '$API_URL/gists/$gistId';
    } else {
      method = 'post';
      url = '$API_URL/gists';
    }
    final s = Get.find<SettingsController>();
    final accessToken = await s.getString('githubOauthAccessKey');
    await (usedefault ? Dio() : dioWithProxyAdapter).request(
      url,
      options: Options(
        method: method,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/json',
        },
      ),
      data: {
        'description':
            'updated by Listen1_xuan(https://github.com/HBWuChang/listen1_xuan) at ${DateTime.now().toLocal()}',
        'public': isPublic,
        'files': files,
      },
    );
  }

  static Future<Map<String, dynamic>> importMySettingsFromGist(
    String gistId,
  ) async {
    final s = Get.find<SettingsController>();
    final accessToken = await s.getString('githubOauthAccessKey');
    final response = await (usedefault ? Dio() : dioWithProxyAdapter).get(
      '$API_URL/gists/$gistId',
      options: Options(
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/json',
        },
      ),
    );
    return response.data['files'];
  }

  static Future<String> getLatestReleaseVersionBuildNumber() async {
    final latestRelease = await getLatestRelease();
    final tagName = latestRelease.tagName;
    return tagName.split('+').last;
  }

  static Future<GitHubRelease> getLatestRelease() async {
    return (await getReleasesList()).first;
  }

  static Future<List<GitHubRelease>> getReleasesList() async {
    //   curl -L \
    // -H "Accept: application/vnd.github+json" \
    // -H "Authorization: Bearer <YOUR-TOKEN>" \
    // -H "X-GitHub-Api-Version: 2022-11-28" \
    // https://api.github.com/repos/OWNER/REPO/releases

    late Response response;
    try {
      response = await (usedefault ? Dio() : dioWithProxyAdapter).get(
        '$API_URL/repos/HBWuChang/listen1_xuan/releases',
        options: Options(
          headers: {
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
          },
        ),
      );
    } catch (e) {
      response = await Dio().get(
        '$API_URL/repos/HBWuChang/listen1_xuan/releases',
        options: Options(
          headers: {
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
          },
        ),
      );
    }
    List<dynamic> releasesData = response.data;
    List<GitHubRelease> releases = releasesData
        .map((releaseJson) => GitHubRelease.fromJson(releaseJson))
        .toList();
    return releases;
  }
}

class GithubAuthDialog extends StatefulWidget {
  final String url;

  const GithubAuthDialog({super.key, required this.url});

  @override
  State<GithubAuthDialog> createState() => _GithubAuthDialogState();
}

class _GithubAuthDialogState extends State<GithubAuthDialog> {
  final TextEditingController _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _submit(String url) {
    Github.handleCallback(
      url,
      onCompleted: () {
        if (mounted) Navigator.of(context).pop();
        Get.find<SettingsController>().refreshLoginData();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('GitHub 授权'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SelectableText('请打开授权网页，授权后将回调地址复制到下面的输入框中。'),
          TextField(
            controller: _codeController,
            decoration: const InputDecoration(labelText: '回调地址'),
            onSubmitted: _submit,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Github.status.value = 0;
            Github._pkceVerifier = null;
            Github._oauthState = null;
            Navigator.of(context).pop();
          },
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => g_launchURL(Uri.parse(widget.url)),
          child: const Text('打开授权网页'),
        ),
        TextButton(
          onPressed: () => _submit(_codeController.text),
          child: const Text('我已输入'),
        ),
      ],
    );
  }
}
class GithubDeviceAuthDialog extends StatefulWidget {
  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final int expiresIn;
  final int interval;

  const GithubDeviceAuthDialog({
    super.key,
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresIn,
    required this.interval,
  });

  @override
  State<GithubDeviceAuthDialog> createState() => _GithubDeviceAuthDialogState();
}
class _GithubDeviceAuthDialogState extends State<GithubDeviceAuthDialog> {
  Timer? _pollTimer;
  Timer? _countdownTimer;
  bool _polling = false;
  int _remaining = 0;
  int _interval = 5;

  @override
  void initState() {
    super.initState();
    _remaining = widget.expiresIn.clamp(1, 900).toInt();
    _interval = widget.interval.clamp(5, 60).toInt();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _remaining <= 1) {
        _countdownTimer?.cancel();
        _pollTimer?.cancel();
        if (mounted && _remaining <= 1) {
          Github.status.value = 0;
          Navigator.of(context).pop();
          showErrorSnackbar('登录超时', 'GitHub 设备授权码已过期，请重新尝试');
        }
        return;
      }
      setState(() => _remaining--);
    });
    _pollTimer = Timer.periodic(Duration(seconds: _interval), (_) => _poll());
  }

  Future<void> _poll() async {
    if (_polling || !mounted || _remaining <= 0) return;
    _polling = true;
    try {
      final response = await Github._pollDeviceToken(widget.deviceCode);
      final error = response['error'];
      if (error == 'authorization_pending') {
        return;
      }
      if (response['access_token'] is String) {
        _pollTimer?.cancel();
        _countdownTimer?.cancel();
        await Github._completeDeviceAuthorization(
          response['access_token'] as String,
          onCompleted: () {
            if (mounted) Navigator.of(context).pop();
            Get.find<SettingsController>().refreshLoginData();
          },
        );
      } else if (error == 'slow_down') {
        _interval = (_interval + 5).clamp(5, 120).toInt();
        _pollTimer?.cancel();
        _pollTimer = Timer.periodic(Duration(seconds: _interval), (_) => _poll());
      } else {
        throw FormatException('GitHub 授权失败: ${error ?? '未知错误'}');
      }
    } catch (e, stackTrace) {
      _pollTimer?.cancel();
      _countdownTimer?.cancel();
      Github.status.value = 0;
      debugPrint('GitHub 设备授权轮询失败: ${e.runtimeType}\n$stackTrace');
      if (mounted) {
        Navigator.of(context).pop();
        showErrorSnackbar('登录失败', 'GitHub 授权未完成，请重新尝试');
      }
    } finally {
      _polling = false;
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('GitHub 授权'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('请打开 GitHub 设备授权页面，并输入以下一次性验证码：'),
          const SizedBox(height: 12),
          SelectableText(
            widget.userCode,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SelectableText(widget.verificationUri),
          const SizedBox(height: 12),
          Text('授权窗口保持打开，应用会自动等待确认（剩余约 $_remaining 秒）。'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => g_launchURL(Uri.parse(widget.verificationUri)),
          child: const Text('打开授权页面'),
        ),
        TextButton(
          onPressed: () => Clipboard.setData(
            ClipboardData(text: widget.verificationUri),
          ),
          child: const Text('复制地址'),
        ),
        TextButton(
          onPressed: () {
            _pollTimer?.cancel();
            _countdownTimer?.cancel();
            Github.status.value = 0;
            Navigator.of(context).pop();
          },
          child: const Text('取消'),
        ),
      ],
    );
  }
}
