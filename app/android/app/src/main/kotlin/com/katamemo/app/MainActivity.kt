package com.katamemo.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions

import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private val channelName = "katamemo/picker"
    private val pickRequestCode = 4711
    private var pendingResult: MethodChannel.Result? = null

    private val dictRequestCode = 4712
    private var pendingDictResult: MethodChannel.Result? = null

    private val cjkRun = Regex("[\\u4e00-\\u9fff\\u3400-\\u4dbf\\u3000-\\u303f\\uff00-\\uffef]+")

    private fun hasCjk(s: String) =
        s.any { it.code in 0x4E00..0x9FFF || it.code in 0x3400..0x4DBF }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickAudio" -> {
                        if (pendingResult != null) {
                            result.error("busy", "上一次选择还没结束", null)
                            return@setMethodCallHandler
                        }
                        pendingResult = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "audio/*"
                        }
                        try {
                            startActivityForResult(
                                Intent.createChooser(intent, "选择音频文件"), pickRequestCode
                            )
                        } catch (e: Exception) {
                            pendingResult = null
                            result.error("no_picker", e.message ?: "打不开文件选择器", null)
                        }
                    }
                    "ocr" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("bad_args", "path 不能为空", null)
                            return@setMethodCallHandler
                        }

                        thread(name = "katamemo-ocr") {
                            try {
                                val runs = doOcr(path)

                                runOnUiThread { result.success(runs) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("ocr_failed", e.message ?: "识别失败", null)
                                }
                            }
                        }
                    }

                    "openUrl" -> {
                        val url = call.argument<String>("url")
                        if (url == null || !url.startsWith("https://")) {
                            result.error("bad_args", "只支持 https 链接", null)
                            return@setMethodCallHandler
                        }
                        try {
                            startActivity(
                                Intent(Intent.ACTION_VIEW, Uri.parse(url))
                                    .addCategory(Intent.CATEGORY_BROWSABLE)
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("no_browser", e.message ?: "没有可用的浏览器", null)
                        }
                    }

                    "pickDict" -> {
                        if (pendingDictResult != null) {
                            result.error("busy", "上一次选择还没结束", null)
                            return@setMethodCallHandler
                        }
                        pendingDictResult = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                            putExtra(
                                Intent.EXTRA_MIME_TYPES,
                                arrayOf(
                                    "text/csv",
                                    "text/tab-separated-values",
                                    "application/json",
                                    "text/plain",
                                ),
                            )
                        }
                        try {
                            startActivityForResult(
                                Intent.createChooser(intent, "选择词典文件"), dictRequestCode
                            )
                        } catch (e: Exception) {
                            pendingDictResult = null
                            result.error("no_picker", e.message ?: "打不开文件选择器", null)
                        }
                    }

                    "readPackAudio" -> {
                        val pack = call.argument<String>("pack")
                        val offset = call.argument<Number>("offset")?.toLong() ?: -1L
                        val length = call.argument<Number>("length")?.toInt() ?: -1
                        if (pack == null || !pack.startsWith("assets/audio_pack/") ||
                            offset < 0L || length <= 0 || length > 4 * 1024 * 1024
                        ) {
                            result.error("bad_args", "无效的分片读取参数", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(readPackSlice("flutter_assets/$pack", offset, length))
                        } catch (e: Exception) {
                            result.error("pack_read_failed", e.message ?: "读取音频分片失败", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun readPackSlice(assetPath: String, offset: Long, length: Int): ByteArray {
        val out = ByteArray(length)
        try {
            assets.openFd(assetPath).use { afd ->
                FileInputStream(afd.fileDescriptor).use { fis ->
                    fis.channel.position(afd.startOffset + offset)
                    var got = 0
                    while (got < length) {
                        val n = fis.read(out, got, length - got)
                        if (n <= 0) break
                        got += n
                    }
                    if (got != length) throw IllegalStateException("分片截断：$got/$length")
                    return out
                }
            }
        } catch (_: java.io.FileNotFoundException) {
            assets.open(assetPath).use { ins ->
                var rem = offset
                while (rem > 0) {
                    val skipped = ins.skip(rem)
                    if (skipped <= 0) {
                        if (ins.read() < 0) break
                        rem--
                    } else {
                        rem -= skipped
                    }
                }
                var got = 0
                while (got < length) {
                    val n = ins.read(out, got, length - got)
                    if (n <= 0) break
                    got += n
                }
                if (got != length) throw IllegalStateException("分片截断：$got/$length")
                return out
            }
        }
    }

    private fun doOcr(path: String): List<Map<String, Any>> {
        val image = InputImage.fromFilePath(applicationContext, Uri.fromFile(File(path)))
        val latin = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        val zh = TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
        val runs = mutableListOf<Map<String, Any>>()

        fun add(text: String, l: Int, t: Int, r: Int, b: Int, cjk: Int) {
            if (text.isNotBlank()) {
                runs.add(
                    mapOf("text" to text, "l" to l, "t" to t, "r" to r, "b" to b, "cjk" to cjk)
                )
            }
        }

        try {
            for (block in Tasks.await(latin.process(image)).textBlocks) {
                for (line in block.lines) {
                    if (hasCjk(line.text)) continue
                    val box = line.boundingBox ?: continue
                    add(line.text.trim(), box.left, box.top, box.right, box.bottom, 0)
                }
            }
            for (block in Tasks.await(zh.process(image)).textBlocks) {
                for (line in block.lines) {
                    if (!hasCjk(line.text)) continue
                    val box = line.boundingBox ?: continue
                    var idx = 0
                    for (m in cjkRun.findAll(line.text)) {
                        val seg = line.text.substring(idx, m.range.first).trim()

                        if (seg.any { it.isLetter() }) {
                            add(seg, box.left, box.top, box.right, box.bottom, 0)
                        }
                        add(m.value, box.left, box.top, box.right, box.bottom, 1)
                        idx = m.range.last + 1
                    }
                    val tail = line.text.substring(idx).trim()
                    if (tail.any { it.isLetter() }) {
                        add(tail, box.left, box.top, box.right, box.bottom, 0)
                    }
                }
            }
        } finally {

            latin.close()
            zh.close()
        }
        return runs
    }

    @Deprecated("Flutter 仍支持；这里只用系统文件选择器，不需要 ActivityResult API")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == pickRequestCode) {
            val res = pendingResult ?: return
            pendingResult = null
            val uri: Uri? = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null) {
                res.success(null)
                return
            }
            try {
                val name = displayName(uri) ?: "picked"
                val out = File(cacheDir, "pick_${System.currentTimeMillis()}_$name")
                contentResolver.openInputStream(uri).use { input ->
                    requireNotNull(input) { "读不到这个文件" }
                    out.outputStream().use { input.copyTo(it) }
                }
                res.success(out.absolutePath)
            } catch (e: Exception) {
                res.error("copy_failed", e.message ?: "复制文件失败", null)
            }
            return
        }
        if (requestCode == dictRequestCode) {
            val res = pendingDictResult ?: return
            pendingDictResult = null
            val uri: Uri? = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null) {
                res.success(null)
                return
            }

            val name = displayName(uri) ?: "dict.txt"
            thread(name = "katamemo-dict-copy") {
                try {
                    val out = File(cacheDir, "pick_${System.currentTimeMillis()}_$name")
                    contentResolver.openInputStream(uri).use { input ->
                        requireNotNull(input) { "读不到这个文件" }
                        out.outputStream().use { input.copyTo(it) }
                    }
                    normalizeToUtf8(out)
                    runOnUiThread { res.success(out.absolutePath) }
                } catch (e: Exception) {
                    runOnUiThread { res.error("copy_failed", e.message ?: "复制文件失败", null) }
                }
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun normalizeToUtf8(f: File) {
        val head = ByteArray(2)
        val n = f.inputStream().use { it.read(head) }
        val charset = when {
            n == 2 && head[0] == 0xFF.toByte() && head[1] == 0xFE.toByte() -> Charsets.UTF_16LE
            n == 2 && head[0] == 0xFE.toByte() && head[1] == 0xFF.toByte() -> Charsets.UTF_16BE
            isValidUtf8(f) -> return
            else -> java.nio.charset.Charset.forName("GB18030")
        }
        val skip = if (charset == Charsets.UTF_16LE || charset == Charsets.UTF_16BE) 2L else 0L
        val tmp = File(f.parentFile, f.name + ".utf8")
        f.inputStream().use { input ->
            input.skip(skip)
            java.io.InputStreamReader(input, charset).use { reader ->
                java.io.OutputStreamWriter(tmp.outputStream(), Charsets.UTF_8).use { writer ->
                    reader.copyTo(writer)
                }
            }
        }
        if (!tmp.renameTo(f)) {
            tmp.copyTo(f, overwrite = true)
            tmp.delete()
        }
    }

    private fun isValidUtf8(f: File): Boolean = try {
        val dec = Charsets.UTF_8.newDecoder()
            .onMalformedInput(java.nio.charset.CodingErrorAction.REPORT)
            .onUnmappableCharacter(java.nio.charset.CodingErrorAction.REPORT)
        java.io.InputStreamReader(f.inputStream(), dec).use { r ->
            val buf = CharArray(8192)
            while (r.read(buf) >= 0) {  }
        }
        true
    } catch (_: java.nio.charset.CharacterCodingException) {
        false
    }

    private fun displayName(uri: Uri): String? = try {
        contentResolver.query(uri, null, null, null, null)?.use { c ->
            val idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (idx >= 0 && c.moveToFirst()) c.getString(idx) else null
        }
    } catch (_: Exception) {
        null
    }
}
