import java.util.Properties

// (mobile_scanner 7.x pins its own CameraX 1.5.x — no manual force needed.
// We previously forced 1.4.0 to dodge a Samsung-specific NPE in mobile_scanner
// 5.x's CameraX 1.3.3, but the 7.x rewrite + 1.5.x supersedes that fix.)

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
    // v0.5.0: bonsoir 5.x transitively pulls in androidx.fragment 1.7.1 and
    // androidx.window 1.2.0, both of which need compileSdk 34+. Flutter's
    // stable channel default (flutter.compileSdkVersion) is still 33 in
    // 3.44, so override explicitly. compileSdk only controls which APIs the
    // build can compile against; it doesn't change minSdk or targetSdk, so
    // there's no runtime behaviour change for users on older Android.
    compileSdk = 36
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

            // Keep R8 enabled (it shrinks the APK by tens of MB) but apply
            // our own ProGuard rules on top of the default Android optimize
            // set.  Without proguard-rules.pro, R8 strips ML Kit's barcode
            // scanner internals (mobile_scanner 7.x's consumer rule uses a
            // single-dot wildcard that only matches the root package), and
            // the QR scanner crashes at first use with an obfuscated NPE.
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Note: com.wireguard.android:tunnel is not on any public Maven repo —
    // it is an internal module in the wireguard-android project and must be
    // compiled from Go source. WireGuard support is implemented via a stub
    // VPN service for now; native WireGuard-Go will be bundled in Phase 2.
}
