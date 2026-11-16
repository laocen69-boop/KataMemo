import 'package:flutter/material.dart';

class KColors extends ThemeExtension<KColors> {

  final Color bg;
  final Color surface;
  final Color alt;
  final Color line;
  final Color border;

  final Color text;
  final Color sec;
  final Color t2;
  final Color t3;
  final Color faint;
  final Color pen;

  final Color brand;
  final Color brand2;
  final Color deep;
  final Color hl;
  final Color tint;
  final Color mntint;
  final Color mnDash;
  final Color ring;
  final Color danger;
  final Color onbrand;

  final Color track;
  final Color knob;

  final Color bandGradTop;
  final Color bandGradBottom;
  final Color bandLine;
  final Color bandText;
  final Color bandInk;
  final Color bandFaint;
  final Color bandTrack;
  final Color bandDivider;
  final Color bandChipBg;
  final Color bandChipText;

  final Color cur;
  final Color curTrack;

  final bool shadowOn;

  final Color nBg;
  final Color nT1;
  final Color nT2;
  final Color nT3;
  final Color nFaint;
  final Color nFaint2;
  final Color nFaint3;

  final Color s0, s1, s2, s3, s4;

  final Color q2, q3, q4;

  final Color mWeak;
  final Color mFair;
  final Color mStrong;
  final Color mNone;
  final Color catDeep;
  final Color catMid;
  final Color catTint;
  final Color brown;
  final Color star;
  final Color red;
  final Color redDeep;
  final Color nPale;
  final Color red2;
  final Color yellowTint;

  final Color g800;
  final Color g700;
  final Color g400;
  final Color g300;
  final Color g200;
  final Color g100;
  final Color catTint2;
  final Color catEdge;
  final Color nEdge;
  final Color nInk;
  final Color nInk2;
  final Color nSlate2;
  final Color nPanel9;
  final Color badge;
  final Color orange;
  final Color orange2;
  final Color phon;
  final Color onTeal;
  final Color teal1;
  final Color teal2;
  final Color iconSlate;
  final Color brand2b;
  final Color ringAlt;
  final Color ink2;
  final Color ink3;
  final Color nSlate;
  final Color hl2;
  final Color nPanel1;
  final Color nPanel2;
  final Color nPanel3;
  final Color nPanel4;
  final Color nPanel5;
  final Color nPanel6;
  final Color nPanel7;
  final Color nPanel8;

  final Color gSlot1;
  final Color gSlot2;
  final Color gSlot3;
  final Color gSlot4;
  final Color gSlot1Tint;
  final Color gSlot2Tint;
  final Color gSlot3Tint;
  final Color gSlot4Tint;
  final Color gWarnBg;
  final Color gWarn;
  final Color gWrite;

  const KColors({
    required this.bg,
    required this.surface,
    required this.alt,
    required this.line,
    required this.border,
    required this.text,
    required this.sec,
    required this.t2,
    required this.t3,
    required this.faint,
    required this.pen,
    required this.brand,
    required this.brand2,
    required this.deep,
    required this.hl,
    required this.tint,
    required this.mntint,
    required this.mnDash,
    required this.ring,
    required this.danger,
    required this.onbrand,
    required this.track,
    required this.knob,
    required this.bandGradTop,
    required this.bandGradBottom,
    required this.bandLine,
    required this.bandText,
    required this.bandInk,
    required this.bandFaint,
    required this.bandTrack,
    required this.bandDivider,
    required this.bandChipBg,
    required this.bandChipText,
    required this.cur,
    required this.curTrack,
    required this.shadowOn,
    required this.nBg,
    required this.nT1,
    required this.nT2,
    required this.nT3,
    required this.nFaint,
    required this.nFaint2,
    required this.nFaint3,
    required this.s0,
    required this.s1,
    required this.s2,
    required this.s3,
    required this.s4,
    required this.q2,
    required this.q3,
    required this.q4,
    required this.mWeak,
    required this.mFair,
    required this.mStrong,
    required this.mNone,
    required this.catDeep,
    required this.catMid,
    required this.catTint,
    required this.brown,
    required this.star,
    required this.red,
    required this.redDeep,
    required this.nPale,
    required this.red2,
    required this.yellowTint,
    required this.g800,
    required this.g700,
    required this.g400,
    required this.g300,
    required this.g200,
    required this.g100,
    required this.catTint2,
    required this.catEdge,
    required this.nEdge,
    required this.nInk,
    required this.nInk2,
    required this.nSlate2,
    required this.nPanel9,
    required this.badge,
    required this.orange,
    required this.orange2,
    required this.phon,
    required this.onTeal,
    required this.teal1,
    required this.teal2,
    required this.iconSlate,
    required this.brand2b,
    required this.ringAlt,
    required this.ink2,
    required this.ink3,
    required this.nSlate,
    required this.hl2,
    required this.nPanel1,
    required this.nPanel2,
    required this.nPanel3,
    required this.nPanel4,
    required this.nPanel5,
    required this.nPanel6,
    required this.nPanel7,
    required this.nPanel8,
    required this.gSlot1,
    required this.gSlot2,
    required this.gSlot3,
    required this.gSlot4,
    required this.gSlot1Tint,
    required this.gSlot2Tint,
    required this.gSlot3Tint,
    required this.gSlot4Tint,
    required this.gWarnBg,
    required this.gWarn,
    required this.gWrite,
  });

