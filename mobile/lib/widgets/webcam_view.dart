import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;

import '../l10n/app_localizations.dart';
import '../providers/settings_provider.dart';
import '../services/webcam_fetch_diag.dart';

/// How long a frameless camera shows the "waking up" spinner before falling
/// back to the honest plain placeholder. Generous on purpose: a go2rtc
/// producer wakes in under a second, uv4l has been seen taking 3 s+, and a
/// remote data-saver cadence only attempts a frame every few seconds - the
/// window has to survive several slow attempts before giving up.
const _kWakeWindow = Duration(seconds: 25);

// ── Shared webcam renderer ────────────────────────────────────────────────────
//
// Self-paced snapshot-fetch loop, shared between the dashboard tile preview and
// the full-screen printer camera view. We pull each snapshot ourselves with
// `http.get` and only schedule the next fetch *after* the current one resolves
// - successful, errored, or timed out. The effective frame rate self-adapts to
// whatever the webcam server can actually deliver: fast Crowsnest setups still
// hit the configured 15-30 FPS, slow uv4l-mjpeg and cellular-tunnel paths drop
// to whatever they can sustain, but they never sit on the placeholder forever.
//
// Crucially, the snapshot URL is whatever PrinterStatusService resolved for the
// path it's currently winning on - LAN-direct at home, or the Pi's /mg-extcam
// proxy when remote - so an external phone-cam keeps working over the tunnel.
//
// Used by both the dashboard tile preview (BoxFit.cover, optionally throttled
// by the dashboard refresh setting) and the full-screen printer camera view
// (BoxFit.contain, target-FPS) - one renderer, no drift between the two.

class WebcamView extends ConsumerStatefulWidget {
  /// Absolute, ready-to-fetch snapshot URL (already includes mg_token for
  /// tunnel mode). Built by PrinterStatusService each poll. Null while no
  /// webcam is configured or the printer hasn't been reached yet - build()
  /// then falls back to the UI-type logo placeholder.
  final String? webcamSnapshotUrl;
  final bool webcamFlipH;
  final bool webcamFlipV;
  final int webcamRotation; // 0 | 90 | 180 | 270
  /// Crowsnest / Mainsail Target FPS. Acts as the ceiling on the fetch rate;
  /// the actual rate is bounded below by whatever the server can sustain.
  final int webcamTargetFps;
  /// True when the snapshot URL is an external camera (custom or auto-detected)
  /// - the fetch loop then pulls a single frame from a (possibly MJPEG-stream)
  /// source instead of doing a plain snapshot GET.
  final bool webcamIsExternal;
  /// 'mainsail' | 'fluidd' | null - shown as a logo while there's no frame yet.
  final String? uiType;

  /// Owning printer's id, for the bug-report webcam diagnostics
  /// ([WebcamFetchDiag]). Null skips recording (nothing else changes).
  final String? printerId;

  /// How a frame fills its box. The dashboard tile crops to fill
  /// ([BoxFit.cover]); the full-screen camera letterboxes the whole frame
  /// ([BoxFit.contain]).
  final BoxFit fit;

  /// When true (the dashboard tile), the global dashboard camera-refresh
  /// setting caps the frame rate to save data. When false (the full-screen
  /// camera, which the user is actively watching), the rate is bounded only by
  /// the printer's own target FPS and what the upstream can actually deliver.
  final bool respectDashboardThrottle;

  const WebcamView({
    super.key,
    this.webcamSnapshotUrl,
    this.webcamFlipH = false,
    this.webcamFlipV = false,
    this.webcamRotation = 0,
    this.webcamTargetFps = 15,
    this.webcamIsExternal = false,
    this.uiType,
    this.printerId,
    this.fit = BoxFit.cover,
    this.respectDashboardThrottle = true,
  });

  @override
  ConsumerState<WebcamView> createState() => _WebcamViewState();
}

