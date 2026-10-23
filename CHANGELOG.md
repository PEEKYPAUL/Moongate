# Changelog

What changed in each Moongate release, newest first, in plain language. The full technical write-up of every change is in the pull request that shipped it (linked from each GitHub release) and in the commit history.

## v0.9.76

- Colour view: Sliced / Loaded switch shows what is actually in your MMU gates (Happy Hare, AFC; needs plugin 0.6.29)
- Files you view or save are cached for the session, no second download
- Hold a file's thumbnail in Start a print to see it big

## v0.9.75

- Fixed: MMU prints under Happy Hare showed one colour in the Colour view

## v0.9.74

- Colour view now uses the extruder colours you picked in PrusaSlicer
- Save to phone: download any stored G-code file from Start a print or the viewer

## v0.9.73

- New Colour view in the G-code viewer: multi-material files in their filament colours, with a key per tool
- Viewer menu: choose which view it opens with

## v0.9.72

- New G-code layer viewer: spin, zoom and step through a sliced file in 3D before you print
- Heat maps for temperature, flow, layer time, speed and fan speed

## v0.9.71

- Fixed: renaming a printer now updates iPhone notification titles
- Fixed: far fewer server calls when a printer keeps rejecting its token

## v0.9.70

- Links inside the printer page open in their own tab; the printer page stays put
- A printer with no camera shows the Mainsail / Fluidd logo again
- Plugin 0.6.28: no more untracked-file warning in Mainsail's Software Update panel

## v0.9.69

- New Single-printer dashboard: one printer full screen (Menu, Dashboard layout)
- Power button now offers Turn on / Turn off
- Fixed: tile buttons could carry over when auto-arrange moved printers

## v0.9.68

- Start print can preheat and heat-soak first, then start by itself (plugin 0.6.27)
- Alert when a finished print is cool enough to remove
- New MOONGATE_TEMP_NOTIFY macro for your own temperature alerts

## v0.9.67

- Heat-soak alert now waits for the real temperatures, chamber included
- iPhone: the preheat sheet says the heat-soak alert is Android-only for now

## v0.9.66

- MOONGATE_NOTIFY messages now reach Android (plugin 0.6.26)

## v0.9.65

- Fixed: Control panel controls hidden behind the navigation bar or keyboard
- Macro buttons line up in a tidy grid

## v0.9.64

- New Control panel: heaters, motion and macro buttons in one customisable sheet
- Config editor suggests Klipper sections and options and flags odd values
- Hide-backups filter also catches timestamped config copies

## v0.9.63

- File System can hide backup and hidden files
- Settings backups now carry every setting

## v0.9.62

- Fixed: the guided tour could point off screen or get stuck
- Tour gains a Console and File System step

## v0.9.61

- New per-printer Console and File System (config editor with backup and restore)
- Android: loud alerts for paused, failed and errored prints
- Cameras fall back to a working one instead of failing quietly
- iPhone: first open of a printer found by hostname now works; needs iOS 15

## v0.9.60

- Compact tiles get the full action row (pause, cancel, files, macros, light)
- Update badge now nudges for plugin 0.6.22

## v0.9.59

- Switch between a printer's cameras on the tile (plugin 0.6.22)
- Tap-to-pair from the Pi's pairing page on the same phone

## v0.9.58

- Camera tiles say "Camera unreachable" instead of spinning forever
- Fixed: some phones left a home printer stuck on the tunnel

## v0.9.57

- Fixed: the printer page could stay on the tunnel while you were at home

## v0.9.56

- Time remaining now matches Mainsail
- Camera tiles show a spinner while a camera wakes up
- Direct (LAN/VPN) printers make no cloud calls at all

## v0.9.55

- Fixed: v0.9.54 dashboard could stick on Connecting
- iPhone: no stray gap at the bottom, buttons sit in the corners

## v0.9.54

- 3rd-party printers supported (first: Elegoo Centauri Carbon) in Direct mode
- Nothing hides under the phone's navigation bar any more
- Steadier dashboard on flaky WiFi

## v0.9.53

- Time remaining (or finish time) on the dashboard tile while printing

## v0.9.52

- go2rtc / WebRTC cameras now show on the tile and in the printer page

## v0.9.51

- New Direct (LAN/VPN) mode: add a printer with zero cloud
- Switch a printer between cloud and Direct from its edit dialog
- Printers now need a real name

## v0.9.50

- Dashboard flags an out-of-date plugin and can update it with one tap (plugin 0.6.16)

## v0.9.49

- Fixed: the pairing pop-up re-appearing every launch
- Fixed: starred macros vanishing
- Removed printers stop calling home (plugin 0.6.15)

## v0.9.48

- Hold a tile's camera to open it full screen
- New Local-only switch to stop all remote traffic
- Print cards get their own notification category
- Friendlier message while a Pi is still booting

## v0.9.47

- New language: Brazilian Portuguese
- Restore keeps printers paired after the backup was made
- Print notification shows heating from the first moments

## v0.9.46

- Pause / play button to switch print notifications off and on

## v0.9.45

- Fixed: a printer switched on in the background could stay offline
- Multi-toolhead preheat more reliable

## v0.9.44

- Multi-toolhead detection fixed at the source (plugin 0.6.12)

## v0.9.43

- More reliable tool-changer detection

## v0.9.42

- Preheat every toolhead at once
- Notifications list every tool's temperature
- Fixed: the Printer unreachable page fills the screen

## v0.9.41

