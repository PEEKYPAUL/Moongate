import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import 'tutorial_controller.dart';

/// Wraps the whole app below the app-lock gate. When a tutorial is running it
/// paints a dimming scrim with a spotlight hole over the current step's anchor
/// and a callout card explaining it, with Skip / Next controls. When idle it is
/// invisible and just passes [child] through.
class TutorialOverlay extends ConsumerStatefulWidget {
  final Widget child;
  const TutorialOverlay({super.key, required this.child});

  @override
  ConsumerState<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends ConsumerState<TutorialOverlay> {
  final GlobalKey _stackKey = GlobalKey();
  List<Rect> _holeRects = const [];
  int _resolvedForIndex = -1;
  int _settleScheduledForIndex = -1;

  /// Resolve every anchor's rectangle in the overlay's own coordinate space,
  /// after layout. Retries on the next frame until the targets are mounted (they
  /// may belong to a screen we just navigated to), then stores the rects.
  void _resolveRect(TutorialState s) {
    final step = s.current;
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;

    if (step == null) {
      if (_holeRects.isNotEmpty) setState(() => _holeRects = const []);
      return;
    }
    if (step.anchors.isEmpty) {
      // Centred message step: no spotlight.
      if (_holeRects.isNotEmpty || _resolvedForIndex != s.index) {
        setState(() {
          _holeRects = const [];
          _resolvedForIndex = s.index;
        });
      }
      return;
    }
    final boxes = [
      for (final k in step.anchors)
        k.currentContext?.findRenderObject() as RenderBox?,
    ];
    if (stackBox == null || boxes.any((b) => b == null || !b.hasSize)) {
      // Not all laid out yet; try again next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _resolveRect(ref.read(tutorialControllerProvider));
      });
      return;
    }
    final rects = [
      for (final b in boxes)
        stackBox.globalToLocal(b!.localToGlobal(Offset.zero)) & b.size,
    ];
    if (!_sameRects(rects, _holeRects) || _resolvedForIndex != s.index) {
      setState(() {
        _holeRects = rects;
        _resolvedForIndex = s.index;
      });
    }
  }

  bool _sameRects(List<Rect> a, List<Rect> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tutorialControllerProvider);

    final isDrawerStep = state.current?.requiresDrawer ?? false;

    // On a new step, drop the previous spotlight straight away so it never
    // flashes at a stale position while things move.
    if (state.active && _resolvedForIndex != state.index) {
      _holeRects = const [];
      // Static targets (tiles, the menu button) resolve next frame. Drawer
      // entries wait for the open + scroll to settle (below) so the spotlight
      // appears AFTER the scroll, not before.
      if (!isDrawerStep) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _resolveRect(ref.read(tutorialControllerProvider));
        });
      }
    }
    // Delayed pass(es) for targets that animate into place: a drawer entry
    // sliding/scrolling in, a bottom sheet rising.
    if (state.active && _settleScheduledForIndex != state.index) {
      _settleScheduledForIndex = state.index;
      final delays = isDrawerStep ? const [640] : const [360, 760];
      for (final ms in delays) {
        Future.delayed(Duration(milliseconds: ms), () {
          if (mounted) _resolveRect(ref.read(tutorialControllerProvider));
        });
      }
    }

    return Stack(
      key: _stackKey,
      children: [
        widget.child,
        if (state.active)
          Positioned.fill(
            child: _TutorialScrim(
              state: state,
              holes: _holeRects,
              onNext: () => ref.read(tutorialControllerProvider.notifier).next(),
              onBack: () => ref.read(tutorialControllerProvider.notifier).previous(),
              onSkip: () => ref.read(tutorialControllerProvider.notifier).finish(),
            ),
          ),
      ],
    );
  }
}

class _TutorialScrim extends StatelessWidget {
  final TutorialState state;
  final List<Rect> holes;
  final VoidCallback onNext;
  final VoidCallback onBack;
  final VoidCallback onSkip;

  const _TutorialScrim({
    required this.state,
    required this.holes,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);

    final step = state.current;
    final dim = step?.dimScreen ?? true;

    // The combined area of everything we're spotlighting, used to place the card
    // opposite it.
    final union = holes.isEmpty
        ? null
        : holes.reduce((a, b) => a.expandToInclude(b));

    // Some steps spotlight several adjacent elements (the hotend / bed / chamber
    // chips) and read better as one box around the whole group than a separate
    // ring per chip. Collapse to the bounding box when the step asks for it.
    final paintHoles =
        (step?.unifyAnchors ?? false) && union != null ? [union] : holes;

    // Put the card opposite the spotlight: at the bottom when the target sits in
    // the top 60% of the screen, otherwise at the top. Avoids covering the very
    // thing we are pointing at. A step can force the card to the top (e.g. when
    // a bottom sheet is on screen).
    final cardAtBottom = (step?.forceCardTop ?? false)
        ? false
        : (union == null ? true : union.center.dy < size.height * 0.6);
    final text = _copyFor(l, state.current?.id);

    // Hold the card back until the spotlight has resolved, so it appears once in
    // its final position rather than flashing at the bottom then jumping to the
    // top as the target scrolls into view. Steps with no spotlight (e.g. the
    // preheat sheet) have nothing to wait for, so they show it straight away.
    final showCard = (step?.anchors.isEmpty ?? true) || holes.isNotEmpty;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Scrim with the spotlight hole. Absorbs taps so the UI behind is
          // inert during the tour (the user advances with Next).
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {}, // swallow taps on the dimmed area
              child: CustomPaint(
                painter: _SpotlightPainter(holes: paintHoles, dim: dim),
              ),
            ),
          ),
          // Callout card, held back until the spotlight is ready.
          if (showCard)
            Positioned(
            left: 16,
            right: 16,
            top: cardAtBottom ? null : padding.top + 16,
            bottom: cardAtBottom ? padding.bottom + 24 : null,
            child: _CalloutCard(
              text: text,
              stepIndex: state.index,
              stepTotal: state.total,
              isLast: state.isLast,
              canBack: state.index > 0,
              onNext: onNext,
              onBack: onBack,
              onSkip: onSkip,
              nextLabel: state.isLast ? l.tutorialDone : l.tutorialNext,
              backLabel: l.tutorialBack,
              skipLabel: l.tutorialSkip,
            ),
          ),
        ],
      ),
    );
  }
}

