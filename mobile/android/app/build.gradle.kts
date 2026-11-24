import java.util.Properties

// (mobile_scanner 7.x pins its own CameraX 1.5.x - no manual force needed.
// We previously forced 1.4.0 to dodge a Samsung-specific NPE in mobile_scanner
// 5.x's CameraX 1.3.3, but the 7.x rewrite + 1.5.x supersedes that fix.)

plugins {
    id("com.android.application")
    // Declared explicitly (Flutter would apply KGP itself with builtInKotlin
    // off) so the Compose compiler plugin below has a Kotlin plugin to attach
    // to: the home-screen widget is Jetpack Glance, whose @Composable layouts
    // need the Compose compiler. Nothing else in the app uses Compose.
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
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

    buildFeatures {
        // Generate BuildConfig so MainActivity can compile the APK-installer
        // channel out of the Play flavor (SELF_UPDATE == false). AGP 8+/9
        // defaults this OFF, so enable it explicitly.
        buildConfig = true
        // NOTE: `compose` is left unset on purpose. AGP 9 turns the feature on
        // by itself when it sees the Compose compiler plugin (the Glance
        // widget) and ignores an explicit `false` with a warning.
    }

    // AGP 9.5 wires its Compose Preview tooling into every variant once the
    // Compose compiler plugin is applied, and that tooling refuses to configure
    // unless unit tests exist for the variant AND see Android resources
    // (otherwise `flutter build apk --release` dies at configuration time with
    // "Compose Preview failed ... Unit tests are disabled for this variant").
    // There are no Android unit tests or previews in this app, so switching
    // both on is free: nothing extra runs in an assemble.
    testOptions {
        unitTests.isIncludeAndroidResources = true
    }

    // Distribution channels. BOTH keep the same applicationId and are built by
    // the single `release` buildType (so the same signing key, cert 8878da71),
    // which is what lets a device move between the sideloaded APK and the Play
    // build in place - no re-pair, no wipe. The flavor changes ONLY the merged
    // manifest (REQUEST_INSTALL_PACKAGES + the updater FileProvider live in
    // src/github) and the SELF_UPDATE BuildConfig flag - never the package id
    // or the key. Do NOT add an applicationIdSuffix to either.
    flavorDimensions += "distribution"
    productFlavors {
        create("github") {
            dimension = "distribution"
            buildConfigField("boolean", "SELF_UPDATE", "true")
        }
        create("play") {
            dimension = "distribution"
            buildConfigField("boolean", "SELF_UPDATE", "false")
        }
    }
}

androidComponents {
    // See the testOptions note above: the release variants arrive here with
    // unit tests switched off, which AGP's Compose Preview wiring rejects.
    beforeVariants(selector().all()) { variant ->
        (variant as? com.android.build.api.variant.HasHostTestsBuilder)
            ?.hostTests
            ?.get(com.android.build.api.variant.HostTestBuilder.UNIT_TEST_TYPE)
            ?.enable = true
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")

    // Home-screen widget (v0.9.79): Jetpack Glance renders the fleet snapshot
    // the print-notification isolate writes through home_widget (which itself
    // depends on glance-appwidget 1.2.0 - keep these on the same line).
    // glance-material3 supplies the Material 3 colour scheme the widget falls
    // back to below Android 12, where there is no dynamic colour.
    implementation("androidx.glance:glance-appwidget:1.2.0")
    implementation("androidx.glance:glance-material3:1.2.0")
    // glance-material3 only carries Material 3 at runtime scope; the widget
    // calls lightColorScheme / darkColorScheme itself, so it needs the compile
    // dependency too. Same version glance-material3 1.2.0 already resolves.
    implementation("androidx.compose.material3:material3:1.0.0")
}
