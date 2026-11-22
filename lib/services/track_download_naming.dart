import 'package:listen1_xuan/models/Track.dart';
import 'package:path/path.dart' as p;

/// 下载歌曲时用到的纯函数：命名、扩展名、MIME、双语歌词合并。
/// 不依赖 Flutter / GetX，便于单元测试。
class TrackDownloadNaming {
  TrackDownloadNaming._();

  static const _illegal = r'\/:*?"<>|';
  static const _maxBaseLength = 120;

  /// 「歌手 - 歌名」，去掉文件系统不允许的字符并限制长度。
  static String baseName(Track track) {
    final title = _clean(track.title);
    final artist = _clean(track.artist);
    var name = title.isEmpty
        ? (track.id.isEmpty ? 'untitled' : track.id)
        : artist.isEmpty
            ? title
            : '$artist - $title';
    name = _clean(name);
    if (name.length > _maxBaseLength) name = name.substring(0, _maxBaseLength).trim();
    // Windows 不允许以点或空格结尾。
    name = name.replaceAll(RegExp(r'[. ]+$'), '');
    return name.isEmpty ? 'untitled' : name;
  }

  static String _clean(String? value) {
    if (value == null) return '';
    var out = value.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ');
    for (final c in _illegal.split('')) {
      out = out.replaceAll(c, '_');
    }
    return out.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// 从播放地址推断扩展名；B 站的 .m4s 音频实际是 m4a。
  static String audioExtension(String url) {
    String ext;
    try {
      final uri = Uri.parse(url);
      ext = uri.pathSegments.isEmpty
          ? ''
          : p.extension(uri.pathSegments.last).toLowerCase();
    } catch (_) {
      ext = p.extension(url).toLowerCase();
    }
    if (ext == '.m4s' || ext == '.mp4') return '.m4a';
    const known = {'.mp3', '.flac', '.m4a', '.aac', '.ogg', '.opus', '.wav', '.ape'};
    return known.contains(ext) ? ext : '.mp3';
  }

  static String mimeForExtension(String ext) {
    switch (ext.toLowerCase()) {
      case '.mp3':
        return 'audio/mpeg';
      case '.flac':
        return 'audio/flac';
      case '.m4a':
      case '.aac':
        return 'audio/mp4';
      case '.ogg':
      case '.opus':
        return 'audio/ogg';
      case '.wav':
        return 'audio/wav';
      default:
        // MediaStore 会按 MIME 改扩展名（text/plain 会变成 .lrc.txt），
        // 用 octet-stream 才能原样保留 .lrc 等文件名。
        return 'application/octet-stream';
    }
  }

  static final _tag = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');

  static int? _tagMillis(RegExpMatch m) {
    final min = int.tryParse(m.group(1)!);
    final sec = int.tryParse(m.group(2)!);
    if (min == null || sec == null) return null;
    final frac = m.group(3);
    var ms = 0;
    if (frac != null && frac.isNotEmpty) {
      ms = int.parse(frac.padRight(3, '0').substring(0, 3));
    }
    return (min * 60 + sec) * 1000 + ms;
  }

  /// 把翻译歌词按时间戳插到原文下一行，生成常见播放器都能显示的双语 LRC。
  /// 没有翻译时原样返回。
  static String mergeTranslation(String lyric, String? translation) {
    if (translation == null || translation.trim().isEmpty) return lyric;
    final byTime = <int, String>{};
    for (final line in const LineSplitterCompat().split(translation)) {
      final tags = _tag.allMatches(line).toList();
      if (tags.isEmpty) continue;
      final text = line.substring(tags.last.end).trim();
      if (text.isEmpty) continue;
      for (final t in tags) {
        final ms = _tagMillis(t);
        if (ms != null) byTime[ms] = text;
      }
    }
    if (byTime.isEmpty) return lyric;
    final out = StringBuffer();
    for (final line in const LineSplitterCompat().split(lyric)) {
      out.writeln(line);
      final tags = _tag.allMatches(line).toList();
      if (tags.isEmpty) continue;
      final original = line.substring(tags.last.end).trim();
      for (final t in tags) {
        final ms = _tagMillis(t);
        final tr = ms == null ? null : byTime[ms];
        if (tr != null && tr != original) out.writeln('${t.group(0)}$tr');
      }
    }
    return out.toString();
  }
}

/// 与 dart:convert 的 LineSplitter 行为一致，避免为一个函数引入 convert。
class LineSplitterCompat {
  const LineSplitterCompat();
  Iterable<String> split(String text) =>
      text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n').where((l) => l.isNotEmpty);
}
