package top.taipi.chestnut

import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import androidx.work.WorkManager
import java.io.File
import java.util.concurrent.TimeUnit

/** 下载通知的回调：进度条上的"取消"，以及完成通知点击直接拉安装器 */
class UpdateDownloadReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            UpdateDownloadWorker.ACTION_CANCEL -> {
                WorkManager.getInstance(context)
                    .cancelUniqueWork(UpdateDownloadWorker.UNIQUE_WORK_NAME)
                notificationManager(context).apply {
                    cancel(UpdateDownloadWorker.FGS_NOTIFICATION_ID)
                    cancel(UpdateDownloadWorker.FINAL_NOTIFICATION_ID)
                }
            }
            UpdateDownloadWorker.ACTION_INSTALL -> install(context)
        }
    }

    /** 安装器无法拉起（如未知来源被禁）时兜底回应用，由应用内恢复流程接管 */
    private fun install(context: Context) {
        val apk = findApk(context)
        if (apk != null) {
            val uri = FileProvider.getUriForFile(
                context,
                "${context.packageName}.fileprovider",
                apk,
            )
            val installer = Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_ACTIVITY_NEW_TASK,
                )
            try {
                context.startActivity(installer)
                notificationManager(context).cancel(UpdateDownloadWorker.FINAL_NOTIFICATION_ID)
                return
            } catch (_: ActivityNotFoundException) {
                // 落到兜底
            }
        }
        context.startActivity(
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }

    private fun findApk(context: Context): File? {
        val infos = try {
            WorkManager.getInstance(context)
                .getWorkInfosForUniqueWork(UpdateDownloadWorker.UNIQUE_WORK_NAME)
                .get(2, TimeUnit.SECONDS)
        } catch (_: Exception) {
            null
        }
        val path = infos?.firstOrNull()?.outputData?.getString(UpdateDownloadWorker.KEY_FILE_URI)
            ?.let { Uri.parse(it).path }
        val file = path?.let { File(it) }
        return if (file != null && file.exists()) file else null
    }

    private fun notificationManager(context: Context): NotificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
}
