import 'dart:convert';
import 'dart:io';

/// 把用户从浏览器复制或导出的 Cookie 统一解析成 [Cookie] 列表。
///
/// 支持的格式：
/// - 请求头：`Cookie: a=1; b=2`，或不带前缀的 `a=1; b=2`
/// - 浏览器扩展导出的 JSON：EditThisCookie / Cookie-Editor 的数组，
///   或包含 `cookies` 数组的对象（字段 `name`、`value`、`domain`）
/// - Netscape `cookies.txt`（制表符分隔的七列）
///
/// [domains] 不为空时，只保留属于这些站点的 Cookie；
/// 不含域名信息的格式（请求头）全部保留。
class CookieImport {
  const CookieImport._();

  static const int maxInputLength = 256 * 1024;

  static List<Cookie> parse(String input, {List<String> domains = const []}) {
    final text = input.trim();
    if (text.isEmpty) return const [];
    if (text.length > maxInputLength) {
      throw const FormatException('内容过长，请只粘贴目标站点的 Cookie');
    }
    final List<_Entry> entries;
    if (text.startsWith('[') || text.startsWith('{')) {
      entries = _fromJson(text);
    } else if (_looksLikeNetscape(text)) {
      entries = _fromNetscape(text);
    } else {
      entries = _fromHeader(text);
    }
    final wanted = domains.map(_hostOf).where((h) => h.isNotEmpty).toList();
    final result = <String, Cookie>{};
    for (final e in entries) {
      if (e.name.isEmpty || !_validName(e.name)) continue;
      if (e.domain != null && wanted.isNotEmpty && !_matches(e.domain!, wanted)) continue;
      // 同名 Cookie 以最后出现的为准（与浏览器覆盖行为一致）。
      result[e.name] = Cookie(e.name, _sanitizeValue(e.value));
    }
    return result.values.toList();
  }

  /// 缺少 [required] 中任意一个非空 Cookie 时返回缺失的名称。
  static List<String> missing(List<Cookie> cookies, List<String> required) {
    final present = cookies.where((c) => c.value.isNotEmpty).map((c) => c.name).toSet();
    return required.where((name) => !present.contains(name)).toList();
  }

  static List<_Entry> _fromHeader(String text) {
    var body = text;
    final lines = body.split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty);
    // 允许粘贴整段请求头：只取 Cookie 那一行。
    final cookieLine = lines.firstWhere(
      (l) => l.toLowerCase().startsWith('cookie:'),
      orElse: () => lines.join('; '),
    );
    body = cookieLine.toLowerCase().startsWith('cookie:')
        ? cookieLine.substring('cookie:'.length)
        : cookieLine;
    return body
        .split(';')
        .map((part) => part.trim())
        .where((part) => part.contains('='))
        .map((part) {
          final i = part.indexOf('=');
          return _Entry(part.substring(0, i).trim(), part.substring(i + 1).trim(), null);
        })
        .toList();
  }

  static List<_Entry> _fromJson(String text) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const FormatException('JSON 格式不正确');
    }
    final list = decoded is List
        ? decoded
        : decoded is Map && decoded['cookies'] is List
            ? decoded['cookies'] as List
            : throw const FormatException('JSON 中没有找到 Cookie 数组');
    return list
        .whereType<Map>()
        .map((m) => _Entry(
              '${m['name'] ?? ''}'.trim(),
              '${m['value'] ?? ''}',
              m['domain'] == null ? null : '${m['domain']}',
            ))
        .toList();
  }

  static bool _looksLikeNetscape(String text) =>
      text.startsWith('# Netscape HTTP Cookie File') ||
      text.split(RegExp(r'\r?\n')).any((l) => l.split('\t').length >= 7);

  static List<_Entry> _fromNetscape(String text) {
    final out = <_Entry>[];
    for (var line in text.split(RegExp(r'\r?\n'))) {
      if (line.startsWith('#HttpOnly_')) line = line.substring('#HttpOnly_'.length);
      if (line.isEmpty || line.startsWith('#')) continue;
      final cols = line.split('\t');
      if (cols.length < 7) continue;
      out.add(_Entry(cols[5].trim(), cols.sublist(6).join('\t').trim(), cols[0].trim()));
    }
    return out;
  }

  static String _hostOf(String url) {
    final uri = Uri.tryParse(url);
    final host = (uri != null && uri.host.isNotEmpty) ? uri.host : url;
    return _registrable(host.toLowerCase());
  }

  /// 取站点主域（如 `api.bilibili.com` → `bilibili.com`），用于宽松匹配子域 Cookie。
  static String _registrable(String host) {
    final parts = host.replaceFirst(RegExp(r'^\.'), '').split('.');
    return parts.length <= 2 ? parts.join('.') : parts.sublist(parts.length - 2).join('.');
  }

  static bool _matches(String domain, List<String> wanted) {
    final d = _registrable(domain.toLowerCase());
    return wanted.contains(d);
  }

  static bool _validName(String name) => RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$").hasMatch(name);

  /// 去掉会破坏请求头的字符；保留 URL 编码值原样（如 B 站 SESSDATA）。
  static String _sanitizeValue(String value) {
    var v = value.trim();
    if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) v = v.substring(1, v.length - 1);
    return v.replaceAll(RegExp(r'[\r\n;\x00-\x1f]'), '');
  }
}

class _Entry {
  final String name;
  final String value;
  final String? domain;
  const _Entry(this.name, this.value, this.domain);
}
