allprojects {
    repositories {
        // 国内镜像优先，官方源兜底（直连易超时）
        maven("https://maven.aliyun.com/repository/google")
        maven("https://maven.aliyun.com/repository/central")
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// amap_map 1.0.15 写死 compileSdk 35，而 flutter_plugin_android_lifecycle
// 2.0.35 的 AAR 元数据要求依赖方 compileSdk >= 36，这里强制对齐避免构建失败
subprojects {
    afterEvaluate {
        if (name == "amap_map") {
            extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)
                ?.compileSdk = 36
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
