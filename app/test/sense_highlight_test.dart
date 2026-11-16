import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:katamemo/models.dart';
import 'package:katamemo/theme/k_colors.dart';
import 'package:katamemo/widgets/sense_highlight.dart';
import 'package:katamemo/widgets/word_tile.dart';

void main() {
  group('resolveSenseHighlight - 主题词库与分类义项优选及标红', () {
    test('同形多义词在不同主题下优先显示最贴切义项并标红（bunga：植物 vs 金融银行）', () {
      final bunga = WordCard(
        id: 'bunga',
        word: 'bunga',
        zh: '花；利息；轮胎花纹；花色',
        topics: const ['植物', '金融银行'],
      );
      const plantBook = BookNode(
        id: 'topic:植物',
        name: '植物',
        count: 10,
        filter: {'topicsAny': ['植物']},
      );
      const financeBook = BookNode(
        id: 'topic:金融银行',
        name: '金融银行',
        count: 10,
        filter: {'topicsAny': ['金融银行']},
      );

      final resPlant = resolveSenseHighlight(card: bunga, book: plantBook);
      expect(resPlant.hasHighlight, isTrue);
      expect(resPlant.highlightedPrefix, '花');
      expect(resPlant.fullText, '花；利息；轮胎花纹；花色');

      final resFinance = resolveSenseHighlight(card: bunga, book: financeBook);
      expect(resFinance.hasHighlight, isTrue);
      expect(resFinance.highlightedPrefix, '利息');
      expect(resFinance.fullText.startsWith('利息；花'), isTrue);
    });

    test('同形多义词在不同主题下优先显示最贴切义项（kangkung：动物 vs 蔬菜作物）', () {
      final kangkung = WordCard(
        id: 'kangkung',
        word: 'kangkung',
        zh: '雨蛙；空心菜、蕹菜；生长快；未长椰肉的椰果；牲畜颈木具',
        topics: const ['动物', '蔬菜作物'],
      );
      const animalBook = BookNode(
        id: 'topic:动物',
        name: '动物',
        count: 10,
        filter: {'topicsAny': ['动物']},
      );
      const vegBook = BookNode(
        id: 'topic:蔬菜作物',
        name: '蔬菜作物',
        count: 10,
        filter: {'topicsAny': ['蔬菜作物']},
      );

      final resAnimal = resolveSenseHighlight(card: kangkung, book: animalBook);
      expect(resAnimal.hasHighlight, isTrue);
      expect(resAnimal.highlightedPrefix, '雨蛙');

      final resVeg = resolveSenseHighlight(card: kangkung, book: vegBook);
      expect(resVeg.hasHighlight, isTrue);
      expect(resVeg.highlightedPrefix, '空心菜、蕹菜');
      expect(resVeg.fullText.startsWith('空心菜、蕹菜；雨蛙'), isTrue);
    });

    test('手机与聊天软件数码词在不同主题下优选贴切义项（beranda：房屋居所 vs 通讯网络）', () {
      final beranda = WordCard(
        id: 'beranda',
        word: 'beranda',
        zh: '阳台、门廊；船舱；（网站、应用的）主页、首页',
        topics: const ['房屋居所', '通讯网络', '计算机网络'],
      );
      const houseBook = BookNode(
        id: 'topic:房屋居所',
        name: '房屋居所',
        count: 10,
        filter: {'topicsAny': ['房屋居所']},
      );
      const netBook = BookNode(
        id: 'topic:通讯网络',
        name: '通讯网络',
        count: 10,
        filter: {'topicsAny': ['通讯网络']},
      );

      final resHouse = resolveSenseHighlight(card: beranda, book: houseBook);
      expect(resHouse.hasHighlight, isTrue);
      expect(resHouse.highlightedPrefix, '阳台、门廊');

      final resNet = resolveSenseHighlight(card: beranda, book: netBook);
      expect(resNet.hasHighlight, isTrue);
      expect(resNet.highlightedPrefix, '（网站、应用的）主页、首页');
      expect(resNet.fullText.startsWith('（网站、应用的）主页、首页；'), isTrue);
    });

    test('其他高频多义词在对应主题下优选贴切义项（pesawat / rabu / mengunduh）', () {
      final pesawat = WordCard(
        id: 'pesawat',
        word: 'pesawat',
        zh: '器械；机械装置；飞机',
        topics: const ['科技工程', '交通工具'],
      );
      const transportBook = BookNode(
        id: 'topic:交通工具',
        name: '交通工具',
        count: 10,
        filter: {'topicsAny': ['交通工具']},
      );
      final resTransport =
          resolveSenseHighlight(card: pesawat, book: transportBook);
      expect(resTransport.highlightedPrefix, '飞机');
      expect(resTransport.fullText, '飞机；器械；机械装置');

      final rabu = WordCard(
        id: 'rabu',
        word: 'Rabu',
        zh: '肺；星期三、周三',
        topics: const ['身体部位', '星期'],
      );
      const weekBook = BookNode(
        id: 'topic:星期',
        name: '星期',
        count: 10,
        filter: {'topicsAny': ['星期']},
      );
      final resWeek = resolveSenseHighlight(card: rabu, book: weekBook);
      expect(resWeek.highlightedPrefix, '星期三、周三');
      expect(resWeek.fullText, '星期三、周三；肺');
    });

    test('按词性分类（wordClass）结合 zhPosSegments 优先显示对应词性义项', () {
      final tahu = WordCard(
        id: 'tahu',
        word: 'tahu',
        zh: '知道、明白；习惯；豆腐',
        zhPos: 'v|v|n',
      );
      const nounBook = BookNode(
        id: 'pos:n',
        name: '名词',
        count: 10,
        filter: {'wordClass': ['n']},
      );
      const verbBook = BookNode(
        id: 'pos:v',
        name: '动词',
        count: 10,
        filter: {'wordClass': ['v']},
      );

      final resNoun = resolveSenseHighlight(card: tahu, book: nounBook);
      expect(resNoun.hasHighlight, isTrue);
      expect(resNoun.highlightedPrefix, '豆腐');
      expect(resNoun.fullText, '豆腐；知道、明白；习惯');

      final resVerb = resolveSenseHighlight(card: tahu, book: verbBook);
      expect(resVerb.hasHighlight, isTrue);
      expect(resVerb.highlightedPrefix, '知道、明白');
    });

    test('搜索中文关键词时优先将匹配义项前置并标红，保留尾部（写作：…）注记', () {
      final menyematkan = WordCard(
        id: 'menyematkan',
        word: 'menyematkan',
        zh: '别上、扣住；附加上；（聊天、评论中）置顶',
      );
      final resPin = resolveSenseHighlight(
        card: menyematkan,
        query: '置顶',
      );
      expect(resPin.hasHighlight, isTrue);
      expect(resPin.highlightedPrefix, '（聊天、评论中）置顶');
      expect(resPin.fullText, '（聊天、评论中）置顶；别上、扣住；附加上');

      final dengan = WordCard(
        id: 'dengan',
        word: 'dengan',
        zh: '同伴；奴仆；我；和、同、与（写作：dgn）',
        topics: const ['家庭人际'],
      );
      final resQuery = resolveSenseHighlight(
        card: dengan,
        query: '和',
      );
      expect(resQuery.hasHighlight, isTrue);
      expect(resQuery.highlightedPrefix, '和、同、与');
      expect(resQuery.fullText.endsWith('（写作：dgn）'), isTrue);
    });

    test('常规浏览与搜索印尼语词头时不标绿不乱重排；中文搜索才高亮优选', () {
      final mengunduh = WordCard(
        id: 'mengunduh',
        word: 'mengunduh',
        zh: '采摘（果实）；下载、拷取（数据）',
        topics: const ['计算机网络'],
      );

      final resGeneral = resolveSenseHighlight(card: mengunduh);
      expect(resGeneral.hasHighlight, isFalse);
      expect(resGeneral.reordered, isFalse);
      expect(resGeneral.fullText, '采摘（果实）；下载、拷取（数据）');

      final resIdSearch = resolveSenseHighlight(
        card: mengunduh,
        query: 'mengunduh',
      );
      expect(resIdSearch.hasHighlight, isFalse);
      expect(resIdSearch.reordered, isFalse);

      final di = WordCard(
        id: 'di',
        word: 'di',
        zh: '在（表处所）；在（表时间 di pagi hari 在早上）',
      );
      expect(resolveSenseHighlight(card: di, query: 'di').hasHighlight, isFalse);

      final resZhSearch = resolveSenseHighlight(
        card: mengunduh,
        query: '下载',
      );
      expect(resZhSearch.hasHighlight, isTrue);
      expect(resZhSearch.highlightedPrefix, '下载、拷取（数据）');
      expect(resZhSearch.fullText, '下载、拷取（数据）；采摘（果实）');
    });

    test('单义词与无主题/搜索命中的多义词保持常规文本不高亮', () {
      final apel = WordCard(
        id: 'apel',
        word: 'apel',
        zh: '苹果',
        topics: const ['水果'],
      );
      const fruitBook = BookNode(
        id: 'topic:水果',
        name: '水果',
        count: 10,
        filter: {'topicsAny': ['水果']},
      );
      expect(resolveSenseHighlight(card: apel, book: fruitBook).hasHighlight,
          isFalse);
      expect(
          resolveSenseHighlight(card: apel, query: '苹果').hasHighlight, isTrue);

      final bunga = WordCard(
        id: 'bunga',
        word: 'bunga',
        zh: '花；利息；轮胎花纹',
      );
      expect(resolveSenseHighlight(card: bunga).hasHighlight, isFalse);
    });
  });

  testWidgets('WordTile 在主题词库下将最贴切义项前置并以 k.deep + k.tint 高亮显示', (tester) async {
    final card = WordCard(
      id: 'bunga',
      word: 'bunga',
      zh: '花；利息；轮胎花纹',
      topics: const ['植物', '金融银行'],
    );
    const financeBook = BookNode(
      id: 'topic:金融银行',
      name: '金融银行',
      count: 10,
      filter: {'topicsAny': ['金融银行']},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WordTile(
            card: card,
            book: financeBook,
            enrolled: true,
            onTap: () {},
            onLongPress: () {},
          ),
        ),
      ),
    );

    expect(find.textContaining('利息；花；轮胎花纹'), findsOneWidget);

    final richTexts = tester.widgetList<Text>(
      find.descendant(
        of: find.byType(SearchMeaningLine),
        matching: find.byType(Text),
      ),
    );
    expect(richTexts, isNotEmpty);
    final meaningText = richTexts.first;
    final rootSpan = meaningText.textSpan as TextSpan?;
    expect(rootSpan, isNotNull);
    final children = rootSpan!.children!.whereType<TextSpan>().toList();
    final hlSpan = children.firstWhere((s) => s.text == '利息');
    expect(hlSpan.style?.color, KColors.light.deep);
    expect(hlSpan.style?.backgroundColor, KColors.light.tint);
  });
}
