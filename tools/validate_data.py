#!/usr/bin/env python3
"""Validate KataMemo open-source data assets and audio_pack integrity."""

from __future__ import annotations

import json
import os
import sys
import unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(ROOT, "app", "assets", "data")
PACK_DIR = os.path.join(ROOT, "app", "assets", "audio_pack")
AUDIO_DIR = os.path.join(ROOT, "app", "assets", "audio")

VALID_TIERS = {
    "t1", "t2", "t3", "t4", "t5", "t6", "t7",
    "advanced", "phrase", "derived", "redup", "proper", "affix", "lookup",
}
VALID_POS = {"n", "v", "a", "adv", "num", "part", "pron", "interj", "conj", "prep"}


def is_ascii_lowercase_id(s: str) -> bool:
    if not s or s != s.lower():
        return False
    # id must not contain combining diacritics or accented e (e.g., é/ê)
    nfd = unicodedata.normalize("NFD", s)
    return all(unicodedata.category(ch) != "Mn" for ch in nfd)


def load_audio_index(errors: list[str]) -> set[str]:
    idx_path = os.path.join(PACK_DIR, "ardi_idx.tsv")
    if not os.path.isfile(idx_path):
        errors.append(f"Missing audio index: {idx_path}")
        return set()

    shard_sizes: dict[int, int] = {}
    names: set[str] = set()
    with open(idx_path, "r", encoding="utf-8") as f:
        for lineno, raw in enumerate(f, 1):
            line = raw.rstrip("\r\n")
            if not line:
                continue
            parts = line.split("\t")
            if len(parts) != 4:
                errors.append(f"ardi_idx.tsv:{lineno} invalid column count")
                continue
            name, shard_s, off_s, size_s = parts
            try:
                shard = int(shard_s)
                off = int(off_s)
                size = int(size_s)
            except ValueError:
                errors.append(f"ardi_idx.tsv:{lineno} non-integer offset/size")
                continue

            if shard not in shard_sizes:
                pak_path = os.path.join(PACK_DIR, f"ardi_{shard:02d}.pak")
                if not os.path.isfile(pak_path):
                    errors.append(f"Missing shard file: {pak_path}")
                    shard_sizes[shard] = -1
                else:
                    shard_sizes[shard] = os.path.getsize(pak_path)

            total = shard_sizes[shard]
            if total >= 0 and (off < 0 or size <= 0 or off + size > total):
                errors.append(
                    f"ardi_idx.tsv:{lineno} ({name}) out of bounds: off={off}, size={size}, shard_size={total}"
                )
            names.add(name)
    return names


def audio_exists(rel: str, packed_names: set[str]) -> bool:
    if rel.startswith("edge/ardi/"):
        basename = rel[len("edge/ardi/"):]
        if basename in packed_names:
            return True
    return os.path.isfile(os.path.join(AUDIO_DIR, rel))


def validate_words(packed_names: set[str], errors: list[str]) -> int:
    words_path = os.path.join(DATA_DIR, "words.json")
    with open(words_path, "r", encoding="utf-8") as f:
        words = json.load(f)

    if not isinstance(words, list) or not words:
        errors.append("words.json must be a non-empty JSON array")
        return 0

    seen_ids: set[str] = set()
    for idx, entry in enumerate(words):
        if not isinstance(entry, dict):
            errors.append(f"words[{idx}] is not an object")
            continue
        wid = entry.get("id")
        w = entry.get("w")
        tier = entry.get("t")
        zh = entry.get("zh")
        pos = entry.get("c")

        if not isinstance(wid, str) or not is_ascii_lowercase_id(wid):
            errors.append(f"words[{idx}] invalid id={wid!r} (must be lowercase without accents)")
        elif wid in seen_ids:
            errors.append(f"Duplicate id: {wid!r}")
        else:
            seen_ids.add(wid)

        if not isinstance(w, str) or not w.strip():
            errors.append(f"words[{wid}] missing display word 'w'")
        if tier not in VALID_TIERS:
            errors.append(f"words[{wid}] invalid tier 't'={tier!r}")
        if not isinstance(zh, str) or not zh.strip():
            errors.append(f"words[{wid}] empty Chinese gloss 'zh'")
        if pos is not None and pos not in VALID_POS:
            errors.append(f"words[{wid}] invalid pos 'c'={pos!r}")

        ex_list = entry.get("ex")
        if ex_list is not None:
            if not isinstance(ex_list, list):
                errors.append(f"words[{wid}] 'ex' must be a list")
            else:
                for ex_i, ex in enumerate(ex_list):
                    if not isinstance(ex, dict) or not str(ex.get("i", "")).strip() or not str(ex.get("z", "")).strip():
                        errors.append(f"words[{wid}].ex[{ex_i}] missing 'i' or 'z'")

        au = entry.get("au")
        if isinstance(au, dict):
            a_path = au.get("a")
            if isinstance(a_path, str) and a_path and not audio_exists(a_path, packed_names):
                errors.append(f"words[{wid}] missing audio asset: {a_path}")

        ap = entry.get("ap")
        if isinstance(ap, list):
            for part in ap:
                if isinstance(part, str) and part and not audio_exists(part, packed_names):
                    errors.append(f"words[{wid}] missing audio part: {part}")

    return len(words)


def validate_aux_json(errors: list[str]) -> None:
    for fname in ("books.json", "grammar.json", "writing.json"):
        path = os.path.join(DATA_DIR, fname)
        if not os.path.isfile(path):
            errors.append(f"Missing data file: {path}")
            continue
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        if not data:
            errors.append(f"Empty JSON file: {fname}")


def main() -> int:
    errors: list[str] = []
    packed_names = load_audio_index(errors)
    count = validate_words(packed_names, errors)
    validate_aux_json(errors)

    if errors:
        print(f"FAILED with {len(errors)} error(s):")
        for err in errors[:30]:
            print("  -", err)
        if len(errors) > 30:
            print(f"  ... and {len(errors) - 30} more")
        return 1

    print(f"OK: {count} words, {len(packed_names)} packed audio entries, all JSON & audio links valid.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
