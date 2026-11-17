import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'data_repo.dart';
import 'db.dart';
import 'notifications.dart';
import 'perf_log.dart' show kFrameLog;
import 'screens/home_shell.dart';
import 'theme/k_colors.dart';
import 'version.dart' show kAppName, kOpenTheme;
import 'widgets/ai_widgets.dart' show AiFloatingBall, kRootNavKey;
import 'widgets/speak_button.dart' show kSpeakGreen;

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);

  if (kFrameLog) _installFrameLog();
  runApp(const KataMemoApp());
}

void _installFrameLog() {
  SchedulerBinding.instance.addTimingsCallback((timings) {
    for (final t in timings) {
      debugPrint(
          'KMF b=${(t.buildDuration.inMicroseconds / 1000).toStringAsFixed(1)} '
          'r=${(t.rasterDuration.inMicroseconds / 1000).toStringAsFixed(1)}');
    }
  });
}

class KataMemoApp extends StatelessWidget {
  const KataMemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(AppDb()),
      child: const _AppBody(),
    );
  }
}

class _AppBody extends StatelessWidget {
  const _AppBody();

  @override
  Widget build(BuildContext context) {

    final themeMode = context.select<AppState, ThemeMode>((a) => a.themeMode);
    final ready = context.select<AppState, bool>((a) => a.ready);
    final app = context.read<AppState>();
    return MaterialApp(

      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        final mq = MediaQuery.of(context);
        final bool wideWeb = kIsWeb && mq.size.width > 500;
        final double targetW = wideWeb ? 420.0 : mq.size.width;
        const designW = 390.0;
        final scale = targetW / designW;
        final canvasH = mq.size.height / scale;
        Widget scaled = MediaQuery(
          data: mq.copyWith(
            size: Size(designW, canvasH),
            padding: mq.padding / scale,
            viewInsets: mq.viewInsets / scale,
            viewPadding: mq.viewPadding / scale,
          ),
          child: FittedBox(
            fit: BoxFit.fill,
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: designW,
              height: canvasH,

              child: Stack(
                children: [
                  Positioned.fill(child: child),
                  const Positioned.fill(child: AiFloatingBall()),
                ],
              ),
            ),
          ),
        );
        if (wideWeb) {
          scaled = ColoredBox(
            color: const Color(0xFFEAF0ED),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints.tightFor(
                  width: targetW,
                  height: mq.size.height,
                ),
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 24,
                      ),
                    ],
                  ),
                  child: ClipRect(child: scaled),
                ),
              ),
            ),
          );
        }

        final dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            statusBarBrightness: dark ? Brightness.dark : Brightness.light,
          ),
          child: scaled,
        );
      },
      title: kAppName,

      navigatorKey: kRootNavKey,
      debugShowCheckedModeBanner: false,
      theme: _theme(false),
      darkTheme: _theme(true),

      themeMode: themeMode,
      home: FutureBuilder(
        future: app.init(),
        builder: (context, snap) {
          if (!ready) return _ImportSplash(repo: app.repo);

          NotificationService.init(enabled: app.reminderOn);
          return const HomeShell();
        },
      ),
    );
  }

  ThemeData _theme(bool dark) {

    final k = kOpenTheme
        ? (dark ? KColorsBlue.dark : KColorsBlue.light)
        : (dark ? KColors.dark : KColors.light);

    KColors.current = k;

    final base = dark ? const ColorScheme.dark() : const ColorScheme.light();
    final scheme = base.copyWith(
      primary: kSpeakGreen,
      onPrimary: k.onbrand,
      secondary: k.deep,
      onSecondary: k.onbrand,
      primaryContainer: k.tint,
      onPrimaryContainer: k.deep,
      secondaryContainer: k.tint,
      onSecondaryContainer: k.deep,

      inversePrimary: kSpeakGreen,

      surfaceTint: Colors.transparent,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      extensions: <ThemeExtension<dynamic>>[k],
      scaffoldBackgroundColor: k.bg,
      appBarTheme: AppBarTheme(
        backgroundColor: k.surface,

        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        toolbarHeight: 56,
        shape: Border(bottom: BorderSide(color: k.line, width: 0.5)),
      ),
      cardTheme: CardThemeData(
        elevation: k.shadowOn ? 2 : 0,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: k.surface,
      ),
      fontFamilyFallback: const [
        'Noto Sans SC',
        'PingFang SC',
        'Microsoft YaHei'
      ],
    );
  }
}

class _ImportSplash extends StatelessWidget {
  const _ImportSplash({required this.repo});

  final DataRepo repo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: ValueListenableBuilder<double?>(
            valueListenable: repo.importProgress,
            builder: (context, p, _) {
              final pct = p == null ? null : (p * 100).clamp(0, 100).round();
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(repo.importIsUpdate ? '词库已更新，正在重新导入' : '正在准备词库',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),

                    child: LinearProgressIndicator(
                        value: p,
                        minHeight: 6,
                        color: context.k.brand,
                        backgroundColor: context.k.tint),
                  ),
                  const SizedBox(height: 10),
                  Text(pct == null ? '读取中…' : '$pct%',
                      style: const TextStyle(
                          fontSize: 13,
                          fontFeatures: [FontFeature.tabularFigures()])),
                  const SizedBox(height: 18),
                  Text(
                      repo.importIsUpdate
                          ? '只在词库更新后需要一次，约数秒。\n学习记录、加入的词和自建词都不受影响。'
                          : (kIsWeb
                              ? '首次打开需载入本地词库，请稍候（约数秒）。'
                              : '只有第一次打开需要，约十秒。'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12.5,
                          height: 1.5,
                          color: Theme.of(context).hintColor)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