  static const KColors light = KColors(
    bg: Color(0xFFF1F4F2),
    surface: Color(0xFFFFFFFF),
    alt: Color(0xFFEEF3F0),
    line: Color(0xFFEDF2EF),
    border: Color(0xFFE3EAE6),
    text: Color(0xFF16241F),
    sec: Color(0xFF46564F),
    t2: Color(0xFF62736B),
    t3: Color(0xFF7E8D86),
    faint: Color(0xFFAEB9B3),
    pen: Color(0xFF7E8D86),
    brand: Color(0xFF4CAF8D),
    brand2: Color(0xFF6FC2A3),
    deep: Color(0xFF15704F),
    hl: Color(0xFF2E7D5B),
    tint: Color(0xFFE6F4EE),
    mntint: Color(0xFFF0F9F4),
    mnDash: Color(0xFFA9D8C3),
    ring: Color(0xFFE4EBE7),
    danger: Color(0xFFD8574B),
    onbrand: Color(0xFFFFFFFF),

    track: Color(0xFFD5DBD8),
    knob: Color(0xFFFFFFFF),

    bandGradTop: Color(0xFF9FD0B0),
    bandGradBottom: Color(0xFFD5E6DB),
    bandLine: Color(0xFFB9D8C4),

    bandText: Color(0xFF35584A),
    bandInk: Color(0xFF10201E),
    bandFaint: Color(0xFF3F6355),
    bandTrack: Color(0xBFFFFFFF),
    bandDivider: Color(0x3815503A),
    bandChipBg: Color(0x9EFFFFFF),
    bandChipText: Color(0xFF15704F),

    cur: Color(0xFFEAF5EF),
    curTrack: Color(0xFFCFE3D9),
    shadowOn: true,
    nBg: Color(0xFFF7F8F8),
    nT1: Color(0xFF5F6368),
    nT2: Color(0xFF757575),
    nT3: Color(0xFF8A8F93),
    nFaint: Color(0xFF9AA0A6),
    nFaint2: Color(0xFF9E9E9E),
    nFaint3: Color(0xFFBDBDBD),
    s0: Color(0xFF1B5E20),
    s1: Color(0xFF43A047),
    s2: Color(0xFFF9A825),
    s3: Color(0xFFE53935),
    s4: Color(0xFF757575),
    q2: Color(0xFF7A8B99),
    q3: Color(0xFFE9A94D),
    q4: Color(0xFF8E8EE0),
    mWeak: Color(0xFFF4511E),
    mFair: Color(0xFFFB8C00),
    mStrong: Color(0xFF9CCC65),
    mNone: Color(0xFFBDBDBD),
    catDeep: Color(0xFF27500A),
    catMid: Color(0xFF3B6D11),
    catTint: Color(0xFFEAF3DE),
    brown: Color(0xFF854F0B),
    star: Color(0xFFFFA940),
    red: Color(0xFFE24B4A),
    redDeep: Color(0xFFA32D2D),
    nPale: Color(0xFFF0F1F3),
    red2: Color(0xFFC9604F),
    yellowTint: Color(0xFFFAEEDA),
    nSlate: Color(0xFF6B7A85),
    hl2: Color(0xFF2E7D62),
    nPanel1: Color(0xFFF5F6F5),
    nPanel2: Color(0xFFF1F3F6),
    nPanel3: Color(0xFFF1F3F4),
    nPanel4: Color(0xFFF1F2F4),
    nPanel5: Color(0xFFE7ECEA),
    nPanel6: Color(0xFFE7EAEE),
    nPanel7: Color(0xFFE4E7EB),
    nPanel8: Color(0xFFE3E6EA),
    nSlate2: Color(0xFF42535C),
    nPanel9: Color(0xFFF2F3F5),
    badge: Color(0xFFFF3B30),
    orange: Color(0xFFFF9800),
    orange2: Color(0xFFE8834A),

    nEdge: Color(0xFFB9C4BE),
    catTint2: Color(0xFFF6FBF0),
    catEdge: Color(0xFFA5D6C3),
    nInk: Color(0xFF2B2F33),
    nInk2: Color(0xFF2C2C2C),
    g800: Color(0xFF424242),
    g700: Color(0xFF616161),
    g400: Color(0xFFBDBDBD),
    g300: Color(0xFFE0E0E0),
    g200: Color(0xFFEEEEEE),
    g100: Color(0xFFF5F5F5),
    phon: Color(0xFF668078),
    onTeal: Color(0xFF12312E),
    teal1: Color(0xFF57A8A4),
    teal2: Color(0xFF7CBBB5),
    iconSlate: Color(0xFF44515A),
    brand2b: Color(0xFF8FD4B8),
    ringAlt: Color(0xFFEDEFF1),
    ink2: Color(0xFF3A3F45),
    ink3: Color(0xFF1A1A1A),
    gSlot1: Color(0xFF4C86C8),
    gSlot2: Color(0xFFE9A94D),
    gSlot3: Color(0xFF4CAF8D),
    gSlot4: Color(0xFF8A6BBE),
    gSlot1Tint: Color(0x244C86C8),
    gSlot2Tint: Color(0x24E9A94D),
    gSlot3Tint: Color(0x244CAF8D),
    gSlot4Tint: Color(0x248A6BBE),
    gWarnBg: Color(0xFFFFF6E5),
    gWarn: Color(0xFFB0630F),
    gWrite: Color(0xFF8A6BBE),
  );

