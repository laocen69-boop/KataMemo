import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:katamemo/audio.dart';
import 'package:katamemo/db.dart';

void main() {
  test('内置男声 Ogg 映射到 ardi_m4a 下的同名 m4a', () {
    expect(AudioService.iosAudioPath('edge/ardi/id-makan.ogg'),
        'edge/ardi_m4a/id-makan.m4a');
    expect(AudioService.iosAudioPath('edge/ardi/id-toko buku.OGG'),
        'edge/ardi_m4a/id-toko buku.m4a');
  });

  test('数据相对路径补 assets 前缀；iOS 先试 m4a', () {

    expect(AudioService.audioAssetCandidates('edge/ardi/id-tahun.ogg', isIOS: false),
        ['audio/edge/ardi/id-tahun.ogg']);
    expect(AudioService.audioAssetCandidates('edge/ardi/id-tahun.ogg', isIOS: true),
        ['audio/edge/ardi_m4a/id-tahun.m4a', 'audio/edge/ardi/id-tahun.ogg']);

    expect(AudioService.audioAssetCandidates('wiktionary/x.wav', isIOS: true),
        ['audio/wiktionary/x.wav']);

    expect(AudioService.audioAssetCandidates('edge/ardi/id-x.mp3', isIOS: true),
        ['audio/edge/ardi/id-x.mp3']);
  });

  test('不是内置男声 Ogg 的不映射', () {
    expect(AudioService.iosAudioPath('wiktionary/x.wav'), isNull);
    expect(AudioService.iosAudioPath('edge/gadis/id-a.ogg'), isNull);
    expect(AudioService.iosAudioPath('edge/ardi/id-a.mp3'), isNull);
  });

  group('内置未引用音频兜底匹配（2026-11-14）', () {
    tearDown(() => AudioService.instance.debugBuiltInAssets = null);

    test('resolveBuiltInAudio 支持大小写、重音折叠、下划线与空格兼容', () async {
      AudioService.instance.debugBuiltInAssets = {
        'edge/ardi/id-abate.ogg',
        'edge/ardi/id-acara_tugas.ogg',
        'edge/ardi/id-air_emas.ogg',
        'edge/ardi/id-toko buku.ogg',
        'edge/ardi/id-debat.ogg',
      };
      expect(await AudioService.instance.resolveBuiltInAudio('Abate'),
          'edge/ardi/id-abate.ogg');
      expect(await AudioService.instance.resolveBuiltInAudio('Débat'),
          'edge/ardi/id-debat.ogg');
      expect(await AudioService.instance.resolveBuiltInAudio('acara tugas'),
          'edge/ardi/id-acara_tugas.ogg');
      expect(await AudioService.instance.resolveBuiltInAudio('toko buku'),
          'edge/ardi/id-toko buku.ogg');
      expect(await AudioService.instance.resolveBuiltInAudio('tidak_ada_xyz'),
          isNull);
    });

    test('createUserWord 与 updateUserWord 自动绑定内置音频并保留 user: 自导录音',
        () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      await databaseFactory.deleteDatabase(inMemoryDatabasePath);
      AudioService.instance.debugBuiltInAssets = {
        'edge/ardi/id-abate.ogg',
        'edge/ardi/id-abaya.ogg',
      };
      final db = AppDb(dbPath: inMemoryDatabasePath);
      addTearDown(db.close);

      final r1 = await db.createUserWord(word: 'abate', zh: '减弱');
      expect(r1.id, 'abate');
      final c1 = (await db.getWord('abate'))!;
      expect(c1.audio, 'edge/ardi/id-abate.ogg');

      final u1 = await db.updateUserWord('abate', word: 'abaya', zh: '长袍');
      expect(u1.id, 'abaya');
      final c2 = (await db.getWord('abaya'))!;
      expect(c2.audio, 'edge/ardi/id-abaya.ogg');

      final rawDb = await db.db;
      await rawDb.update('words', {'audio_ardi': 'user:abaya.mp3'},
          where: 'id = ?', whereArgs: ['abaya']);
      await db.updateUserWord('abaya', word: 'abate', zh: '减弱');
      final c3 = (await db.getWord('abate'))!;
      expect(c3.audio, 'user:abaya.mp3');
    });
  });
}
