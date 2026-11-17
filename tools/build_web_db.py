#!/usr/bin/env python3
"""Pre-build a gzipped SQLite database (web_seed.db.gz) for instant Web/PWA startup."""

from __future__ import annotations

import gzip
import json
import os
import re
import sqlite3
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(ROOT, "app", "assets", "data")
DB_Dart = os.path.join(ROOT, "app", "lib", "db.dart")
VER_Dart = os.path.join(ROOT, "app", "lib", "version.dart")
OUT_PATH = os.path.join(DATA_DIR, "web_seed.db.gz")


def read_versions() -> tuple[int, int]:
    with open(DB_Dart, "r", encoding="utf-8") as f:
        db_txt = f.read()
    with open(VER_Dart, "r", encoding="utf-8") as f:
        ver_txt = f.read()

    dv = int(re.search(r"const int kDataVersion\s*=\s*(\d+);", db_txt).group(1))
    sv = int(re.search(r"const int kSchemaVersion\s*=\s*(\d+);", db_txt).group(1))
    no_kbbi = "kNoKbbiBuild = true" in ver_txt
    if no_kbbi:
        dv += 500000
    return sv, dv


def encode_maps(items: list[dict] | None) -> str | None:
    if not items:
        return None
    return json.dumps(items, ensure_ascii=False, separators=(",", ":"))


def encode_gn(gn: object) -> str | None:
    if not gn:
        return None
    if isinstance(gn, list):
        return json.dumps(gn, ensure_ascii=False, separators=(",", ":"))
    return json.dumps([gn], ensure_ascii=False, separators=(",", ":"))


