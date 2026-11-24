# 第三方组件与许可声明

本仓库代码许可证见根目录 `LICENSE`。
下面列出随仓库分发、或构建时引入的第三方组件与参考来源。

## 一、Flutter / Dart 包（构建时从 pub.dev 下载，本仓库不含其源码）

| 包 | 用途 |
|---|---|
| provider | 应用状态注入 |
| sqflite | 本地 SQLite 数据库 |
| sqflite_common_ffi_web | Web 端 SQLite WASM 数据库适配器 |
| path / path_provider | 文件路径 |
| audioplayers | 音频播放 |
| fl_chart | 统计图表 |
| image_picker | 相册选图 / 拍照 |
| ffi | 调用本地 FSRS 库 |
| flutter_local_notifications / flutter_timezone / timezone | 每日提醒 |
| flutter_markdown_plus（及其依赖 markdown） | AI 助手回答的排版 |
| sqflite_common_ffi、flutter_lints（开发依赖） | 测试与静态检查 |

各包按其自身在 pub.dev 声明的许可证分发（多为 MIT 或 BSD 系），版权归各自作者。
准确版本见 `app/pubspec.lock`。

## 二、Google ML Kit（拍照抓词）

- `com.google.mlkit:text-recognition` 与 `text-recognition-chinese`（Gradle 依赖）。
- **闭源 SDK，不随本仓库分发**：构建时由 Gradle 从 Google Maven 下载，打进 APK 的是其二进制。
- 使用须遵守 [Google ML Kit 服务条款](https://developers.google.com/ml-kit/terms)。版权归 Google LLC。

## 三、FSRS 算法与本地训练库

- `app/android/app/src/main/jniLibs/arm64-v8a/libfsrs.so`：由本项目用
  [fsrs-rs-c](https://github.com/open-spaced-repetition/fsrs-rs-c)（**MIT**）的 C 接口
  交叉编译，内核为 [fsrs-rs](https://github.com/open-spaced-repetition/fsrs-rs)
  （**BSD-3-Clause**）。版权归 open-spaced-repetition 组织及贡献者。
  该库只做本地参数训练，删除后 App 自动隐藏「在本机优化」入口。
- `app/lib/fsrs.dart` 是 FSRS-6 的 Dart 实现，公式与默认参数对照
  [fsrs-rs](https://github.com/open-spaced-repetition/fsrs-rs)（BSD-3-Clause）与
  [ts-fsrs](https://github.com/open-spaced-repetition/ts-fsrs)（MIT）校验，特此致谢。

## 四、数据来源

| 来源 | 内容 | 许可 / 说明 |
|---|---|---|
| KBBI（Badan Bahasa，印尼教育部） | 音标 `ph`（「看KBBI」仅跳转官网） | 仅作读音与学习参考，版权归原权利方；如权利方有异议请联系移除 |
| 维基百科（id / zh，CC BY-SA 4.0） | 专名与百科科普的默认助记（事实摘写/改写） | CC BY-SA 4.0，署名各条目作者；来源条目写在助记末尾「（维基：…）」 |
| wordfreq | 词频**档位标签**（只含推导结果，不含数据本身） | CC BY-SA 4.0，署名 Robyn Speer 等 |
| Microsoft Edge 朗读服务（id-ID-ArdiNeural） | `app/assets/audio_pack/` 离线合成发音 | 仅供个人语言学习与研究参考；如权利方有异议请联系移除 |
| 开源平行语料（Tatoeba / ALT / FLORES-200 / NTREX-128 / tico-19） | 部分单词与短语例句 | 分别依 CC BY 2.0 FR（Tatoeba 贡献者）、CC BY 4.0（NICT ALT）、CC BY-SA 4.0（FLORES-200 / NTREX-128）、CC0（tico-19）使用并署名 |
| 大语言模型 | 部分中文释义与例句 | 本项目整理校对，错漏难免 |

## 五、其他

- Flutter SDK 与 Dart：BSD-3-Clause（Google）。
- Material Icons 字体：Apache License 2.0（Google），构建时按用到的图标子集化。
- **Plus Jakarta Sans** 字体（`app/assets/fonts/PlusJakartaSans-*.ttf`）：SIL Open Font License 1.1（Tokotype / Pemerintah Provinsi DKI Jakarta）。
- **Noto Sans** 字体（`app/assets/fonts/NotoSans-*.ttf`）：SIL Open Font License 1.1（Google）。
- `app/web/sqlite3.wasm` 与 `app/web/sqflite_sw.js`：由 `sqflite_common_ffi_web` / `sqlite3.dart` 官方工具生成（MIT / SQLite Public Domain）。

发现遗漏或需要更正，请提 issue。
