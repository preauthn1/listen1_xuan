package com.xiebian.listen1_xuan

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors

/**
 * 把下载好的歌曲/歌词放进公共的 Download/<subdir> 目录。
 *
 * Android 10+ 走 MediaStore.Downloads：不需要任何存储权限，文件管理器和
 * 音乐播放器都能看到；Download 目录允许任意 MIME，歌词 .lrc 可以和歌曲放在一起。
 * Android 9 及以下直接写公共目录（需要 WRITE_EXTERNAL_STORAGE，Dart 侧先申请）。
 */
class TrackDownloads(private val activity: Activity) {
    private val io = Executors.newSingleThreadExecutor()
    private val manager = activity.getSystemService(NotificationManager::class.java)

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "save" -> {
                val src = call.argument<String>("path")
                val name = call.argument<String>("name")
                val mime = call.argument<String>("mime") ?: "application/octet-stream"
                val subdir = call.argument<String>("subdir") ?: "Listen1/Music"
                if (src == null || name == null) {
                    result.error("bad_args", "path and name are required", null)
                    return
                }
                io.execute {
                    try {
                        val location = save(File(src), name, mime, subdir)
                        activity.runOnUiThread { result.success(location) }
                    } catch (e: Exception) {
                        activity.runOnUiThread { result.error("save_failed", e.message, null) }
                    }
                }
            }
            "open" -> {
                val location = call.argument<String>("location")
                val mime = call.argument<String>("mime") ?: "audio/*"
                result.success(location != null && open(location, mime))
            }
            "needsLegacyPermission" -> result.success(Build.VERSION.SDK_INT < Build.VERSION_CODES.Q)
            "progress" -> {
                progress(
                    call.argument<Int>("done") ?: 0,
                    call.argument<Int>("total") ?: 0,
                    call.argument<String>("title") ?: "",
                )
                result.success(null)
            }
            "finish" -> {
                finish(call.argument<Int>("done") ?: 0, call.argument<Int>("failed") ?: 0)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun save(src: File, name: String, mime: String, subdir: String): String {
        if (!src.exists()) throw IOException("source missing")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = activity.contentResolver
            val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            val relative = "${Environment.DIRECTORY_DOWNLOADS}/$subdir"
            // 重新下载同一首歌时覆盖本应用之前写入的文件；别的应用的同名文件删不掉，
            // 交给 MediaStore 自动加序号。
            resolver.query(
                collection,
                arrayOf(MediaStore.MediaColumns._ID),
                "${MediaStore.MediaColumns.RELATIVE_PATH}=? AND ${MediaStore.MediaColumns.DISPLAY_NAME}=?",
                arrayOf("$relative/", name),
                null,
            )?.use { cursor ->
                while (cursor.moveToNext()) {
                    try {
                        resolver.delete(ContentUris.withAppendedId(collection, cursor.getLong(0)), null, null)
                    } catch (_: Exception) {
                    }
                }
            }
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(MediaStore.MediaColumns.RELATIVE_PATH, relative)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = resolver.insert(collection, values) ?: throw IOException("MediaStore insert failed")
            try {
                resolver.openOutputStream(uri)?.use { out -> src.inputStream().use { it.copyTo(out) } }
                    ?: throw IOException("cannot open output")
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
            } catch (e: Exception) {
                resolver.delete(uri, null, null)
                throw e
            }
            return uri.toString()
        }
        @Suppress("DEPRECATION")
        val root = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        val dir = File(root, subdir)
        if (!dir.exists() && !dir.mkdirs()) throw IOException("cannot create $dir")
        val out = File(dir, name)
        src.copyTo(out, overwrite = true)
        MediaScannerConnection.scanFile(activity, arrayOf(out.path), arrayOf(mime), null)
        return out.path
    }

    private fun open(location: String, mime: String): Boolean {
        if (!location.startsWith("content://")) return false
        return try {
            activity.startActivity(
                Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(Uri.parse(location), mime)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                },
            )
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun canNotify(): Boolean =
        Build.VERSION.SDK_INT < 33 ||
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "歌曲下载", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "下载歌曲和歌词的进度"
                },
            )
        }
    }

    private fun builder(): Notification.Builder {
        ensureChannel()
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(activity, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(activity)
        }
    }

    private fun progress(done: Int, total: Int, title: String) {
        if (!canNotify() || total <= 0) return
        val n = builder()
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle("正在下载（$done/$total）")
            .setContentText(title)
            .setProgress(total, done, false)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
        manager.notify(TAG, 0, n)
    }

    private fun finish(done: Int, failed: Int) {
        if (!canNotify()) return
        val text = if (failed > 0) "完成 $done 首，失败 $failed 首" else "已保存到 Download/Listen1/Music"
        val n = builder()
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle(if (failed > 0) "下载结束" else "下载完成（$done 首）")
            .setContentText(text)
            .setAutoCancel(true)
            .build()
        manager.notify(TAG, 0, n)
    }

    companion object {
        private const val CHANNEL = "track_downloads"
        private const val TAG = "track_downloads"
    }
}