class _WebcamViewState extends ConsumerState<WebcamView>
    with WidgetsBindingObserver {
  /// Bytes of the most recent successful snapshot. Null until the first fetch
  /// lands; build() shows the UI-type logo placeholder in that window. After
  /// the first frame, `Image.memory(gaplessPlayback: true)` keeps the last
  /// decoded frame on screen across re-fetches - no flicker between updates.
  Uint8List? _currentBytes;

  /// True while the app is backgrounded - the fetch loop idles instead of
  /// pulling frames over the network. Resumes on foreground.
  bool _appPaused = false;

  /// True once the wake window expired without a single frame - build() then
  /// shows the honest plain placeholder instead of the waking spinner.
  bool _wakeExpired = false;
  Timer? _wakeTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _armWakeWindow();
    _loop();
  }

  @override
  void dispose() {
    _wakeTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(WebcamView old) {
    super.didUpdateWidget(old);
    // A changed URL (transport flipped LAN<->tunnel, webcam re-detected) is a
    // fresh chance at a first frame - restart the wake window.
    if (old.webcamSnapshotUrl != widget.webcamSnapshotUrl &&
        _currentBytes == null) {
      _armWakeWindow();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasPaused = _appPaused;
    _appPaused = state != AppLifecycleState.resumed;
    // The camera slept while we idled in the background (no fetches), so a
    // return to the foreground is a fresh wake - give it a fresh window.
    if (wasPaused && !_appPaused && _currentBytes == null) _armWakeWindow();
  }

  /// (Re)start the wake window. Timer-driven rather than wall-clock so the
  /// window doesn't burn while the loop idles in the background mid-count,
  /// and so widget tests can advance it with pump(). No-ops without a URL
  /// (nothing is being fetched, the plain placeholder is already honest).
  void _armWakeWindow() {
    if (_currentBytes != null) return;
    _wakeTimer?.cancel();
    final url = widget.webcamSnapshotUrl;
    if (url == null || url.isEmpty) return;
    if (_wakeExpired) setState(() => _wakeExpired = false);
    _wakeTimer = Timer(_kWakeWindow, () {
      if (mounted && _currentBytes == null) {
        setState(() => _wakeExpired = true);
      }
    });
  }

  /// First (and every) successful frame: store + repaint, and retire the wake
  /// window for good - once a camera has produced a frame, failures keep the
  /// last frame on screen, never a spinner.
  void _storeFrame(Uint8List bytes) {
    _wakeTimer?.cancel();
    if (mounted) setState(() => _currentBytes = bytes);
  }

  /// Sequential snapshot-fetch loop. One in flight at a time; the next
  /// `_fetchOnce` only starts after the previous has fully resolved, so a slow
  /// upstream naturally throttles the effective frame rate.
  Future<void> _loop() async {
    while (mounted) {
      // Idle while backgrounded - no fetch, so an on-demand camera (go2rtc)
      // drops its stream and the sensor idles. (A printer whose webcam is hidden
      // renders no WebcamView at all, so there's nothing to throttle here.)
      if (_appPaused) {
        await Future.delayed(const Duration(milliseconds: 400));
        continue;
      }

      final start = DateTime.now();
      await _fetchOnce();
      if (!mounted) return;

      // The dashboard refresh setting caps the rate ONLY for the tile preview.
      // The full-screen view ignores it and runs at the printer's target FPS.
      // The rate follows the phone's network, not the connection path: on Wi-Fi
      // (even reaching a printer remotely over the tunnel) the faster local rate
      // is used; only on metered mobile data does the slower tunnel rate apply.
      final refresh = ref.read(onMobileDataProvider)
          ? ref.read(tunnelCameraRefreshProvider)
          : ref.read(localCameraRefreshProvider);
      final fixed = widget.respectDashboardThrottle ? refresh.intervalMs : null;
      final int intervalMs;
      if (fixed != null) {
        intervalMs = fixed;
      } else {
        final fps = widget.webcamTargetFps.clamp(1, 60);
        intervalMs = (1000 / fps).round();
      }

      final elapsedMs = DateTime.now().difference(start).inMilliseconds;
      final remaining = intervalMs - elapsedMs;
      if (remaining > 0) {
        await Future.delayed(Duration(milliseconds: remaining));
      }
    }
  }

  /// One GET to the snapshot URL. Success → store bytes; failure → swallow
  /// silently so gaplessPlayback keeps the previous frame (or the placeholder).
  Future<void> _fetchOnce() async {
    final url = widget.webcamSnapshotUrl;
    if (url == null || url.isEmpty) return;
    // External cameras usually expose an MJPEG stream, not a snapshot - a plain
    // GET on `.../video` would never return. Pull a single frame instead.
    if (widget.webcamIsExternal) {
      await _fetchFrameFromStream(url);
      return;
    }
    String result = 'error';
    try {
      // Generous 8 s timeout - uv4l-mjpeg has been observed to take 3 s+ per
      // snapshot on first wake. Better to block the loop briefly and get a
      // frame than spin-fail and never display anything.
      final resp =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (!mounted) return;
      if (resp.statusCode == 200 && _looksLikeImage(resp.bodyBytes)) {
        _storeFrame(resp.bodyBytes);
        result = 'ok';
      } else if (resp.statusCode != 200) {
        result = 'http ${resp.statusCode}';
      } else {
        result = resp.bodyBytes.isEmpty ? 'empty' : 'not-image';
      }
    } on TimeoutException {
      result = 'timeout';
    } catch (_) {
      // Network blip / 401 / parse error - previous frame stays.
    } finally {
      WebcamFetchDiag.record(widget.printerId,
          url: url, external: false, result: result);
    }
  }

  /// Pull ONE frame from an external camera URL. Handles both a plain snapshot
  /// (Content-Type image/*) and an MJPEG stream (multipart/x-mixed-replace) -
  /// for a stream we read until the first complete JPEG, then close the
  /// connection. Used for custom / auto-detected external cameras (LAN-direct,
  /// or the Pi's /mg-extcam proxy when remote).
  Future<void> _fetchFrameFromStream(String url) async {
    final client = http.Client();
    String result = 'error';
    try {
      final req = http.Request('GET', Uri.parse(url));
      final resp = await client.send(req).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) {
        result = 'http ${resp.statusCode}';
        return;
      }
      final ctype = (resp.headers['content-type'] ?? '').toLowerCase();
      final isMultipart = ctype.contains('multipart');
      final buffer = BytesBuilder();
      const maxBytes = 8 * 1024 * 1024; // safety cap
      await for (final chunk
          in resp.stream.timeout(const Duration(seconds: 8))) {
        buffer.add(chunk);
        if (isMultipart) {
          final frame = _extractJpeg(buffer.toBytes());
          if (frame != null) {
            _storeFrame(frame);
            result = 'ok';
            return; // got a frame - finally closes the still-open stream
          }
        }
        if (buffer.length > maxBytes) break;
      }
      // Non-multipart snapshot (or a multipart that ended without a clean
      // frame): use whatever bytes we collected if they look usable.
      if (!isMultipart) {
        final bytes = buffer.toBytes();
        if (_looksLikeImage(bytes)) {
          _storeFrame(bytes);
          result = 'ok';
        } else {
          // A 200 with zero bytes is the cold-camera-that-couldn't-start
          // signature (seen in the field on go2rtc with a wedged device) -
          // keep it distinct from a body that just isn't an image.
          result = bytes.isEmpty ? 'empty' : 'not-image';
        }
      } else {
        result = 'no-frame';
      }
    } on TimeoutException {
      result = 'timeout';
    } catch (_) {
      // Blip - keep the last frame on screen.
    } finally {
      client.close(); // aborts an MJPEG stream still in flight
      WebcamFetchDiag.record(widget.printerId,
          url: url, external: true, result: result);
    }
  }

  /// True when [d] starts like an image the engine can decode (JPEG, PNG,
  /// GIF, WebP, BMP). A camera URL that answers 200 with something else -
  /// typically a go2rtc / WebRTC player PAGE, which is HTML - must never be
  /// stored: Image.memory can't decode it, so it would replace the
  /// placeholder (or the last good frame) with a broken-image error box.
  static bool _looksLikeImage(Uint8List d) {
    if (d.length < 12) return false;
    if (d[0] == 0xFF && d[1] == 0xD8) return true;                    // JPEG
    if (d[0] == 0x89 && d[1] == 0x50 && d[2] == 0x4E && d[3] == 0x47) {
      return true;                                                    // PNG
    }
    if (d[0] == 0x47 && d[1] == 0x49 && d[2] == 0x46) return true;    // GIF
    if (d[0] == 0x52 && d[1] == 0x49 && d[2] == 0x46 && d[3] == 0x46 &&
        d[8] == 0x57 && d[9] == 0x45 && d[10] == 0x42 && d[11] == 0x50) {
      return true;                                                    // WebP
    }
    if (d[0] == 0x42 && d[1] == 0x4D) return true;                    // BMP
    return false;
  }

  /// Find the first complete JPEG (SOI ff d8 … EOI ff d9) in [d], or null if
  /// one isn't present yet. Carves a single frame out of an MJPEG stream.
  static Uint8List? _extractJpeg(Uint8List d) {
    int start = -1;
    for (int i = 0; i + 1 < d.length; i++) {
      if (d[i] == 0xFF && d[i + 1] == 0xD8) {
        start = i;
        break;
      }
    }
    if (start < 0) return null;
    for (int i = start + 2; i + 1 < d.length; i++) {
      if (d[i] == 0xFF && d[i + 1] == 0xD9) {
        return Uint8List.sublistView(d, start, i + 2);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _currentBytes;
    final url = widget.webcamSnapshotUrl;
    // Waking = we're actively fetching but nothing has landed yet and the
    // window hasn't given up. An unset URL skips straight to the placeholder
    // - there's nothing to wake.
    final waking =
        bytes == null && url != null && url.isNotEmpty && !_wakeExpired;
    WebcamFetchDiag.recordShowing(widget.printerId,
        bytes != null ? 'frames' : (waking ? 'waking' : 'placeholder'));
    Widget image = bytes != null
        ? Image.memory(bytes, fit: widget.fit, gaplessPlayback: true)
        : Container(
            color: Colors.black54,
            child: Center(
                child: waking
                    ? const _WebcamWaking()
                    : _WebcamPlaceholder(uiType: widget.uiType)),
          );

    // Apply the webcam display transforms Mainsail has configured, so the image
    // matches the orientation shown in the web UI in both places.
    final needsRotate = widget.webcamRotation != 0;
    final needsFlip = widget.webcamFlipH || widget.webcamFlipV;

    if (needsRotate) {
      image = Transform.rotate(
        angle: widget.webcamRotation * math.pi / 180,
        child: image,
      );
    }
    if (needsFlip) {
      image = Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(
          widget.webcamFlipH ? -1.0 : 1.0,
          widget.webcamFlipV ? -1.0 : 1.0,
          1.0,
        ),
        child: image,
      );
    }

    return image;
  }
}

// ── Waking spinner ────────────────────────────────────────────────────────────
//
// Shown instead of the placeholder while the first frame is still being
// chased and the wake window hasn't expired. On-demand cameras (go2rtc)
// genuinely take a moment to start their producer on the first request - an
// honest "waking up" beats a logo that reads as broken.

class _WebcamWaking extends StatelessWidget {
  const _WebcamWaking();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: Colors.white38,
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            l.webcamWakingUp,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

// ── Webcam placeholder ────────────────────────────────────────────────────────
//
// Shown while there's no frame yet (no webcam configured, camera service not
// running, or the first fetch still in flight). Displays the Mainsail or Fluidd
// logo when the UI type is known, otherwise a generic icon.

class _WebcamPlaceholder extends StatelessWidget {
  final String? uiType; // 'mainsail' | 'fluidd' | null

  const _WebcamPlaceholder({this.uiType});

  @override
  Widget build(BuildContext context) {
    if (uiType == 'mainsail') {
      return Opacity(
        opacity: 0.35,
        child: SvgPicture.asset(
          'assets/icons/mainsail_logo.svg',
          width: 130,
          fit: BoxFit.contain,
        ),
      );
    }
    if (uiType == 'fluidd') {
      return Opacity(
        opacity: 0.35,
        child: SvgPicture.asset(
          'assets/icons/fluidd_logo.svg',
          width: 130,
          fit: BoxFit.contain,
        ),
      );
    }
    return const Icon(Icons.videocam_off, color: Colors.white30, size: 40);
  }
}
