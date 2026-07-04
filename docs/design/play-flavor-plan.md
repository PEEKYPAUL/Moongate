# Play Store vs sideload: build-flavor split

## Why

Moongate is distributed three ways from one Flutter codebase:

- **GitHub Releases** (sideloaded APK) and **KIAUH** - the app self-updates by
  downloading the latest release APK and handing it to the system installer.
- **Google Play** (new) - Play **forbids** apps that download and install their
  own APKs, and restricts the `REQUEST_INSTALL_PACKAGES` permission. Play
  delivers updates itself.

Both must come from the same code, keep the same package name
(`com.moongate.app.moongate`) and the **same signing key** (cert `8878da71`), so
a user can move between the sideloaded APK and the Play build **in place, with no
re-pair and no wipe**. That continuity is the whole reason we registered the
existing key with Play App Signing.

## How: one Gradle flavor dimension, two flavors

`mobile/android/app/build.gradle.kts` defines a `distribution` dimension with two
flavors. Neither sets an `applicationIdSuffix`; both use the single `release`
buildType, so **package id and signing key are identical**. The flavor changes
only two things:

| | `github` (default) | `play` |
|---|---|---|
| Self-updater | kept | removed |
| `REQUEST_INSTALL_PACKAGES` | present | absent |
| Updater `FileProvider` | present | absent |
| `BuildConfig.SELF_UPDATE` | `true` | `false` |
| Ships as | `.apk` (GitHub Releases) | `.aab` (Play) |
| Updates via | in-app download + install | Google Play |

### The two mechanisms

1. **Manifest split.** `REQUEST_INSTALL_PACKAGES` and the updater `FileProvider`
   were moved out of `src/main/AndroidManifest.xml` into a new
   `src/github/AndroidManifest.xml`. The merger unions them into the github
   build (its final manifest is equivalent to pre-split); the play `.aab` simply
   never has them.

2. **Dart channel flag.** `mobile/lib/config/build_channel.dart` exposes
   `kSelfUpdateEnabled`, driven by `--dart-define=MOONGATE_CHANNEL` (paired with
   `--flavor`). It gates three spots:
   - `update_service.dart` - `checkForUpdate()` returns null on the play channel.
     This is the **primary gate**: with no update, the dashboard banner, the
     installer dialog, and the whole download path are unreachable (dead-code
     eliminated, since the flag is `const`).
   - `main.dart` - skips the leftover-APK cleanup (nothing is ever written).
   - `MainActivity.kt` - the native install `MethodChannel` is compiled out when
     `BuildConfig.SELF_UPDATE == false`, so the package-installer intent isn't
     even present in the Play binary.

## Build commands

```
# GitHub / KIAUH sideload (signed APK, self-updating) - behaviour identical to before
flutter build apk --release --flavor github --dart-define=MOONGATE_CHANNEL=github
#   -> mobile/build/app/outputs/flutter-apk/app-github-release.apk

# Play (App Bundle, no self-update, no install permission)
flutter build appbundle --release --flavor play --dart-define=MOONGATE_CHANNEL=play
#   -> mobile/build/app/outputs/bundle/playRelease/app-play-release.aab

# Local dev - flavors make --flavor MANDATORY now (a bare `flutter run` errors)
flutter run --flavor github
```

CI (`.github/workflows/build-android.yml`) builds the github APK (published to
GitHub Releases exactly as before) and the play `.aab` (uploaded as the
`Moongate-play-aab` workflow artifact for **manual** Play Console upload, never
auto-published - same posture as the iOS submit flow).

## What the Play build does about updates

Nothing active. Google Play auto-updates in the background. That is the correct,
policy-safe default. A nicer in-app nudge via Google's Play In-App Update API
(`in_app_update`, flavor-gated) is a good fast-follow once the app is live on
Play, but is not needed for v1.

## Operational caveats (read before shipping)

1. **Play App Signing key MUST be `8878da71`.** When creating the Play app,
   choose "use your own key" and upload the release keystore. If Google
   generates a fresh key, Play installs get a different signature and
   sideload<->Play becomes a **forced-uninstall wipe** (printers + cloud identity
   lost). Play Console action, do not get it wrong.

2. **Shared versionCode across channels.** Both flavors read the one build
   number from `pubspec.yaml`. Android only updates to a **strictly higher**
   build number, so cross-moving to the *same* build is a no-op (not a wipe).
   Let one channel lead on versioning if this matters.

3. **Foreground-service special-use is the most likely Play *rejection*.** The
   `FOREGROUND_SERVICE_SPECIAL_USE` service ships to Play too; it needs a Play
   Console review declaration for the subtype, and Google may push back toward
   `dataSync` (which reintroduces the Android 15 6h/day cap that breaks long
   prints). Prepare the justification.

4. **Debug-signing fallback unchanged (deliberate).** A `--release` build with no
   `key.properties` still falls back to debug signing (existing behaviour, for
   local `flutter run --release`). Play refuses debug-signed `.aab` uploads, so
   the Play path is safe; but only ever build the Play `.aab` in CI or on the
   work box (CDG-3D-TECH) that holds the keystore - never the psych box.

5. **`flutter run` / `flutter build` now require `--flavor github`.** Once
   flavors exist, the bare commands error "this app has flavors". Update local
   muscle-memory and any scripts.

6. **iOS is unaffected.** Android product flavors do not create iOS schemes;
   `flutter build ipa` needs no `--flavor`. Watch the (non-required) `Build iOS`
   check on the first CI run regardless.
