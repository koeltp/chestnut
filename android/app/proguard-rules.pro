# 栗子记账 release 混淆规则
#
# Flutter 引擎与插件的 keep 规则由 Flutter Gradle 插件自动注入，
# 这里只需补充三方 SDK 的显式 keep（高德 SDK 内部有反射与 JNI 调用）。

# ---------- 高德地图 SDK（amap_map / x_amap_base 底层） ----------
# 地图渲染走 JNI + 反射加载资源类，混淆会导致黑屏/闪退
-keep class com.amap.api.** {*;}
-keep class com.autonavi.** {*;}
-keep class com.loc.** {*;}
-dontwarn com.amap.api.**
-dontwarn com.autonavi.**

# ---------- 应用内更新下载（WorkManager） ----------
# Worker 类名会被持久化进 WorkManager 数据库，升级安装后按名反射恢复；
# 混淆改名会导致历史下载任务无法恢复
-keep class top.taipi.chestnut.UpdateDownloadWorker { *; }
-keep class top.taipi.chestnut.UpdateDownloadReceiver { *; }

# WorkManager 内置 Room 数据库（WorkDatabase）在初始化时按名反射实例化
# 生成的 *_Impl 类；R8 会裁掉未显式引用的构造器，导致启动即崩
# （NoSuchMethodException: WorkDatabase_Impl.<init>，仅 release 包出现）
-keep class * extends androidx.room.RoomDatabase {
    <init>();
}
-keep class androidx.room.RoomDatabase { <init>(); }
