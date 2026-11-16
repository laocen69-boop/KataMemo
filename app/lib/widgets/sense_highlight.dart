library;

import '../models.dart';

class SenseHighlightResult {

  final String fullText;

  final String? highlightedPrefix;

  final String remainderText;

  final bool reordered;

  const SenseHighlightResult({
    required this.fullText,
    this.highlightedPrefix,
    required this.remainderText,
    this.reordered = false,
  });

  static const empty = SenseHighlightResult(fullText: '', remainderText: '');

  bool get hasHighlight =>
      highlightedPrefix != null && highlightedPrefix!.isNotEmpty;
}

final RegExp _kSpellingNoteRe = RegExp(r'(\s*[（(]写作[：:][^）)]+[）)])\s*$');
final RegExp _kParensRe = RegExp(r'[（(][^）)]*[）)]');
final RegExp _kSubSplitRe = RegExp(r'[、，,/]');
final RegExp _kCjkRe = RegExp(r'[\u4e00-\u9fff]');

String _stripParens(String s) => s.replaceAll(_kParensRe, '').trim();

List<String> _splitTopLevel(String text, Pattern sepPattern) {
  final out = <String>[];
  var depth = 0;
  var start = 0;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (ch == '（' || ch == '(') {
      depth++;
    } else if (ch == '）' || ch == ')') {
      if (depth > 0) depth--;
    } else if (depth == 0 && sepPattern.allMatches(ch).isNotEmpty) {
      final seg = text.substring(start, i).trim();
      if (seg.isNotEmpty) out.add(seg);
      start = i + 1;
    }
  }
  final tail = text.substring(start).trim();
  if (tail.isNotEmpty) out.add(tail);
  return out;
}

SenseHighlightResult resolveSenseHighlight({
  WordCard? card,
  String? zh,
  BookNode? book,
  String? query,
  bool enableHighlight = true,
}) {
  final raw = (card?.zhClean ?? zh ?? '').trim();
  if (raw.isEmpty || !enableHighlight) {
    return SenseHighlightResult(fullText: raw, remainderText: raw);
  }

  final q = (query ?? '').trim();
  final hasCjkQuery = q.isNotEmpty && _kCjkRe.hasMatch(q);
  final hasBookContext =
      book != null &&
      ((book.filter?['topicsAny'] is List &&
              (book.filter!['topicsAny'] as List).isNotEmpty) ||
          (book.filter?['domainsAny'] is List &&
              (book.filter!['domainsAny'] as List).isNotEmpty) ||
          (book.filter?['wordClass'] is List &&
              (book.filter!['wordClass'] as List).isNotEmpty) ||
          book.filter?['grammarFunc'] is String ||
          kTopicSenseKeywords.containsKey(book.name.trim()) ||
          kDomainToTopics.containsKey(book.name.trim()) ||
          const {'古语', '古典', '口语', '缩写简称', '修辞比喻'}
              .contains(book.name.trim()));

  if (!hasBookContext && !hasCjkQuery) {
    return SenseHighlightResult(fullText: raw, remainderText: raw);
  }

  var sep = '；';
  var rawSegs = _splitTopLevel(raw, RegExp(r'[；;]'));

  if (rawSegs.length == 1) {
    final mNote = _kSpellingNoteRe.firstMatch(raw);
    final bodyOnly =
        mNote == null ? raw : raw.substring(0, mNote.start).trim();
    final tailNote = mNote == null ? '' : mNote.group(1)!;
    final subSegs = _splitTopLevel(bodyOnly, RegExp(r'[、，]'));
    if (subSegs.length >= 2 && hasCjkQuery) {
      final subScores = _scoreAllSegments(
        subSegs,
        card: card,
        book: book,
        query: q,
      );
      var bestSub = 0;
      for (var i = 1; i < subSegs.length; i++) {
        if (subScores[i] > subScores[bestSub]) bestSub = i;
      }
      if (bestSub > 0 && subScores[bestSub] >= 2000) {
        final chosen = subSegs[bestSub];
        final rest = [
          for (var i = 0; i < subSegs.length; i++)
            if (i != bestSub) subSegs[i],
        ].join('、');
        final rem = '${rest.isEmpty ? '' : '、$rest'}$tailNote';
        return SenseHighlightResult(
          fullText: '$chosen$rem',
          highlightedPrefix: chosen,
          remainderText: rem,
          reordered: true,
        );
      }
      if (subScores[0] >= 2000) {
        final firstSub = subSegs[0];
        return SenseHighlightResult(
          fullText: raw,
          highlightedPrefix: firstSub,
          remainderText: raw.substring(firstSub.length),
          reordered: false,
        );
      }
    }

    if (bodyOnly.isNotEmpty &&
        hasCjkQuery &&
        _stripParens(bodyOnly).contains(q)) {
      return SenseHighlightResult(
        fullText: raw,
        highlightedPrefix: bodyOnly,
        remainderText: tailNote,
        reordered: false,
      );
    }
    return SenseHighlightResult(fullText: raw, remainderText: raw);
  }

  final cleanSegs = <String>[];
  String? extractedSpellingNote;
  for (final s in rawSegs) {
    final m = _kSpellingNoteRe.firstMatch(s);
    if (m != null) {
      extractedSpellingNote ??= m.group(1)!;
      final stripped = s.substring(0, m.start).trim();
      cleanSegs.add(stripped.isEmpty ? s : stripped);
    } else {
      cleanSegs.add(s);
    }
  }

  final scores = _scoreAllSegments(
    cleanSegs,
    card: card,
    book: book,
    query: query,
  );
  var bestIdx = 0;
  for (var i = 1; i < cleanSegs.length; i++) {
    if (scores[i] > scores[bestIdx]) {
      bestIdx = i;
    }
  }

  if (bestIdx == 0) {
    if (scores[0] <= 15) {
      return SenseHighlightResult(fullText: raw, remainderText: raw);
    }
    final firstClean = cleanSegs[0];
    final rem = raw.substring(firstClean.length);
    return SenseHighlightResult(
      fullText: raw,
      highlightedPrefix: firstClean,
      remainderText: rem,
      reordered: false,
    );
  }

  final chosen = cleanSegs[bestIdx];
  final others = [
    for (var i = 0; i < cleanSegs.length; i++)
      if (i != bestIdx) cleanSegs[i],
  ];
  final tail = extractedSpellingNote ?? '';
  final rem = '$sep${others.join(sep)}$tail';
  return SenseHighlightResult(
    fullText: '$chosen$rem',
    highlightedPrefix: chosen,
    remainderText: rem,
    reordered: true,
  );
}

