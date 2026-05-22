import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

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
/// All failures (network error, bad JSON, timeout) are silently swallowed —
/// the update check should never interrupt the user if something goes wrong.
class UpdateService {
  static const _versionJsonUrl =
      'https://raw.githubusercontent.com/PEEKYPAUL/moongate/master/APK/latest_version.json';

  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final info          = await PackageInfo.fromPlatform();
      final installedBuild = int.tryParse(info.buildNumber) ?? 0;

      final response = await http
          .get(Uri.parse(_versionJsonUrl))
          .timeout(const Duration(seconds: 8));

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
      return null; // silent fail — never bother the user with update check errors
    }
  }
}