/// Maps a step id to its localized copy. Kept here so the controller stays free
/// of l10n. New steps add a case as the tour grows.
String _copyFor(AppLocalizations l, String? id) {
  switch (id) {
    case 'localBar':
      return l.tutorialLocalBar;
    case 'tunnelBar':
      return l.tutorialTunnelBar;
    case 'remoteBuilding':
      return l.tutorialRemoteBuilding;
    case 'temps':
      return l.tutorialTemps;
    case 'estop':
      return l.tutorialEstop;
    case 'webcam':
      return l.tutorialWebcam;
    case 'preheatPress':
      return l.tutorialPreheatPress;
    case 'preheatSheet':
      return l.tutorialPreheatSheet;
    case 'addPrinter':
      return l.tutorialAddPrinter;
    case 'menuIcon':
      return l.tutorialMenuIcon;
    case 'menuPrinters':
      return l.tutorialMenuPrinters;
    case 'menuBackup':
      return l.tutorialMenuBackup;
    case 'menuDisplaySize':
      return l.tutorialMenuDisplaySize;
    case 'menuColumns':
      return l.tutorialMenuColumns;
    case 'menuCameras':
      return l.tutorialMenuCameras;
    case 'menuLanguage':
      return l.tutorialMenuLanguage;
    default:
      return '';
  }
}

class _CalloutCard extends StatelessWidget {
  final String text;
  final int stepIndex;
  final int stepTotal;
  final bool isLast;
  final bool canBack;
  final VoidCallback onNext;
  final VoidCallback onBack;
  final VoidCallback onSkip;
  final String nextLabel;
  final String backLabel;
  final String skipLabel;

  const _CalloutCard({
    required this.text,
    required this.stepIndex,
    required this.stepTotal,
    required this.isLast,
    required this.canBack,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
    required this.nextLabel,
    required this.backLabel,
    required this.skipLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 8,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 12),
            // Progress dots, centred above the buttons.
            if (stepTotal > 1)
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < stepTotal; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2.5),
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == stepIndex
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface
                                    .withValues(alpha: 0.25),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Row(
              children: [
                // Back: step back one if the user advanced by mistake. Hidden on
                // the first step.
                if (canBack)
                  TextButton(onPressed: onBack, child: Text(backLabel)),
                const Spacer(),
                // Skip is the exit hatch for the whole tour; on the last step
                // it would just duplicate Done, so it's hidden there.
                if (!isLast) ...[
                  TextButton(onPressed: onSkip, child: Text(skipLabel)),
                  const SizedBox(width: 4),
                ],
                FilledButton(onPressed: onNext, child: Text(nextLabel)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints the dimming scrim everywhere except a rounded hole over [hole].
class _SpotlightPainter extends CustomPainter {
  final List<Rect> holes;
  final bool dim;
  _SpotlightPainter({required this.holes, this.dim = true});

  @override
  void paint(Canvas canvas, Size size) {
    // Steps that open their own modal (preheat sheet) ask us not to dim - the
    // sheet's own barrier handles that. The tap-absorber stays so the sheet
    // can't be dismissed out from under the tour.
    if (!dim) return;
    final scrim = Paint()..color = Colors.black.withValues(alpha: 0.72);
    if (holes.isEmpty) {
      canvas.drawRect(Offset.zero & size, scrim);
      return;
    }
    // Pad each target so even a thin (3px) bar gets a visible highlight.
    final cuts = [
      for (final h in holes)
        RRect.fromRectAndRadius(h.inflate(8), const Radius.circular(10)),
    ];
    var holesPath = Path();
    for (final c in cuts) {
      holesPath = Path.combine(PathOperation.union, holesPath, Path()..addRRect(c));
    }
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        holesPath,
      ),
      scrim,
    );
    // A soft ring around each hole.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.7);
    for (final c in cuts) {
      canvas.drawRRect(c, ring);
    }
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter old) =>
      old.dim != dim ||
      old.holes.length != holes.length ||
      !_listEq(old.holes, holes);

  static bool _listEq(List<Rect> a, List<Rect> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
