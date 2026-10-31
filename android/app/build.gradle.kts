import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeys = Properties()
// Uppercase survives Windows environment normalization through Flutter/Dart.
val deviceTestBuild = providers.gradleProperty("ZERO_PLAYER_DEVICE_TEST").orNull == "true"
val releaseKeyFile = rootProject.file("key.properties")
if (releaseKeyFile.exists()) {
    releaseKeyFile.inputStream().use { releaseKeys.load(it) }
}

android {
    namespace = "dev.zeroplayer.zero_player"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    packaging {
        // APK downloads stay compact; Android extracts native libraries once
        // at installation. Preserve all codecs, fonts, and selected ABIs.
        jniLibs.useLegacyPackaging = true
        jniLibs.excludes += setOf("**/libonnxruntime.so", "**/libsherpa-onnx-c-api.so", "**/libsherpa-onnx-cxx-api.so")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.zeroplayer.zero_player"
        if (deviceTestBuild) applicationIdSuffix = ".devtest"
        manifestPlaceholders["appLabel"] = if (deviceTestBuild) "Zero Player 测试" else "Zero Player"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        // Match the Dart AOT targets; do not advertise partial 32-bit native support.
        ndk {
            abiFilters.clear()
            // AGP forbids ndk.abiFilters together with Flutter's ABI splits.
            if (project.findProperty("split-per-abi") != "true") {
                // Keep emulator binaries out of an explicitly arm64 phone build.
                val targets = (project.findProperty("target-platform") as? String
                    ?: "android-arm64").split(",")
                if ("android-arm64" in targets) abiFilters.add("arm64-v8a")
                if ("android-x64" in targets) abiFilters.add("x86_64")
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
            isMinifyEnabled = true
            isShrinkResources = true
            signingConfig = if (deviceTestBuild) signingConfigs.getByName("debug") else signingConfigs.findByName("release")
        }
    }
}

// Fail a release build explicitly instead of producing unsigned artifacts.
tasks.configureEach {
    if (name == "validateSigningRelease" || name == "packageRelease" || name == "packageReleaseBundle") {
        doFirst {
            check(deviceTestBuild || releaseKeyFile.exists()) {
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

// Both Dart FFI clients use sherpa's bundled libonnxruntime.so. Exclude the
// second Maven distribution instead of choosing an ABI-dependent pickFirst.
configurations.configureEach {
    exclude(group = "com.microsoft.onnxruntime", module = "onnxruntime-android")
}
