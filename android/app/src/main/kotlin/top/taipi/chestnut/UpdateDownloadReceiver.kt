package top.taipi.chestnut

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.work.WorkManager

/** 下载进度通知上"取消"按钮的回调：停掉 Worker 并清掉通知 */
class UpdateDownloadReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != UpdateDownloadWorker.ACTION_CANCEL) return
        WorkManager.getInstance(context)
            .cancelUniqueWork(UpdateDownloadWorker.UNIQUE_WORK_NAME)
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
            as NotificationManager
        nm.cancel(UpdateDownloadWorker.FGS_NOTIFICATION_ID)
        nm.cancel(UpdateDownloadWorker.FINAL_NOTIFICATION_ID)
    }
}
