import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeys = Properties()
val releaseKeyFile = rootProject.file("key.properties")
if (releaseKeyFile.exists()) {
    releaseKeyFile.inputStream().use { releaseKeys.load(it) }
}

android {
    namespace = "dev.zeroplayer.zero_player"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.zeroplayer.zero_player"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        // Match the Dart AOT targets; do not advertise partial 32-bit native support.
        ndk {
            abiFilters.clear()
            // AGP forbids ndk.abiFilters together with Flutter's ABI splits.
            if (project.findProperty("split-per-abi") != "true") {
                abiFilters.addAll(listOf("arm64-v8a", "x86_64"))
            }
        }
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseKeyFile.exists()) {
            create("release") {
                storeFile = file(releaseKeys.getProperty("storeFile"))
                storePassword = releaseKeys.getProperty("storePassword")
                keyAlias = releaseKeys.getProperty("keyAlias")
                keyPassword = releaseKeys.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

// Fail a release build explicitly instead of producing unsigned artifacts.
tasks.configureEach {
    if (name == "validateSigningRelease" || name == "packageRelease" || name == "packageReleaseBundle") {
        doFirst {
            check(releaseKeyFile.exists()) {
                "Release signing is missing. See docs/implementation/BUILD.md."
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