- Option to hide the dashboard's add and reorder buttons

## v0.9.40

- Tile temperatures stay one size and wrap instead of shrinking

## v0.9.39

- Multi-toolhead printers show every hotend on the tile
- Font picker grows to 36 typefaces
- Fixed: status notification follows your dashboard order

## v0.9.38

- Choose the app's font (Menu, Theme)

## v0.9.37

- Phone colours theme (Material You) on Android 12+
- Shorter first-run tutorial

## v0.9.36

- New guided tour of the app after your first printer
- Long-press anywhere on a tile to open preheat

## v0.9.35

- Display-size slider scales icons as well as text
- Pairing guide reminds you to install the plugin first

## v0.9.34

- Power all machines works with macro-powered printers too
- Downloaded updates are cleared after installing

## v0.9.33

- Optional Global power button: switch every machine on or off
- Plugin fix: an unpaired printer no longer retries every few seconds

## v0.9.32

- Fixed: chamber temperature missing for some sensor setups

## v0.9.31

- Fixed: Show only online devices resetting itself

## v0.9.30

- Long-press a tile's temperatures to preheat, with an optional heat-soak timer

## v0.9.29

- Show only online devices in the status notification

## v0.9.28

- Fixed: a switched-off printer still showing Printing

## v0.9.27

- Print cards stay pinned under the status notification

## v0.9.26

- Update button in What's new installs in the app
- Print notification readable without expanding it

## v0.9.25

- Reworked print notifications: a status list plus one card per active print
- Choose what each print card shows

## v0.9.24

- Tiles show only the current temperature, so E-STOP never gets pushed off

## v0.9.23

- Icon guide covers the Emergency-stop button

## v0.9.22

- Compact tiles get the power button and line up with full tiles

## v0.9.21

- Set the E-STOP colour in the Custom theme
- Compact tiles match the full tile layout

## v0.9.20

- Custom background fills the whole screen

## v0.9.19

- Cleaner E-STOP button

## v0.9.18

- Fixed: temperatures hard to read on the Light theme
- New look for the E-STOP button

## v0.9.17

- Print progress matches Mainsail exactly
- Emergency stop from the dashboard (double-tap)
- In-app updates with a progress bar

## v0.9.16

- Powered-off printers no longer cost data or battery in the background

## v0.9.15

- Faster camera rate whenever you are on WiFi
- Printers warm up in the background so they open instantly

## v0.9.14

- Separate camera feed rates for home and away

## v0.9.13

- Drag tiles into any order again
- Restore rebuilds your dashboard exactly

## v0.9.12

- Show or hide each printer's webcam
- See-through tiles on the Custom theme

## v0.9.11

- Clear a finished print from the tile
- Custom dashboard background image
- Advanced Power Switch for macro-powered printers

## v0.9.10

- Power a printer on or off from its tile
- Show webcams switch to turn all feeds off at once

## v0.9.9

- Print notification shows the finish time
- Choose what the notification shows

## v0.9.8

- Re-opening a printer is instant
- Control printer lights from the dashboard

## v0.9.7

- Square camera feeds on the dashboard

## v0.9.6

- Run macros from the dashboard, star your favourites

## v0.9.5

- Full-screen camera view with pinch to zoom

## v0.9.4

- Arrange your printer tiles by hand

## v0.9.3

- Clearer notification category names

## v0.9.2

- Webcam on the printer page works remotely

## v0.9.1

- What's new button on the update banner

## v0.9.0

- External network cameras, e.g. an old phone, on any tile

## v0.8.5

- Clearer reconnect banner when the cloud sign-in drops

## v0.8.4

- Re-pairing reconnects in seconds

## v0.8.3

- Fixed: keyboard not re-opening on the Add Printer form

## v0.8.2

- Print a stored file from the dashboard
- New app icon
- Notification fixes

## v0.8.1

- Notification fixes and an update-frequency setting

## v0.8.0

- Optional print notifications
- Backups now include your settings
- Printers sort by activity

## v0.7.0

- Eight languages
- Icon guide
- Square tiles in single-column view

## v0.6.5

- How pairing works guide

## v0.6.4

- Fixed remote access over the internet (update the Pi)

## v0.6.3

- Restore brings printers back online without re-pairing
- Report a problem from the menu

## v0.6.2

- Set a printer's address by hand

## v0.6.1

- Fixed: a printer stuck on Starting up

## v0.6.0

- Optional App lock with PIN, fingerprint or face

## v0.5.2

- Back up and restore your printer list to a file

## v0.5.1

- Instant pairing
- Dashboard camera feed rate setting

## v0.5.0

- Finds your Pi on the local network automatically

## v0.4.4

- Pi advertises itself on the local network (groundwork for v0.5.0)

## v0.4.3

- Webcam tile works on slow camera servers

## v0.4.2

- Re-pair after reinstall just works
- Type the GATE code if you can't scan the QR

## v0.4.1

- Fixed the tile webcam preview

## v0.4.0

- Hardened remote access
- Buy me a coffee and What's new

## v0.3.0

- Cloud pairing, no URL sharing

## v0.2.29

- Initial public release

## v0.2.0 to v0.2.28 (pre-release)

- Cloudflare tunnel remote access with automatic local / remote fallback
- In-app update banner
- Custom theme, chamber temperature, grid columns, print progress like Mainsail
- Camera and QR-scanner fixes on Samsung phones
- Licence changed to PolyForm Noncommercial 1.0.0 (v0.2.28)
