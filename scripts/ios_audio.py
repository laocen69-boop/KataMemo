# -*- coding: utf-8 -*-
"""把内置男声音频从 Ogg-Opus 转成 iOS 能播的 AAC（.m4a），供 iOS 包使用。

为什么：iOS 的系统播放器（audioplayers 在 iOS 上走 AVPlayer）不认 Ogg 容器，
安卓包里的 36,796 个 `.ogg` 在 iPhone 上一个都放不出声。iOS 包改放同名 `.m4a`，
App 在 iOS 上先找 `edge/ardi_m4a/<名>.m4a`（见 `app/lib/audio.dart` 的 `iosAudioPath`）。

产出：app/assets/audio/edge/ardi_m4a/*.m4a（AAC-LC 单声道 22.05 kHz / 24 kbps，全库约 260 MB）
      ⚠️ 只是**新增**文件，原 Ogg 一个不动（AGENTS §0-1「不要删音频」）。
断点续跑：已存在且非空的 .m4a 跳过；`--limit N` 只转前 N 个（试跑用）。

用法：
  python scripts/ios_audio.py --ffmpeg "C:\\path\\to\\ffmpeg.exe"    # Windows 指定 ffmpeg
  python3 scripts/ios_audio.py                                      # Mac 上 brew install ffmpeg 后直接跑
"""
import argparse
import os
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

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

SRC = ("app", "assets", "audio", "edge", "ardi")
DST = ("app", "assets", "audio", "edge", "ardi_m4a")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ffmpeg", default=shutil.which("ffmpeg") or "ffmpeg")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--jobs", type=int, default=max(2, (os.cpu_count() or 4) - 1))
    a = ap.parse_args()

    src_dir = safe_join(BASE, *SRC)
    dst_dir = safe_join(BASE, *DST)
    os.makedirs(dst_dir, exist_ok=True)
    names = sorted(f for f in os.listdir(src_dir) if f.lower().endswith(".ogg"))
    if a.limit:
        names = names[:a.limit]

    def one(fn):
        out = safe_join(BASE, *DST, fn[:-4] + ".m4a")
        if os.path.exists(out) and os.path.getsize(out) > 0:
            return "skip"
        cmd = [a.ffmpeg, "-v", "error", "-y", "-i", safe_join(BASE, *SRC, fn),
               # 单声道 22.05 kHz、24 kbps：语音够用；实测单个 ≈ Ogg 的 1.3 倍（48k 会到 2.5 倍、全库 400+ MB）
               "-vn", "-ac", "1", "-ar", "22050", "-c:a", "aac", "-b:a", "24k",
               "-movflags", "+faststart", out]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0 or not os.path.exists(out):
            return "fail:" + fn + " " + (r.stderr or "").strip()[:120]
        return "ok"

    ok = skip = 0
    fails = []
    with ThreadPoolExecutor(a.jobs) as ex:
        for i, res in enumerate(ex.map(one, names), 1):
            if res == "ok":
                ok += 1
            elif res == "skip":
                skip += 1
            else:
                fails.append(res)
            if i % 2000 == 0:
                print(f"  {i}/{len(names)}  新转 {ok} · 跳过 {skip} · 失败 {len(fails)}", flush=True)
    print(f"完成：共 {len(names)} 个 · 新转 {ok} · 已有跳过 {skip} · 失败 {len(fails)}")
    for f in fails[:20]:
        print("  ", f)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
