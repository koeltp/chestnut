package top.taipi.chestnut

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import java.io.File
import java.io.IOException
import java.security.MessageDigest
import java.io.RandomAccessFile
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request

/**
 * 应用内更新包下载器：OkHttp + Range 断点续传，跑在前台 Worker 里。
 *
 * 替代系统 DownloadManager——实测 vivo ROM 上系统下载器任务会假死在
 * 排队态（网络就绪也不开跑），且通知不可定制。
 *
 * 行为约定（与 Dart 侧 SystemDownloader 的通道契约对齐）：
 * - 进度经 setProgress 上报（received/total），MainActivity.query 透传给 Dart；
 * - 半成品文件保留在 updates/ 目录，重试/停止后凭 Range 头续传；
 * - 成功落盘后发"点击安装"通知；失败在重试耗尽后发失败通知；
 * - 校验（sha256/fileSize）与安装仍由 Dart 侧 UpdateService 负责。
 */
class UpdateDownloadWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {

    companion object {
        const val UNIQUE_WORK_NAME = "update_apk_download"
        const val KEY_URL = "url"
        const val KEY_FILE_NAME = "fileName"
        const val KEY_TITLE = "title"
        const val KEY_RECEIVED = "received"
        const val KEY_TOTAL = "total"
        const val KEY_FILE_URI = "fileUri"
        const val KEY_SHA256 = "sha256"
        const val KEY_FILE_SIZE = "fileSize"
        const val ACTION_CANCEL = "top.taipi.chestnut.action.CANCEL_UPDATE_DOWNLOAD"
        const val ACTION_INSTALL = "top.taipi.chestnut.action.INSTALL_UPDATE"

        private const val CHANNEL_ID = "update_download"
        const val FGS_NOTIFICATION_ID = 1001
        const val FINAL_NOTIFICATION_ID = 1002
        private const val MAX_ATTEMPTS = 5
        private const val PROGRESS_INTERVAL_MS = 500L

        // REPLACE 策略下新 Worker 可能与旧 Worker 短暂并存，串行化写盘避免互踩
        private val writeMutex = Mutex()
    }

    private val appContext = applicationContext

    override suspend fun doWork(): Result {
        val url = inputData.getString(KEY_URL) ?: return Result.failure()
        val fileName = inputData.getString(KEY_FILE_NAME) ?: return Result.failure()
        val title = inputData.getString(KEY_TITLE) ?: "栗子记账更新包"

        setForeground(createForegroundInfo(title, 0, -1))
        ensureChannel()

        return try {
            val file = downloadToFile(url, fileName, title)
            verifyFile(file)
            notifyDone(title)
            Result.success(
                workDataOf(
                    KEY_FILE_URI to Uri.fromFile(file).toString(),
                    KEY_TOTAL to file.length().toInt(),
                ),
            )
        } catch (e: CancellationException) {
            // 被取消（用户取消/约束变更）：半成品留给下次续传，不算失败
            throw e
        } catch (e: Exception) {
            if (runAttemptCount + 1 >= MAX_ATTEMPTS) {
                notifyFailed(title)
                Result.failure()
            } else {
                Result.retry()
            }
        }
    }

    /** 下载主体：目标同名残包存在则带 Range 续传，服务器不支持时从头重下 */
    private suspend fun downloadToFile(url: String, fileName: String, title: String): File =
        withContext(Dispatchers.IO) {
            val target = updateDir(fileName)
            writeMutex.withLock {
                val received0 = if (target.exists()) target.length() else 0L
                val requestBuilder = Request.Builder().url(url)
                if (received0 > 0) {
                    requestBuilder.header("Range", "bytes=$received0-")
                }
                val client = OkHttpClient.Builder()
                    .connectTimeout(20, TimeUnit.SECONDS)
                    .readTimeout(30, TimeUnit.SECONDS)
                    .build()
                client.newCall(requestBuilder.build()).execute().use { resp ->
                    when {
                        // 已有字节超出服务器文件末端（换包/清理不一致）：删残包重来
                        resp.code == 416 -> {
                            target.delete()
                            throw IOException("Range 416，残包已清理待重下")
                        }
                        resp.code != 200 && resp.code != 206 ->
                            throw IOException("HTTP ${resp.code}")
                    }
                    val body = resp.body ?: throw IOException("空响应体")
                    var received = received0
                    // 206 的 Content-Length 是剩余区间的长度
                    val total = if (resp.code == 206) {
                        received + body.contentLength()
                    } else {
                        received = 0
                        target.delete()
                        target.parentFile?.mkdirs()
                        target.createNewFile()
                        body.contentLength()
                    }
                    RandomAccessFile(target, "rw").use { raf ->
                        raf.seek(received)
                        val buf = ByteArray(64 * 1024)
                        body.byteStream().use { input ->
                            var lastTick = 0L
                            while (true) {
                                if (isStopped) {
                                    // 停止（取消/约束变更/超时）：保留半成品供续传
                                    throw CancellationException("worker stopped")
                                }
                                val n = input.read(buf)
                                if (n < 0) break
                                raf.write(buf, 0, n)
                                received += n
                                val now = SystemClock.elapsedRealtime()
                                if (now - lastTick >= PROGRESS_INTERVAL_MS) {
                                    lastTick = now
                                    updateProgress(title, received, total)
                                }
                            }
                        }
                    }
                }
                target
            }
        }

