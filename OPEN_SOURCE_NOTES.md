# 开源数据与隐私说明

本文档说明 KataMemo 开源版的数据构成、第三方组件声明与隐私边界。

## 仓库内容

| 内容 | 说明 |
|---|---|
| `app/` Flutter 源码与测试 | 应用逻辑、UI 与单元/组件测试 |
| `app/assets/data/words.json` | 词表（96519 条），含词形、词频档位、词性、中文释义、音标、主题分类、词根词缀拆解、派生词形、非正式写法、语源标签、例句与发音路径 |
| 例句 | 本项目编写与校对的双语例句（84784 条） |
| `app/assets/data/books.json` | 184 个分级与主题词书节点 |
| `app/assets/data/grammar.json`、`writing.json` | 本项目独立编写的印尼语语法与写作教程 |
| 词卡「用法」 | 50 个高频功能词的自编用法说明与例句 |
| `app/assets/audio_pack/` | 离线合成语音分片包（96518 条） |

## 第三方组件与参考致谢

- **FSRS-6 记忆算法与端内优化**：Dart 端记忆调度对照 [open-spaced-repetition](https://github.com/open-spaced-repetition) 的 `fsrs-rs` 与 `ts-fsrs` 实现；`app/android/app/src/main/jniLibs/arm64-v8a/libfsrs.so` 基于 [fsrs-rs-c](https://github.com/open-spaced-repetition/fsrs-rs-c)（MIT）与 [fsrs-rs](https://github.com/open-spaced-repetition/fsrs-rs)（BSD-3-Clause）编译，仅做本机离线参数训练（删除该 `.so` 后 App 会自动隐藏本机优化入口，其余功能不受影响）。
- **词频分级**：档位划分参考了开源项目 [wordfreq](https://github.com/rspeer/wordfreq)（Robyn Speer 等，CC BY-SA 4.0），本仓库仅保留推导出的分级标签。
- **拍照抓词 OCR**：使用 Google ML Kit Text Recognition（`com.google.mlkit:text-recognition` 与 `text-recognition-chinese`），仅在 Gradle 声明依赖并在构建时下载，仅图片与识别结果均在设备本地处理；依据 [Google 数据披露说明](https://developers.google.com/ml-kit/android-data-disclosure)，SDK 本身可能上报基础诊断与使用统计。
- 完整第三方依赖许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 网络与隐私边界

- **默认完全离线运行**：在用户主动配置大模型之前，背词、查词、语法阅读、学习统计与拍照抓词全部在设备本地完成，App 本身不向任何服务器发送网络请求。
- **外部网页跳转**：学习页「看KBBI」与设置页「印尼语能力参考」仅在用户点击后调用系统浏览器打开对应官网或公开页面，App 不内置、不抓取外部网页内容。
- **可选「问一问」AI 助手**：`INTERNET` 权限仅用于该功能。仅当用户在「设置 → AI 助手」填入自己的 API Key 并发起提问时，App 才会将问题与当前学习上下文直接发送至用户选定的模型服务商接口；App 不内置任何 Key、不经过任何中转服务器、不收集任何用户数据。设置页预设的服务商名称与默认接口地址仅作填写便利，本项目与相关服务商无任何关联。

## 词库与语音免责声明

- 中文释义与双语例句经多轮校对整理，但词库规模庞大，仍可能存在疏漏或语境偏差，仅供学习参考。
- 词条音标参考自印尼语规范资料，内置离线语音由语音合成工具生成，均仅用于个人语言学习与研究。如相关权利方认为存在不当之处，欢迎通过 GitHub Issue 联系，我们将第一时间配合移除或替换。
