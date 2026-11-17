#!/usr/bin/env python3
"""Synthesize a single Indonesian word/phrase to 24kHz 16kbps Opus .ogg via edge-tts."""

from __future__ import annotations

import argparse
import asyncio
import os
import subprocess
import tempfile

import edge_tts
import imageio_ffmpeg


async def synth(text: str, out_ogg: str, voice: str, rate: str) -> None:
    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    with tempfile.NamedTemporaryFile(suffix=".mp3", delete=False) as tmp:
        mp3_path = tmp.name
    try:
        comm = edge_tts.Communicate(text, voice, rate=rate)
        await comm.save(mp3_path)
        os.makedirs(os.path.dirname(os.path.abspath(out_ogg)), exist_ok=True)
        subprocess.run(
            [
                ffmpeg,
                "-y",
                "-i",
                mp3_path,
                "-c:a",
                "libopus",
                "-b:a",
                "16k",
                "-ar",
                "24000",
                "-ac",
                "1",
                out_ogg,
            ],
            check=True,
            capture_output=True,
        )
    finally:
        if os.path.exists(mp3_path):
            os.remove(mp3_path)


def main() -> None:
    parser = argparse.ArgumentParser(description="Synthesize Indonesian audio to Opus .ogg")
    parser.add_argument("text", help="Indonesian text to speak (e.g. 'rumah' or '\"ke\"')")
    parser.add_argument("out", help="Output .ogg path (e.g. id-rumah.ogg)")
    parser.add_argument("--voice", default="id-ID-ArdiNeural", help="Edge-TTS voice name")
    parser.add_argument("--rate", default="-10%", help="Speech rate (e.g. +0%, -15%, -25%)")
    args = parser.parse_args()

    asyncio.run(synth(args.text, args.out, args.voice, args.rate))
    print(f"Generated {args.out} ({os.path.getsize(args.out)} B)")


if __name__ == "__main__":
    main()
