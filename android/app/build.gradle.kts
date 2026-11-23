plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Must come after the Android plugin.
    id("com.chaquo.python")
}

android {
    namespace = "com.example.pdf_watermark_remover"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.pdf_watermark_remover"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // The engine's native libraries (PDFium, Pillow) are shipped for 64-bit ARM phones.
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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

// Python runs inside the app. The engine package comes straight from ../../processing_engine,
// and `pdfwm_mobile.py` (src/main/python) is the entry point called from MainActivity.
chaquopy {
    defaultConfig {
        version = "3.13"
        pip {
            install("pypdf==7.1.0")
            install("pypdfium2==5.15.2")
            // Pillow comes from Chaquopy's own Android builds (no Android wheels on PyPI).
            install("Pillow==11.0.0")
        }
        // pypdfium2 loads libpdfium.so and its version.json by file path, so these two
        // packages must be unpacked to real files instead of being read from the APK.
        extractPackages("pypdfium2", "pypdfium2_raw")
    }
    sourceSets {
        getByName("main") {
            srcDir("src/main/python")
            srcDir("../../processing_engine")
            include("pdfwm_mobile.py", "pdf_watermark_engine/**/*.py")
        }
    }
}
