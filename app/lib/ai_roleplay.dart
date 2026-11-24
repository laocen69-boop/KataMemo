/// 印尼语情景角色扮演引擎（BIPA A1–B2 分级 · TBBBI 语法与语用规范 · 任务词形态还原打卡）。
///
/// 设计原则：
///   1. **12 个高频真实交际场景**全部原创编写，严格遵守 EYD V 拼写规范（附着词连写、pun 分写、
///      介词 di/ke 分写与被动前缀 di- 连写、称谓语 Bapak/Ibu/Anda/Kak/Mas/Mbak 大写、对象语态体标记前置）；
///   2. **语域与礼貌显式化**：区分日常亲切体（Kak/Mas/Mbak）、公务敬语体（Bapak/Ibu/Anda + 间接委婉请求）
///      与商务/学术规范体，避免学生把口语词写进正式场合或反之；
///   3. **错词/新词驱动输出**：自动将学生近期错词、痛点词或场景核心词设为「本轮任务词」，
///      并通过 [matchRoleplayTargetWords] 结合 [indonesianStem] 识别词根及 meN-/di-/ber-/-kan/-i/-an/-nya 派生形，
///      学生在句子里自然用出变形即自动打钩。
library;

import 'ai_chat.dart';
import 'ai_tools.dart' show indonesianStem;
import 'app_state.dart';

class AiRoleplayScenario {
  final String id;
  final String title;
  final String level; // A1, A2, B1, B2
  final String register; // 语域与称谓要求
  final String aiRole; // AI 扮演的角色
  final String userGoal; // 学生的交际任务
  final String grammarFocus; // 本场景重点操练的语法与语用点
  final String openerId; // AI 开场第一句（规范印尼语）
  final String openerZh; // 开场白中文译文
  final List<String> defaultTargets; // 默认推荐任务词（无错词时兜底）

  const AiRoleplayScenario({
    required this.id,
    required this.title,
    required this.level,
    required this.register,
    required this.aiRole,
    required this.userGoal,
    required this.grammarFocus,
    required this.openerId,
    required this.openerZh,
    required this.defaultTargets,
  });
}

