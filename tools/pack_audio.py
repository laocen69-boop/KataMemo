#!/usr/bin/env python3
"""Inspect, unpack, replace/add, and verify entries in app/assets/audio_pack."""

from __future__ import annotations

import argparse
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACK_DIR = os.path.join(ROOT, "app", "assets", "audio_pack")
IDX_PATH = os.path.join(PACK_DIR, "ardi_idx.tsv")
SHARD_COUNT = 16


def load_index() -> list[list]:
    entries = []
    with open(IDX_PATH, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.rstrip("\r\n")
            if not line:
                continue
            name, shard_s, off_s, size_s = line.split("\t")
            entries.append([name, int(shard_s), int(off_s), int(size_s)])
    return entries


def save_index(entries: list[list]) -> None:
    with open(IDX_PATH, "w", encoding="utf-8", newline="\n") as f:
        for name, shard, off, size in entries:
            f.write(f"{name}\t{shard}\t{off}\t{size}\n")


def shard_path(shard: int) -> str:
    return os.path.join(PACK_DIR, f"ardi_{shard:02d}.pak")


def cmd_verify() -> int:
    entries = load_index()
    shards: dict[int, bytes] = {}
    for name, shard, off, size in entries:
        if shard not in shards:
            p = shard_path(shard)
            if not os.path.isfile(p):
                print(f"ERROR: missing shard {p}")
                return 1
            with open(p, "rb") as pf:
                shards[shard] = pf.read()
        data = shards[shard][off : off + size]
        if len(data) != size or not (data.startswith(b"OggS") or data.startswith(b"RIFF")):
            print(f"ERROR: corrupt entry {name} (shard={shard}, off={off}, size={size})")
            return 1
    print(f"OK: verified {len(entries)} entries across {len(shards)} shard(s).")
    return 0


def cmd_unpack(name: str, out_dir: str) -> int:
    entries = load_index()
    for e_name, shard, off, size in entries:
        if e_name == name:
            with open(shard_path(shard), "rb") as pf:
                pf.seek(off)
                data = pf.read(size)
            os.makedirs(out_dir, exist_ok=True)
            out_path = os.path.join(out_dir, name)
            with open(out_path, "wb") as of:
                of.write(data)
            print(f"Extracted {name} ({size} B) -> {out_path}")
            return 0
    print(f"ERROR: {name} not found in ardi_idx.tsv")
    return 1


def cmd_replace(ogg_file: str, name: str | None) -> int:
    if not os.path.isfile(ogg_file):
        print(f"ERROR: file not found: {ogg_file}")
        return 1
    with open(ogg_file, "rb") as f:
        new_bytes = f.read()
    if not (new_bytes.startswith(b"OggS") or new_bytes.startswith(b"RIFF")):
        print("ERROR: input audio must be valid Ogg/Opus or WAV")
        return 1

    target_name = name or os.path.basename(ogg_file)
    entries = load_index()

    target_shard = None
    for e in entries:
        if e[0] == target_name:
            target_shard = e[1]
            break

    if target_shard is None:
        # Pick the smallest shard for new entries
        sizes = {s: os.path.getsize(shard_path(s)) for s in range(SHARD_COUNT)}
        target_shard = min(sizes, key=sizes.get)
        entries.append([target_name, target_shard, 0, len(new_bytes)])
        action = "Added"
    else:
        action = "Replaced"

    p_path = shard_path(target_shard)
    with open(p_path, "rb") as pf:
        old_shard = pf.read()

    parts = []
    cur_off = 0
    for e in entries:
        if e[1] != target_shard:
            continue
        e_name, _, off, size = e
        if e_name == target_name:
            chunk = new_bytes
        else:
            chunk = old_shard[off : off + size]
            if len(chunk) != size:
                print(f"ERROR: corrupt existing chunk {e_name}")
                return 1
        e[2] = cur_off
        e[3] = len(chunk)
        parts.append(chunk)
        cur_off += len(chunk)

    with open(p_path, "wb") as pf:
        pf.write(b"".join(parts))
    save_index(entries)

    print(f"{action} {target_name} in shard {target_shard} ({len(new_bytes)} B).")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Manage KataMemo audio_pack shards")
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("verify", help="Verify all entries in ardi_idx.tsv")

    p_unpack = sub.add_parser("unpack", help="Extract one audio file from pack")
    p_unpack.add_argument("name", help="Entry filename (e.g. id-ke.ogg)")
    p_unpack.add_argument("--out", default=".", help="Output directory")

    p_rep = sub.add_parser("replace", help="Replace or add an .ogg entry into pack")
    p_rep.add_argument("file", help="Path to local .ogg file")
    p_rep.add_argument("--name", default=None, help="Target entry name (defaults to filename)")

    args = parser.parse_args()
    if args.cmd == "verify":
        return cmd_verify()
    if args.cmd == "unpack":
        return cmd_unpack(args.name, args.out)
    if args.cmd == "replace":
        return cmd_replace(args.file, args.name)
    return 1


if __name__ == "__main__":
    sys.exit(main())