  static const KColors dark = KColors(
    bg: Color(0xFF14161A),
    surface: Color(0xFF1C1F24),
    alt: Color(0xFF24282D),
    line: Color(0xFF2F343A),
    border: Color(0xFF2F343A),
    text: Color(0xFFE8EBEE),
    sec: Color(0xFFA6ADB4),
    t2: Color(0xFFA6ADB4),
    t3: Color(0xFF8A9096),
    faint: Color(0xFF6F757C),
    pen: Color(0xFF8A9096),
    brand: Color(0xFF5CC4A0),
    brand2: Color(0xFF2F7F66),
    deep: Color(0xFF7FD6B8),
    hl: Color(0xFF7FD6B8),
    tint: Color(0xFF1E2B27),
    mntint: Color(0xFF1E2B27),
    mnDash: Color(0xFF2F7F66),
    ring: Color(0xFF2F343A),
    danger: Color(0xFFE57368),
    onbrand: Color(0xFF0B1F18),
    track: Color(0xFF3A4148),
    knob: Color(0xFF8A9096),
    bandGradTop: Color(0xFF242E2B),
    bandGradBottom: Color(0xFF1B2422),
    bandLine: Color(0xFF2F343A),
    bandText: Color(0xFFA9B2AF),
    bandInk: Color(0xFFE8EBEE),
    bandFaint: Color(0xFF8A9490),
    bandTrack: Color(0x1FFFFFFF),
    bandDivider: Color(0x24E8EBEE),
    bandChipBg: Color(0x385CC4A0),

    bandChipText: Color(0xFF9FE3CA),
    cur: Color(0xFF1E2B27),
    curTrack: Color(0xFF2C3A36),
    shadowOn: false,
    nBg: Color(0xFF14161A),
    nT1: Color(0xFFA6ADB4),
    nT2: Color(0xFFA6ADB4),
    nT3: Color(0xFF8A9096),
    nFaint: Color(0xFF6F757C),
    nFaint2: Color(0xFF6F757C),
    nFaint3: Color(0xFF6F757C),
    s0: Color(0xFF3FA56F),
    s1: Color(0xFF5FBF8F),
    s2: Color(0xFFF2B25C),
    s3: Color(0xFFE57368),
    s4: Color(0xFF7C858C),
    q2: Color(0xFF9AAAB6),
    q3: Color(0xFFF2B25C),
    q4: Color(0xFFA5A5F0),
    mWeak: Color(0xFFE9805F),
    mFair: Color(0xFFEE9A4E),
    mStrong: Color(0xFFA9D67A),
    mNone: Color(0xFF3A4148),
    catDeep: Color(0xFFABE085),
    catMid: Color(0xFF86C25A),
    catTint: Color(0xFF2D371F),
    brown: Color(0xFFD2A878),
    star: Color(0xFFF2B25C),
    red: Color(0xFFE57368),
    redDeep: Color(0xFFF0A09A),
    nPale: Color(0xFF24282D),
    red2: Color(0xFFD98E82),

    g800: Color(0xFFD8DDE2),
    g700: Color(0xFFA6ADB4),
    g400: Color(0xFF8A9096),
    g300: Color(0xFF2F343A),
    g200: Color(0xFF2F343A),
    g100: Color(0xFF24282D),
    catTint2: Color(0xFF1E2B27),
    catEdge: Color(0xFF2F7F66),
    nEdge: Color(0xFF3A4148),
    nInk: Color(0xFFE8EBEE),
    nInk2: Color(0xFFE8EBEE),
    nSlate2: Color(0xFFA0B2BB),
    nPanel9: Color(0xFF24282D),
    badge: Color(0xFFE57368),
    orange: Color(0xFFCB984D),
    orange2: Color(0xFFDEA07C),
    nSlate: Color(0xFF8A9096),
    hl2: Color(0xFF7FD6B8),
    nPanel1: Color(0xFF24282D),
    nPanel2: Color(0xFF24282D),
    nPanel3: Color(0xFF24282D),
    nPanel4: Color(0xFF24282D),
    nPanel5: Color(0xFF2A2E34),
    nPanel6: Color(0xFF2A2E34),
    nPanel7: Color(0xFF2A2E34),
    nPanel8: Color(0xFF2A2E34),

    phon: Color(0xFFA4AEB4),
    onTeal: Color(0xFF57C1B7),
    teal1: Color(0xFF68B1AD),
    teal2: Color(0xFF68B1AA),
    iconSlate: Color(0xFFA2AFB9),
    brand2b: Color(0xFF59BF96),
    ringAlt: Color(0xFF2F343A),
    ink2: Color(0xFFA6ADB4),
    ink3: Color(0xFFADADAD),
    yellowTint: Color(0xFF332C18),
    gSlot1: Color(0xFF6EA0DC),
    gSlot2: Color(0xFFE9B466),
    gSlot3: Color(0xFF5CC4A1),
    gSlot4: Color(0xFFAA8CDC),
    gSlot1Tint: Color(0x296EA0DC),
    gSlot2Tint: Color(0x29E9B466),
    gSlot3Tint: Color(0x295CC4A1),
    gSlot4Tint: Color(0x29AA8CDC),
    gWarnBg: Color(0xFF2A2417),
    gWarn: Color(0xFFE9B466),
    gWrite: Color(0xFFAA8CDC),
  );

