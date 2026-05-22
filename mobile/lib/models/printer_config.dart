import 'dart:convert';

class PrinterConfig {
  final String id;
  final String name;

  /// Local network address, e.g. "192.168.1.50:80".
  /// Used when the phone is on the same WiFi as the printer.
  final String host;

  final String token;

  /// Cloudflare Tunnel URL, e.g. "https://xxxx.trycloudflare.com".
  /// Used for remote access from any network — null until the tunnel
  /// is set up on the Pi (cloudflared service running).
  final String? remoteHost;

  const PrinterConfig({
    required this.id,
    required this.name,
    required this.host,
    required this.token,
    this.remoteHost,
  });

  PrinterConfig copyWith({String? name, String? remoteHost}) => PrinterConfig(
        id: id,
        name: name ?? this.name,
        host: host,
        token: token,
        remoteHost: remoteHost ?? this.remoteHost,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'token': token,
        if (remoteHost != null) 'remoteHost': remoteHost,
      };

  factory PrinterConfig.fromJson(Map<String, dynamic> j) => PrinterConfig(
        id: j['id'] as String,
        name: j['name'] as String,
        host: j['host'] as String,
        token: j['token'] as String,
        remoteHost: j['remoteHost'] as String?,
      );

  static List<PrinterConfig> listFromJson(String raw) {
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => PrinterConfig.fromJson(e as Map<String, dynamic>)).toList();
  }

  static String listToJson(List<PrinterConfig> printers) =>
      jsonEncode(printers.map((p) => p.toJson()).toList());
}

/// Whether the last successful status poll used the local IP or the tunnel.
enum PrinterConnection { local, remote, offline }

class PrinterStatus {
  final String state; // 'printing' | 'paused' | 'standby' | 'error' | 'offline'
  final double progress; // 0.0 – 1.0
  final double hotendTemp;
  final double hotendTarget;
  final double bedTemp;
  final double bedTarget;
  final String? filename;

  /// Which network path was used to reach the printer.
  final PrinterConnection connection;

  /// Webcam snapshot path as reported by Moonraker (e.g. "/webcam/?action=snapshot"
  /// for mjpeg-streamer, "/webcam/snapshot" for Crowsnest/uStreamer).
  /// Null until first successful poll; fall back to the mjpeg-streamer default.
  final String? webcamSnapshotPath;

  const PrinterStatus({
    required this.state,
    required this.progress,
    required this.hotendTemp,
    required this.hotendTarget,
    required this.bedTemp,
    required this.bedTarget,
    this.filename,
    this.connection = PrinterConnection.offline,
    this.webcamSnapshotPath,
  });

  bool get isPrinting => state == 'printing' || state == 'paused';
  bool get isIdle => state == 'standby';

  static const offline = PrinterStatus(
    state: 'offline',
    progress: 0,
    hotendTemp: 0,
    hotendTarget: 0,
    bedTemp: 0,
    bedTarget: 0,
    connection: PrinterConnection.offline,
  );
}
