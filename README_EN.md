[中文](README.md) | **English**

# KataMemo

**KataMemo** is an open-source Indonesian vocabulary & grammar learning app tailored for **Chinese speakers**, built with **Flutter + SQLite + FSRS-6**.

> **Offline-first & privacy-friendly**: All 96k+ vocabulary entries, bilingual examples, grammar/writing guides, and 96k+ offline voice clips work completely offline out of the box. Network access is only used when you optionally configure your own LLM API key for the built-in AI tutor or open external reference links.

---

## Core Features

- **96k+ Indonesian Vocabulary & 84k+ Bilingual Examples**
  - Tiered by real corpus frequency (`t1`–`t7`), plus phrases, derived words, reduplications, affixes, and proper nouns.
  - Tap any word in an example sentence for instant lookup.
- **FSRS-6 Spaced Repetition**
  - Native FSRS-6 scheduling with optional on-device parameter optimization (`libfsrs.so`).
- **Offline Pronunciation**
  - 96k+ Opus audio clips packed into sharded `.pak` archives (`app/assets/audio_pack/`) for fast offline playback.
- **Grammar & Writing Guides + Personal Notes**
  - Built-in Indonesian grammar & writing reference with block-level user editing and note-taking.
- **Custom Wordbooks, Dictionary Import & Backup**
  - Import personal wordlists/dictionaries (`.csv` / `.tsv` / `.txt` / `.json`) and export/import full learning backups.
- **Optional BYO-Key AI Tutor**
  - Works with OpenAI-compatible & Claude APIs using your own key (zero relay servers, zero tracking).

---

## Platform Status

- **Android (`arm64-v8a`)**: Fully tested and verified on real devices. Prebuilt APKs are available in [Releases](https://github.com/laocen69-boop/KataMemo/releases).
- **Web / PWA (including iOS Safari "Add to Home Screen")**: Static web build and self-hosting guide available at [docs/Web与PWA部署说明.md](docs/Web与PWA部署说明.md) (with a manual GitHub Pages workflow in `.github/workflows/deploy-web.yml`).
- **iOS Native (`app/ios/`)**: Experimental setup only (`docs/iOS打包说明.md`), not yet compiled/verified on macOS or iPhone.

---

## Build from Source

Requires **Flutter 3.44+** (Dart 3.12+) and Android SDK (JDK 17):

```bash
git clone https://github.com/laocen69-boop/KataMemo.git
cd KataMemo/app
flutter pub get
flutter build apk --release --target-platform android-arm64
```

Or run the data checks & test suite:

```bash
python3 tools/validate_data.py
python3 tools/pack_audio.py verify
cd app && flutter analyze --no-pub && flutter test --no-pub
```

---

## Contributing & Documentation

- Contribution guide: [CONTRIBUTING.md](CONTRIBUTING.md)
- Vocabulary & audio curation workflow (ZH): [docs/词库贡献与新增工作流.md](docs/词库贡献与新增工作流.md)
- Data sources & privacy boundary: [OPEN_SOURCE_NOTES.md](OPEN_SOURCE_NOTES.md)
- Third-party notices: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
- License: [MIT](LICENSE)
