import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../theme/k_colors.dart';

Future<void> showFirstNotice(BuildContext context) {
  final k = context.k;
  Widget item(IconData icon, String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: k.deep),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: k.text)),
                  const SizedBox(height: 3),
                  Text(body,
                      style: TextStyle(
                          fontSize: 13.5, height: 1.5, color: k.t2)),
                ],
              ),
            ),
          ],
        ),
      );
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      key: const ValueKey('first-notice'),
      backgroundColor: k.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(kIsWeb ? '使用须知（网页版）' : '使用须知',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            item(
                Icons.auto_awesome_outlined,
                '中文由大语言模型生成',
                '词库的中文释义和例句译文，大部分由大语言模型生成，并经过多轮自动校对。'
                    '词库近十万条（含词组搭配），另有语法与写作学习模块，数量巨大，错漏难以完全避免。'
                    '遇到可疑的地方请以印尼语原文为准，'
                    '单词卡和语法页都能点铅笔自己改，${kIsWeb ? '修改只存在当前浏览器本地。' : '修改只存本机。'}'),
            item(Icons.menu_book_outlined, '音标参考 KBBI',
                '本版不含 KBBI 印尼语释义，「看KBBI」只跳转官网；音标参考 KBBI（印尼语大词典）；'
                    '部分例句由大语言模型生成，可能不够地道。'),
            item(Icons.volume_up_outlined, '发音是合成的',
                '单词发音由语音合成生成，不是真人录音，个别词的重音或读法可能不准。'
                    '${kIsWeb ? '首次打开请轻触一次页面以解锁浏览器自动发音；进入学习后网页版会在后台按词频自动下载全库离线语音包（约 220 MB，分 512 个分片存入浏览器私有沙盒），使用移动流量时可点击右下角悬浮进度球随时暂停，或在「设置 → 离线语音包」管理与清理。' : ''}'),
            if (kIsWeb)
              item(
                  Icons.web_outlined,
                  '学习记录与离线语音只存在当前浏览器中',
                  '本网页版没有账号和云同步，词库、进度、笔记与离线语音均集中保存在你自己的浏览器私有沙盒中（不会在手机「文件」里产生散文件），他人无法看到。'
                      '首次加载并缓存完语音后，即使开飞行模式或断网也能正常背词、看语法与听发音。'
                      '清理浏览器缓存、切换浏览器或长期未打开时数据可能丢失，建议在「设置 → 记忆算法」定期导出学习数据包备份；'
                      'iPhone Safari 推荐点分享 →「添加到主屏幕」以获得更稳定的全屏与离线体验。')
            else
              item(
                  Icons.phone_android_outlined,
                  '学习记录只存在这台手机上',
                  '没有账号和云同步，卸载或清除数据会全部丢失。'
                      '换机或重装前，请在「设置 → 记忆算法」里导出学习数据包。'),
            if (kIsWeb)
              item(
                  Icons.lock_outline,
                  '数据本地处理，AI 接口按需直连',
                  '背词、查词、语法与统计均在浏览器本地运行，网页版不含拍照抓词功能，也不会向作者上传任何数据。'
                      '只有你在「设置 → AI 助手」填入自己的 API Key 并发起提问时，才会由浏览器直接请求对应服务商（部分服务商可能受浏览器跨域限制，请勿在公共设备上保存 Key）。')
            else
              item(
                  Icons.wifi_off_outlined,
                  '连接大模型之前离线运行',
                  '背词、查词、语法、统计都在本机完成，App 自身不发出网络请求。'
                      '点参考链接（KBBI 官网、印尼语榜单等）会打开系统浏览器访问第三方页面。'
                      '只有你在「设置 → AI 助手」填入自己的 API Key 并提问时，'
                      '才会把提问和当前话题的资料发给你选的服务商；不内置 Key、不经中转、不收集使用数据。'
                      '若使用支持同 Key 联网的服务商（如 DeepSeek、智谱 GLM）或在设置里启用了搜索服务，'
                      '仅在本地词库与知识库均无答案时默认按需将搜索词发往对应服务商查网页作参考（按服务商规则计费，可在设置中随时关闭）。'
                      '例外：拍照抓词用的 Google ML Kit 会按 Google 的说明发送诊断与使用统计'
                      '（设备信息、错误码），图片和文字只在手机上识别、不上传。'),
            item(Icons.school_outlined, '仅供学习参考',
                '本应用帮助你背单词，不能替代权威词典或正式课程。'),
          ],
        ),
      ),
      actions: [
        FilledButton(
          key: const ValueKey('first-notice-ok'),
          style: FilledButton.styleFrom(
              backgroundColor: k.brand, foregroundColor: k.onbrand),
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('我知道了'),
        ),
      ],
    ),
  );
}