/// 12 个原创 BIPA A1–B2 真实交际场景（全部通过 EYD V 13 项拼写与 TBBBI 语态核查）。
const List<AiRoleplayScenario> kAiRoleplayScenarios = [
  AiRoleplayScenario(
    id: 'warung_makan',
    title: '餐馆点菜与忌口',
    level: 'A1',
    register: '日常礼貌体（称呼 Kak / Mas / Mbak）',
    aiRole: '印尼家常菜馆（warung makan）服务员 Mas Budi',
    userGoal: '点一份主食和饮料、说明不要太辣或不放花生，并询问能否扫码支付（QRIS）。',
    grammarFocus: '否定词 tidak / bukan / jangan 的分工；数词+量词/部分词（satu porsi、segelas）；委婉请求 minta / tolong。',
    openerId: 'Selamat siang, Kak! Silakan duduk. Hari ini mau pesan makanan apa, dan minumnya mau dingin atau hangat?',
    openerZh: '中午好！请坐。今天想点什么吃的，饮料要冰的还是温的？',
    defaultTargets: ['pesan', 'pedas', 'tanpa', 'bayar'],
  ),
  AiRoleplayScenario(
    id: 'ojol_arah',
    title: '网约摩的与指路',
    level: 'A1',
    register: '日常实用体（称呼 Pak / Bang / Kak）',
    aiRole: '正在寻找上车点的网约摩的（ojol）司机 Pak Dani',
    userGoal: '告诉司机你在商场大门旁边的便利店门口、穿什么颜色的衣服，并在路上请他到了十字路口左转。',
    grammarFocus: '方位介词 di / ke / dari 分写；方位名词 di sebelah / di depan；祈使句与委婉词 tolong / ya。',
    openerId: 'Halo, Kak. Saya pengemudi ojol yang menjemput Kakak. Sekarang titik jemputnya di sebelah mana, ya?',
    openerZh: '您好，我是来接您的网约摩的司机。请问您现在的上车点具体在哪一边呢？',
    defaultTargets: ['jemput', 'depan', 'belok', 'tunggu'],
  ),
  AiRoleplayScenario(
    id: 'tawar_pasar',
    title: '传统市场买水果砍价',
    level: 'A2',
    register: '市井亲切体（称呼 Bu / Pak，可自然使用礼貌口语）',
    aiRole: '传统市场（pasar tradisional）水果摊主 Ibu Sari',
    userGoal: '询问芒果每公斤多少钱、表示买两公斤希望能便宜一点，并挑选熟度刚好的水果。',
    grammarFocus: '价格与计量提问（berapa harganya / per kilogram）；条件与让步（kalau ambil dua...）；形容词程度比较（terlalu matang / lebih murah）。',
    openerId: 'Silakan dilihat dulu buahnya, Kak. Mangga harum manis ini baru datang tadi pagi. Mau ambil berapa kilogram?',
    openerZh: '先看看水果吧。这批香甜芒是今天早上刚到的。您想拿几公斤？',
    defaultTargets: ['harga', 'tawar', 'manis', 'timbang'],
  ),
  AiRoleplayScenario(
    id: 'cari_kos',
    title: '看房与租学生公寓',
    level: 'A2',
    register: '礼貌半正式体（称呼 Ibu / Bapak + Saya / Anda）',
    aiRole: '印尼学生公寓（kos-kosan）房东 Ibu Ratna',
    userGoal: '询问月租是否包含水电网费、房间空调和浴室是否正常，以及最短租期是几个月。',
    grammarFocus: '定语后置（DM 语序：kamar mandi dalam、biaya listrik）；已完/未完体标记 sudah / belum；包含动词 termasuk。',
    openerId: 'Selamat sore. Ini kamar kos yang masih kosong di lantai dua. Apakah Anda ingin melihat fasilitas di dalamnya dulu?',
    openerZh: '下午好。这就是二楼还空着的房间。您想先看看里面的设施吗？',
    defaultTargets: ['sewa', 'termasuk', 'listrik', 'bersih'],
  ),
  AiRoleplayScenario(
    id: 'bandara_imigrasi',
    title: '机场入境与海关申报',
    level: 'A2',
    register: '正式公务体（称呼 Bapak / Ibu + 标准书面/口语 bahasa baku）',
    aiRole: '雅加达机场入境边检官员（petugas imigrasi）',
    userGoal: '说明来印尼的目的是旅游（或商务出差）、计划停留的天数、下榻酒店位置，并出示返程机票。',
    grammarFocus: '时间介词 selama vs pada；目的介词 untuk；将来与计划表达 akan / berencana。',
    openerId: 'Selamat malam. Boleh saya lihat paspor dan tiket pulang Anda? Berapa lama Anda akan tinggal di Indonesia, dan untuk keperluan apa?',
    openerZh: '晚上好。请出示您的护照和返程机票好吗？您将在印尼停留多久，来访目的是什么？',
    defaultTargets: ['tujuan', 'tinggal', 'selama', 'kembali'],
  ),
  AiRoleplayScenario(
    id: 'klinik_obat',
    title: '诊所看病与说明症状',
    level: 'B1',
    register: '礼貌正式体（称呼 Dokter + 清晰描述感受与时长）',
    aiRole: '全科诊所医生 Dokter Hendra',
    userGoal: '描述自己从昨天开始发烧、喉咙痛且咳嗽，说明是否有药物过敏，并询问药是饭前还是饭后吃。',
    grammarFocus: '时间起点 sejak；身体感受与被动遭受（terasa sakit / kehujanan）；频次表达 sehari tiga kali；前后时间 sebelum / sesudah makan。',
    openerId: 'Selamat pagi, silakan masuk. Keluhan apa yang Anda rasakan sejak kemarin, dan apakah sudah sempat minum obat?',
    openerZh: '早上好，请进。从昨天起您觉得哪里不舒服，已经吃过药了吗？',
    defaultTargets: ['demam', 'periksa', 'resep', 'istirahat'],
  ),
  AiRoleplayScenario(
    id: 'belanja_daring',
    title: '网购少发与退换货客服',
    level: 'B1',
    register: '礼貌客服沟通体（称呼 Kak / Admin + 条理清晰说明事实）',
    aiRole: '印尼电商平台店铺客服 Admin Toko',
    userGoal: '说明刚收到的包裹里少了一件商品且外盒破损，表示已拍下开箱视频，要求补发或退款。',
    grammarFocus: '第一二人称对象语态（paket yang baru saya terima）；关系从句 yang；因果连词 karena（不与 maka 并用）。',
    openerId: 'Halo, Kak. Terima kasih sudah menghubungi toko kami. Ada kendala apa dengan pesanan yang baru Kakak terima?',
    openerZh: '您好，感谢联系本店。请问您刚收到的订单遇到了什么问题？',
    defaultTargets: ['pesanan', 'rusak', 'bukti', 'ganti'],
  ),
  AiRoleplayScenario(
    id: 'hotel_keluhan',
    title: '酒店入住与设施报修',
    level: 'B1',
    register: '得体礼貌请求体（称呼 Bapak / Ibu + 委婉祈使 mohon / apakah bisa）',
    aiRole: '酒店前台值班经理',
    userGoal: '反映房间空调不制冷且无线网络信号弱，请工程人员上来看看，或者申请更换到安静的房间。',
    grammarFocus: 'di- 被动式与第一二人称对象语态（segera kami perbaiki）；使役/受益后缀 -kan 与处所后缀 -i；目的连词 agar / supaya（不叠用）。',
    openerId: 'Selamat malam, Bapak. Mohon maaf atas ketidaknyamanannya. Boleh dijelaskan kendala di kamar Bapak agar segera kami perbaiki?',
    openerZh: '晚上好，先生。非常抱歉给您带来不便。能请您说明一下房间的具体问题，以便我们马上修复吗？',
    defaultTargets: ['keluhan', 'perbaiki', 'pindah', 'nyaman'],
  ),
  AiRoleplayScenario(
    id: 'kampus_dosen',
    title: '向大学导师请假与改期',
    level: 'B1',
    register: '学术敬语体（称呼 Bapak / Ibu Dosen + 严禁口语缩写，用 mohon maaf / apakah berkenan）',
    aiRole: '印尼大学论文指导老师 Ibu Lestari',
    userGoal: '礼貌致歉，说明周一因签证办理（或身体不适）无法参加面谈，请求将指导时间改到周三下午并提交初稿。',
    grammarFocus: '语用得体准则与间接请求（Apakah Ibu berkenan...）；星期与类名大小写（hari Senin / hari Rabu）；正式连词 oleh karena itu。',
    openerId: 'Selamat pagi. Saya sudah membaca pesan singkat Anda. Mengapa Anda tidak dapat hadir pada kuliah hari Senin ini?',
    openerZh: '早上好。我已经看了您的短信。请问您为什么无法参加本周一的课程？',
    defaultTargets: ['hadir', 'izin', 'jadwal', 'bimbingan'],
  ),
  AiRoleplayScenario(
    id: 'bank_rekening',
    title: '银行开户与银行卡挂失',
    level: 'B2',
    register: '正式服务规范体（称呼 Bapak / Ibu + 标准术语与对象语态）',
    aiRole: '印尼本地银行柜台客户经理',
    userGoal: '说明银行卡昨天在取款机被吞（或遗失），申请立即冻结旧卡、补办新卡，并开通手机银行转账功能。',
    grammarFocus: '名词化词缀 peN-...-an 与 per-...-an（pembukaan / penggantian / persyaratan）；被动式 di- 与非意愿 ter-（tertelan mesin ATM）。',
    openerId: 'Selamat pagi, Ibu. Silakan duduk. Untuk pembukaan rekening baru atau pelaporan kartu yang hilang, dokumen apa saja yang sudah Ibu siapkan?',
    openerZh: '早上好，女士，请坐。办理新开户或银行卡挂失，请问您已经准备好了哪些证件材料？',
    defaultTargets: ['rekening', 'hilang', 'syarat', 'daftar'],
  ),
  AiRoleplayScenario(
    id: 'kantor_rapat',
    title: '跨国团队项目延期协商',
    level: 'B2',
    register: '商务正式体（称呼 Bapak / Ibu / Rekan-rekan + 规范书面词汇）',
    aiRole: '印尼分公司项目负责人 Pak Arif',
    userGoal: '汇报当前进度、解释供应商交货延迟的原因，提出先上线核心功能的折中方案，并征求印尼团队意见。',
    grammarFocus: '规范词形（memengaruhi / mengubah / menyukseskan）；对象语态与体标记前置（harus kita dahulukan）；让步复句 meskipun...（不配 tetapi）。',
    openerId: 'Selamat pagi, rekan-rekan. Jadwal peluncuran proyek kita perlu disesuaikan lagi. Menurut Anda, bagian mana yang harus kita dahulukan minggu ini?',
    openerZh: '大家早上好。我们项目的上线排期需要重新调整。在您看来，本周我们应该优先推进哪一部分？',
    defaultTargets: ['jadwal', 'pengaruhi', 'setuju', 'selesai'],
  ),
  AiRoleplayScenario(
    id: 'interview_kerja',
    title: '驻印尼岗位求职面试',
    level: 'B2',
    register: '正式职场敬语体（标准印尼语 bahasa baku + 逻辑衔接词 selain itu / dengan demikian）',
    aiRole: '印尼外企人力资源主管',
    userGoal: '介绍自己的专业背景与跨文化沟通经验、说明为什么想来印尼工作，并向面试官提一个关于团队协作的问题。',
    grammarFocus: '系词 adalah / merupakan 的规范用法；动词后缀 -kan 与 -i 的精微区分（menguasai bahasa vs menawarkan solusi）；正式体标记 telah。',
    openerId: 'Selamat siang, terima kasih telah hadir tepat waktu. Bisakah Anda menceritakan pengalaman kerja yang paling relevan dengan posisi yang Anda lamar ini?',
    openerZh: '下午好，感谢您准时到场。您能谈谈与您所申请岗位最相关的一段工作经历吗？',
    defaultTargets: ['pengalaman', 'kuasai', 'tantangan', 'kontribusi'],
  ),
];