List<int> _scoreAllSegments(
  List<String> segs, {
  WordCard? card,
  BookNode? book,
  String? query,
}) {
  final n = segs.length;
  final scores = List<int>.filled(n, 0);

  scores[0] += 15;

  final q = (query ?? '').trim();
  final filter = book?.filter;
  final bookName = (book?.name ?? '').trim();

  final activeTopics = <String>{
    if (filter?['topicsAny'] is List)
      for (final x in (filter!['topicsAny'] as List)) '$x',
    if (kTopicSenseKeywords.containsKey(bookName)) bookName,
  };
  final activeDomains = <String>{
    if (filter?['domainsAny'] is List)
      for (final x in (filter!['domainsAny'] as List)) '$x',
    if (kDomainToTopics.containsKey(bookName)) bookName,
  };
  final activeWordClasses = <String>{
    if (filter?['wordClass'] is List)
      for (final x in (filter!['wordClass'] as List)) '$x',
    if (filter?['grammarFunc'] is String) filter!['grammarFunc'] as String,
  };

  final domainMappedTopics = <String>{};
  for (final d in activeDomains) {
    final mapped = kDomainToTopics[d];
    if (mapped != null) domainMappedTopics.addAll(mapped);
  }

  final isArchaicBook =
      activeDomains.contains('Arkais') ||
      activeDomains.contains('Klasik') ||
      bookName == '古语' ||
      bookName == '古典';
  final isColloquialBook =
      activeDomains.contains('Cakapan') ||
      activeDomains.contains('Melayu Jakarta') ||
      bookName == '口语' ||
      activeTopics.contains('口语与俚语（Bahasa Gaul）');
  final isAbbrBook =
      activeDomains.contains('singkatan') ||
      activeDomains.contains('akronim') ||
      bookName == '缩写简称';
  final isFigurativeBook =
      activeDomains.contains('kiasan') || bookName == '修辞比喻';

  final zpSegs = card?.zhPosSegments;

  if (q.isNotEmpty && _kCjkRe.hasMatch(q)) {
    final qTokens = q
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty && _kCjkRe.hasMatch(t))
        .toList();
    for (final qt in qTokens) {
      var anyExactOrSub = false;
      for (var i = 0; i < n; i++) {
        final seg = segs[i];
        final core = _stripParens(seg);
        final coreParts =
            core.split(_kSubSplitRe).map((s) => s.trim()).where((s) => s.isNotEmpty);
        if (core == qt || seg == qt) {
          scores[i] += 3000;
          anyExactOrSub = true;
        } else if (core.startsWith(qt) || coreParts.contains(qt)) {
          scores[i] += 2500;
          anyExactOrSub = true;
        } else if (core.contains(qt)) {
          scores[i] += 2100;
          anyExactOrSub = true;
        } else if (seg.contains(qt)) {
          scores[i] += 1800;
          anyExactOrSub = true;
        }
      }

      if (!anyExactOrSub && qt.length >= 3) {
        for (var i = 0; i < n; i++) {
          final core = _stripParens(segs[i]);
          var bgHits = 0;
          for (var k = 0; k < qt.length - 1; k++) {
            final bg = qt.substring(k, k + 2);
            if (core.contains(bg)) bgHits++;
          }
          if (bgHits > 0) {
            scores[i] += bgHits * 600;
          }
        }
      }
    }
  }

  final effectiveBookTopics = <String>{
    ...activeTopics,
    ...domainMappedTopics,
  };

  for (var i = 0; i < n; i++) {
    final seg = segs[i];
    if (effectiveBookTopics.isNotEmpty) {
      var bestTopicScore = 0;
      for (final tp in effectiveBookTopics) {
        final s = _scoreSegmentForTopic(seg, tp);
        if (s > bestTopicScore) bestTopicScore = s;
      }
      scores[i] += bestTopicScore;
    }

    if (isColloquialBook &&
        (seg.contains('（口') || seg.contains('（俗') || seg.contains('口语'))) {
      scores[i] += 400;
    }
    if (isArchaicBook &&
        (seg.contains('（古') || seg.contains('（旧') || seg.contains('（书'))) {
      scores[i] += 400;
    }
    if (isAbbrBook &&
        (seg.contains('缩写') || seg.contains('简称') || seg.contains('缩合'))) {
      scores[i] += 400;
    }
    if (isFigurativeBook && (seg.contains('（喻') || seg.contains('比喻'))) {
      scores[i] += 400;
    }
    if (!isArchaicBook &&
        (seg.contains('（僻') || seg.contains('此义非 KBBI'))) {
      scores[i] -= 1000;
    }

    if (activeWordClasses.isNotEmpty) {
      if (zpSegs != null && i < zpSegs.length) {
        final pos = zpSegs[i];
        if (activeWordClasses.contains(pos)) {
          scores[i] += 500;
        }
      }
      for (final wc in activeWordClasses) {
        if (_segmentHasInlinePos(seg, wc)) {
          scores[i] += 420;
        }
      }
    }
  }

  return scores;
}