    /** 双通道上报进度：通知栏刷进度条 + setProgress 供 Dart 轮询查询 */
    private suspend fun updateProgress(title: String, received: Long, total: Long) {
        val data = workDataOf(
            KEY_RECEIVED to received.toInt(),
            KEY_TOTAL to total.toInt(),
        )
        setProgress(data)
        notificationManager()
            .notify(FGS_NOTIFICATION_ID, buildNotification(title, received, total))
    }

    override suspend fun getForegroundInfo(): ForegroundInfo {
        val title = inputData.getString(KEY_TITLE) ?: "栗子记账更新包"
        return createForegroundInfo(title, 0, -1)
    }

    private fun createForegroundInfo(title: String, received: Long, total: Long): ForegroundInfo {
        ensureChannel()
        val notification = buildNotification(title, received, total)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ForegroundInfo(
                FGS_NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            ForegroundInfo(FGS_NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(title: String, received: Long, total: Long): Notification {
        val contentIntent = PendingIntent.getActivity(
            appContext,
            0,
            Intent(appContext, MainActivity::class.java).setFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK,
            ),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val cancelIntent = PendingIntent.getBroadcast(
            appContext,
            0,
            Intent(appContext, UpdateDownloadReceiver::class.java).setAction(ACTION_CANCEL),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(appContext, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle(title)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setContentIntent(contentIntent)
            .setProgress(100, 0, total <= 0)
            .apply {
                if (total > 0) {
                    val percent = ((received * 100) / total).toInt().coerceIn(0, 100)
                    setProgress(100, percent, false)
                    setContentText("$percent% · ${received / 1_000_000}/${total / 1_000_000} MB")
                } else {
                    setContentText("正在下载…")
                }
            }
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "取消",
                cancelIntent,
            )
            .build()
    }

    /** 校验不通过删掉文件抛异常 → Result.retry() 从头重下，最多 MAX_ATTEMPTS 次 */
    private fun verifyFile(file: File) {
        val expectedSize = inputData.getInt(KEY_FILE_SIZE, -1)
        if (expectedSize > 0 && file.length() != expectedSize.toLong()) {
            file.delete()
            throw IOException("文件大小不符（${file.length()} / $expectedSize）")
        }
        val expectedSha = inputData.getString(KEY_SHA256)
        if (!expectedSha.isNullOrEmpty()) {
            val actual = file.inputStream().use { input ->
                val digest = MessageDigest.getInstance("SHA-256")
                val buf = ByteArray(64 * 1024)
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    digest.update(buf, 0, n)
                }
                digest.digest().joinToString("") { "%02x".format(it) }
            }
            if (!actual.equals(expectedSha, ignoreCase = true)) {
                file.delete()
                throw IOException("SHA-256 校验失败（$actual）")
            }
        }
    }

    /** 下载完成通知：点击直接拉系统安装器（Receiver），拉不起再回应用 */
    private fun notifyDone(title: String) {
        val installIntent = PendingIntent.getBroadcast(
            appContext,
            0,
            Intent(appContext, UpdateDownloadReceiver::class.java).setAction(ACTION_INSTALL),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification = NotificationCompat.Builder(appContext, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle(title)
            .setContentText("下载完成，点击安装")
            .setAutoCancel(true)
            .setOngoing(false)
            .setContentIntent(installIntent)
            .build()
        notificationManager().notify(FINAL_NOTIFICATION_ID, notification)
    }

    private fun notifyFailed(title: String) {
        val notification = NotificationCompat.Builder(appContext, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle(title)
            .setContentText("下载失败，请打开应用重试")
            .setAutoCancel(true)
            .setOngoing(false)
            .build()
        notificationManager().notify(FINAL_NOTIFICATION_ID, notification)
    }

    private fun notificationManager(): NotificationManager =
        appContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notificationManager().createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "更新下载",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply { description = "应用内更新包下载进度" },
            )
        }
    }

    private fun updateDir(fileName: String): File {
        val root = appContext.getExternalFilesDir(null)
            ?: throw IOException("外部存储不可用")
        return File(File(root, "updates").apply { mkdirs() }, fileName)
    }
}