AiRoleplayScenario? aiRoleplayById(String id) {
  for (final s in kAiRoleplayScenarios) {
    if (s.id == id) return s;
  }
  return null;
}

final RegExp _reToken = RegExp(r'[a-zà-ÿ]+(?:-[a-zà-ÿ]+)*', caseSensitive: false);

/// 检测学生在对话消息 [userTexts] 中已经自然用出了哪些任务词 [targets]。
///
/// 支持：
///   · 原词精确匹配（大小写无关）；
///   · 连字符叠词拆半匹配（如 `anak-anak` 命中 `anak`）；
///   · 印尼语派生词干还原匹配（如学生写出 `memesan`/`pesanan`/`dipesan` 均可命中目标词 `pesan`，
///     写出 `memengaruhi` 命中 `pengaruhi` 或 `pengaruh`）；
///   · 多词短语子串匹配。
Set<String> matchRoleplayTargetWords(
  List<String> targets,
  Iterable<String> userTexts,
) {
  if (targets.isEmpty) return const {};
  final combinedLower = userTexts.map((s) => s.toLowerCase()).join('\n');
  if (combinedLower.trim().isEmpty) return const {};

  final userStems = <String>{};
  for (final m in _reToken.allMatches(combinedLower)) {
    final tok = m.group(0)!.toLowerCase();
    userStems.add(tok);
    userStems.addAll(indonesianStem(tok));
    if (tok.contains('-')) {
      for (final part in tok.split('-')) {
        if (part.length >= 3) {
          userStems.add(part);
          userStems.addAll(indonesianStem(part));
        }
      }
    }
  }

  final matched = <String>{};
  for (final rawTarget in targets) {
    final t = rawTarget.trim();
    if (t.isEmpty) continue;
    final tl = t.toLowerCase();
    if (tl.contains(' ')) {
      if (combinedLower.contains(tl)) matched.add(rawTarget);
      continue;
    }
    final targetStems = <String>{tl, ...indonesianStem(tl)};
    if (targetStems.any(userStems.contains)) {
      matched.add(rawTarget);
    }
  }
  return matched;
}