bool _segmentHasInlinePos(String seg, String wc) {
  return switch (wc) {
    'v' => seg.contains('v.') || seg.contains('动词'),
    'n' => seg.contains('n.') || seg.contains('名词'),
    'a' => seg.contains('a.') || seg.contains('形容词'),
    'adv' => seg.contains('adv.') || seg.contains('副词'),
    'quantifier' => seg.contains('量词') || seg.contains('数量单位'),
    'particle' || 'part' => seg.contains('语气') || seg.contains('助词'),
    'prep' => seg.contains('介词'),
    'conj' => seg.contains('连词'),
    'pron' => seg.contains('代词'),
    'num' => seg.contains('数词'),
    _ => false,
  };
}

int _scoreSegmentForTopic(String seg, String topic) {
  final kws = kTopicSenseKeywords[topic];
  if (kws == null || kws.isEmpty) return 0;
  final core = _stripParens(seg);
  final coreParts =
      core.split(_kSubSplitRe).map((s) => s.trim()).where((s) => s.isNotEmpty).toSet();
  var best = 0;
  for (final kw in kws) {
    var s = 0;
    if (kw.length >= 2) {
      if (core == kw || seg == kw) {
        s = 400;
      } else if (core.startsWith(kw) || coreParts.contains(kw)) {
        s = 320;
      } else if (core.contains(kw)) {
        s = 260;
      } else if (seg.contains(kw)) {

        s = 10;
      }
    } else {

      if (core == kw || coreParts.contains(kw)) {
        s = 300;
      }
    }
    if (s > best) best = s;
  }
  return best;
}

const Map<String, List<String>> kDomainToTopics = {

  '生物': ['动物', '植物', '身体部位', '农业渔业'],
  '化学': ['化学'],
  '物理': ['物理'],
  '医学': ['医疗就医', '身体健康', '身体部位'],
  '心理': ['情感心理', '情绪感受', '性格品质'],
  '语言文学': ['语言与语法', '学习教育'],
  '法律': ['政法军事', '政务证件'],
  '经济金融': ['金融银行', '购物金钱'],
  '计算机': ['计算机网络', '通讯网络'],
  '地理地质': ['地质水文', '自然万物'],
  '数学': ['数学计量'],
  '音乐艺术': ['文体娱乐'],
  '体育': ['文体娱乐'],
  '宗教': ['宗教信仰'],
  '军事': ['战争冲突', '政法军事'],
  '交通航海': ['交通出行', '交通工具'],
  '天文气象': ['天气气候', '天文宇宙'],
  '农业': ['农业渔业', '蔬菜作物', '植物'],
  '教育': ['学习教育'],
  '建筑': ['城市建筑', '房屋居所'],
  '口语': ['口语与俚语（Bahasa Gaul）'],

  'Komputer': ['计算机网络', '通讯网络'],
  'Informatika': ['计算机网络', '通讯网络'],
  'Teknologi Informasi': ['计算机网络', '通讯网络'],
  'Telekomunikasi': ['通讯网络', '通信传媒'],
  'Ilmu Komunikasi': ['通讯网络', '通信传媒'],
  'Ekonomi dan Keuangan': ['金融银行', '购物金钱'],
  'Ekonomi': ['金融银行', '购物金钱'],
  'Keuangan': ['金融银行', '购物金钱'],
  'Perbankan': ['金融银行'],
  'Akuntansi': ['金融银行'],
  'Perdagangan': ['购物金钱', '金融银行'],
  'Hukum': ['政法军事', '政务证件'],
  'Pidana': ['政法军事'],
  'Kedokteran dan Fisiologi': ['医疗就医', '身体健康'],
  'Kedokteran': ['医疗就医', '身体健康'],
  'Kesehatan': ['医疗就医', '身体健康'],
  'Penyakit': ['医疗就医', '身体健康'],
  'Farmasi': ['医疗就医', '化学'],
  'Farmasi dan Farmakologi': ['医疗就医', '化学'],
  'Anatomi': ['身体部位'],
  'Biologi': ['动物', '植物', '身体部位'],
  'Botani': ['植物', '水果', '蔬菜作物'],
  'Tumbuhan': ['植物', '水果', '蔬菜作物'],
  'Zoologi': ['动物'],
  'Hewan': ['动物'],
  'Pertanian': ['农业渔业', '蔬菜作物'],
  'Perkebunan': ['农业渔业', '植物'],
  'Peternakan': ['农业渔业', '动物'],
  'Perikanan': ['农业渔业', '动物'],
  'Fisika': ['物理'],
  'Listrik': ['物理', '科技工程'],
  'Optik': ['物理'],
  'Kimia': ['化学'],
  'Astronomi': ['天文宇宙'],
  'Meteorologi': ['天气气候'],
  'Hidrometeorologi': ['天气气候', '地质水文'],
  'Cuaca': ['天气气候'],
  'Geografi dan Geologi': ['地质水文', '自然万物'],
  'Geografi': ['地质水文', '自然万物'],
  'Geologi': ['地质水文'],
  'Matematika': ['数学计量'],
  'Statistika': ['数学计量'],
  'Linguistik': ['语言与语法', '学习教育'],
  'Tata Bahasa': ['语言与语法'],
  'Sastra': ['语言与语法', '学习教育'],
  'Kesusastraan': ['语言与语法', '学习教育'],
  'Psikologi': ['情感心理', '情绪感受'],
  'Psikoanalisis': ['情感心理'],
  'Musik': ['文体娱乐'],
  'Kesenian': ['文体娱乐'],
  'Seni': ['文体娱乐'],
  'Film': ['文体娱乐'],
  'Fotografi': ['文体娱乐'],
  'Olahraga': ['文体娱乐'],
  'Olah Raga': ['文体娱乐'],
  'Agama Islam': ['宗教信仰'],
  'Agama Katolik': ['宗教信仰'],
  'Agama Kristen': ['宗教信仰'],
  'Agama Hindu': ['宗教信仰'],
  'Agama Budha': ['宗教信仰'],
  'Islam': ['宗教信仰'],
  'Kristen': ['宗教信仰'],
  'Militer': ['战争冲突', '政法军事'],
  'Pertahanan': ['战争冲突', '政法军事'],
  'Kemiliteran': ['战争冲突', '政法军事'],
  'Pelayaran': ['交通出行', '交通工具'],
  'Perhubungan': ['交通出行', '交通工具'],
  'Lalu Lintas': ['交通出行'],
  'Penerbangan': ['交通出行', '交通工具'],
  'Pendidikan': ['学习教育'],
  'Sekolah': ['学习教育'],
  'Arsitektur': ['城市建筑', '房屋居所'],
  'Bangunan': ['城市建筑', '房屋居所'],
  'Konstruksi': ['城市建筑', '工程技术'],
  'Manajemen': ['工作职场'],
  'Administrasi dan Kepegawaian': ['工作职场', '政务证件'],
};

