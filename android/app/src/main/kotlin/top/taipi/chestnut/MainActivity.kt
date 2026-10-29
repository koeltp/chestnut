package top.taipi.chestnut

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

// 必须继承 FlutterFragmentActivity：local_auth 的 Android 生物识别
// 依赖 FragmentActivity（BiometricPrompt），FlutterActivity 会直接报错
class MainActivity : FlutterFragmentActivity() {

    companion object {
        private const val CHANNEL = "top.taipi.chestnut/system_downloader"
        private const val UPDATE_DIR = "updates"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        // 交给系统 DownloadManager 下载：App 退后台/被冻结不影响，
                        // 断网重连与断点续传由系统自理
                        "start" -> result.success(startUpdateDownload(call))
                        "query" -> result.success(queryDownload(call))
                        "cancel" -> result.success(cancelDownload(call))
                        // 清空更新目录里历次下载的残留 APK
                        "cleanup" -> {
                            updateDir().listFiles()?.forEach { it.delete() }
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("DOWNLOAD_ERROR", e.message ?: e.javaClass.simpleName, null)
                }
            }
    }

    /** 更新包下载目录：App 外部专属空间，无需存储权限，卸载即清 */
    private fun updateDir(): File {
        val root = getExternalFilesDir(null)
            ?: throw IllegalStateException("外部存储不可用")
        return File(root, UPDATE_DIR).apply { mkdirs() }
    }

    private fun downloadManager(): DownloadManager =
        getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager

    /** 入队系统下载，返回 downloadId；目标同名残包先删除避免入队冲突 */
    private fun startUpdateDownload(call: MethodCall): Long {
        val url = call.argument<String>("url")
            ?: throw IllegalArgumentException("url 必填")
        val fileName = call.argument<String>("fileName")
            ?: throw IllegalArgumentException("fileName 必填")
        val title = call.argument<String>("title") ?: "栗子记账更新包"

        val target = File(updateDir(), fileName)
        if (target.exists()) target.delete()

        val request = DownloadManager.Request(Uri.parse(url))
            .setTitle(title)
            .setDescription("栗子记账")
            .setMimeType("application/vnd.android.package-archive")
            .setNotificationVisibility(
                DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED
            )
            .setDestinationInExternalFilesDir(this, null, "$UPDATE_DIR/$fileName")
        return downloadManager().enqueue(request)
    }

    /** 查询单条下载状态；记录不存在（已被系统清理/从未入队）返回 status=0 */
    private fun queryDownload(call: MethodCall): Map<String, Any> {
        val id = call.argument<Number>("id")?.toLong()
            ?: throw IllegalArgumentException("id 必填")
        val query = DownloadManager.Query().setFilterById(id)
        downloadManager().query(query).use { cursor ->
            if (!cursor.moveToFirst()) {
                return mapOf("status" to 0, "received" to 0, "total" to -1)
            }
            fun col(name: String): Int =
                cursor.getInt(cursor.getColumnIndexOrThrow(name))
            return mapOf(
                "status" to col(DownloadManager.COLUMN_STATUS),
                "received" to col(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR),
                "total" to col(DownloadManager.COLUMN_TOTAL_SIZE_BYTES),
                "localUri" to (cursor.getString(
                    cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI)
                ) ?: ""),
                "reason" to col(DownloadManager.COLUMN_REASON),
            )
        }
    }

    /** 取消并删除下载（含已落盘/半途文件），返回被移除的记录数 */
    private fun cancelDownload(call: MethodCall): Int {
        val id = call.argument<Number>("id")?.toLong()
            ?: throw IllegalArgumentException("id 必填")
        return downloadManager().remove(id).toInt()
    }
}