def main() -> None:
    t0 = time.time()
    schema_ver, data_ver = read_versions()
    words_path = os.path.join(DATA_DIR, "words.json")
    with open(words_path, "r", encoding="utf-8") as f:
        words = json.load(f)

    with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as tmp:
        tmp_db = tmp.name

    try:
        conn = sqlite3.connect(tmp_db)
        cur = conn.cursor()
        cur.executescript(f"""
        PRAGMA journal_mode = DELETE;
        PRAGMA synchronous = OFF;
        PRAGMA user_version = {schema_ver};

        CREATE TABLE words (
          id TEXT PRIMARY KEY,
          word TEXT NOT NULL,
          tier TEXT,
          rank INTEGER,
          frequency INTEGER DEFAULT 0,
          phonetic TEXT,
          word_class TEXT,
          full_name TEXT,
          affix_type TEXT,
          pos_all TEXT,
          proper_kind TEXT,
          domains TEXT,
          topics TEXT,
          origin TEXT,
          base_word TEXT,
          non_standard TEXT,
          non_standard_forms TEXT,
          clitics TEXT,
          variants TEXT,
          senses TEXT,
          examples TEXT,
          derivations TEXT,
          gabungan TEXT,
          root_count INTEGER,
          zh TEXT,
          affix_base TEXT,
          affixes TEXT,
          grammar_function TEXT,
          grammar_notes TEXT,
          audio_ardi TEXT,
          audio_gadis TEXT,
          audio_human TEXT,
          audio_parts TEXT,
          mnemonic TEXT,
          mnemonic_default TEXT,
          mnemonic_images TEXT,
          phrase_tier TEXT,
          zh_pos TEXT,
          quiz_zh TEXT,
          user_word INTEGER DEFAULT 0,
          user_blocks TEXT,
          card_order TEXT,
          no_freq INTEGER DEFAULT 0,
          enabled INTEGER DEFAULT 1,
          favorite INTEGER DEFAULT 0
        );

        CREATE TABLE srs (
          card_id TEXT PRIMARY KEY,
          stability REAL DEFAULT 0,
          difficulty REAL DEFAULT 5,
          due INTEGER,
          last_review INTEGER,
          reps INTEGER DEFAULT 0,
          lapses INTEGER DEFAULT 0,
          state INTEGER DEFAULT 0,
          step INTEGER DEFAULT 0,
          first_seen INTEGER
        );

        CREATE TABLE study_log (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          card_id TEXT,
          rating INTEGER,
          ts INTEGER
        );

        CREATE TABLE meta (k TEXT PRIMARY KEY, v TEXT);

        CREATE TABLE plan (
          card_id TEXT PRIMARY KEY,
          ts INTEGER NOT NULL
        );

        CREATE TABLE user_edit (
          card_id TEXT NOT NULL,
          field TEXT NOT NULL,
          value TEXT,
          ts INTEGER,
          PRIMARY KEY (card_id, field)
        );

        CREATE TABLE word_list (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          ids_json TEXT NOT NULL,
          created_at INTEGER
        );

        CREATE TABLE grammar_progress (
          card_id TEXT PRIMARY KEY,
          seen_at INTEGER,
          starred INTEGER NOT NULL DEFAULT 0,
          drill_ok INTEGER NOT NULL DEFAULT 0,
          drill_total INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE grammar_edit (
          scope TEXT NOT NULL,
          page_id TEXT NOT NULL,
          block_key TEXT NOT NULL,
          kind TEXT NOT NULL,
          payload TEXT NOT NULL,
          ts INTEGER NOT NULL,
          PRIMARY KEY (scope, page_id, block_key)
        );

        CREATE TABLE ai_chat (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          ctx_key TEXT NOT NULL,
          title TEXT NOT NULL,
          subtitle TEXT,
          system TEXT,
          preview TEXT,
          msg_count INTEGER NOT NULL DEFAULT 0,
          created INTEGER NOT NULL,
          updated INTEGER NOT NULL,
          msgs TEXT NOT NULL
        );

        CREATE TABLE dict_source (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          format TEXT NOT NULL,
          entry_count INTEGER NOT NULL DEFAULT 0,
          enabled INTEGER NOT NULL DEFAULT 1,
          added_at INTEGER NOT NULL
        );

        CREATE TABLE dict_entry (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          source_id INTEGER NOT NULL,
          lemma TEXT NOT NULL,
          fold TEXT NOT NULL,
          fold_loose TEXT NOT NULL DEFAULT '',
          homograph INTEGER NOT NULL DEFAULT 1,
          pronunciation TEXT,
          senses_json TEXT NOT NULL
        );
        """)

        rows = []
        for m in words:
            wid = m.get("id") or m["w"]
            examples = [
                {
                    "i": e.get("i") or "",
                    "z": e.get("z"),
                    "s": e.get("s"),
                    "q": e.get("q"),
                }
                for e in (m.get("ex") or [])
            ]
            derivations = [
                {
                    "f": d.get("f") or "",
                    "p": d.get("p"),
                    "g": d.get("g"),
                    "d": None,
                }
                for d in (m.get("dv") or [])
            ]
            ax = m.get("ax")
            affixes = []
            affix_base = None
            if isinstance(ax, dict):
                affix_base = ax.get("b")
                for a in (ax.get("a") or []):
                    affixes.append({
                        "type": a.get("t") or "",
                        "morph": a.get("m") or "",
                        "name": a.get("n") or "",
                        "meaning": a.get("g") or "",
                    })
            au = m.get("au") if isinstance(m.get("au"), dict) else {}
            ap = [str(p) for p in (m.get("ap") or [])]
            cl = m.get("cl")
            clitics = None
            if isinstance(cl, list) and cl:
                clitics = encode_maps([
                    {"base": c.get("b", ""), "form": c.get("f", ""), "note": c.get("n")}
                    for c in cl
                ])

            rows.append((
                wid,
                m["w"],
                m.get("t") or "core",
                m.get("r"),
                m.get("f") or 0,
                m.get("ph"),
                m.get("c"),
                m.get("fl"),
                m.get("af"),
                m.get("pa"),
                m.get("pk"),
                1 if m.get("nf") == 1 else 0,
                ",".join(m["d"]) if isinstance(m.get("d"), list) else None,
                ",".join(m["tp"]) if isinstance(m.get("tp"), list) else None,
                m.get("o"),
                m.get("rc"),
                m.get("b"),
                m.get("n"),
                ",".join(m["v"]) if isinstance(m.get("v"), list) else None,
                ",".join(m["ns"]) if isinstance(m.get("ns"), list) else None,
                clitics,
                None,  # senses (kKbbiLocal=false)
                encode_maps(examples),
                encode_maps(derivations),
                None,  # gabungan
                m.get("pt"),
                m.get("zp"),
                m.get("zh"),
                affix_base,
                encode_maps(affixes),
                m.get("gf"),
                encode_gn(m.get("gn")),
                au.get("a"),
                au.get("g"),
                au.get("h"),
                json.dumps(ap, ensure_ascii=False, separators=(",", ":")) if ap else None,
                m.get("mn"),
                m.get("qz"),
                m.get("en") if m.get("en") is not None else 1,
                0,
            ))

        cur.executemany(
            """
            INSERT OR REPLACE INTO words (
              id, word, tier, rank, frequency, phonetic, word_class,
              full_name, affix_type, pos_all, proper_kind, no_freq,
              domains, topics, origin, root_count, base_word,
              non_standard, variants, non_standard_forms, clitics,
              senses, examples, derivations, gabungan, phrase_tier,
              zh_pos, zh, affix_base, affixes, grammar_function,
              grammar_notes, audio_ardi, audio_gadis, audio_human,
              audio_parts, mnemonic_default, quiz_zh, enabled, favorite
            ) VALUES (
              ?,?,?,?,?,?,?,?,?,?,
              ?,?,?,?,?,?,?,?,?,?,
              ?,?,?,?,?,?,?,?,?,?,
              ?,?,?,?,?,?,?,?,?,?
            )
            """,
            rows,
        )

        cur.execute("INSERT OR REPLACE INTO meta (k, v) VALUES (?, ?)", ("data_version", str(data_ver)))

        cur.executescript("""
        CREATE INDEX idx_words_tier ON words(tier);
        CREATE INDEX idx_srs_due ON srs(due);
        CREATE INDEX idx_log_ts ON study_log(ts);
        CREATE INDEX idx_words_rank ON words(rank);
        CREATE INDEX idx_words_word_class ON words(word_class);
        CREATE INDEX idx_log_card ON study_log(card_id);
        CREATE INDEX idx_ai_chat_updated ON ai_chat(updated);
        CREATE INDEX idx_dict_entry_fold ON dict_entry(fold);
        CREATE INDEX idx_dict_entry_fold_loose ON dict_entry(fold_loose);
        CREATE INDEX idx_dict_entry_source ON dict_entry(source_id);
        """)
        conn.commit()
        conn.close()

        raw_size = os.path.getsize(tmp_db)
        with open(tmp_db, "rb") as src, gzip.open(OUT_PATH, "wb", compresslevel=9) as dst:
            while True:
                chunk = src.read(1024 * 1024)
                if not chunk:
                    break
                dst.write(chunk)
        gz_size = os.path.getsize(OUT_PATH)
        print(
            f"Built {OUT_PATH}: {len(rows)} words, "
            f"raw={raw_size/1024/1024:.2f} MB -> gz={gz_size/1024/1024:.2f} MB "
            f"in {time.time() - t0:.2f}s (schema={schema_ver}, data={data_ver})"
        )
    finally:
        if os.path.exists(tmp_db):
            os.remove(tmp_db)


if __name__ == "__main__":
    main()