const Map<String, List<String>> kTopicSenseKeywords = {
  '日常起居': [
    '睡', '起床', '洗澡', '洗', '刷牙', '梳理', '打开', '关上', '坐', '站',
    '放下', '干净', '脏', '房间', '厨房', '钥匙', '灯', '打扫', '晾晒', '折叠',
    '切', '煮', '炒', '烧', '家务', '日常', '起居', '醒来', '起身', '旁边',
    '隔壁', '小心', '当心',
  ],
  '餐饮食物': [
    '吃', '喝', '饭', '面', '面包', '肉', '鱼', '菜', '水果', '糖', '盐',
    '咖啡', '茶', '牛奶', '汤', '味道', '甜', '咸', '辣', '苦', '酸', '饿',
    '饱', '餐', '厨', '食', '饮', '料理', '小吃', '点心', '米饭', '鸡', '蛋',
    '奶', '锅', '碗', '杯', '勺', '盘', '筷', '豆腐', '空心菜',
  ],
  '烹饪厨艺': [
    '烹饪', '厨艺', '食谱', '调味', '腌制', '佐料', '火候', '翻炒', '切块',
    '剁', '蒸', '煎', '炸', '烤', '煮', '炒', '炖', '拌',
  ],
  '饮品酒水': [
    '咖啡', '茶', '果汁', '酒', '饮料', '奶茶', '牛奶', '饮用水', '汽水',
    '啤酒', '葡萄酒', '冰镇', '解渴', '清酒', '饮品',
  ],
  '食材调料': [
    '食材', '原料', '香料', '面粉', '调味', '食用油', '配料', '淀粉', '蜂蜜',
    '奶油', '馅', '糖', '盐', '醋', '酱', '胡椒', '辣椒', '姜', '蒜', '葱',
    '肉', '鱼', '蛋', '豆腐',
  ],
  '服饰穿着': [
    '衣服', '衣物', '服装', '裤', '衬衫', '鞋', '帽', '布料', '裙', '外套',
    '穿', '凉鞋', '腰带', '缝', '纽扣', '口袋', '制服', '首饰', '戒指', '项链',
    '袜', '领带', '头巾', '沙龙', '戴',
  ],
  '房间家具': [
    '门', '地板', '墙壁', '隔板', '椅子', '窗户', '灯', '柜', '衣橱', '镜子',
    '被子', '架子', '搁架', '书架', '桌', '床', '沙发', '家具', '抽屉', '垫',
    '毯', '枕',
  ],
  '厨房用具': [
    '冰箱', '冰柜', '炉灶', '炉子', '水壶', '锅', '筛子', '过滤器', '臼',
    '锅铲', '抹刀', '捣杵', '勺', '刀', '案板', '砧板', '灶', '烤箱', '微波炉',
  ],
  '餐具': [
    '杯', '盘', '碟', '碗', '餐巾', '擦手巾', '筷子', '筷', '吸管', '勺',
    '叉', '刀', '茶杯', '餐具',
  ],
  '房屋居所': [
    '房屋', '房子', '家', '房间', '门', '窗', '窗户', '屋顶', '地板', '墙',
    '厨房', '浴室', '卧室', '寝室', '床', '桌', '椅', '柜', '院子', '庭院',
    '篱笆', '阳台', '门廊', '住宅', '居所', '楼层', '空间',
  ],
  '颜色': [
    '红', '蓝', '绿', '黄', '黑', '白', '灰', '棕', '褐', '紫', '橙', '青',
    '靛', '金', '银', '粉', '米色', '深色', '浅色', '彩色', '颜色', '色',
  ],
  '交通工具': [
    '汽车', '巴士', '摩托', '自行车', '火车', '飞机', '轮船', '船', '船舶',
    '出租车', '卡车', '渡轮', '缆车', '高铁', '邮轮', '货船', '油轮', '客轮',
    '帆船', '战斗机', '校车', '私家车', '面包车', '马车', '小巴', '地铁', '机车',
    '直升机', '车辆', '交通工具',
  ],
  '交通出行': [
    '汽车', '摩托', '自行', '公交', '火车', '飞机', '轮船', '船', '出租',
    '驾车', '驾驶', '汽油', '到达', '出发', '乘坐', '上车', '下车', '下，下去',
    '道路', '红绿灯', '码头', '港口', '停车', '乘客', '司机', '堵车', '交通',
    '车', '票', '机场', '车站', '船员', '机组', '行走', '行程', '路线', '通道',
    '借过',
  ],
  '购物金钱': [
    '买', '卖', '价格', '价钱', '钱', '付款', '支付', '商店', '市场', '折扣',
    '贵', '便宜', '银行', '存款', '借', '债', '税', '工资', '利润', '获利',
    '亏', '费用', '分期', '还价', '钱包', '账户', '货币', '交易', '购物',
    '消费', '收银', '找零', '老板', '代理商', '贷款', '赊账', '现金', '越南盾',
  ],
  '城市建筑': [
    '城市', '都市', '乡村', '农村', '建筑', '大楼', '楼房', '塔', '桥', '砖',
    '水泥', '混凝土', '屋顶', '柱子', '装修', '建造', '拆除', '建筑师', '街道',
    '人行道', '排水', '宫殿', '纪念碑', '工地', '阳台', '门廊',
  ],
  '生活实用': [
    '饭馆', '餐馆', '大排档', '小卖部', '杂货店', '床铺', '卧室', '客厅',
    '浴室', '洗手间', '厕所', '开水', '热水', '冷水', '饮用水', '炒饭', '炒面',
    '炸鸡', '零食', '小吃', '点心', '冷饮', '堂食', '打包', '找零', '身份证',
    '休息日', '营业', '高峰',
  ],
  '星期': [
    '星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日',
    '星期天', '周日', '周一', '周二', '周三', '周四', '周五', '周六', '礼拜',
    '星期',
  ],
  '月份': [
    '一月', '二月', '三月', '四月', '五月', '六月', '七月', '八月', '九月',
    '十月', '十一月', '十二月', '月份', '正月',
  ],
  '数字': [
    '零', '一', '二', '三', '四', '五', '六', '七', '八', '九', '十', '百',
    '千', '万', '亿', '数字', '数目', '号码',
  ],
  '序数': [
    '第一', '第二', '第三', '第四', '第五', '第六', '第七', '第八', '第九',
    '第十', '第', '序数', '最初', '三号', '首席',
  ],
  '时间单位': [
    '秒', '分钟', '小时', '钟点', '天', '一天', '白昼', '日子', '星期', '周',
    '月份', '年', '年份', '世纪', '年代', '时刻',
  ],
  '时间日历': [
    '时间', '小时', '分钟', '秒', '早上', '上午', '中午', '下午', '晚上',
    '昨天', '明天', '现在', '以后', '从前', '开始', '结束', '经常', '很少',
    '时代', '季节', '日期', '永远', '一会儿', '暂时', '一天', '白昼', '日子',
    '年', '月份', '星期', '过了', '接下来', '然后', '往后',
  ],
  '频率': [
    '经常', '常常', '总是', '有时', '偶尔', '曾经', '很少', '不常', '从不',
    '频繁', '随时', '改天', '每次', '再三', '一再',
  ],
  '数学计量': [
    '数学', '数字', '加法', '减法', '乘法', '除法', '等于', '计算', '总数',
    '合计', '平均', '百分', '小数', '分数', '公式', '几何', '角度',
    '分（角度）', '测量', '称重', '尺寸', '刻度', '倍数', '一半', '不够',
    '缺少', '数量', '计量', '单位',
  ],
  '身体健康': [
    '疾病', '生病', '疼痛', '药', '医生', '大夫', '医院', '发烧', '咳嗽',
    '感冒', '伤口', '受伤', '检查', '痊愈', '好转', '康复', '健康', '疫苗',
    '护士', '怀孕', '治疗', '症状', '手术', '血压', '营养', '疼', '痛', '病',
    '血', '身体',
  ],
  '身体部位': [
    '眼睛', '鼻子', '耳朵', '牙齿', '舌头', '皮肤', '心脏', '肝脏', '肺',
    '大脑', '肚子', '脖子', '手指', '膝盖', '肩膀', '骨头', '肌肉', '嘴唇',
    '额头', '脸颊', '指甲', '头发', '身体', '脸', '头', '嘴', '手', '脚',
    '腿', '背', '背部', '胸', '血', '尾巴', '关节',
  ],
  '医疗就医': [
    '医院', '医生', '大夫', '诊所', '护士', '病人', '患者', '药房', '处方',
    '挂号', '门诊', '住院', '打针', '输液', '化验', '体检', '体温', '血压',
    '血糖', '发烧', '咳嗽', '感冒', '疼痛', '伤口', '受伤', '手术', '疫苗',
    '接种', '急诊', '救护车', '病房', '症状', '疾病', '生病', '过敏', '剂量',
    '康复', '好转', '复查', '转诊', '忌口', '药', '病', '医',
  ],
  '情绪感受': [
    '高兴', '开心', '快乐', '幸福', '生气', '愤怒', '发怒', '害怕', '恐惧',
    '悲伤', '伤心', '难过', '担心', '忧虑', '焦虑', '惊讶', '害羞', '失望',
    '满意', '羡慕', '嫉妒', '紧张', '无聊', '喜欢', '讨厌', '哭', '笑',
  ],
  '情感心理': [
    '爱情', '恋爱', '想念', '高兴', '开心', '喜欢', '伤心', '难过', '生气',
    '愤怒', '发怒', '害怕', '敬畏', '害羞', '骄傲', '自豪', '失望', '希望',
    '担心', '忧虑', '焦虑', '快乐', '讨厌', '耐心', '平静', '幸福', '幸运',
    '情绪', '嫉妒', '勇敢', '沮丧', '抑郁', '感激', '内心', '心理', '小心',
    '谨慎', '哭', '笑', '怒', '怕',
  ],
  '性格品质': [
    '勤劳', '懒惰', '诚实', '虚伪', '撒谎', '吝啬', '小气', '大方', '友善',
    '友好', '骄傲', '谦虚', '聪明', '愚蠢', '笨', '认真', '马虎', '忠诚',
    '背叛', '内向', '外向', '话多', '性格', '脾气', '品质', '善良',
  ],
  '工作职场': [
    '工作', '办公', '办公室', '职业', '员工', '老板', '上司', '会议', '任务',
    '职责', '合同', '面试', '项目', '公司', '事业', '专业', '岗位', '同事',
    '加班', '简历', '应聘', '辞职', '领导', '秘书', '薪水', '工资', '组织',
    '代理', '谋生',
  ],
  '学习教育': [
    '学习', '教学', '学校', '老师', '教师', '学生', '大学生', '课程', '大学',
    '书', '课本', '考试', '分数', '成绩', '学分', '班级', '知识', '阅读',
    '计算', '语言', '词典', '图书馆', '学位', '学士', '硕士', '背诵', '翻译',
    '作业', '研究', '专业', '教室', '讲台', '例子', '语法',
  ],
  '学习用品': [
    '书', '册', '包', '袋', '胶水', '黏合', '铅笔', '画笔', '笔', '墨水',
    '油墨', '回形针', '夹子', '词典', '字典', '文件夹', '胶带', '板擦',
    '橡皮', '尺', '本子', '笔记本', '文具', '纸',
  ],
  '通讯网络': [
    '电话', '手机', '话费', '流量', '网络', '信号', '下载', '上传', '应用',
    '软件', '账号', '密码', '验证码', '消息', '短信', '来电', '通话', '呼叫',
    '通讯录', '联系人', '号码', '电池', '充电', '屏幕', '轻触', '截屏',
    '直播', '链接', '更新', '内存', '存储', '铃声', '震动', '无线', '蓝牙',
    '耳机', '套餐', '上网', '连接', '主页', '首页', '转发', '转达', '置顶',
    '固定显示', '推送', '通知', '话题标签', '归档', '存档', '备份', '分享',
    '设置', '窗口', '发送', '接收', '通道', '代码', '回复', '打招呼',
  ],
  '通信传媒': [
    '电话', '手机', '短信', '消息', '信件', '邮件', '寄', '寄送', '发送',
    '接收', '邮票', '报纸', '杂志', '新闻', '报道', '广播', '电视', '网络',
    '信号', '地址', '联系', '采访', '印刷', '传媒', '通知', '转达', '转发',
    '收音机', '无线电',
  ],
  '常用量词': [
    '量词', '数量单位', '个', '位', '条', '根', '棵', '株', '支', '张', '片',
    '块', '件', '双', '对', '一对', '一双', '群', '批', '套', '座', '辆',
    '架', '艘', '篇', '本', '册', '粒', '颗', '滴', '捆', '尾（量词）',
  ],
  '政务证件': [
    '身份证', '护照', '签证', '户口', '户籍', '证明', '证件', '申请', '表格',
    '材料', '提交', '盖章', '公证', '移民', '税务', '派出所', '办事处', '局',
    '署', '政府', '公务员', '签名', '指纹', '复印', '委托', '许可', '审批',
    '登记', '排队', '窗口', '居民', '公所', '手续', '归档', '案件', '文书',
    '职责',
  ],
  '计算机网络': [
    '电脑', '计算机', '网络', '程序', '数据', '数字', '软件', '硬件', '屏幕',
    '轻触', '信号', '电池', '电缆', '充电', '下载', '上传', '账号', '密码',
    '网址', '网页', '网站', '主页', '首页', '线上', '离线', '应用', '社交',
    '人工智能', '算法', '代码', '编程', '路由', '截屏', '视频', '音频',
    '邮件', '聊天', '窗口', '备份', '归档', '存档', '设置', '分享', '转发',
    '置顶', '推送', '通知', '话题标签', '病毒', '输入', '存储',
  ],
  '科学研究': [
    '实验室', '研究', '科学', '理论', '实验', '观测', '分析', '定律', '公式',
    '常数', '样本', '变量', '论文', '学术', '推理', '假说', '考证',
  ],
  '工程技术': [
    '工程', '技术', '机械', '机器', '引擎', '焊接', '轴承', '发电', '工厂',
    '施工', '设备',
  ],
  '物理': [
    '物理', '电力', '电流', '电压', '导电', '磁场', '磁铁', '能量', '光',
    '光线', '光源', '光波', '辐射', '原子', '粒子', '核能', '力学', '光学',
    '波', '电荷', '放电', '静电', '光谱', '折射', '反射', '空间', '速度',
    '电感',
  ],
  '化学': [
    '化学', '元素', '分子', '化合物', '酸', '碱', '合金', '腐蚀', '溶液',
    '氧化', '催化', '气体', '液体', '固体', '蒸汽', '药剂', '剂',
  ],
  '天文宇宙': [
    '天文', '宇宙', '行星', '恒星', '卫星', '彗星', '流星', '陨石', '星系',
    '星座', '轨道', '月食', '日食', '太空', '银河', '天体', '星际', '望远镜',
    '地球', '月亮', '太阳', '星星', '星',
  ],
  '科技工程': [
    '机器', '机械', '电力', '能源', '设备', '测量', '技术', '工程', '工厂',
    '金属', '电子', '电池', '电缆', '武器', '兵器', '电器', '发电', '仪器',
    '仪表', '装配', '零件',
  ],
  '金融银行': [
    '账户', '账号', '账目', '存款', '取款', '取现', '转账', '转移', '汇款',
    '余额', '账单', '应收款', '分期', '贷款', '借款', '赊账', '利息',
    '手续费', '信用卡', '借记卡', '银行卡', '卡片', '银行', '取款机', '柜员',
    '现金', '现款', '零钱', '纸币', '硬币', '钱币', '汇率', '外币', '兑换',
    '交易', '业务', '额度', '抵押', '担保', '到期', '缴费', '收款', '对账',
    '股份', '份额', '保险', '资产', '资本', '财富', '经济', '破产', '倒闭',
    '支付', '付款', '投资', '欠款', '债务', '萧条',
  ],
  '政法军事': [
    '国家', '政府', '总统', '部长', '人民', '公民', '法律', '法令', '选举',
    '政党', '军队', '士兵', '战争', '和平', '权利', '义务', '政治', '政策',
    '法院', '法官', '警察', '外交', '内阁', '规定', '国', '王', '兵', '枪',
    '炮', '战', '案件', '武器', '兵器', '管理', '职责', '传唤',
  ],
  '战争冲突': [
    '战争', '打仗', '武器', '兵器', '枪', '炮', '子弹', '炸弹', '轰炸',
    '进攻', '攻击', '侵袭', '防御', '敌人', '投降', '停战', '和平', '堡垒',
    '基地', '部队', '入侵', '革命', '冲突',
  ],
  '宗教信仰': [
    '上帝', '真主', '祈祷', '清真寺', '教堂', '寺庙', '经文', '信仰', '神圣',
    '天使', '先知', '斋戒', '礼拜', '牧师', '天堂', '地狱', '罪', '祝福',
    '宗教', '庙', '拜', '伊斯兰', '基督教', '佛教', '神',
  ],
  '节日庆典': [
    '节日', '庆祝', '典礼', '仪式', '宴会', '派对', '烟花', '游行', '传统',
    '习俗', '婚礼', '新娘', '新郎', '求婚', '彩礼', '纪念日', '贺礼', '周年',
  ],
  '文体娱乐': [
    '音乐', '歌曲', '唱歌', '跳舞', '画', '绘画', '电影', '游戏', '玩', '球',
    '比赛', '赢', '输', '冠军', '游泳', '跑', '足球', '羽毛球', '钢琴',
    '吉他', '戏剧', '艺术', '运动', '娱乐', '摄影', '女子（比赛', '攻击',
    '明星',
  ],
  '旅行观光': [
    '旅行', '旅游', '游客', '酒店', '旅馆', '票', '护照', '签证', '机场',
    '车站', '地图', '行李', '预订', '参观', '景点', '海滩', '寺庙', '博物',
    '导游', '度假', '行程',
  ],
  '家庭人际': [
    '家庭', '家人', '父亲', '爸爸', '妈妈', '母亲', '儿子', '女儿', '哥哥',
    '弟弟', '姐姐', '妹妹', '兄', '姐', '兄弟', '姐妹', '祖母', '祖父',
    '奶奶', '爷爷', '丈夫', '妻子', '夫人', '夫妻', '朋友', '同伴', '邻居',
    '亲戚', '亲属', '叔', '阿姨', '表兄', '结婚', '出生', '父母', '孩子',
    '大人',
  ],
  '亲属称谓': [
    '父亲', '母亲', '爸爸', '妈妈', '哥哥', '姐姐', '弟弟', '妹妹', '兄',
    '姐', '兄弟', '姐妹', '儿子', '女儿', '祖父', '祖母', '爷爷', '奶奶',
    '叔', '舅', '姑', '姨', '丈夫', '妻子', '夫人', '亲戚', '亲属', '孙',
    '侄', '外甥', '岳父', '岳母', '公婆', '女婿', '儿媳', '连襟', '妯娌',
  ],
  '自然万物': [
    '海洋', '河流', '地球', '大地', '土地', '泥土', '空气', '大气', '自然',
    '野生', '海', '河', '环境', '生态', '潮', '浪', '天空', '月亮', '太阳',
    '星星', '大自然', '山水',
  ],
  '天气气候': [
    '天气', '下雨', '雨', '暴雨', '风', '云', '雾', '露', '雪', '冰', '雷',
    '雷声', '闪电', '彩虹', '洪水', '干旱', '地震', '海啸', '火山', '气温',
    '温度', '炎热', '寒冷', '潮湿', '干燥', '气候', '阴天', '晴天', '旱季',
    '雨季', '季节', '大气',
  ],
  '农业渔业': [
    '农业', '农民', '稻田', '田', '种植', '播种', '收割', '收获', '采摘',
    '种子', '秧苗', '肥料', '灌溉', '养殖', '畜牧', '渔民', '捕鱼', '渔网',
    '钓鱼', '鱼塘', '砍伐', '庄稼',
  ],
  '动物': [
    '动物', '野兽', '鸟', '鱼', '昆虫', '蝴蝶', '蜜蜂', '蚂蚁', '鲨鱼',
    '鲸鱼', '海豚', '青蛙', '雨蛙', '蛙', '乌龟', '骆驼', '袋鼠', '狮子',
    '老虎', '大象', '象', '猴子', '羊', '鸡', '鸭', '鹰', '鹦鹉', '乌鸦',
    '蝙蝠', '刺猬', '松鼠', '幼虫', '毛虫', '害虫', '爬虫', '哺乳', '猎豹',
    '鳄鱼', '海龟', '物种', '狗', '猫', '牛', '马', '猪', '蛇', '鼠', '鹿',
    '兽', '虫', '尾巴',
  ],
  '植物': [
    '植物', '树', '森林', '花', '花朵', '花卉', '花草', '叶', '根', '茎',
    '干', '竹', '藤', '木材', '芽', '灌木', '苔藓', '蕨', '果园', '光合',
    '果实', '种子', '籽',
  ],
  '地质水文': [
    '地质', '地震', '火山', '岩石', '矿物', '土壤', '土地', '陆地', '河流',
    '水源', '地下水', '海湾', '半岛', '岛屿', '三角洲', '潮汐', '支流',
    '山谷', '平原', '高原', '盆地', '溶洞', '基岩', '断层', '山丘', '丘陵',
    '矿', '钻井', '山崖', '地基',
  ],
  '水果': [
    '水果', '果实', '果', '香蕉', '芒果', '木瓜', '菠萝', '西瓜', '椰子',
    '椰', '榴莲', '山竹', '红毛丹', '柚子', '橙子', '橘子', '柠檬', '葡萄',
    '苹果', '梨', '桃', '李', '荔枝', '龙眼', '草莓', '樱桃', '石榴',
    '百香果', '牛油果', '番石榴', '波罗蜜',
  ],
  '蔬菜作物': [
    '蔬菜', '菜', '空心菜', '白菜', '菠菜', '洋葱', '辣椒', '茄子', '黄瓜',
    '南瓜', '苦瓜', '丝瓜', '冬瓜', '玉米', '稻', '米', '麦', '豆', '花生',
    '木薯', '红薯', '马铃薯', '土豆', '姜', '蒜', '葱', '芹菜', '生菜',
    '卷心菜', '萝卜', '番茄', '西红柿', '蘑菇', '菌', '作物',
  ],
  '工具材料': [
    '工具', '方式', '锤', '钉子', '螺丝', '扳手', '起子', '锯', '锉', '砂纸',
    '绳', '铁丝', '链条', '木头', '木材', '铁', '钢', '金属', '塑料', '橡胶',
    '胶水', '机器', '机械', '钻', '材料', '原料',
  ],
  '疑问词': [
    '什么', '谁', '哪', '哪里', '哪个', '怎么', '怎样', '如何', '多少', '几',
    '何时', '为什么', '为何', '难道', '吗', '呢',
  ],
  '人称代词': [
    '我', '你', '您', '他', '她', '它', '我们', '咱们', '你们', '他们',
    '她们', '自己', '自身', '大家', '俺', '人家',
  ],
  '指示词': [
    '这', '这个', '这里', '这儿', '这样', '这么', '那', '那个', '那里',
    '那儿', '那样', '那么', '上述', '该', '此', '彼',
  ],
  '程度副词': [
    '非常', '十分', '极其', '极', '最', '太', '不太', '过于', '过分', '很',
    '更', '越', '稍微', '略微', '有点', '足够', '够', '完全', '格外', '相当',
  ],
  '方向方位': [
    '上', '上面', '上方', '下', '下面', '下方', '前', '前面', '前方', '后',
    '后面', '后方', '左', '左边', '左侧', '右', '右边', '右侧', '东', '南',
    '西', '北', '中', '中间', '内', '里', '外', '外面', '外部', '旁', '旁边',
    '侧', '方向', '方位', '边',
  ],
  '问候礼貌语': [
    '你好', '您好', '喂', '哈喽', '打招呼', '早上好', '下午好', '晚上好',
    '晚安', '再见', '抱歉', '对不起', '原谅', '谢谢', '感谢', '致谢',
    '不客气', '劳驾', '打扰', '借过', '请', '欢迎', '平安', '祝',
  ],
  '问候寒暄': [
    '早上好', '中午好', '午安', '下午好', '晚上好', '晚安', '欢迎', '快乐',
    '再见', '平安', '顺风', '认识', '久仰', '失陪', '祝', '好吗', '近况',
    '问候',
  ],
  '礼貌客套': [
    '谢谢', '道谢', '感谢', '不客气', '没关系', '没问题', '对不起', '道歉',
    '抱歉', '原谅', '借过', '劳驾', '打扰', '请', '稍候', '等一下', '当然',
    '别担心', '别忘了',
  ],
  '问答常用': [
    '什么', '谁', '哪里', '几点', '多少', '多大', '为什么', '怎么', '意思',
    '知道', '明白', '慢一点', '再说一遍', '可以吗',
  ],
  '语言与语法': [
    '标点', '句号', '逗号', '问号', '感叹号', '连字符', '破折号', '引号',
    '括号', '字母', '斜体', '粗体', '元音', '辅音', '拼音', '正字法',
    '规范词', '标准词', '词根', '动词', '名词', '形容词', '代词', '数词',
    '副词', '状语', '连词', '介词', '重叠词', '复合词', '感叹词', '冠词',
    '疑问词', '称呼语', '助动词', '主动句', '被动句', '疑问句', '祈使句',
    '陈述句', '复合句', '从句', '主句', '词缀', '前缀', '后缀', '中缀',
    '派生词', '同义词', '反义词', '同音', '多义词', '修辞', '语体', '习语',
    '班顿', '书评', '主旨', '主题句', '提纲', '语篇', '记叙文', '描写文',
    '说明文', '议论文', '劝说文', '语言', '语法', '格', '词',
  ],
  '口语与俚语（Bahasa Gaul）': [
    '口语', '俗', '俚', '语气', '嘛', '呗', '呀', '啦', '吧', '呢', '哎',
    '哇', '咦', '俺', '只是', '如果', '非常', '极其', '加油', '快点', '怎',
    '竟然',
  ],
  '拟声词': [
    '声', '拟声', '滴答', '沙沙', '搏动', '心跳', '锣', '叫声', '嘎吱',
    '铃声', '叮当', '咚咚', '敲击', '砰', '轰隆', '雷声', '啪', '哗', '嗡',
    '喵', '汪', '咕', '咔',
  ],
};