/// 从学生本机学习数据里自动挑选 4 个适合带入情景对话的任务词（优先：今日错词 → 长期痛点词 → 今日学过的词）。
Future<List<(String word, String zh)>> loadUserRoleplayTargets(
  AppState app, {
  int maxCount = 4,
}) async {
  final out = <(String, String)>[];
  final seen = <String>{};
  void add(String? w, String? zh) {
    final word = (w ?? '').trim();
    if (word.isEmpty || out.length >= maxCount) return;
    final key = word.toLowerCase();
    if (seen.add(key)) {
      out.add((word, (zh ?? '').trim()));
    }
  }

  try {
    final d = await app.db.db;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;

    // 1. 今日答错（困难/模糊）的词
    final badRows = await d.rawQuery(
      'SELECT w.word AS word, w.zh AS zh, SUM(CASE WHEN l.rating <= 1 THEN 1 ELSE 0 END) AS bad '
      'FROM study_log l JOIN words w ON w.id = l.card_id '
      'WHERE l.ts >= ? AND w.tier NOT IN (\'affix\', \'proper\') '
      'GROUP BY l.card_id HAVING bad > 0 ORDER BY bad DESC LIMIT ?',
      [todayStart, maxCount],
    );
    for (final r in badRows) {
      add(r['word'] as String?, r['zh'] as String?);
    }

    // 2. 长期痛点词（lapses >= 4）
    if (out.length < maxCount) {
      final leechRows = await d.rawQuery(
        'SELECT w.word AS word, w.zh AS zh FROM srs s JOIN words w ON w.id = s.card_id '
        'WHERE s.lapses >= 4 AND w.tier NOT IN (\'affix\', \'proper\') '
        'ORDER BY s.lapses DESC LIMIT ?',
        [maxCount],
      );
      for (final r in leechRows) {
        add(r['word'] as String?, r['zh'] as String?);
      }
    }

    // 3. 今日学过的普通词
    if (out.length < maxCount) {
      final todayRows = await d.rawQuery(
        'SELECT w.word AS word, w.zh AS zh, MAX(l.ts) AS t '
        'FROM study_log l JOIN words w ON w.id = l.card_id '
        'WHERE l.ts >= ? AND w.tier NOT IN (\'affix\', \'proper\') '
        'GROUP BY l.card_id ORDER BY t DESC LIMIT ?',
        [todayStart, maxCount],
      );
      for (final r in todayRows) {
        add(r['word'] as String?, r['zh'] as String?);
      }
    }
  } catch (_) {}

  return out;
}

