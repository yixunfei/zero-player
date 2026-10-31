package dev.zeroplayer.zero_player

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

/** SAF grants access only to the directory chosen by the user. */
class VideoDirectoryBridge(private val activity: Activity) {
    private val copies = ConcurrentHashMap<String, AtomicBoolean>()
    fun cancel(path: String?) { path?.let { copies[it]?.set(true) } }
    private var pending: MethodChannel.Result? = null

    fun choose(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("busy", "Directory picker is already open", null)
            return
        }
        try {
            pending = result
            activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
            }, 7202)
        } catch (_: Exception) {
            pending = null
            result.error("directory_failed", "无法打开目录选择器", null)
        }
    }

    fun onResult(code: Int, resultCode: Int, data: Intent?): Boolean {
        if (code != 7202) return false
        val result = pending ?: return true
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return true
        }
        try {
            val flags = (data?.flags ?: 0) and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            activity.contentResolver.takePersistableUriPermission(uri, flags)
            result.success(uri.toString())
        } catch (_: Exception) {
            result.error("directory_failed", "无法保留目录授权，请重新选择", null)
        }
        return true
    }

    fun verify(call: MethodCall, result: MethodChannel.Result) {
        Thread {
            try {
                val tree = Uri.parse(requireNotNull(call.argument<String>("directory")))
                val name = requireNotNull(call.argument<String>("name"))
                val expected = requireNotNull(call.argument<String>("digest"))
                val resolver = activity.contentResolver
                val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
                var found: String? = null
                requireNotNull(resolver.query(children, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)).use { cursor ->
                    while (cursor.moveToNext()) {
                        if (cursor.getString(1) != name) continue
                        check(found == null) { "Ambiguous document identity" }
                        val uri = DocumentsContract.buildDocumentUriUsingTree(tree, cursor.getString(0))
                        val digest = java.security.MessageDigest.getInstance("SHA-256")
                        requireNotNull(resolver.openInputStream(uri)).use { input ->
                            val buffer = ByteArray(128 * 1024)
                            while (true) {
                                val count = input.read(buffer)
                                if (count < 0) break
                                digest.update(buffer, 0, count)
                            }
                        }
                        check(digest.digest().joinToString("") { "%02x".format(it) } == expected) { "Published content differs" }
                        found = uri.toString()
                    }
                }
                activity.runOnUiThread { result.success(found) }
            } catch (_: Exception) {
                activity.runOnUiThread { result.error("verify_failed", "无法核验已保存文件，请检查授权或选择其他目录", null) }
            }
        }.start()
    }

    fun save(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        val directory = call.argument<String>("directory")
        val name = call.argument<String>("name")
        if (path == null || directory == null || name == null || !File(path).isFile) {
            result.error("invalid_file", "待保存的视频不存在", null)
            return
        }
        val cancelled = AtomicBoolean(false)
        copies[path] = cancelled
        Thread {
            var created: Uri? = null
            try {
                val resolver = activity.contentResolver
                val tree = Uri.parse(directory)
                val parent = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
                val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
                val existing = mutableSetOf<String>()
                requireNotNull(resolver.query(children, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)).use { cursor ->
                    while (cursor.moveToNext()) {
                        existing.add(cursor.getString(0))
                        check(cursor.getString(1) != name) { "目标文件已存在" }
                    }
                }
                val target = requireNotNull(DocumentsContract.createDocument(resolver, parent, "video/mp4", name))
                check(!existing.contains(DocumentsContract.getDocumentId(target)))
                created = target
                // Recovery uses the journaled random identity; providers must preserve it.
                requireNotNull(resolver.query(target, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)).use { cursor ->
                    check(cursor.moveToFirst() && cursor.getString(0) == name) { "Provider changed publication identity" }
                }
                requireNotNull(resolver.openOutputStream(target, "w")).use { output ->
                    File(path).inputStream().use { input ->
                        val buffer = ByteArray(128 * 1024)
                        while (true) {
                            check(!cancelled.get())
                            val count = input.read(buffer)
                            if (count < 0) break
                            output.write(buffer, 0, count)
                        }
                    }
                }
                check(!cancelled.get())
                activity.runOnUiThread { result.success(target.toString()) }
            } catch (_: Exception) {
                created?.let { try { DocumentsContract.deleteDocument(activity.contentResolver, it) } catch (_: Exception) {} }
                activity.runOnUiThread { result.error("save_failed", "保存失败，请检查目录授权和剩余空间", null) }
            } finally { copies.remove(path, cancelled) }
        }.start()
    }

    fun close() {
        pending?.success(null)
        pending = null
    }
}
