library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../open_url.dart';
import '../theme/k_colors.dart';

class AiBenchLink {
  const AiBenchLink(this.name, this.url, this.desc, [this.hint = '']);
  final String name;
  final String url;
  final String desc;

  final String hint;
}

const List<AiBenchLink> kAiBenchLeaderboards = [
  AiBenchLink('SEA-HELM 印尼语排行榜', 'https://leaderboard.sea-lion.ai/detailed/ID',
      '东南亚语言模型评测，含印尼语分项', ''),
  AiBenchLink('AI Singapore / SEA-LION', 'https://sea-lion.ai/',
      'SEA-LION 模型与东南亚评测官方入口', ''),
  AiBenchLink('ibahasa 印尼语 Benchmark', 'https://ibahasa.com/id/benchmark',
      '印尼语本土任务评测', ''),
  AiBenchLink('Artificial Analysis 印尼语', 'https://artificialanalysis.ai/models/multilingual/indonesian',
      '多语模型质量/价格/速度对比，可筛印尼语', ''),
  AiBenchLink('Meta MultiLoKo Indonesian', 'https://www.kaggle.com/benchmarks/metaresearch/multiloko-indonesian',
      'Meta 多语知识评测的印尼语子集', ''),
  AiBenchLink('Cohere Global MMLU Lite Indonesian', 'https://www.kaggle.com/benchmarks/cohere-labs/global-mmlu-lite-indonesian',
      'MMLU 轻量版印尼语', ''),
  AiBenchLink('Google Lorax 印尼地方语言', 'https://research.google/pubs/lorax-a-multitask-multilingual-benchmark-suite-for-20-indonesian-languages/',
      '覆盖 20 种印尼地方语言的评测套件', ''),
];

const List<AiBenchLink> kAiBenchOrgs = [
  AiBenchLink('AI Singapore', 'https://aisingapore.org/', 'SEA-LION / SEA-HELM 发起机构'),
  AiBenchLink('Stanford CRFM', 'https://crfm.stanford.edu/', '基础模型研究中心，HELM 评测发起方'),
  AiBenchLink('Google Research', 'https://research.google/', 'Lorax 等评测的发布方'),
  AiBenchLink('Cohere Research', 'https://cohere.com/research', 'Global MMLU 等评测的发布方'),
  AiBenchLink('Meta AI Research', 'https://ai.meta.com/research/', 'MultiLoKo 等评测的发布方'),
  AiBenchLink('Hugging Face', 'https://huggingface.co/', '模型与数据集社区'),
  AiBenchLink('Hugging Face Benchmarks', 'https://huggingface.co/benchmarks', '社区维护的公开榜单汇总'),
];

const String kAiBenchDisclaimer =
    '以上为第三方公开页面，只作参考；本项目与它们无关联，内容以各页面为准。'
    '点链接用系统浏览器打开，App 自身不发网络请求。';

class AiBenchLinksCard extends StatelessWidget {
  const AiBenchLinksCard({super.key});

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    Widget row(AiBenchLink l) => InkWell(
          onTap: () async {
            final ok = await openExternalUrl(l.url);
            if (!ok) {
              await Clipboard.setData(ClipboardData(text: l.url));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('浏览器不可用，链接已复制'),
                    duration: Duration(seconds: 3)));
              }
            }
          },
          onLongPress: () async {
            await Clipboard.setData(ClipboardData(text: l.url));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('链接已复制'), duration: Duration(seconds: 3)));
            }
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(l.name,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: k.text)),
                  ),
                  Icon(Icons.open_in_new, size: 15, color: k.nT3),
                ]),
                const SizedBox(height: 2),
                Text(l.desc,
                    style: TextStyle(fontSize: 12, height: 1.5, color: k.t2)),
                if (l.hint.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(l.hint,
                        style: TextStyle(
                            fontSize: 12, height: 1.5, color: k.deep)),
                  ),
              ],
            ),
          ),
        );
    Widget group(String title, List<AiBenchLink> ls) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              child: Text(title,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: k.sec)),
            ),
            for (final (i, l) in ls.indexed) ...[
              if (i > 0) Divider(height: 0.5, thickness: 0.5, color: k.line),
              row(l),
            ],
          ],
        );
    return Container(
      decoration: BoxDecoration(
        color: k.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: k.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          group('榜单', kAiBenchLeaderboards),
          Divider(height: 0.5, thickness: 0.5, color: k.line),
          group('研究机构与社区', kAiBenchOrgs),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Text(kAiBenchDisclaimer,
                style: TextStyle(fontSize: 11.5, height: 1.6, color: k.faint)),
          ),
        ],
      ),
    );
  }
}