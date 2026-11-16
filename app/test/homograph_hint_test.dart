import 'package:flutter_test/flutter_test.dart';
import 'package:katamemo/cloze.dart';
import 'package:katamemo/widgets/homograph_hint.dart';

void main() {
  test('宿主指向缩写卡，缩写卡指回宿主', () {
    expect(homographPartnerId('ini'), 'ini-abbr');
    expect(homographPartnerId('ini-abbr'), 'ini');
    expect(homographPartnerId(homographPartnerId('ham')), 'ham');
  });

  test('缩写卡的挖空要找句子里的缩写词本身', () {
    final span = clozeSpan('Pemerintah menerbitkan SUN untuk membiayai pembangunan.', 'sun-abbr');
    expect(span, isNotNull);
    expect(span!.text, 'SUN');
  });
}
