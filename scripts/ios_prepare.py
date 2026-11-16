# -*- coding: utf-8 -*-
"""打 iOS 包前后切换 pubspec.yaml 里的音频目录。

Flutter 不能按平台分别打包资源目录，而安卓要 Ogg、iOS 要 AAC（见 `scripts/ios_audio.py`）。
两套都列进 pubspec 会让两个平台的包都翻倍，所以打 iOS 包前临时换成 m4a 目录，打完换回来：

  python3 scripts/ios_prepare.py --ios        # 换成 assets/audio/edge/ardi_m4a/（打 iOS 包前）
  flutter build ipa
  python3 scripts/ios_prepare.py --android    # 换回 assets/audio/edge/ardi/（打完立刻换回）

⚠️ 换成 --ios 状态下不要打安卓包（安卓包会没有声音）。
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "rebuild"))
try:
    from common import BASE, safe_join  # noqa: E402
except ImportError:  # 开源仓库里没有 scripts/rebuild：退回同口径的简化版
    BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    def safe_join(base, *parts):
        p = os.path.realpath(os.path.join(base, *parts))
        if not p.startswith(os.path.realpath(base) + os.sep):
            raise ValueError("路径越界：" + p)
        return p

OGG = "    - assets/audio/edge/ardi/\n"
M4A = "    - assets/audio/edge/ardi_m4a/\n"


def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--ios", action="store_true")
    g.add_argument("--android", action="store_true")
    a = ap.parse_args()
    p = safe_join(BASE, "app", "pubspec.yaml")
    t = open(p, encoding="utf-8", newline="").read()
    nl = "\r\n" if "\r\n" in t else "\n"
    ogg, m4a = OGG.replace("\n", nl), M4A.replace("\n", nl)
    if a.ios:
        m4a_dir = safe_join(BASE, "app", "assets", "audio", "edge", "ardi_m4a")
        if not os.path.isdir(m4a_dir) or not os.listdir(m4a_dir):
            sys.exit("还没有 m4a 音频：先跑 python3 scripts/ios_audio.py")
        if m4a in t:
            print("已经是 iOS 状态")
            return
        if ogg not in t:
            sys.exit("pubspec.yaml 里找不到安卓音频目录那一行，手动检查")
        t = t.replace(ogg, m4a)
    else:
        if ogg in t:
            print("已经是安卓状态")
            return
        if m4a not in t:
            sys.exit("pubspec.yaml 里找不到 iOS 音频目录那一行，手动检查")
        t = t.replace(m4a, ogg)
    open(p, "w", encoding="utf-8", newline="").write(t)
    print("pubspec.yaml 音频目录 →", "iOS（m4a）" if a.ios else "安卓（ogg）")


if __name__ == "__main__":
    main()
