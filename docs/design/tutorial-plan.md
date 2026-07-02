# Moongate in-app live tutorial — design plan (v1)

Status: design only, not yet built. Android first, iOS later (shared Dart, so most of it ships
on iPhone automatically; the Print-notifications steps are Android-only and are skipped on iOS).

## Locked decisions
- **Demo target**: drive the user's REAL first tile, snapshot real state, fake briefly, restore.
- **Offline/printing during the tour**: fully fake the demoed tile so the whole script always
  flows, regardless of the printer's real state.
- **Localization**: all 8 languages up front.
- **Scope v1**: build the full script in one cut (still tested in slices on the phone).
- **Layout-columns step**: describe only — do NOT drive the drawer open/closed to show a reflow.
- **This doc lives on**: the `feat/dashboard-updates` branch (public repo, that's fine).

## 1. What it is
A one-time, opt-in, *live* walkthrough offered right after the user adds their first printer.
It drives the real UI and the user's real tile (faking a couple of states briefly, then
restoring), with callout boxes that point at each element and a Next button. Re-runnable any
time from the bottom of the hamburger menu.

## 2. Architecture (build our own, no package)
- **Overlay**: a `TutorialOverlay` mounted in `app.dart` builder, same level as `AppLockGate`
  (Stack + Positioned.fill). It dims the screen, cuts a "spotlight" hole over the current
  target, and shows a callout box (text + Next / Skip / progress dots).
- **Targeting**: attach `GlobalKey`s to each element we spotlight (tile connection bar, temp
  chips, webcam area, printer-screen icons, each drawer row). The overlay reads the key's
  RenderBox to position the hole + callout.
- **Controller**: a Riverpod `tutorialControllerProvider` = a step state machine. Each step
  knows: which screen it needs, what to set up (open drawer / open a sheet / navigate / inject
  fake state), which GlobalKey to spotlight, and the copy. It orchestrates navigation and
  drawer/sheet open-close *between* steps, waits a frame for layout, then positions the callout.
- **Demo state injection (real tile, restore after, fully fake when needed)**: a transient
  `demoOverride` latch on `PrinterStatusService` for the demoed printer. For the duration of the
  tile + preheat portion it emits a controlled synthetic `PrinterStatus` — seeded from the real
  poll where available, but filled in where not (idle state so preheat is offered, populated
  hotend/bed, local connection) so the script is deterministic even if the printer is offline or
  printing. Individual steps tweak it (force `connection: remote` for tunnel mode; `chamberTemp`
  > 0 for the chamber chip). Releasing the latch lets the next real poll take over, so the tile
  snaps back to truth with no persisted change.
- **Theme + size for the demo**: at start, snapshot `themeMode` + `fontScale` (+ custom theme),
  force `dark` + `1.0`, restore on finish/skip. Because the slider stacks chips past 1.15x and a
  custom theme can recolour everything, standardising makes the demo predictable.
- **Persistence**: mirror the pairing-help pattern. `tutorial_offered` (bool) gates the
  first-run offer; set when the user ticks "don't remind again" or finishes. A re-run from the
  menu ignores the flag.
- **Crash/leave safety**: also persist `tutorial_in_progress` + the snapshot, so if the app is
  backgrounded/killed mid-demo we restore theme/size on next launch (don't strand the user on
  standard theme). Restore on lifecycle pause too.
- **Localization**: ~35-40 new `tutorial*` keys in all 8 `.arb` files + `flutter gen-l10n`.

## 3. Trigger + entry points
- **Offer popup** (after first printer, in dashboard `_load()` when list goes empty -> 1):
  "Would you like a quick tour of how Moongate works?" with **Start tutorial** and
  **No thanks** + a "Don't remind me again" checkbox.
- **Menu entry**: pinned at the very bottom of the drawer (in the pinned area by the version),
  "App tutorial", runs it on demand.
- **End-of-demo prompt**: dismissable, "don't show again".

## 4. The live script (draft copy — English; translated to 8 langs at build)

### Dashboard tile
1. **Local mode** — spotlight the green bar + wifi icon.
   "The colour bar shows how Moongate is reaching this printer. Green with a Wi-Fi icon means
    you are on the same network — a fast, direct local connection."
