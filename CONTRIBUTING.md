# Contributing to KataMemo

Thank you for your interest in **KataMemo**! Contributions of bug fixes, UI improvements, vocabulary/example corrections, and audio fixes are all welcome.

## 1. Code Changes (`app/`)

1. Fork this repository and create a branch from `main`.
2. Run static analysis and the full test suite before opening a Pull Request:
   ```bash
   cd app
   flutter pub get
   flutter analyze --no-pub
   flutter test --no-pub
   ```
3. Keep PRs focused and include tests for new behavior or bug fixes.

## 2. Vocabulary & Audio Changes (`app/assets/data/`, `app/assets/audio_pack/`)

Please follow the detailed curation rules and tool commands in [docs/词库贡献与新增工作流.md](docs/词库贡献与新增工作流.md):

- Never delete existing audio entries or change published word `id`s.
- Use `tools/synth_audio.py` and `tools/pack_audio.py` to generate/replace `.ogg` clips in `audio_pack/`.
- Always run the data integrity checks before submitting:
  ```bash
  python3 tools/validate_data.py
  python3 tools/pack_audio.py verify
  ```

## 3. Reporting Issues

- Found a mispronounced word, wrong Chinese gloss, or typo? Use the **Word / Audio Report** issue template.
- Found an app crash or UI bug? Use the **Bug Report** issue template.
