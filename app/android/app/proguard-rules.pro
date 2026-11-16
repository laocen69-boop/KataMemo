# 拍照抓词（ML Kit 文本识别）在 release 包崩溃的修复（2026-10-27）。
#
# 症状：release 真机拍照后 OCR 抛
#   NullPointerException: Attempt to invoke virtual method
#   'java.lang.Class java.lang.Object.getClass()' on a null object reference
#   （debug 包没这问题——debug 不跑 R8。）
#
# 根因（本工程 mapping.txt 实锤）：
#   com.google.android.gms.internal.mlkit_vision_text_bundled_common.zba
#     -> R8$$REMOVED$$CLASS$$175
#   AGP 9 给 release 默认开 R8（本工程从未配过任何 keep 规则，proguard-rules.pro
#   此前不存在），ML Kit bundled 的 proto 消息类被**整类删除/改名**。ML Kit 运行时
#   靠反射访问这些 proto（text-recognition-bundled-common AAR 自带的 consumer 规则
#   只保 `<fields>` 不保类本身），类没了 ⇒ 原生引擎侧拿到 null ⇒ getClass() NPE。
#
# 处置：把 ML Kit 与其 gms/visionkit 内部实现包整体 keep 住。体积代价约 1-2 MB
# dex（ML Kit 模型大头在 native .so，不受 R8 影响）。
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_bundled_common.** { *; }
-keep class com.google.android.libraries.vision.visionkit.** { *; }
