import 'package:flutter_test/flutter_test.dart';
import 'package:listen1_xuan/models/Track.dart';
import 'package:listen1_xuan/services/track_download_naming.dart';

void main() {
  group('baseName', () {
    test('artist - title', () {
      expect(
        TrackDownloadNaming.baseName(Track(id: 'netrack_1', title: '晴天', artist: '周杰伦')),
        '周杰伦 - 晴天',
      );
    });

    test('strips characters that are illegal in file names', () {
      expect(
        TrackDownloadNaming.baseName(Track(id: 'x', title: 'A/B: C?', artist: 'D<E>')),
        'D_E_ - A_B_ C_',
      );
    });

    test('falls back to id, never empty, no trailing dot', () {
      expect(TrackDownloadNaming.baseName(Track(id: 'qqtrack_9')), 'qqtrack_9');
      expect(TrackDownloadNaming.baseName(Track(id: 'x', title: 'end.')), 'end');
    });

    test('is length limited', () {
      final name = TrackDownloadNaming.baseName(Track(id: 'x', title: 'a' * 400));
      expect(name.length, lessThanOrEqualTo(120));
    });
  });

  group('audioExtension', () {
    test('keeps known extensions, ignores query', () {
      expect(TrackDownloadNaming.audioExtension('https://m.example/a/b.flac?x=1'), '.flac');
      expect(TrackDownloadNaming.audioExtension('https://m.example/a/b.mp3'), '.mp3');
    });

    test('bilibili m4s is saved as m4a, unknown falls back to mp3', () {
      expect(TrackDownloadNaming.audioExtension('https://upos.example/123-1-30280.m4s?e=1'), '.m4a');
      expect(TrackDownloadNaming.audioExtension('https://example/stream'), '.mp3');
    });
  });

  test('lrc keeps its extension through MediaStore', () {
    expect(TrackDownloadNaming.mimeForExtension('.lrc'), 'application/octet-stream');
    expect(TrackDownloadNaming.mimeForExtension('.mp3'), 'audio/mpeg');
  });

  group('mergeTranslation', () {
    const lrc = '[ti:x]\n[00:01.00]Hello\n[00:05.50]World\n';
    const tr = '[00:01.00]你好\n[00:05.50]世界\n';

    test('adds the translation under each matching line', () {
      expect(
        TrackDownloadNaming.mergeTranslation(lrc, tr),
        '[ti:x]\n[00:01.00]Hello\n[00:01.00]你好\n[00:05.50]World\n[00:05.50]世界\n',
      );
    });

    test('tolerates different fraction precision', () {
      expect(
        TrackDownloadNaming.mergeTranslation('[00:01.0]Hi\n', '[00:01.000]嗨\n'),
        '[00:01.0]Hi\n[00:01.0]嗨\n',
      );
    });

    test('no translation leaves lyric untouched', () {
      expect(TrackDownloadNaming.mergeTranslation(lrc, null), lrc);
      expect(TrackDownloadNaming.mergeTranslation(lrc, '  '), lrc);
    });
  });
}
