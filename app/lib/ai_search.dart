library;

import 'dart:convert';

import 'platform/io_shim.dart';

import 'ai_chat.dart' show AiException, redactKey;

class AiSearchProvider {
  final String id;
  final String name;
  final String vendor;
  final String endpoint;

  final String console;

  final int freeMonthly;

  final String note;

  final String? reuseAiKeyOf;

  final bool overseas;

  final String tag;

  const AiSearchProvider({
    required this.id,
    required this.name,
    required this.vendor,
    required this.endpoint,
    required this.console,
    required this.freeMonthly,
    required this.note,
    this.reuseAiKeyOf,
    this.overseas = false,
    this.tag = '',
  });

  bool get ownKey => reuseAiKeyOf == null;
}

const List<AiSearchProvider> kAiSearchProviders = [
  AiSearchProvider(
    id: 'bocha',
    name: '博查搜索',
    vendor: '博查 · 国内搜索',
    endpoint: 'https://api.bochaai.com/v1/web-search',
    console: 'https://open.bochaai.com/',
    freeMonthly: 0,
    tag: '国内推荐',
    note: '国内服务。官网写着注册后可免费领 1000 次调用资源包（有效期以官网为准），用完按量付费。'
        '到开放平台登录后创建 API Key 填进来',
  ),
  AiSearchProvider(
    id: 'zhipu',
    name: '智谱搜索',
    vendor: '用你已填的智谱 GLM Key',
    endpoint: 'https://open.bigmodel.cn/api/paas/v4/web_search',
    console: 'https://open.bigmodel.cn/usercenter/apikeys',
    freeMonthly: 0,
    tag: '国内',
    reuseAiKeyOf: 'glm',
    note: '国内服务，不用另外注册，直接用智谱 GLM 的 Key。官方价目约 0.01 元 / 次（没写免费额度），账户里要有余额',
  ),
  AiSearchProvider(
    id: 'tavily',
    name: 'Tavily',
    vendor: 'Tavily · 专给 AI 用的搜索',
    endpoint: 'https://api.tavily.com/search',
    console: 'https://app.tavily.com/home',
    freeMonthly: 1000,
    overseas: true,
    tag: '海外推荐',
    note: '海外服务，国内不一定能直连。每月 1000 次免费，注册不用绑信用卡；复制 Key（tvly- 开头）填进来就能用',
  ),
  AiSearchProvider(
    id: 'deepseek',
    name: 'DeepSeek 搜索',
    vendor: '用你已填的 DeepSeek Key',
    endpoint: 'https://api.deepseek.com/v1/tools/search',
    console: 'https://platform.deepseek.com/usage',
    freeMonthly: 0,
    note: '不用另外注册，直接用 DeepSeek 的 Key。官方没给免费额度，按成功请求计费'
        '（约 0.75 美元 / 千次，2026-11-01 起），账户里要有余额',
    tag: '国内',
    reuseAiKeyOf: 'deepseek',
  ),
  AiSearchProvider(
    id: 'custom',
    name: '自定义 API',
    vendor: '兼容 POST JSON 搜索接口',
    endpoint: '',
    console: '',
    freeMonthly: 0,
    note:
        '自备接口地址（须 https）与 Bearer Key，发 POST {query, count}；兼容 results / organic / items / search_result 返回格式',
    tag: '自定义',
  ),
];

AiSearchProvider? aiSearchProviderById(String? id) {
  for (final p in kAiSearchProviders) {
    if (p.id == id) return p;
  }
  return null;
}

class AiSearchHit {
  final String title;
  final String url;
  final String snippet;
  final String? date;
  const AiSearchHit(this.title, this.url, this.snippet, {this.date});

  Map<String, Object?> toJson() => {
        'title': title,
        'url': url,
        'snippet': snippet,
        if (date != null) 'date': date,
      };
}

const int kAiSearchQueryMax = 128;

String _clip(String s, int n) {
  final t = s.trim().replaceAll(RegExp(r'\s+'), ' ');
  return t.length <= n ? t : '${t.substring(0, n)}…';
}

bool aiValidCustomSearchEndpoint(String raw) {
  final u = Uri.tryParse(raw.trim());
  return u != null && u.scheme == 'https' && u.host.isNotEmpty;
}

Uri _resolveSearchEndpoint(AiSearchProvider p, String? customEndpoint) {
  if (p.id != 'custom') return Uri.parse(p.endpoint);
  final raw = (customEndpoint ?? '').trim();
  if (raw.isEmpty) {
    throw AiException('还没填自定义搜索的接口地址', linkProblem: false);
  }
  final u = Uri.tryParse(raw);
  if (u == null || u.scheme != 'https' || u.host.isEmpty) {
    throw AiException('自定义搜索地址须为有效的 https:// 链接', linkProblem: false);
  }
  return u;
}

({Uri url, Map<String, String> headers, String body}) aiSearchRequest(
  AiSearchProvider p,
  String key,
  String query, {
  int count = 5,
  String? customEndpoint,
}) {
  final q = _clip(query, kAiSearchQueryMax);
  final n = count.clamp(1, 8);
  final body = switch (p.id) {
    'tavily' => {
        'query': q,
        'max_results': n,
        'search_depth': 'basic',
        'topic': 'general',
        'include_answer': false,
      },
    'bocha' => {'query': q, 'count': n, 'summary': true, 'freshness': 'noLimit'},

    'zhipu' => {
        'search_query': _clip(q, 70),
        'search_engine': 'search_std',
        'search_intent': false,
        'count': n,
      },
    'custom' => {'query': q, 'count': n},
    _ => {'query': q, 'count': n, 'need_content': false},
  };
  return (
    url: _resolveSearchEndpoint(p, customEndpoint),
    headers: {
      HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
      HttpHeaders.authorizationHeader: 'Bearer ${key.trim()}',
    },
    body: jsonEncode(body),
  );
}

