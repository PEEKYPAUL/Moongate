import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../config/build_channel.dart';

/// Information about an available update fetched from GitHub.
class UpdateInfo {
  final String version;
  final int    buildNumber;
  final String apkUrl;

  const UpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.apkUrl,
  });
}

/// Checks whether a newer APK has been published to the GitHub repo.
///
/// CI writes APK/latest_version.json on every master build.  This service
/// fetches that file and compares its build number against the installed one.
/// Returns [UpdateInfo] when a newer build exists, null otherwise.
/// All failures (network error, bad JSON, timeout) are silently swallowed -
/// the update check should never interrupt the user if something goes wrong.
class UpdateService {
  static const _versionJsonUrl =
      'https://raw.githubusercontent.com/PEEKYPAUL/moongate/master/APK/latest_version.json';

  Future<UpdateInfo?> checkForUpdate() async {
    // Android only: this self-update path tracks the GitHub APK build. On iOS
    // the App Store handles updates, and the manifest's build number / apk_url
    // refer to the Android build - surfacing them on an iPhone is meaningless
    // (you can't install an APK) and pointing users at an off-store download is
    // an App Store review risk. Returning null suppresses the update banner and
    // the in-app updater on iOS; the "What's new" changelog still shows.
    //
    // Same on the Play channel (kSelfUpdateEnabled == false): Google Play
    // delivers updates and REQUEST_INSTALL_PACKAGES is absent from that build's
    // manifest, so the self-updater must stay dark. See config/build_channel.dart.
    if (!Platform.isAndroid || !kSelfUpdateEnabled) return null;
    try {
      final info          = await PackageInfo.fromPlatform();
      final installedBuild = int.tryParse(info.buildNumber) ?? 0;

      // Cache-buster: GitHub's raw CDN caches files for ~5 min by default.
      // Without this, an unlucky timing window - user opens the app right
      // before CI publishes a new manifest - leaves them on a stale "no
      // update" result for several minutes.  Appending a per-request timestamp
      // forces a cold hit.
      final url = Uri.parse(
          '$_versionJsonUrl?cb=${DateTime.now().millisecondsSinceEpoch}');

      final response = await http.get(
        url,
        // Belt-and-braces: also ask any HTTP cache (proxy, OS) not to use a
        // cached body.  The cache-buster above already handles CDN; this is
        // for clients that ignore query strings when caching.
        headers: const {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;

      final body        = jsonDecode(response.body) as Map<String, dynamic>;
      final latestBuild = (body['build_number'] as num).toInt();
      final version     = body['version']    as String;
      final apkUrl      = body['apk_url']    as String;

      if (latestBuild > installedBuild) {
        return UpdateInfo(version: version, buildNumber: latestBuild, apkUrl: apkUrl);
      }
      return null; // already up to date
    } catch (_) {
      return null; // silent fail - never bother the user with update check errors
    }
  }
}
