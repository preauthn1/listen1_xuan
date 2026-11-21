import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

bool isAndroidUpdatePackage(String name) =>
    name.startsWith('app-') && (name.endsWith('.apk') || name.endsWith('.zip'));

/// Keep input ordering, replacing each APK with its same-stem ZIP if available.
/// Unrelated builds and variants must never replace one another.
List<T> preferAndroidZip<T>(
  List<T> packages,
  String Function(T) name, {
  String Function(T)? buildKey,
}) {
  final groups = <String, T>{};
  for (final package in packages) {
    final filename = name(package).replaceAll(' ', '.');
    final key =
        '${p.basenameWithoutExtension(filename)}:${buildKey?.call(package) ?? ''}';
    if (!groups.containsKey(key) || filename.endsWith('.zip')) {
      groups[key] = package;
    }
  }
  return groups.values.toList();
}

bool isAndroidUpdateCache(String name) =>
    name.endsWith('.apk') ||
    name.endsWith('.apk.extracting') ||
    (name.startsWith('app-') && name.endsWith('.zip')) ||
    name == 'canary.zip';

/// Extract only a single APK into the update directory, never archive paths.
/// Keep the APK until installation completes; the installer reads it later.
Future<String> extractAndroidUpdate(
  String archivePath,
  String directory,
) async {
  final archiveBytes = await File(archivePath).readAsBytes();
  if (archiveBytes.length > 256 * 1024 * 1024) {
    throw const FormatException('安装包 ZIP 文件过大');
  }
  final archive = ZipDecoder().decodeBytes(
    archiveBytes,
    verify: true,
  );
  if (archive.files.length > 1024) {
    throw const FormatException('安装包 ZIP 条目过多');
  }
  final apks = archive.files
      .where((file) => file.isFile && file.name.endsWith('.apk'))
      .toList();
  if (apks.length != 1) {
    throw const FormatException('安装包 ZIP 必须包含且仅包含一个 APK');
  }
  final apk = apks.single;
  final candidate = apk.name.replaceAll('\\', '/');
  if (candidate.startsWith('/') || candidate.contains('../')) {
    throw const FormatException('安装包路径非法');
  }
  if (apk.isSymbolicLink) {
    throw const FormatException('安装包不能是符号链接');
  }
  final content = apk.content as List<int>;
  if (content.length > 512 * 1024 * 1024) {
    throw const FormatException('安装包 APK 解压后过大');
  }
  if (apk.size > 0 && content.length > apk.size * 100) {
    throw const FormatException('安装包压缩比异常');
  }
  if (apk.crc32 != null && getCrc32(content) != apk.crc32) {
    throw const FormatException('安装包 ZIP 校验失败');
  }
  final destination = p.join(directory, p.basename(apk.name));
  final partial = File('$destination.extracting');
  try {
    await partial.writeAsBytes(content, flush: true);
    await partial.rename(destination);
  } finally {
    if (await partial.exists()) await partial.delete();
  }
  // An interrupted extraction keeps the archive for a retry.
  await File(archivePath).delete();
  return destination;
}