List<AiSearchHit> aiParseSearch(AiSearchProvider p, String body, {int max = 8}) {
  try {
    final j = jsonDecode(body);
    if (j is! Map) return const [];

    Object? rs;
    switch (p.id) {
      case 'bocha':
        final root = j['data'] is Map ? j['data'] as Map : j;
        final wp = root['webPages'];
        rs = wp is Map ? wp['value'] : null;
      case 'zhipu':
        rs = j['search_result'];
      case 'custom':
        final root = j['data'] is Map ? j['data'] as Map : j;
        final wp = root['webPages'];
        rs = j['results'] ??
            j['search_result'] ??
            j['organic'] ??
            j['items'] ??
            (wp is Map ? wp['value'] : null);
      default:
        rs = j['results'];
    }
    if (rs is! List) return const [];
    final out = <AiSearchHit>[];
    for (final r in rs) {
      if (r is! Map) continue;
      final url = '${r['url'] ?? r['link'] ?? ''}'.trim();
      final u = Uri.tryParse(url);
      if (u == null || (u.scheme != 'https' && u.scheme != 'http')) continue;
      final title = '${r['title'] ?? r['name'] ?? ''}';
      String pick(List<String> keys) {
        for (final k in keys) {
          final v = '${r[k] ?? ''}'.trim();
          if (v.isNotEmpty) return v;
        }
        return '';
      }

      final text = switch (p.id) {
        'tavily' => pick(['content']),
        'zhipu' => pick(['content']),
        'custom' => pick(['summary', 'snippet', 'content', 'description']),
        _ => pick(['summary', 'snippet']),
      };
      final date = r['date'] ?? r['published_date'] ?? r['publish_date'] ?? r['datePublished'];
      out.add(AiSearchHit(
        _clip(title, 100),
        url,
        _clip(text, 500),
        date: date == null || '$date'.isEmpty ? null : '$date'.split('T').first,
      ));
      if (out.length >= max) break;
    }
    return out;
  } catch (_) {
    return const [];
  }
}

String aiSearchErrorText(AiSearchProvider p, int status, String body) {
  var detail = '';
  try {
    final j = jsonDecode(body);
    if (j is Map) {
      final e = j['error'] ?? j['detail'];
      if (e is Map && e['message'] is String) detail = e['message'] as String;
      if (e is String) detail = e;
      if (e is Map && e['error'] is String) detail = e['error'] as String;
    }
  } catch (_) {}
  final tail = detail.isEmpty ? '' : '\n服务商说明：${_clip(detail, 120)}';
  return switch (status) {
    400 => '搜索请求被拒绝（400）$tail',
    401 => '${p.name} 的 Key 不对或已失效，请到「AI 设置 → 联网搜索」重新填写$tail',
    402 || 432 || 433 => '${p.name} 的额度用完了或余额不足，请到官网查看$tail',
    403 => '${p.name} 没有权限（或所在地区不支持）$tail',
    429 => '搜索太频繁或本月额度用完了，稍后再试$tail',
    >= 500 => '${p.name} 那边出错了（$status），稍后再试',
    _ => '搜索失败（$status）$tail',
  };
}

Future<List<AiSearchHit>> aiWebSearch(
  AiSearchProvider p,
  String key,
  String query, {
  int count = 5,
  String? customEndpoint,
  HttpClient? client,
}) async {
  if (query.trim().isEmpty) {
    throw AiException('搜索词是空的', linkProblem: false);
  }
  if (key.trim().isEmpty) {
    throw AiException('还没填 ${p.name} 的 Key', linkProblem: false);
  }
  final r = aiSearchRequest(p, key, query,
      count: count, customEndpoint: customEndpoint);
  final http = client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 12));
  try {
    final req = await http.postUrl(r.url);
    r.headers.forEach(req.headers.set);
    req.followRedirects = false;
    req.add(utf8.encode(r.body));
    final resp = await req.close().timeout(const Duration(seconds: 20));
    final text = await resp
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 15), onTimeout: () => '');
    if (resp.statusCode != 200) {
      throw AiException(
          aiSearchErrorText(p, resp.statusCode, redactKey(text, key.trim())),
          linkProblem: false,
          statusCode: resp.statusCode);
    }
    return aiParseSearch(p, text);
  } on AiException {
    rethrow;
  } on SocketException {
    throw AiException('搜索连不上网络，检查一下网络再试', linkProblem: false);
  } on HandshakeException {
    throw AiException('搜索的安全连接建立失败', linkProblem: false);
  } catch (e) {
    throw AiException('搜索失败：${redactKey('$e', key.trim())}', linkProblem: false);
  } finally {
    if (client == null) http.close(force: true);
  }
}

String aiSearchMonthKey([DateTime? now]) {
  final n = now ?? DateTime.now();
  return '${n.year}${n.month.toString().padLeft(2, '0')}';
}