  @override
  KColors copyWith({
    Color? bg,
    Color? surface,
    Color? alt,
    Color? line,
    Color? border,
    Color? text,
    Color? sec,
    Color? t2,
    Color? t3,
    Color? faint,
    Color? pen,
    Color? brand,
    Color? brand2,
    Color? deep,
    Color? hl,
    Color? tint,
    Color? mntint,
    Color? mnDash,
    Color? ring,
    Color? danger,
    Color? onbrand,
    Color? track,
    Color? knob,
    Color? bandGradTop,
    Color? bandGradBottom,
    Color? bandLine,
    Color? bandText,
    Color? bandInk,
    Color? bandFaint,
    Color? bandTrack,
    Color? bandDivider,
    Color? bandChipBg,
    Color? bandChipText,
    Color? cur,
    Color? curTrack,
    bool? shadowOn,
    Color? nBg,
    Color? nT1,
    Color? nT2,
    Color? nT3,
    Color? nFaint,
    Color? nFaint2,
    Color? nFaint3,
    Color? s0,
    Color? s1,
    Color? s2,
    Color? s3,
    Color? s4,
    Color? q2,
    Color? q3,
    Color? q4,
    Color? mWeak,
    Color? mFair,
    Color? mStrong,
    Color? mNone,
    Color? catDeep,
    Color? catMid,
    Color? catTint,
    Color? brown,
    Color? star,
    Color? red,
    Color? redDeep,
    Color? nPale,
    Color? red2,
    Color? yellowTint,
    Color? g800,
    Color? g700,
    Color? g400,
    Color? g300,
    Color? g200,
    Color? g100,
    Color? catTint2,
    Color? catEdge,
    Color? nEdge,
    Color? nInk,
    Color? nInk2,
    Color? nSlate2,
    Color? nPanel9,
    Color? badge,
    Color? orange,
    Color? orange2,
    Color? phon,
    Color? onTeal,
    Color? teal1,
    Color? teal2,
    Color? iconSlate,
    Color? brand2b,
    Color? ringAlt,
    Color? ink2,
    Color? ink3,
    Color? nSlate,
    Color? hl2,
    Color? nPanel1,
    Color? nPanel2,
    Color? nPanel3,
    Color? nPanel4,
    Color? nPanel5,
    Color? nPanel6,
    Color? nPanel7,
    Color? nPanel8,
    Color? gSlot1,
    Color? gSlot2,
    Color? gSlot3,
    Color? gSlot4,
    Color? gSlot1Tint,
    Color? gSlot2Tint,
    Color? gSlot3Tint,
    Color? gSlot4Tint,
    Color? gWarnBg,
    Color? gWarn,
    Color? gWrite,
  }) =>
      KColors(
        gSlot1: gSlot1 ?? this.gSlot1,
        gSlot2: gSlot2 ?? this.gSlot2,
        gSlot3: gSlot3 ?? this.gSlot3,
        gSlot4: gSlot4 ?? this.gSlot4,
        gSlot1Tint: gSlot1Tint ?? this.gSlot1Tint,
        gSlot2Tint: gSlot2Tint ?? this.gSlot2Tint,
        gSlot3Tint: gSlot3Tint ?? this.gSlot3Tint,
        gSlot4Tint: gSlot4Tint ?? this.gSlot4Tint,
        gWarnBg: gWarnBg ?? this.gWarnBg,
        gWarn: gWarn ?? this.gWarn,
        gWrite: gWrite ?? this.gWrite,
        bg: bg ?? this.bg,
        surface: surface ?? this.surface,
        alt: alt ?? this.alt,
        line: line ?? this.line,
        border: border ?? this.border,
        text: text ?? this.text,
        sec: sec ?? this.sec,
        t2: t2 ?? this.t2,
        t3: t3 ?? this.t3,
        faint: faint ?? this.faint,
        pen: pen ?? this.pen,
        brand: brand ?? this.brand,
        brand2: brand2 ?? this.brand2,
        deep: deep ?? this.deep,
        hl: hl ?? this.hl,
        tint: tint ?? this.tint,
        mntint: mntint ?? this.mntint,
        mnDash: mnDash ?? this.mnDash,
        ring: ring ?? this.ring,
        danger: danger ?? this.danger,
        onbrand: onbrand ?? this.onbrand,
        track: track ?? this.track,
        knob: knob ?? this.knob,
        bandGradTop: bandGradTop ?? this.bandGradTop,
        bandGradBottom: bandGradBottom ?? this.bandGradBottom,
        bandLine: bandLine ?? this.bandLine,
        bandText: bandText ?? this.bandText,
        bandInk: bandInk ?? this.bandInk,
        bandFaint: bandFaint ?? this.bandFaint,
        bandTrack: bandTrack ?? this.bandTrack,
        bandDivider: bandDivider ?? this.bandDivider,
        bandChipBg: bandChipBg ?? this.bandChipBg,
        bandChipText: bandChipText ?? this.bandChipText,
        cur: cur ?? this.cur,
        curTrack: curTrack ?? this.curTrack,
        shadowOn: shadowOn ?? this.shadowOn,
        nBg: nBg ?? this.nBg,
        nT1: nT1 ?? this.nT1,
        nT2: nT2 ?? this.nT2,
        nT3: nT3 ?? this.nT3,
        nFaint: nFaint ?? this.nFaint,
        nFaint2: nFaint2 ?? this.nFaint2,
        nFaint3: nFaint3 ?? this.nFaint3,
        s0: s0 ?? this.s0,
        s1: s1 ?? this.s1,
        s2: s2 ?? this.s2,
        s3: s3 ?? this.s3,
        s4: s4 ?? this.s4,
        q2: q2 ?? this.q2,
        q3: q3 ?? this.q3,
        q4: q4 ?? this.q4,
        mWeak: mWeak ?? this.mWeak,
        mFair: mFair ?? this.mFair,
        mStrong: mStrong ?? this.mStrong,
        mNone: mNone ?? this.mNone,
        catDeep: catDeep ?? this.catDeep,
        catMid: catMid ?? this.catMid,
        catTint: catTint ?? this.catTint,
        brown: brown ?? this.brown,
        star: star ?? this.star,
        red: red ?? this.red,
        redDeep: redDeep ?? this.redDeep,
        nPale: nPale ?? this.nPale,
        red2: red2 ?? this.red2,
        yellowTint: yellowTint ?? this.yellowTint,
        g800: g800 ?? this.g800,
        g700: g700 ?? this.g700,
        g400: g400 ?? this.g400,
        g300: g300 ?? this.g300,
        g200: g200 ?? this.g200,
        g100: g100 ?? this.g100,
        catTint2: catTint2 ?? this.catTint2,
        catEdge: catEdge ?? this.catEdge,
        nEdge: nEdge ?? this.nEdge,
        nInk: nInk ?? this.nInk,
        nInk2: nInk2 ?? this.nInk2,
        nSlate2: nSlate2 ?? this.nSlate2,
        nPanel9: nPanel9 ?? this.nPanel9,
        badge: badge ?? this.badge,
        orange: orange ?? this.orange,
        orange2: orange2 ?? this.orange2,
        phon: phon ?? this.phon,
        onTeal: onTeal ?? this.onTeal,
        teal1: teal1 ?? this.teal1,
        teal2: teal2 ?? this.teal2,
        iconSlate: iconSlate ?? this.iconSlate,
        brand2b: brand2b ?? this.brand2b,
        ringAlt: ringAlt ?? this.ringAlt,
        ink2: ink2 ?? this.ink2,
        ink3: ink3 ?? this.ink3,
        nSlate: nSlate ?? this.nSlate,
        hl2: hl2 ?? this.hl2,
        nPanel1: nPanel1 ?? this.nPanel1,
        nPanel2: nPanel2 ?? this.nPanel2,
        nPanel3: nPanel3 ?? this.nPanel3,
        nPanel4: nPanel4 ?? this.nPanel4,
        nPanel5: nPanel5 ?? this.nPanel5,
        nPanel6: nPanel6 ?? this.nPanel6,
        nPanel7: nPanel7 ?? this.nPanel7,
        nPanel8: nPanel8 ?? this.nPanel8,
      );

