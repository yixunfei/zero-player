package dev.zeroplayer.zero_player

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
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
    private var saveResult: MethodChannel.Result? = null
    private var savePath: String? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "zero_player/platform")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveFile" -> {
                        if (saveResult != null) {
                            result.error("busy", "A save dialog is already open", null)
                        } else {
                            saveResult = result
                            savePath = call.argument<String>("path")
                            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = call.argument<String>("mime") ?: "application/octet-stream"
                                putExtra(Intent.EXTRA_TITLE, call.argument<String>("name"))
                            }
                            startActivityForResult(intent, 7201)
                        }
                    }
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

    @Deprecated("Uses the activity result bridge for Flutter file export")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 7201) return
        val pending = saveResult ?: return
        val path = savePath
        saveResult = null
        savePath = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || path == null) {
            pending.success(false)
            return
        }
        Thread {
            try {
                contentResolver.openOutputStream(uri, "w").use { output ->
                    requireNotNull(output)
                    File(path).inputStream().use { input -> input.copyTo(output) }
                }
                runOnUiThread { pending.success(true) }
            } catch (_: Exception) {
                runOnUiThread { pending.error("save_failed", "Unable to save file", null) }
            }
        }.start()
    }
}
