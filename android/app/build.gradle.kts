import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 签名信息从本地 key.properties 读取（该文件不入库，见 .gitignore）
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "top.taipi.chestnut"
    compileSdk = flutter.compileSdkVersion
    // 不显式声明 ndkVersion：本项目无原生代码，debug 构建不需要 NDK；
    // 而新版 Android CLI 无法自动安装 NDK（包索引加载失败），
    // 显式声明反而会触发强制校验导致构建失败。

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "top.taipi.chestnut"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // 统一使用自建证书签名：debug 与 release 同签名，
    // 日常调试与正式发布的 SHA1 一致（高德等平台鉴权不用换）
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

    buildTypes {
        debug {
            // 双包共存：Dev 包名加 .debug 后缀，与生产包数据完全隔离，
            // flutter run / 真机调试永远落在此包，绝不触碰生产包真实数据。
            // 注意：高德 Android Key 按包名绑定，Dev 包需用控制台中
            // chestnut_dev 这个 Key（Dart 侧 kReleaseMode 切换 +
            // src/debug/AndroidManifest.xml 覆写 meta-data）
            applicationIdSuffix = ".debug"
            signingConfig = signingConfigs.getByName("release")
        }
        release {
            signingConfig = signingConfigs.getByName("release")
            // R8 混淆 + 资源收缩：减小 APK 体积（高德 SDK 占比较大）。
            // keep 规则见 proguard-rules.pro，改动后需真机回归地图/定位功能
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