  KColors withBrandHue(double hue,
      {double satMul = 1.0, double lightShift = 0.0}) {
    Color cHue(Color c) => HSLColor.fromColor(c).withHue(hue).toColor();
    Color cSat(Color c) {
      final x = HSLColor.fromColor(c).withHue(hue);
      return x
          .withSaturation((x.saturation * satMul).clamp(0.0, 1.0))
          .toColor();
    }

    Color cLift(Color c) {
      final x = HSLColor.fromColor(c).withHue(hue);
      final y = x.withSaturation((x.saturation * satMul).clamp(0.0, 1.0));
      return y
          .withLightness((y.lightness + lightShift).clamp(0.0, 1.0))
          .toColor();
    }

    return copyWith(

      bg: cLift(bg),
      alt: cLift(alt),
      tint: cLift(tint),
      mntint: cLift(mntint),
      hl: cLift(hl),
      hl2: cLift(hl2),
      cur: cLift(cur),
      curTrack: cLift(curTrack),
      catTint: cLift(catTint),
      catTint2: cLift(catTint2),
      bandGradTop: cLift(bandGradTop),
      bandGradBottom: cLift(bandGradBottom),

      line: cSat(line),
      border: cSat(border),
      ring: cSat(ring),
      ringAlt: cSat(ringAlt),
      track: cSat(track),
      brand: cSat(brand),
      brand2: cSat(brand2),
      brand2b: cSat(brand2b),
      catEdge: cSat(catEdge),
      catDeep: cSat(catDeep),
      catMid: cSat(catMid),

      s0: cSat(brand),
      bandLine: cSat(bandLine),

      text: cHue(text),
      deep: cHue(deep),
      mnDash: cHue(mnDash),
      bandText: cHue(bandText),
      bandInk: cHue(bandInk),
      bandFaint: cHue(bandFaint),
      bandChipText: cHue(bandChipText),

      sec: cHue(sec),
      t2: cHue(t2),
      t3: cHue(t3),
      pen: cHue(pen),
      faint: cHue(faint),
      nEdge: cHue(nEdge),
      phon: cHue(phon),
      onbrand: cHue(onbrand),
      bandDivider: cHue(bandDivider),
      bandChipBg: cHue(bandChipBg),
    );
  }