/// 构造情景角色扮演的 [AiChatContext]。
AiChatContext aiRoleplayContext(
  AiRoleplayScenario scenario, {
  List<String> targetWords = const [],
}) {
  final targets = targetWords.isNotEmpty ? targetWords : scenario.defaultTargets;
  final targetStr = targets.join('、');

  final system = '''
你是印尼语情景对话教练，正在与中文母语的印尼语学习者进行沉浸式角色扮演。
$kIndoTutorSkill

【本次情景设定】
- 场景：${scenario.title}（难度：BIPA ${scenario.level}）
- 你的角色：${scenario.aiRole}
- 语域与称谓规范：${scenario.register}
- 学生的交际任务：${scenario.userGoal}
- 重点操练语法点：${scenario.grammarFocus}
- 学生本轮要尽量自然用出的「任务词」（用原词或合法派生词形均可）：$targetStr

【角色扮演与纠错规则】
1. 每次回复分两段：
   - 第一段：直接以「${scenario.aiRole}」的身份用**自然、规范的印尼语**接话（1–3 句，符合本场景语域，严格遵守 EYD V 拼写规范：-nya/-ku/-mu/-lah/-kah 连写、pun 分写、介词 di/ke 分写与被动前缀 di- 连写、称谓语大写），并在句末推进对话，引导学生开口或用出剩余任务词；紧跟一行括号中文翻译。
   - 第二段（仅当学生上一句有拼写、词缀、语态、语序或语域不当，或成功用出任务词时）：用 `>` 引用块简短点评（最多指出 2 处最关键的偏误，给出「原句 → 地道改法（原因）」；若学生自然用出了任务词，顺带表扬一句）。
2. 如果学生卡壳或用中文求助，先给 2 个不同礼貌度/句式的印尼语表达范例供他模仿，再继续保持角色对话。
3. 当学生完成交际任务或主动要求「结束复盘」时，输出一份简明总结：任务完成度、已用出的任务词、3 条最值得记住的表达或纠错要点，并附一道 `:::quiz` 互动巩固题。$kAiQuizFormatRule
'''.trim();

  return AiChatContext(
    key: 'roleplay:${scenario.id}',
    title: '情景 · ${scenario.title}',
    subtitle: 'BIPA ${scenario.level} · 任务词 ${targets.length} 个',
    system: system,
    quick: [
      ('提示我下一句', '我现在不知道该怎么接话，请结合当前场景和还没用上的任务词，给我 2 个地道的印尼语回答提示（附中文和词缀/语域说明）。'),
      ('结束并复盘', '我们结束这轮情景对话吧！请全面复盘我刚才的表现（任务词使用、语法词缀与语域得体度），并在最后出一道 :::quiz 互动选择题巩固刚才的核心表达。'),
      ('换个更礼貌的说法', '我刚才那句话如果对长辈或正式场合说，应该怎么改写得更得体？请对比口语和正式体。'),
    ],
  );
}
