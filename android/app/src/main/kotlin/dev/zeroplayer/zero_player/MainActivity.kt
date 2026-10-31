package dev.zeroplayer.zero_player

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodCall
import android.app.PictureInPictureParams
import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration
import android.net.ConnectivityManager
import android.util.Rational
import android.content.Intent
import android.app.Activity
import java.io.File

class MainActivity : FlutterActivity() {
    private val videoPicker by lazy { VideoFilePicker(this) }
    private val videoDirectories by lazy { VideoDirectoryBridge(this) }
    private var saveResult: MethodChannel.Result? = null
    private var savePath: String? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        videoPicker.progress = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "zero_player/local_video_progress")
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "zero_player/platform")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveFile" -> requestSave(call, result)
                    "chooseLocalVideo" -> videoPicker.choose(call, result)
                    "cancelLocalVideo" -> { videoPicker.cancel(); result.success(null) }
                    "clearLocalVideoCopies" -> videoPicker.clear(call, result)
                    "chooseVideoDirectory" -> videoDirectories.choose(result)
                    "verifyVideoInDirectory" -> videoDirectories.verify(call, result)
                    "saveVideoToDirectory" -> videoDirectories.save(call, result)
                    "cancelVideoSave" -> { videoDirectories.cancel(call.argument<String>("path")); result.success(null) }
                    "isTelevision" -> {
                        val mode = getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
                        result.success(mode.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION)
                    }
                    "isMetered" -> {
                        val network = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                        result.success(network.isActiveNetworkMetered)
                    }
                    "pictureInPicture" -> {
                        try {
                            val params = PictureInPictureParams.Builder().setAspectRatio(Rational(16, 9)).build()
                            result.success(enterPictureInPictureMode(params))
                        } catch (_: Exception) { result.success(false) }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestSave(call: MethodCall, result: MethodChannel.Result) {
        if (saveResult != null) {
            result.error("busy", "A save dialog is already open", null)
            return
        }
        val path = call.argument<String>("path")
        if (path == null || !File(path).isFile) {
            result.error("invalid_file", "The export file does not exist", null)
            return
        }
        try {
            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = call.argument<String>("mime") ?: "application/octet-stream"
                putExtra(Intent.EXTRA_TITLE, call.argument<String>("name"))
            }
            saveResult = result
            savePath = path
            startActivityForResult(intent, 7201)
        } catch (_: Exception) {
            if (saveResult === result) {
                finishSave(result, error = "Unable to open the file picker")
            } else {
                result.error("save_failed", "Unable to prepare the file picker", null)
            }
        }
    }

    private fun finishSave(pending: MethodChannel.Result, saved: Boolean = false, error: String? = null) {
        if (saveResult !== pending) return
        saveResult = null
        savePath = null
        if (error == null) pending.success(saved)
        else pending.error("save_failed", error, null)
    }

    override fun onDestroy() {
        try {
            videoPicker.close()
            videoDirectories.close()
            saveResult?.let { finishSave(it) }
        } finally {
            super.onDestroy()
        }
    }

    @Deprecated("Uses the activity result bridge for Flutter file export")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (videoPicker.onResult(requestCode, resultCode, data)) return
        if (videoDirectories.onResult(requestCode, resultCode, data)) return
        if (requestCode != 7201) return
        val pending = saveResult ?: return
        val path = savePath
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || path == null) {
            finishSave(pending)
            return
        }
        Thread {
            try {
                contentResolver.openOutputStream(uri, "w").use { output ->
                    requireNotNull(output)
                    File(path).inputStream().use { input -> input.copyTo(output) }
                }
                runOnUiThread { finishSave(pending, saved = true) }
            } catch (_: Exception) {
                runOnUiThread { finishSave(pending, error = "Unable to save file") }
            }
        }.start()
    }
}
