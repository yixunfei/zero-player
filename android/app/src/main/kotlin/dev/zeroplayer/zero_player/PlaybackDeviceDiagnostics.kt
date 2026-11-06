package dev.zeroplayer.zero_player

import android.app.ActivityManager
import android.app.Activity
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import android.os.Debug
import android.os.Process

/** Numeric, local-only evidence; never includes URLs, traces or user content. */
class PlaybackDeviceDiagnostics(private val context: Context) {
    var lastTrimLevel = -1
    private val previousExits by lazy { readPreviousExits() }

    fun snapshot(): Map<String, Any> {
        val manager = context.getSystemService(ActivityManager::class.java)
        val memory = ActivityManager.MemoryInfo()
        manager.getMemoryInfo(memory)
        val runtime = Runtime.getRuntime()
        return mapOf(
            "sdk" to Build.VERSION.SDK_INT,
            "pid" to Process.myPid(),
            "requestedOrientation" to ((context as? Activity)?.requestedOrientation ?: -1),
            "configurationOrientation" to context.resources.configuration.orientation,
            "pssKiB" to Debug.getPss(),
            "nativeHeapBytes" to Debug.getNativeHeapAllocatedSize(),
            "javaHeapBytes" to runtime.totalMemory() - runtime.freeMemory(),
            "javaHeapLimitBytes" to runtime.maxMemory(),
            "availableMemoryBytes" to memory.availMem,
            "lowMemory" to memory.lowMemory,
            "lastTrimLevel" to lastTrimLevel,
            "exitHistorySupported" to (Build.VERSION.SDK_INT >= 30),
            "previousExits" to previousExits,
        )
    }

    private fun readPreviousExits(): List<Map<String, Any>> {
        if (Build.VERSION.SDK_INT < 30) return emptyList()
        return try {
            context.getSystemService(ActivityManager::class.java)
                .getHistoricalProcessExitReasons(context.packageName, 0, 3)
                .map { exit ->
                    mapOf(
                        "timestamp" to exit.timestamp,
                        "reason" to reasonLabel(exit.reason),
                        "reasonCode" to exit.reason,
                        "status" to exit.status,
                        "rssKiB" to exit.rss,
                        "pssKiB" to exit.pss,
                    )
                }
        } catch (_: Exception) { emptyList() }
    }

    private fun reasonLabel(reason: Int): String = when (reason) {
        ApplicationExitInfo.REASON_LOW_MEMORY -> "low_memory"
        ApplicationExitInfo.REASON_CRASH_NATIVE -> "native_crash"
        ApplicationExitInfo.REASON_CRASH -> "java_crash"
        ApplicationExitInfo.REASON_ANR -> "anr"
        ApplicationExitInfo.REASON_SIGNALED -> "signal"
        ApplicationExitInfo.REASON_USER_REQUESTED -> "user_requested"
        ApplicationExitInfo.REASON_USER_STOPPED -> "user_stopped"
        ApplicationExitInfo.REASON_EXIT_SELF -> "exit_self"
        else -> "other"
    }
}
