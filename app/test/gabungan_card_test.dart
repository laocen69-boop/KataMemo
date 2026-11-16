import 'package:flutter_test/flutter_test.dart';
import 'package:katamemo/models.dart';

void main() {
  test('搭配卡的组件发音列能往返（audio_parts ↔ audioParts）', () {
    final c = WordCard.fromDb({
      'id': 'gigi taring',
      'word': 'gigi taring',
      'tier': 'lookup',
      'audio_parts': '["edge/ardi/id-gigi.ogg","edge/ardi/id-taring.ogg"]',
    });
    expect(c.audioParts, ['edge/ardi/id-gigi.ogg', 'edge/ardi/id-taring.ogg']);
    expect(c.audio, isNull, reason: '没有整句音频时 audio 为空');

    final back = WordCard.fromDb(c.toMap());
    expect(back.audioParts, c.audioParts);
  });

  test('普通词没有组件发音时不写这一列', () {
    final c = WordCard(id: 'aku', word: 'aku', audioArdi: 'edge/ardi/id-aku.ogg');
    expect(c.audioParts, isEmpty);
    expect(c.toMap()['audio_parts'], isNull);
  });
}
