plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseStoreFile = providers.gradleProperty("KISAN_DOST_RELEASE_STORE_FILE")
    .orElse(providers.environmentVariable("KISAN_DOST_RELEASE_STORE_FILE"))
    .orNull
val releaseStorePassword = providers.gradleProperty("KISAN_DOST_RELEASE_STORE_PASSWORD")
    .orElse(providers.environmentVariable("KISAN_DOST_RELEASE_STORE_PASSWORD"))
    .orNull
val releaseKeyAlias = providers.gradleProperty("KISAN_DOST_RELEASE_KEY_ALIAS")
    .orElse(providers.environmentVariable("KISAN_DOST_RELEASE_KEY_ALIAS"))
    .orNull
val releaseKeyPassword = providers.gradleProperty("KISAN_DOST_RELEASE_KEY_PASSWORD")
    .orElse(providers.environmentVariable("KISAN_DOST_RELEASE_KEY_PASSWORD"))
    .orNull
val releaseSigningConfigured = listOf(
    releaseStoreFile,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }
val allowUnsignedRelease = providers.gradleProperty("KISAN_DOST_ALLOW_UNSIGNED_RELEASE")
    .orElse(providers.environmentVariable("KISAN_DOST_ALLOW_UNSIGNED_RELEASE"))
    .orNull == "true"
val androidAppProject = project

gradle.taskGraph.whenReady {
    val includesRelease = allTasks.any {
        it.project == androidAppProject && it.name.contains("release", ignoreCase = true)
    }
    if (includesRelease && !releaseSigningConfigured && !allowUnsignedRelease) {
        throw GradleException(
            "Release signing is not configured. Set KISAN_DOST_RELEASE_STORE_FILE, " +
                "KISAN_DOST_RELEASE_STORE_PASSWORD, KISAN_DOST_RELEASE_KEY_ALIAS, and " +
                "KISAN_DOST_RELEASE_KEY_PASSWORD. For local unsigned verification only, " +
                "set KISAN_DOST_ALLOW_UNSIGNED_RELEASE=true."
        )
    }
}

android {
    namespace = "com.example.kisan_dost"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // Keep this application ID until the Play Console owner confirms the production ID.
        applicationId = "com.example.kisan_dost"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningConfigured) {
            create("production") {
                storeFile = file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            // Never sign production releases with the shared Android debug key.
            signingConfig = if (releaseSigningConfigured) {
                signingConfigs.getByName("production")
            } else {
                null
            }
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    implementation("com.google.android.material:material:1.9.0")
}