2. **Tunnel mode** — force orange bar + cloud icon (fake), spotlight it.
   "Orange with a cloud icon means you are away from home, connected securely over the internet
    through your printer's tunnel. Moongate switches between the two automatically." (then restore)
3. **Hotend** — spotlight hotend chip.
   "This is your hotend (nozzle) temperature."
4. **Bed** — spotlight bed chip.
   "And this is the heated bed."
5. **Chamber** — inject fake chamber value if none, spotlight it.
   "If your printer has a chamber sensor, its temperature shows here too." (then remove fake)
6. **Webcam** — spotlight the webcam square.
   "Tapping the camera view opens the full printer interface. Tap Next to see it." -> on Next,
   navigate to the printer screen.

### Printer screen
7. **Intro + controls** — spotlight in turn:
   "Here you can fully control your 3D printer — the full Klipper interface, live."
   - Camera icon: "Open the live webcam full-screen."
   - Edit/Rename icon: "Rename this printer or set its local address."
   - Refresh icon: "Reload the interface."
8. **Back** — spotlight the back arrow.
   "Tap the back arrow to return to your dashboard." -> on Next, navigate back.

### Preheat
9. **Preheat** — long-press to open the sheet, spotlight hotend/bed/heat-soak.
   "Press and hold a printer's name or temperatures to preheat. Set a hotend and bed target,
    and an optional heat-soak time so the printer holds temperature before you print." -> on Next,
    close the sheet (back to dashboard).

### Hamburger menu (open the drawer)
10. **Theme** — spotlight Theme.
    "Choose a light, dark, or fully custom colour theme."
11. **Display size** — spotlight the slider.
    "Make everything bigger or smaller to suit your eyes."
12. **Dashboard layout** — spotlight the columns control (DESCRIBE ONLY, no live reflow).
    "Lay your printers out in one, two, or three columns."
13. **Camera feeds** — spotlight.
    "Set how often the dashboard webcam thumbnails refresh, separately for local and tunnel."
14. **Print notifications** — spotlight (Android only).
    "Get live print progress in your notifications." then Update frequency: "How often they
     update." then Notification content: "Choose and reorder what each notification shows."
     (optionally demo a reorder)
15. **How pairing works / Icon guide / Report a problem** — spotlight each; open the bug-report
    form, pre-fill a demo comment, but DO NOT send.
    "Here is how pairing works, a guide to every icon, and where to report a problem."
16. **Finish** — restore theme + size, set done flag.
    "That's it. You can run this tour again any time from the bottom of the menu." (don't show again)

## 5. Files to touch (new + edited)
New: `features/tutorial/tutorial_controller.dart`, `tutorial_overlay.dart`, `tutorial_steps.dart`,
`tutorial_offer_dialog.dart`.
Edited: `app.dart` (mount overlay), `dashboard_screen.dart` (trigger in `_load()`, drawer entry,
GlobalKeys), `printer_tile.dart` (GlobalKeys on bar/temps/webcam), `printer_screen.dart`
(GlobalKeys on icons + back), `preheat_overlay.dart` (keys), `printer_status_service.dart`
(demoOverride latch), `settings_provider.dart` (tutorial flags), 8x `app_*.arb` + gen-l10n.

## 6. Risks / hard parts
- Orchestrating navigation + drawer + sheets reliably between steps (targets must exist before we
  position a callout; drive setup, wait a frame, then show).
- Faking status without the 4s poll overwriting it (the demoOverride latch handles this).
- Restoring theme/size if the user leaves mid-tour (persist snapshot + restore on resume/launch).
- Localising a lot of prose well in 8 languages (machine translate, native review later).

## 7. Build order (still one release, tested in slices on the phone)
1. Overlay + controller + offer dialog + one real step (local-mode bar) end to end.
2. Rest of the tile tour + full demo-state injection (fully-fake fallback).
3. Printer-screen tour + preheat.
4. Drawer tour.
5. Theme/size snapshot-restore + crash safety + menu entry.
6. All 8-language copy + gen-l10n, polish, version bump + changelog when shipping.
