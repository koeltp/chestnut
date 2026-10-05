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
