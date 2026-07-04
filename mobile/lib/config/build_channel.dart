/// Which distribution channel this build targets.
///
/// Moongate ships the SAME Flutter codebase down two Android channels that must
/// behave differently around app updates:
///
///  * [github] - the sideloaded APK from GitHub Releases (and the KIAUH
///    installer). It self-updates: checks APK/latest_version.json, downloads the
///    new release APK, and hands it to the system package installer. This build
///    carries REQUEST_INSTALL_PACKAGES (added by the `github` flavor's manifest).
///
///  * [play] - the Google Play App Bundle. Play forbids apps that download and
///    install their own APKs, so this build ships WITHOUT the self-updater and
///    WITHOUT REQUEST_INSTALL_PACKAGES; Google Play delivers updates itself.
///
/// The channel is chosen at build time with `--dart-define=MOONGATE_CHANNEL`,
/// paired with the matching Gradle `--flavor` (which selects the manifest):
///
///   flutter build apk       --release --flavor github --dart-define=MOONGATE_CHANNEL=github
///   flutter build appbundle --release --flavor play   --dart-define=MOONGATE_CHANNEL=play
///
/// The default is [github], so a bare `flutter run --flavor github` (and the
/// existing CI command, once it passes the flavor) behaves exactly as before.
enum BuildChannel { github, play }

const String _rawChannel =
    String.fromEnvironment('MOONGATE_CHANNEL', defaultValue: 'github');

const BuildChannel kBuildChannel =
    _rawChannel == 'play' ? BuildChannel.play : BuildChannel.github;

/// True only on the GitHub/KIAUH sideload build, where the app may download and
/// install its own APK. False on the Play build, which suppresses the update
/// check, the update banner, and the in-app installer - updates arrive through
/// Google Play instead. Being a compile-time `const`, the disabled path is
/// tree-shaken out of the Play binary.
const bool kSelfUpdateEnabled = kBuildChannel == BuildChannel.github;
