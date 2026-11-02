package top.taipi.chestnut

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.workDataOf
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.TimeUnit

// 必须继承 FlutterFragmentActivity：local_auth 的 Android 生物识别
// 依赖 FragmentActivity（BiometricPrompt），FlutterActivity 会直接报错
class MainActivity : FlutterFragmentActivity() {

    companion object {
        private const val CHANNEL = "top.taipi.chestnut/system_downloader"
        private const val UPDATE_DIR = "updates"
        private const val REQ_POST_NOTIFICATIONS = 9001
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        // 交给 WorkManager 前台 Worker 下载（OkHttp + Range 续传）：
                        // App 退后台/被杀不中断，进度通知可点击回应用、可取消。
                        // 不再走系统 DownloadManager——vivo ROM 上任务会假死在排队态
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

    /**
     * 入队下载 Worker，返回不透明令牌 id。
     * 同一时刻至多一个下载任务（unique work + REPLACE），query/cancel 均按
     * unique name 定位，id 仅作 Dart 侧记录凭据，无路由意义
     */
    private fun startUpdateDownload(call: MethodCall): Long {
        val url = call.argument<String>("url")
            ?: throw IllegalArgumentException("url 必填")
        val fileName = call.argument<String>("fileName")
            ?: throw IllegalArgumentException("fileName 必填")
        val title = call.argument<String>("title") ?: "栗子记账更新包"

        ensureNotificationPermission()
        val request = OneTimeWorkRequestBuilder<UpdateDownloadWorker>()
            .setInputData(
                workDataOf(
                    UpdateDownloadWorker.KEY_URL to url,
                    UpdateDownloadWorker.KEY_FILE_NAME to fileName,
                    UpdateDownloadWorker.KEY_TITLE to title,
                ),
            )
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build(),
            )
            .setBackoffCriteria(BackoffPolicy.LINEAR, 10, TimeUnit.SECONDS)
            .build()
        WorkManager.getInstance(this).enqueueUniqueWork(
            UpdateDownloadWorker.UNIQUE_WORK_NAME,
            ExistingWorkPolicy.REPLACE,
            request,
        )
        return System.currentTimeMillis() / 1000
    }

    /**
     * 查询下载状态。状态码沿用 DownloadManager 常量以兼容 Dart 侧映射：
     * 1=排队 2=进行中 8=成功 16=失败；0=任务不存在
     */
    private fun queryDownload(call: MethodCall): Map<String, Any> {
        call.argument<Number>("id")
            ?: throw IllegalArgumentException("id 必填")
        val infos = WorkManager.getInstance(this)
            .getWorkInfosForUniqueWork(UpdateDownloadWorker.UNIQUE_WORK_NAME)
            .get(2, TimeUnit.SECONDS)
        val info = infos?.firstOrNull()
            ?: return mapOf("status" to 0, "received" to 0, "total" to -1)

        when (info.state) {
            WorkInfo.State.SUCCEEDED -> {
                val out = info.outputData
                return mapOf(
                    "status" to 8,
                    "received" to out.getInt(UpdateDownloadWorker.KEY_TOTAL, 0),
                    "total" to out.getInt(UpdateDownloadWorker.KEY_TOTAL, -1),
                    "localUri" to (out.getString(UpdateDownloadWorker.KEY_FILE_URI) ?: ""),
                    "reason" to 0,
                )
            }
            // CANCELLED 视为失败：正常取消后 Dart 侧已清记录不会再查询
            WorkInfo.State.FAILED, WorkInfo.State.CANCELLED ->
                return mapOf("status" to 16, "received" to 0, "total" to -1,
                    "localUri" to "", "reason" to 0)
            else -> Unit
        }
        val progress = info.progress
        val status = when (info.state) {
            WorkInfo.State.RUNNING -> 2
            else -> 1 // ENQUEUED / BLOCKED
        }
        return mapOf(
            "status" to status,
            "received" to progress.getInt(UpdateDownloadWorker.KEY_RECEIVED, 0),
            "total" to progress.getInt(UpdateDownloadWorker.KEY_TOTAL, -1),
            "localUri" to "",
            "reason" to 0,
        )
    }

    /** 取消下载任务；半成品文件保留（下次下载凭 Range 续传，cleanup 时统一清） */
    private fun cancelDownload(call: MethodCall): Int {
        call.argument<Number>("id")
            ?: throw IllegalArgumentException("id 必填")
        WorkManager.getInstance(this)
            .cancelUniqueWork(UpdateDownloadWorker.UNIQUE_WORK_NAME)
        return 1
    }

    /** Android 13+ 通知需运行时授权：入队时按需弹系统授权框（拒绝只影响通知可见性） */
    private fun ensureNotificationPermission() {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                REQ_POST_NOTIFICATIONS,
            )
        }
    }
}
