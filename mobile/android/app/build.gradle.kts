import java.util.Properties

// ─── Force CameraX 1.4.0 across all submodules ──────────────────────────────
// mobile_scanner 5.x ships CameraX 1.3.3, which has a Samsung-specific
// NullPointerException in Camera2CameraImpl.attachUseCases() — calling
// .getClass() on a transiently-null object during lifecycle binding.
// CameraX 1.4.0 fixes this.  The 1.3.x → 1.4.x API is fully compatible.
configurations.all {
    resolutionStrategy {
        force("androidx.camera:camera-core:1.4.0")
        force("androidx.camera:camera-camera2:1.4.0")
        force("androidx.camera:camera-lifecycle:1.4.0")
    }
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load signing config from key.properties if it exists (CI and local release builds).
// Falls back to debug signing when the file is absent (local debug builds).
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.reader())
}

android {
    namespace = "com.moongate.app.moongate"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.moongate.app.moongate"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias        = keystoreProperties["keyAlias"]        as String
                keyPassword     = keystoreProperties["keyPassword"]     as String
                storeFile       = file(keystoreProperties["storeFile"]  as String)
                storePassword   = keystoreProperties["storePassword"]   as String
            }
        }
    }

    buildTypes {
        release {
            // Use the release keystore in CI (key.properties present);
            // fall back to debug signing for local `flutter run --release`.
            signingConfig = if (keystorePropertiesFile.exists())
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Note: com.wireguard.android:tunnel is not on any public Maven repo —
    // it is an internal module in the wireguard-android project and must be
    // compiled from Go source. WireGuard support is implemented via a stub
    // VPN service for now; native WireGuard-Go will be bundled in Phase 2.
}
