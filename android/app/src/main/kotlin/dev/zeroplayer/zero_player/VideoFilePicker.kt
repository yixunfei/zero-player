package dev.zeroplayer.zero_player

import android.app.Activity
import android.content.Intent
import android.os.StatFs
import android.provider.OpenableColumns
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.InputStream
import java.util.UUID
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean

/** Streams selected media into an application-owned, bounded cache. */
class VideoFilePicker(private val activity: Activity) {
    companion object { private val copying = AtomicBoolean(false) }
    var progress: MethodChannel? = null
    private var pending: MethodChannel.Result? = null
    private var cancelled = AtomicBoolean(false)
    @Volatile private var activeInput: InputStream? = null
    private var limit = 0L
    private val root get() = File(activity.cacheDir, "local-videos")

    fun choose(call: MethodCall, result: MethodChannel.Result) {
        if (pending != null || copying.get()) {
            result.error("busy", "视频选择器已打开", null)
            return
        }
        limit = (call.argument<Number>("maxBytes")?.toLong() ?: 0L)
        if (limit <= 0) {
            result.error("invalid_limit", "本地视频缓存容量无效", null)
            return
        }
        cancelled = AtomicBoolean(false)
        pending = result
        try {
            activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "video/*"
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }, 7203)
        } catch (_: Exception) {
            pending = null
            result.error("video_failed", "无法打开视频选择器", null)
        }
    }

    fun cancel() {
        cancelled.set(true)
        val input = activeInput
        if (input != null) Thread { try { input.close() } catch (_: Exception) {} }.start()
    }

    fun onResult(code: Int, resultCode: Int, data: Intent?): Boolean {
        if (code != 7203) return false
        val result = pending ?: return true
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || cancelled.get()) {
            pending = null
            result.success(null)
            return true
        }
        val identity = MessageDigest.getInstance("SHA-256").digest(uri.toString().toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
        val stop = cancelled
        val budget = limit
        if (!copying.compareAndSet(false, true)) {
            pending = null
            result.error("busy", "视频副本仍在处理，请稍后重试", null)
            return true
        }
        Thread {
            var directory: File? = null
            try {
                val resolver = activity.contentResolver
                var name = "video.mp4"
                var total = -1L
                resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use {
                    if (it.moveToFirst()) {
                        if (!it.isNull(0)) name = it.getString(0)
                        if (!it.isNull(1) && it.getLong(1) > 0) total = it.getLong(1)
                    }
                }
                val safeName = name.replace(Regex("[<>:\"/\\\\|?*\\x00-\\x1f]"), "_").takeLast(120).ifBlank { "video.mp4" }
                check(root.mkdirs() || root.isDirectory)
                val used = root.walkTopDown().filter { it.isFile }.sumOf { it.length() }
                val reserve = 32L * 1024 * 1024
                check(total < 0 || (total <= budget - used && total <= StatFs(root.path).availableBytes - reserve))
                directory = File(root, UUID.randomUUID().toString())
                check(directory.mkdir())
                val part = File(directory, "copy.part")
                var copied = 0L
                fun report() = activity.runOnUiThread {
                    if (pending === result) progress?.invokeMethod("progress", mapOf("copied" to copied, "total" to total))
                }
                report()
                val stream = requireNotNull(resolver.openInputStream(uri))
                activeInput = stream
                stream.use { input ->
                    part.outputStream().use { output ->
                        val buffer = ByteArray(128 * 1024)
                        var nextReport = 0L
                        var nextSpaceCheck = 0L
                        while (true) {
                            check(!stop.get())
                            val count = input.read(buffer)
                            if (count < 0) break
                            check(copied + count <= budget - used)
                            if (copied >= nextSpaceCheck) {
                                check(StatFs(root.path).availableBytes > reserve + 8L * 1024 * 1024)
                                nextSpaceCheck = copied + 8L * 1024 * 1024
                            }
                            output.write(buffer, 0, count)
                            copied += count
                            if (copied >= nextReport) { report(); nextReport = copied + 1024 * 1024 }
                        }
                        output.flush()
                    }
                }
                check(!stop.get() && copied > 0 && (total < 0 || copied == total))
                val target = File(directory, safeName)
                check(part.renameTo(target))
                activity.runOnUiThread {
                    val current = pending === result
                    val abandoned = !current || stop.get()
                    if (abandoned) {
                        target.delete()
                        target.parentFile?.delete()
                    }
                    if (current) {
                        pending = null
                        result.success(if (abandoned) null else mapOf("path" to target.path, "identity" to identity))
                    }
                }
            } catch (_: Exception) {
                directory?.deleteRecursively()
                activity.runOnUiThread {
                    if (pending === result) {
                        pending = null
                        if (stop.get()) result.success(null)
                        else result.error("video_failed", "无法复制视频：请检查文件权限、缓存容量和可用空间", null)
                    }
                }
            } finally { activeInput = null; copying.set(false) }
        }.start()
        return true
    }

    fun clear(call: MethodCall, result: MethodChannel.Result) {
        if (pending != null || copying.get()) {
            result.error("busy", "请先结束视频选择和复制", null)
            return
        }
        try {
            val protected = (call.argument<List<String>>("protected") ?: emptyList()).map { File(it).canonicalPath }
            val rootPath = root.canonicalPath + File.separator
            root.listFiles()?.forEach { entry ->
                val path = entry.canonicalPath
                if (path.startsWith(rootPath) && protected.none { it == path || it.startsWith(path + File.separator) }) {
                    check(entry.deleteRecursively())
                }
            }
            result.success(null)
        } catch (_: Exception) {
            result.error("cleanup_failed", "本地视频副本清理失败", null)
        }
    }

    fun close() {
        cancel()
        pending?.success(null)
        pending = null
    }
}