  static KColors current = KColors.light;

  @override
  KColors lerp(ThemeExtension<KColors>? other, double t) {
    if (other is! KColors) return this;
    return KColors(
      bg: Color.lerp(bg, other.bg, t)!,
      gSlot1: Color.lerp(gSlot1, other.gSlot1, t)!,
      gSlot2: Color.lerp(gSlot2, other.gSlot2, t)!,
      gSlot3: Color.lerp(gSlot3, other.gSlot3, t)!,
      gSlot4: Color.lerp(gSlot4, other.gSlot4, t)!,
      gSlot1Tint: Color.lerp(gSlot1Tint, other.gSlot1Tint, t)!,
      gSlot2Tint: Color.lerp(gSlot2Tint, other.gSlot2Tint, t)!,
      gSlot3Tint: Color.lerp(gSlot3Tint, other.gSlot3Tint, t)!,
      gSlot4Tint: Color.lerp(gSlot4Tint, other.gSlot4Tint, t)!,
      gWarnBg: Color.lerp(gWarnBg, other.gWarnBg, t)!,
      gWarn: Color.lerp(gWarn, other.gWarn, t)!,
      gWrite: Color.lerp(gWrite, other.gWrite, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      alt: Color.lerp(alt, other.alt, t)!,
      line: Color.lerp(line, other.line, t)!,
      border: Color.lerp(border, other.border, t)!,
      text: Color.lerp(text, other.text, t)!,
      sec: Color.lerp(sec, other.sec, t)!,
      t2: Color.lerp(t2, other.t2, t)!,
      t3: Color.lerp(t3, other.t3, t)!,
      faint: Color.lerp(faint, other.faint, t)!,
      pen: Color.lerp(pen, other.pen, t)!,
      brand: Color.lerp(brand, other.brand, t)!,
      brand2: Color.lerp(brand2, other.brand2, t)!,
      deep: Color.lerp(deep, other.deep, t)!,
      hl: Color.lerp(hl, other.hl, t)!,
      tint: Color.lerp(tint, other.tint, t)!,
      mntint: Color.lerp(mntint, other.mntint, t)!,
      mnDash: Color.lerp(mnDash, other.mnDash, t)!,
      ring: Color.lerp(ring, other.ring, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      onbrand: Color.lerp(onbrand, other.onbrand, t)!,
      track: Color.lerp(track, other.track, t)!,
      knob: Color.lerp(knob, other.knob, t)!,
      bandGradTop: Color.lerp(bandGradTop, other.bandGradTop, t)!,
      bandGradBottom: Color.lerp(bandGradBottom, other.bandGradBottom, t)!,
      bandLine: Color.lerp(bandLine, other.bandLine, t)!,
      bandText: Color.lerp(bandText, other.bandText, t)!,
      bandInk: Color.lerp(bandInk, other.bandInk, t)!,
      bandFaint: Color.lerp(bandFaint, other.bandFaint, t)!,
      bandTrack: Color.lerp(bandTrack, other.bandTrack, t)!,
      bandDivider: Color.lerp(bandDivider, other.bandDivider, t)!,
      bandChipBg: Color.lerp(bandChipBg, other.bandChipBg, t)!,
      bandChipText: Color.lerp(bandChipText, other.bandChipText, t)!,
      cur: Color.lerp(cur, other.cur, t)!,
      curTrack: Color.lerp(curTrack, other.curTrack, t)!,

      shadowOn: t < 0.5 ? shadowOn : other.shadowOn,
      nBg: Color.lerp(nBg, other.nBg, t)!,
      nT1: Color.lerp(nT1, other.nT1, t)!,
      nT2: Color.lerp(nT2, other.nT2, t)!,
      nT3: Color.lerp(nT3, other.nT3, t)!,
      nFaint: Color.lerp(nFaint, other.nFaint, t)!,
      nFaint2: Color.lerp(nFaint2, other.nFaint2, t)!,
      nFaint3: Color.lerp(nFaint3, other.nFaint3, t)!,
      s0: Color.lerp(s0, other.s0, t)!,
      s1: Color.lerp(s1, other.s1, t)!,
      s2: Color.lerp(s2, other.s2, t)!,
      s3: Color.lerp(s3, other.s3, t)!,
      s4: Color.lerp(s4, other.s4, t)!,
      q2: Color.lerp(q2, other.q2, t)!,
      q3: Color.lerp(q3, other.q3, t)!,
      q4: Color.lerp(q4, other.q4, t)!,
      mWeak: Color.lerp(mWeak, other.mWeak, t)!,
      mFair: Color.lerp(mFair, other.mFair, t)!,
      mStrong: Color.lerp(mStrong, other.mStrong, t)!,
      mNone: Color.lerp(mNone, other.mNone, t)!,
      catDeep: Color.lerp(catDeep, other.catDeep, t)!,
      catMid: Color.lerp(catMid, other.catMid, t)!,
      catTint: Color.lerp(catTint, other.catTint, t)!,
      brown: Color.lerp(brown, other.brown, t)!,
      star: Color.lerp(star, other.star, t)!,
      red: Color.lerp(red, other.red, t)!,
      redDeep: Color.lerp(redDeep, other.redDeep, t)!,
      nPale: Color.lerp(nPale, other.nPale, t)!,
      red2: Color.lerp(red2, other.red2, t)!,
      yellowTint: Color.lerp(yellowTint, other.yellowTint, t)!,
      g800: Color.lerp(g800, other.g800, t)!,
      g700: Color.lerp(g700, other.g700, t)!,
      g400: Color.lerp(g400, other.g400, t)!,
      g300: Color.lerp(g300, other.g300, t)!,
      g200: Color.lerp(g200, other.g200, t)!,
      g100: Color.lerp(g100, other.g100, t)!,
      catTint2: Color.lerp(catTint2, other.catTint2, t)!,
      catEdge: Color.lerp(catEdge, other.catEdge, t)!,
      nEdge: Color.lerp(nEdge, other.nEdge, t)!,
      nInk: Color.lerp(nInk, other.nInk, t)!,
      nInk2: Color.lerp(nInk2, other.nInk2, t)!,
      nSlate2: Color.lerp(nSlate2, other.nSlate2, t)!,
      nPanel9: Color.lerp(nPanel9, other.nPanel9, t)!,
      badge: Color.lerp(badge, other.badge, t)!,
      orange: Color.lerp(orange, other.orange, t)!,
      orange2: Color.lerp(orange2, other.orange2, t)!,
      phon: Color.lerp(phon, other.phon, t)!,
      onTeal: Color.lerp(onTeal, other.onTeal, t)!,
      teal1: Color.lerp(teal1, other.teal1, t)!,
      teal2: Color.lerp(teal2, other.teal2, t)!,
      iconSlate: Color.lerp(iconSlate, other.iconSlate, t)!,
      brand2b: Color.lerp(brand2b, other.brand2b, t)!,
      ringAlt: Color.lerp(ringAlt, other.ringAlt, t)!,
      ink2: Color.lerp(ink2, other.ink2, t)!,
      ink3: Color.lerp(ink3, other.ink3, t)!,

      nSlate: Color.lerp(nSlate, other.nSlate, t)!,
      hl2: Color.lerp(hl2, other.hl2, t)!,
      nPanel1: Color.lerp(nPanel1, other.nPanel1, t)!,
      nPanel2: Color.lerp(nPanel2, other.nPanel2, t)!,
      nPanel3: Color.lerp(nPanel3, other.nPanel3, t)!,
      nPanel4: Color.lerp(nPanel4, other.nPanel4, t)!,
      nPanel5: Color.lerp(nPanel5, other.nPanel5, t)!,
      nPanel6: Color.lerp(nPanel6, other.nPanel6, t)!,
      nPanel7: Color.lerp(nPanel7, other.nPanel7, t)!,
      nPanel8: Color.lerp(nPanel8, other.nPanel8, t)!,
    );
  }
}

extension KColorsX on BuildContext {
  KColors get k => Theme.of(this).extension<KColors>() ?? KColors.light;
}

TextStyle mainAppBarTitleStyle(BuildContext context) {
  final base = Theme.of(context).appBarTheme.titleTextStyle ??
      Theme.of(context).textTheme.titleLarge ??
      const TextStyle();
  return base.copyWith(
      fontSize: 18, fontWeight: FontWeight.w600, color: context.k.text);
}

extension KColorsBlue on KColors {
  static final KColors light =
      KColors.light.withBrandHue(205, satMul: 1.45, lightShift: 0.02);
  static final KColors dark =
      KColors.dark.withBrandHue(205, satMul: 1.80, lightShift: 0.0);
}
