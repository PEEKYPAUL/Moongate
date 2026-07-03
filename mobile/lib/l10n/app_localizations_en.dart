// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get updateDownloading => 'Downloading update…';

  @override
  String get updateOpeningInstaller => 'Opening installer…';

  @override
  String get updateFailed => 'Couldn\'t complete the update automatically.';

  @override
  String get updateOpenInBrowser => 'Open in browser';

  @override
  String get lightingTitle => 'Lighting';

  @override
  String get lightingMenuSubtitle =>
      'Control your printers\' lights from the dashboard';

  @override
  String get lightingBanner =>
      'Choose which printers have a light you can control. For each, turn it on and set either an On + Off macro pair, or a single Toggle macro. Optionally pick a status source so the bulb shows the real on/off state.';

  @override
  String get lightingNoPrinters => 'No printers to set up yet.';

  @override
  String get lightingShowOnTile => 'Show on tile';

  @override
  String get lightingNeedMacro =>
      'Set an On + Off pair or a Toggle macro to enable.';

  @override
  String get lightingLoadFailed =>
      'Couldn\'t load this printer\'s macros (it may be offline). Type names manually below.';

  @override
  String get lightingOnMacro => 'Lights ON macro';

  @override
  String get lightingOffMacro => 'Lights OFF macro';

  @override
  String get lightingToggleMacro => 'Toggle macro';

  @override
  String get lightingToggleSection => 'Optional - toggle method';

  @override
  String get lightingStatusSource => 'Light Status Source';

  @override
  String get lightingStatusSourceHelp =>
      'Optional. The Klipper object that reports the light\'s state - e.g. output_pin caselight (not a raw pin like PE3). Leave blank to just track your taps.';

  @override
  String get lightingStatusHint => 'Example: output_pin caselight';

  @override
  String get lightingNotSet => 'Not set';

  @override
  String get lightingPickMacro => 'Select a macro';

  @override
  String get lightingPickStatusSource => 'Select the light status pin';

  @override
  String get lightingManualHint => 'Type the exact name';

  @override
  String get lightingClear => 'Clear';

  @override
  String get lightTurnOn => 'Turn light on';

  @override
  String get lightTurnOff => 'Turn light off';

  @override
  String get lightToggleFailed => 'Couldn\'t reach the printer';

  @override
  String get powerTurnOn => 'Turn on';

  @override
  String get powerTurnOff => 'Turn off';

  @override
  String powerConfirmOn(String name) {
    return 'Turn $name on?';
  }

  @override
  String powerConfirmOff(String name) {
    return 'Turn $name off?';
  }

  @override
  String get powerToggleFailed => 'Couldn\'t change the printer\'s power';

  @override
  String get powerLockedWhilePrinting => 'Can\'t power off while printing';

  @override
  String get globalPowerButtonTitle => 'Global power button';

  @override
  String get globalPowerButtonSubtitle =>
      'A top-bar button to power your whole fleet on or off';

  @override
  String get globalPowerTooltip => 'Power all machines';

  @override
  String get globalPowerSheetTitle => 'Power all machines';

  @override
  String get globalPowerOnAll => 'Power on all';

  @override
  String get globalPowerSlideOff => 'slide to power off all';

  @override
  String get globalPowerConfirmOnTitle => 'Power on all machines?';

  @override
  String get globalPowerConfirmOnBody =>
      'This switches on every machine we can reach.';

  @override
  String get globalPowerPrintingNote =>
      'Machines that are printing are left on';

  @override
  String get globalPowerStateWillSwitchOff => 'will switch off';

  @override
  String get globalPowerStateKeptPrinting => 'printing, kept on';

  @override
  String get globalPowerStateOffline => 'offline, skipped';

  @override
  String get globalPowerStateOnOff => 'on / off';

  @override
  String get globalPowerStateOffOnly => 'off only';

  @override
  String get globalPowerStateOnOnly => 'on only';

  @override
  String get globalPowerStateToggleOnly => 'toggle only';

  @override
  String get globalPowerNothing => 'No machines have power control set up yet';

  @override
  String globalPowerResultOn(int count, int total) {
    return 'Powered on $count of $total machines';
  }

  @override
  String globalPowerResultOff(int count, int total) {
    return 'Powered off $count of $total machines';
  }

  @override
  String get powerScreenTitle => 'Advanced Power Switch';

  @override
  String get powerScreenBanner =>
      'For printers whose power is a Klipper macro rather than a Moonraker power device. Turn it on and set a Power Off macro (the common case), a Power On macro, both, or a single toggle. The tile\'s power button uses any of them.';

  @override
  String get powerUseSwitch => 'Use macros';

  @override
  String get powerNeedMacro =>
      'Set at least one macro: a Power Off (or Power On) macro, or a toggle.';

  @override
  String get powerOnMacro => 'Power On macro';

  @override
  String get powerOffMacro => 'Power Off macro';

  @override
  String get powerToggleSection => 'Or a single toggle macro';

  @override
  String get powerToggleMacro => 'Power Toggle macro';

  @override
  String get powerToggleBulkNote =>
      'A toggle works the tile\'s power button. For Power all machines, set a Power On and/or Power Off macro.';

  @override
  String get powerMenuTitle => 'Advanced Power Switch';

  @override
  String get powerMenuSubtitle => 'Control printer power with a macro';

  @override
  String get powerMacroTooltip => 'Power';

  @override
  String powerMacroToggleConfirm(String name) {
    return 'Switch $name power?';
  }

  @override
  String powerMacroChooseTitle(String name) {
    return 'Switch $name power';
  }

  @override
  String lightChooseTitle(String name) {
    return 'Switch $name light';
  }

  @override
  String get tileOpacityTitle => 'Tile opacity';

  @override
  String get tileOpacityDesc =>
      'How see-through the tiles are (0-100), so a background shows through. The camera feed stays solid.';

  @override
  String get dashboardShowWebcams => 'Webcams';

  @override
  String get dashboardShowWebcamsSubtitle =>
      'Show or hide each printer\'s webcam';

  @override
  String get updateNotesUnavailable =>
      'Couldn\'t load what\'s new - check your connection, or view it on GitHub.';

  @override
  String get updateViewOnGithub => 'View on GitHub';

  @override
  String get cameraConfigTooltip => 'Set camera URL';

  @override
  String get cameraConfigTitle => 'Custom camera';

  @override
  String get cameraConfigDescription =>
      'Show a camera that isn\'t connected to Klipper - like an old phone used as a webcam. Enter the address shown in Mainsail\'s webcam settings.';

  @override
  String get cameraConfigUrlLabel => 'Camera URL';

  @override
  String get cameraConfigRemoteNote =>
      'Works on Wi-Fi, and remotely through your printer. Only cameras on your home network (private addresses) can be reached remotely.';

  @override
  String get cameraConfigInvalid =>
      'Enter a full address, e.g. http://192.168.0.107:8080/video';

  @override
  String get cameraConfigUseDefault => 'Use Klipper camera';

  @override
  String get cameraConfigApply => 'Apply';

  @override
  String get dashboardShowCameraIcons => 'Camera config icons';

  @override
  String get dashboardShowCameraIconsSubtitle =>
      'Show the gear on each camera for setting a custom URL';

  @override
  String get appTitle => 'Moongate';

  @override
  String get languagePickerTitle => 'Choose your language';

  @override
  String get languagePickerSubtitle =>
      'You can change this any time from the menu.';

  @override
  String get languagePickerContinue => 'Continue';

  @override
  String get menuLanguage => 'Language';

  @override
  String get languageSystemDefault => 'System default';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonOk => 'OK';

  @override
  String get commonClose => 'Close';

  @override
  String get commonSave => 'Save';

  @override
  String get commonDone => 'Done';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonShowKeyboard => 'Show keyboard';

  @override
  String get dashboardSignInRetrying =>
      'Reconnecting to the cloud - sign-in is busy, retrying. Your printers will come back automatically.';

  @override
  String get commonRemove => 'Remove';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonEnable => 'Enable';

  @override
  String get commonDisable => 'Disable';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsRemoveAllTitle => 'Remove all printers from this device';

  @override
  String get settingsRemoveAllSubtitle =>
      'Clears the local printer cache. Your Supabase account is kept so re-pairing works seamlessly.';

  @override
  String get settingsRemoveAllConfirmTitle => 'Remove all printers?';

  @override
  String get settingsRemoveAllConfirmBody =>
      'All paired printers will be removed from this device. You can re-add them by running MOONGATE_PAIR on the printer.';

  @override
  String get settingsRemoveAllConfirmAction => 'Remove all';

  @override
  String get dashboardAddPrinter => 'Add printer';

  @override
  String get dashboardRemovePrinter => 'Remove printer';

  @override
  String get dashboardMenuTooltip => 'Menu';

  @override
  String get dashboardRemovePrinterTitle => 'Remove printer?';

  @override
  String dashboardRemovePrinterBody(String name) {
    return 'Remove \"$name\" from Moongate?';
  }

  @override
  String get dashboardRemoveSupabaseUnreachable =>
      'Removed locally, but couldn’t reach Supabase. Run MOONGATE_RESET_OWNER on the Pi if re-pairing fails.';

  @override
  String get dashboardBackUpConfig => 'Back up config';

  @override
  String get dashboardBackUpConfigSubtitle =>
      'Save to a file before reinstalling';

  @override
  String get dashboardRestoreConfig => 'Restore config';

  @override
  String get dashboardRestoreConfigSubtitle => 'Load from a backup file';

  @override
  String get dashboardThemeHeading => 'Theme';

  @override
  String get dashboardThemeSystem => 'Phone colours';

  @override
  String get dashboardThemeDark => 'Dark';

  @override
  String get dashboardThemeLight => 'Light';

  @override
  String get dashboardThemeCustom => 'Custom';

  @override
  String get dashboardFontHeading => 'Font';

  @override
  String get fontStandard => 'Default';

  @override
  String get fontRounded => 'Rounded';

  @override
  String get fontSerif => 'Serif';

  @override
  String get fontReadable => 'High-readability';

  @override
  String get dashboardCustomiseColours => 'Customise colours';

  @override
  String get dashboardCustomiseColoursSubtitle =>
      'Edit the five theme slots - HEX or palette';

  @override
  String get dashboardFontSizeHeading => 'Display size';

  @override
  String get dashboardLayoutHeading => 'Dashboard layout';

  @override
  String dashboardColumnCount(int count) {
    return '$count col';
  }

  @override
  String get dashboardRotateWithDevice => 'Rotate with device';

  @override
  String get dashboardRotateWithDeviceSubtitle =>
      'Unlocks landscape orientation';

  @override
  String get dashboardAutoArrange => 'Auto-arrange by status';

  @override
  String get dashboardAutoArrangeSubtitle =>
      'Sort tiles by activity. Turn off to drag tiles into your own order.';

  @override
  String get dashboardShowButtons => 'Show dashboard buttons';

  @override
  String get dashboardShowButtonsSubtitle =>
      'Show the add and reorder buttons at the bottom. Add printers from the menu when hidden.';

  @override
  String get dashboardReorderHint => 'Hold and drag a tile to reorder';

  @override
  String get dashboardReorderStart => 'Reorder';

  @override
  String get dashboardReorderDone => 'Done';

  @override
  String get dashboardCameraFeedHeading => 'Dashboard camera feed';

  @override
  String get dashboardCameraFeedSubtitle =>
      'How often tiles refresh the camera. Lower rates use much less data.';

  @override
  String get cameraFeedsMenuTitle => 'Dashboard Camera Feeds';

  @override
  String get cameraFeedsMenuSubtitle => 'Local & tunnel feed rates';

  @override
  String get cameraFeedsIntro =>
      'How often each tile refreshes its camera. Moongate uses the Local rate while you\'re on Wi-Fi (even away from home), and the Tunnel rate on mobile data - keeping a fast feed on Wi-Fi and a lighter one on cellular to save data.';

  @override
  String get cameraFeedsLocalRate => 'Local feed polling rate';

  @override
  String get cameraFeedsTunnelRate => 'Tunnel feed polling rate';

  @override
  String get dashboardAboutHeading => 'About';

  @override
  String get dashboardWhatsNew => 'What\'s new';

  @override
  String get dashboardWhatsNewSubtitle => 'Recent changes at a glance';

  @override
  String get dashboardHowPairingWorks => 'How pairing works';

  @override
  String get dashboardHowPairingWorksSubtitle =>
      'Pairing, reinstalling & restore';

  @override
  String get dashboardReportProblem => 'Report a problem';

  @override
  String get dashboardReportProblemSubtitle => 'Send a bug report or feedback';

  @override
  String get dashboardAppLock => 'App lock';

  @override
  String get dashboardAppLockOn => 'On - unlock required on launch';

  @override
  String get dashboardAppLockOff => 'Off';

  @override
  String get dashboardBuyMeCoffee => 'Buy me a coffee';

  @override
  String get dashboardBuyMeCoffeeSubtitle => 'Tip the dev via PayPal';

  @override
  String get dashboardDeleteData => 'Delete my data';

  @override
  String get dashboardDeleteDataSubtitle =>
      'Erase your account and printers from the cloud';

  @override
  String get deleteDataConfirmTitle => 'Delete my data?';

  @override
  String get deleteDataConfirmBody =>
      'This permanently deletes your anonymous account and removes your printers and notification settings from the cloud. Your printers will need to be paired again. This can\'t be undone.';

  @override
  String get deleteDataDone => 'Your data has been deleted';

  @override
  String get deleteDataError => 'Couldn\'t delete your data. Please try again.';

  @override
  String get donationPromptTitle => 'Enjoying Moongate?';

  @override
  String get donationPromptBody =>
      'Moongate is a free side-project I build in my spare time. If it\'s useful to you, a small tip helps keep it going - no pressure, and I won\'t ask again.';

  @override
  String get donationPromptLater => 'Maybe later';

  @override
  String get dashboardSettings => 'Settings';

  @override
  String dashboardVersion(String version) {
    return 'Moongate v$version';
  }

  @override
  String get dashboardSaveBackupDialogTitle => 'Save Moongate backup';

  @override
  String get dashboardBackupFailed =>
      'Backup failed - could not save the file.';

  @override
  String dashboardBackupSuccess(int count) {
    return 'Backed up $count printer(s). This file can restore them on a new install - keep it private.';
  }

  @override
  String dashboardBackupSuccessListOnly(int count) {
    return 'Backed up $count printer(s) (list only - couldn’t reach the cloud for a restore code).';
  }

  @override
  String get dashboardInvalidBackupFile =>
      'Invalid backup file - please pick a Moongate config file.';

  @override
  String dashboardRestoreReconnected(int added, int count) {
    return '$added printer(s) restored - $count reconnected and coming back online.';
  }

  @override
  String dashboardRestoreNoneReconnected(int added) {
    return '$added printer(s) restored, but none reconnected - the backup’s restore code didn’t match any printers (it may be from an older backup, or already used). Re-pair them to bring them online.';
  }

  @override
  String dashboardRestoreListOnly(int added) {
    return '$added printer(s) restored (list only). Re-pair each printer to bring it online.';
  }

  @override
  String get dashboardRestoreApplied =>
      'Dashboard restored to match your backup.';

  @override
  String get dashboardRestoreReplaceTitle => 'Replace dashboard?';

  @override
  String dashboardRestoreReplaceBody(String names) {
    return 'These printers are on this dashboard but not in the backup: $names. Restoring will remove them so the dashboard matches the backup exactly. They stay paired - you can re-add or restore them later.';
  }

  @override
  String get dashboardRestoreReplaceConfirm => 'Replace';

  @override
  String get dashboardRemoveSheetTitle => 'Remove a printer';

  @override
  String dashboardPrinterIdShort(String id) {
    return 'id $id…';
  }

  @override
  String get dashboardPairingHelpPluginTitle => 'First: install the Pi plugin';

  @override
  String get dashboardPairingHelpPluginBody =>
      'Moongate needs its plugin running on your Klipper printer before you can pair. If you haven\'t installed it yet, open the quick-start guide.';

  @override
  String get dashboardPairingHelpPluginAction => 'Open the setup guide';

  @override
  String get dashboardPairingHelpPairOnceTitle => 'Pair once';

  @override
  String get dashboardPairingHelpPairOnceBody =>
      'Scan the QR (or enter the GATE code) to add a printer - that link is saved in this app.';

  @override
  String get dashboardPairingHelpUpdatesTitle =>
      'App updates keep your printers';

  @override
  String get dashboardPairingHelpUpdatesBody =>
      'Updating Moongate never needs a re-pair.';

  @override
  String get dashboardPairingHelpReinstallTitle => 'Reinstalling or new phone?';

  @override
  String get dashboardPairingHelpReinstallBody =>
      'Back up first (Menu → Back up config), then Restore brings your printers back online - no re-pairing.';

  @override
  String get dashboardPairingHelpNoBackupTitle => 'No backup?';

  @override
  String get dashboardPairingHelpNoBackupBody =>
      'Run MOONGATE_RESET_OWNER on the printer\'s console, then pair again.';

  @override
  String get dashboardDontShowAgain => 'Don\'t show this again';

  @override
  String dashboardUpdateAvailable(String version) {
    return 'Update available - v$version';
  }

  @override
  String get dashboardUpdateLater => 'Later';

  @override
  String get dashboardUpdate => 'Update';

  @override
  String get dashboardEmptyTitle => 'No printers added yet';

  @override
  String get dashboardEmptyBody =>
      'Tap the button below to pair your first printer.';

  @override
  String get pairingTitle => 'Add Printer';

  @override
  String get pairingIntro =>
      'Run MOONGATE_PAIR in your Klipper console - scan the QR or type the GATE code shown on the console.';

  @override
  String get pairingNameLabel => 'Printer name';

  @override
  String get pairingNameHint => 'e.g. Voron 2.4';

  @override
  String get pairingScanButton => 'Scan QR code';

  @override
  String get pairingScanRecommended => 'Recommended - connects instantly';

  @override
  String get pairingOr => 'OR';

  @override
  String get pairingGateCodeLabel => 'GATE code';

  @override
  String get pairingGateCodeHint =>
      'Type the 8-digit code shown in your Klipper console.';

  @override
  String get pairingGateCodeValid => 'Code looks valid ✓';

  @override
  String get pairingGateCodeWarning =>
      'Alternative method. Without the QR, the printer can take up to about a minute to come online - it\'s waiting for the secure tunnel to connect. Scan the QR code above for an instant connection.';

  @override
  String get pairingCameraPermissionNeeded => 'Camera permission needed';

  @override
  String get pairingCameraUnavailable => 'Camera unavailable';

  @override
  String get pairingCancelScan => 'Cancel scan';

  @override
  String pairingQrScanned(String code) {
    return 'QR scanned - code $code';
  }

  @override
  String get pairingRescan => 'Rescan';

  @override
  String get pairingAdvancedTitle => 'Advanced - printer on a custom network?';

  @override
  String get pairingAdvancedBody =>
      'Most people can leave this blank. If your printer is behind a reverse proxy (Traefik, Caddy, NPM) or in Docker, enter the same address you use to open its web page (Mainsail / Fluidd) in a browser.';

  @override
  String get pairingAddressLabel => 'Printer address';

  @override
  String get pairingAddressHint => '192.168.1.50:7125';

  @override
  String get pairingPairButton => 'Pair printer';

  @override
  String get pairingRestoreHint =>
      'Reinstalling? Restore your saved printers from a backup file. You\'ll still re-pair each one to bring it online.';

  @override
  String get pairingImportButton => 'Import config from file';

  @override
  String get pairingReportButton => 'Trouble pairing? Send a report';

  @override
  String get pairingCameraPermissionTitle => 'Camera permission required';

  @override
  String get pairingCameraPermissionBody =>
      'Moongate needs camera access to scan QR codes.\n\nOpen Settings → Apps → Moongate → Permissions and enable Camera, then come back and try again.';

  @override
  String get pairingOpenSettings => 'Open Settings';

  @override
  String get pairingErrorNotMoongateQr =>
      'Not a Moongate QR code. Run MOONGATE_PAIR on the printer to generate one.';

  @override
  String get pairingErrorOldQr =>
      'This QR code is from an older Moongate version. Update the Pi to v0.3.0 first.';

  @override
  String get pairingErrorNoCode =>
      'Scan the QR code, or type the GATE code from the printer console.';

  @override
  String get pairingErrorBadAddress =>
      'That printer address doesn\'t look right - try e.g. 192.168.1.50:7125';

  @override
  String pairingErrorFailed(String error) {
    return 'Pairing failed: $error';
  }

  @override
  String get pairingImportInvalidFile =>
      'Invalid backup file - please pick a Moongate config file.';

  @override
  String get pairingImportNoNewPrinters =>
      'No new printers found in that file.';

  @override
  String pairingImportRestoredReconnected(int count, int reconnected) {
    return '$count printer(s) restored - $reconnected reconnected, coming back online.';
  }

  @override
  String pairingImportRestoredRepair(int count) {
    return '$count printer(s) restored - re-pair each Pi to bring it online.';
  }

  @override
  String get customThemeTitle => 'Custom theme';

  @override
  String get customThemeResetTooltip => 'Reset to defaults';

  @override
  String get customThemeResetConfirmTitle => 'Reset custom theme?';

  @override
  String get customThemeResetConfirmBody =>
      'All five colour slots will be reverted to the default purple-on-dark palette.';

  @override
  String get customThemeReset => 'Reset';

  @override
  String get customThemePreview => 'Preview';

  @override
  String get customThemeAccent => 'Accent';

  @override
  String get customThemeAccentDesc => 'Buttons, FAB, progress bars, links';

  @override
  String get customThemeBackground => 'Page background';

  @override
  String get customThemeBackgroundDesc => 'Behind every screen';

  @override
  String get customThemeSurface => 'Cards & tiles';

  @override
  String get customThemeSurfaceDesc => 'Dashboard tiles, sheets, drawer';

  @override
  String get customThemeText => 'Text';

  @override
  String get customThemeTextDesc => 'Body and heading text on surfaces';

  @override
  String get customThemeError => 'Error / Stop';

  @override
  String get customThemeErrorDesc => 'Destructive actions, error overlays';

  @override
  String get customThemeEstop => 'E-STOP button';

  @override
  String get customThemeEstopDesc => 'Emergency-stop ring and icon';

  @override
  String get customThemePresets => 'Presets';

  @override
  String get customThemeInvalidHex => 'Not a valid hex colour';

  @override
  String get customThemeSamplePrinter => 'Sample printer';

  @override
  String get customThemePrinting => 'Printing';

  @override
  String get tilePauseFailed => 'Could not reach printer - pause failed';

  @override
  String get tileResumeFailed => 'Could not reach printer - resume failed';

  @override
  String get tileStopAgainToCancel => 'Press STOP again to cancel the print';

  @override
  String get tileLocal => 'Local';

  @override
  String get tileTunnel => 'Tunnel';

  @override
  String get tilePrinting => 'Printing';

  @override
  String get tilePaused => 'Paused';

  @override
  String get tileResume => 'Resume';

  @override
  String get tilePause => 'Pause';

  @override
  String get tileConfirmStop => 'Confirm stop';

  @override
  String get tileStopPrint => 'Stop print';

  @override
  String get tileFirmwareRestart => 'Firmware restart';

  @override
  String get tileEmergencyStop => 'Emergency stop · double-tap';

  @override
  String get tileEmergencyStopFailed =>
      'Could not reach printer - emergency stop failed';

  @override
  String get tilePrintComplete => 'Print complete';

  @override
  String get tilePrintCancelled => 'Print cancelled';

  @override
  String get tilePrinterError => 'Printer error';

  @override
  String get tileKlipperStarting => 'Klipper starting';

  @override
  String get tileReady => 'Ready';

  @override
  String get tileOffline => 'Offline';

  @override
  String get tileStartingUp => 'Starting up…';

  @override
  String get tileConnected => 'Connected';

  @override
  String get tileConnecting => 'Connecting…';

  @override
  String get tilePrinterUnreachable => 'Printer unreachable';

  @override
  String get tileWaitingForHeartbeat => 'Waiting for first heartbeat';

  @override
  String get tilePrinterIdle => 'Printer idle';

  @override
  String get tileReachingPrinter => 'Reaching printer';

  @override
  String get tileRemoteReady => 'Remote access ready';

  @override
  String get tileRemoteConnecting => 'Remote connecting…';

  @override
  String get tileIdle => 'Idle';

  @override
  String get tileDone => 'Done';

  @override
  String get tileCancelled => 'Cancelled';

  @override
  String get tileClearJobTooltip => 'Clear and set to idle';

  @override
  String get tileClearJobFailed => 'Couldn\'t reset the printer';

  @override
  String get dashboardBackgroundTitle => 'Dashboard background';

  @override
  String get dashboardBackgroundNone => 'None - theme colour';

  @override
  String get dashboardBackgroundCustom => 'Custom image';

  @override
  String get dashboardBackgroundRemove => 'Remove background';

  @override
  String get dashboardBackgroundSet => 'Background updated';

  @override
  String get uiGuideSectionTileButtons => 'Tile buttons';

  @override
  String get uiGuideFilesTitle => 'Print a file';

  @override
  String get uiGuideFilesDesc =>
      'Browse the printer\'s stored G-code files and start one.';

  @override
  String get uiGuideMacrosTitle => 'Macros';

  @override
  String get uiGuideMacrosDesc => 'Run one of the printer\'s Klipper macros.';

  @override
  String get uiGuidePowerTitle => 'Power';

  @override
  String get uiGuidePowerDesc =>
      'Switch the printer on or off, when it has a power device.';

  @override
  String get uiGuideLightingTitle => 'Lighting';

  @override
  String get uiGuideLightingDesc =>
      'Toggle the printer\'s light; the bulb glows when it\'s on.';

  @override
  String get uiGuideCameraViewTitle => 'Camera';

  @override
  String get uiGuideCameraViewDesc => 'Open the live camera full-screen.';

  @override
  String get uiGuideCameraSetupTitle => 'Camera setup';

  @override
  String get uiGuideCameraSetupDesc =>
      'Point a tile at a camera that isn\'t wired into Klipper.';

  @override
  String get uiGuideClearJobTitle => 'Clear a finished print';

  @override
  String get uiGuideClearJobDesc =>
      'Tap the × on a Done or Cancelled tile to set it back to Idle.';

  @override
  String get tileError => 'Error';

  @override
  String get tileStarting => 'Starting';

  @override
  String get tileConnectingBadge => 'Connecting';

  @override
  String get appLockTitle => 'App lock';

  @override
  String get appLockIntro =>
      'Require a PIN - and optionally your fingerprint or face - before Moongate will open. The lock always appears when the app is started fresh.';

  @override
  String get appLockSubtitle => 'PIN required to open the app';

  @override
  String get appLockBiometricTitle => 'Biometric unlock';

  @override
  String get appLockBiometricSubtitle =>
      'Use fingerprint or face - PIN stays as a fallback';

  @override
  String get appLockChangePin => 'Change PIN';

  @override
  String get appLockAutoLock => 'Auto-lock';

  @override
  String get appLockPinUpdated => 'PIN updated';

  @override
  String get appLockChoosePinTitle => 'Choose a PIN';

  @override
  String get appLockChoosePinSubtitle => 'Enter 4-6 digits';

  @override
  String get appLockConfirmPinTitle => 'Confirm PIN';

  @override
  String get appLockPinsDontMatch => 'PINs don\'t match';

  @override
  String get appLockEnterCurrentPin => 'Enter current PIN';

  @override
  String get appLockTimeoutImmediately => 'Immediately';

  @override
  String get appLockTimeoutOneMinute => 'After 1 minute';

  @override
  String get appLockTimeoutFiveMinutes => 'After 5 minutes';

  @override
  String get appLockTimeoutFifteenMinutes => 'After 15 minutes';

  @override
  String get appLockTimeoutColdLaunch => 'Only on app launch';

  @override
  String get lockEnterPin => 'Enter your PIN';

  @override
  String get lockSubtitle => 'Moongate is locked';

  @override
  String lockTooManyAttempts(int seconds) {
    return 'Too many attempts. Try again in ${seconds}s';
  }

  @override
  String get lockWrongPin => 'Wrong PIN';

  @override
  String get lockUseBiometrics => 'Use biometrics';

  @override
  String get lockForgotPin => 'Forgot PIN?';

  @override
  String get lockBiometricReason => 'Unlock Moongate';

  @override
  String get lockResetTitle => 'Reset Moongate?';

  @override
  String get lockResetBody =>
      'This removes the app lock and clears the paired printers from this device so you can start over. Your printers are not deleted - re-pair them by running MOONGATE_PAIR on each one.';

  @override
  String get lockResetConfirm => 'Reset';

  @override
  String get pinContinue => 'Continue';

  @override
  String printerStartingUpRetry(int seconds) {
    return 'Printer is starting up. Retrying in ${seconds}s…';
  }

  @override
  String printerCouldNotReach(String error) {
    return 'Could not reach printer: $error';
  }

  @override
  String get printerAddressCleared => 'Custom address cleared';

  @override
  String get printerAddressUpdated => 'Printer address updated';

  @override
  String printerTunnelUnreachable(String description) {
    return 'Cloudflare tunnel unreachable.\n$description';
  }

  @override
  String get printerEdit => 'Edit printer';

  @override
  String get printerLocalNetwork => 'Local network';

  @override
  String get printerTunnelVia => 'Tunnel via Moongate';

  @override
  String get printerCameraTooltip => 'Camera';

  @override
  String get cameraConnecting => 'Connecting to camera…';

  @override
  String get cameraNoCamera => 'No camera configured for this printer.';

  @override
  String get cameraHintBody =>
      'Webcam won\'t load here remotely - open the Moongate camera.';

  @override
  String get cameraHintOpen => 'Open';

  @override
  String get printerUnreachable => 'Printer unreachable';

  @override
  String get printerUseTunnel => 'Use tunnel';

  @override
  String get printerAddressInvalid => 'Try e.g. 192.168.1.50:7125';

  @override
  String get printerNameLabel => 'Printer name';

  @override
  String get printerAddressLabel => 'Printer address (advanced)';

  @override
  String get printerAddressHint => '192.168.1.50:7125';

  @override
  String get printerAddressHelper =>
      'Only for reverse-proxy / Docker setups. Leave blank to use automatic discovery.';

  @override
  String get feedbackTitle => 'Report a problem';

  @override
  String get feedbackTroublePairing => 'Trouble pairing?';

  @override
  String get feedbackDescription =>
      'Tell us what\'s happening. Your app version, device, network and printer details are attached automatically to help us track it down.';

  @override
  String get feedbackPairingDescription =>
      'Describe what happens when you try to add the printer. Your network + discovery details are attached automatically so we can see why it isn\'t connecting.';

  @override
  String get feedbackWhichPrinter => 'Which printer? (optional)';

  @override
  String get feedbackGeneralOption => 'General / not printer-specific';

  @override
  String get feedbackCommentLabel => 'What went wrong?';

  @override
  String get feedbackCommentHint =>
      'e.g. \"Printer shows Connected / idle but it\'s actually ready - opens fine when I tap the tile.\"';

  @override
  String get feedbackContactLabel => 'Email or contact (optional)';

  @override
  String get feedbackContactHint => 'Only if you want a reply';

  @override
  String get feedbackSending => 'Sending…';

  @override
  String get feedbackSend => 'Send report';

  @override
  String get feedbackSuccess => 'Thanks - your report was sent.';

  @override
  String get feedbackError =>
      'Couldn\'t send - check your connection and try again.';

  @override
  String get splashTagline => 'Klipper remote control';

  @override
  String get uiGuideTitle => 'Icon guide';

  @override
  String get uiGuideMenuSubtitle => 'What the dashboard icons mean';

  @override
  String get uiGuideIntro =>
      'A quick guide to the icons you\'ll see on the dashboard.';

  @override
  String get uiGuideSectionConnection => 'Connection';

  @override
  String get uiGuideSectionTemperatures => 'Temperatures';

  @override
  String get uiGuideSectionControls => 'Print controls';

  @override
  String get uiGuideSectionStatus => 'Status';

  @override
  String get uiGuideSectionWebcam => 'Camera & connection';

  @override
  String get uiGuideLocalTitle => 'Local network';

  @override
  String get uiGuideLocalDesc =>
      'Connected directly over your Wi-Fi - the fastest path.';

  @override
  String get uiGuideTunnelTitle => 'Remote (tunnel)';

  @override
  String get uiGuideTunnelDesc =>
      'Connected from anywhere through the secure Cloudflare tunnel.';

  @override
  String get uiGuideTunnelReadyTitle => 'Remote ready';

  @override
  String get uiGuideTunnelReadyDesc =>
      'The tunnel is up, so remote access is available.';

  @override
  String get uiGuideTunnelConnectingTitle => 'Remote connecting';

  @override
  String get uiGuideTunnelConnectingDesc =>
      'The remote tunnel is still establishing.';

  @override
  String get uiGuideHotendTitle => 'Hotend / nozzle';

  @override
  String get uiGuideHotendDesc => 'Current nozzle temperature.';

  @override
  String get uiGuideBedTitle => 'Heated bed';

  @override
  String get uiGuideBedDesc => 'Current bed temperature.';

  @override
  String get uiGuideChamberTitle => 'Chamber';

  @override
  String get uiGuideChamberDesc =>
      'Chamber temperature - shown only if your printer reports one.';

  @override
  String get uiGuideResumeTitle => 'Resume';

  @override
  String get uiGuideResumeDesc => 'Resume a paused print.';

  @override
  String get uiGuidePauseTitle => 'Pause';

  @override
  String get uiGuidePauseDesc => 'Pause the current print.';

  @override
  String get uiGuideStopTitle => 'Stop';

  @override
  String get uiGuideStopDesc => 'Cancel the print - tap twice to confirm.';

  @override
  String get uiGuideEstopTitle => 'Emergency stop';

  @override
  String get uiGuideEstopDesc =>
      'Double-tap the red triangle to stop the printer immediately (Klipper M112).';

  @override
  String get uiGuideFirmwareRestartTitle => 'Firmware restart';

  @override
  String get uiGuideFirmwareRestartDesc =>
      'Restart Klipper when the printer is idle or in error.';

  @override
  String get uiGuideStatusReadyTitle => 'Ready / complete';

  @override
  String get uiGuideStatusReadyDesc =>
      'The printer is idle, or finished its last print.';

  @override
  String get uiGuideStatusCancelledTitle => 'Cancelled';

  @override
  String get uiGuideStatusCancelledDesc => 'The last print was cancelled.';

  @override
  String get uiGuideStatusErrorTitle => 'Error';

  @override
  String get uiGuideStatusErrorDesc =>
      'Klipper reported an error - open the printer for details.';

  @override
  String get uiGuideStatusStartingTitle => 'Starting up';

  @override
  String get uiGuideStatusStartingDesc =>
      'Klipper is starting; controls appear once it\'s ready.';

  @override
  String get uiGuideOfflineTitle => 'Offline';

  @override
  String get uiGuideOfflineDesc => 'The printer can\'t be reached right now.';

  @override
  String get uiGuideNoWebcamTitle => 'No camera';

  @override
  String get uiGuideNoWebcamDesc =>
      'No webcam snapshot is available for this printer.';

  @override
  String get uiGuideBack => 'Back to dashboard';

  @override
  String get printNotifTitle => 'Print notifications';

  @override
  String get printNotifSubtitle =>
      'Live progress and status while the app is in the background';

  @override
  String get printNotifPermissionNeeded =>
      'Allow notifications to turn this on.';

  @override
  String get printNotifPromptTitle => 'Get print notifications?';

  @override
  String get printNotifPromptBody =>
      'See live status for your printers - progress, temperatures, and alerts when a print starts, finishes or errors. You can change this any time in the menu.';

  @override
  String get printNotifPromptEnable => 'Turn on';

  @override
  String get printNotifPromptNotNow => 'Not now';

  @override
  String get printNotifWatching => 'Watching your printers…';

  @override
  String get printNotifNoPrinters => 'No printers';

  @override
  String get printNotifNoneOnline => 'No printers online';

  @override
  String get notifOnlineOnlyTitle => 'Show only online devices';

  @override
  String get notifOnlineOnlySubtitle =>
      'Hide offline machines from the status notification';

  @override
  String get notifPollIntervalTitle => 'Update frequency';

  @override
  String get notifContentTitle => 'Notification content';

  @override
  String get notifContentSubtitle => 'Choose & reorder what\'s shown';

  @override
  String get notifContentIntro =>
      'Pick which details appear on each print\'s notification card, and drag them into the order you want.';

  @override
  String get notifContentPreview => 'Preview';

  @override
  String get notifFieldProgress => 'Progress';

  @override
  String get notifFieldRemaining => 'Time remaining';

  @override
  String get notifFieldEta => 'Finish time';

  @override
  String get notifFieldHotend => 'Hotend temp';

  @override
  String get notifFieldBed => 'Bed temp';

  @override
  String get printAlertReady => 'Printer ready';

  @override
  String get printStatusReady => 'Ready';

  @override
  String get printStatusHeating => 'Heating';

  @override
  String get printStatusIdle => 'Idle';

  @override
  String get printStatusOffline => 'Offline';

  @override
  String get printStatusPaused => 'Paused';

  @override
  String get printStatusComplete => 'Complete';

  @override
  String get printStatusCancelled => 'Cancelled';

  @override
  String get printStatusError => 'Error';

  @override
  String get printStatusStartingUp => 'Starting up';

  @override
  String get printStatusPrinting => 'Printing';

  @override
  String get printNotifStarted => 'Printing started';

  @override
  String get printNotifFinished => 'Finished';

  @override
  String get notifClearAction => 'Clear';

  @override
  String get printAlertStarted => 'Started printing';

  @override
  String get printAlertResumed => 'Resumed printing';

  @override
  String get printAlertPaused => 'Print paused';

  @override
  String get printAlertComplete => 'Print complete';

  @override
  String get printAlertCancelled => 'Print cancelled';

  @override
  String get printAlertError => 'Printer error';

  @override
  String get tileOpenFiles => 'Print a file';

  @override
  String get gcodeSheetTitle => 'Start a print';

  @override
  String get gcodeLoading => 'Loading files…';

  @override
  String get gcodeEmpty => 'No G-code files on this printer';

  @override
  String get gcodeError => 'Couldn\'t load files';

  @override
  String get gcodeStartButton => 'Start print';

  @override
  String get gcodeStartAction => 'Start';

  @override
  String get gcodeConfirmTitle => 'Start print?';

  @override
  String gcodeConfirmBody(String file) {
    return 'Start printing $file?';
  }

  @override
  String gcodeStarted(String file) {
    return 'Started printing $file';
  }

  @override
  String get gcodeStartFailed => 'Couldn\'t start the print';

  @override
  String get tileMacros => 'Macros';

  @override
  String get macrosSheetTitle => 'Macros';

  @override
  String get macrosLoading => 'Loading macros…';

  @override
  String get macrosError => 'Couldn\'t load macros';

  @override
  String get macrosEmpty => 'No macros on this printer';

  @override
  String get macroFavourite => 'Pin to top';

  @override
  String get macroUnfavourite => 'Unpin';

  @override
  String get macroConfirmTitle => 'Run macro?';

  @override
  String macroConfirmBody(String macro) {
    return 'Run $macro on this printer?';
  }

  @override
  String get macroRunAction => 'Run';

  @override
  String macroSent(String macro) {
    return 'Sent $macro';
  }

  @override
  String macroFailed(String macro) {
    return 'Couldn\'t send $macro';
  }

  @override
  String get preheatTitle => 'Preheat';

  @override
  String get preheatHotend => 'Hotend';

  @override
  String get preheatBed => 'Bed';

  @override
  String get preheatHint => 'Leave a box empty to keep that heater unchanged.';

  @override
  String get preheatSoakLabel => 'Heat-soak timer';

  @override
  String get preheatSoakHelp =>
      'Notify me after this many minutes. 0 = no timer.';

  @override
  String get preheatMinutes => 'min';

  @override
  String get preheatSet => 'Set';

  @override
  String get preheatNotifWarning =>
      'Heat-soak alerts need print notifications switched on.';

  @override
  String get preheatNotifEnable => 'Turn on';

  @override
  String preheatSetConfirm(String summary) {
    return 'Set $summary';
  }

  @override
  String preheatSoakIn(int minutes) {
    return 'heat-soak alert in $minutes min';
  }

  @override
  String get preheatFailed => 'Couldn\'t set the temperatures';

  @override
  String get heatsoakDoneTitle => 'Heat-soak complete';

  @override
  String heatsoakDoneBody(String printer) {
    return '$printer is up to temperature';
  }

  @override
  String get tutorialOfferTitle => 'Take a quick tour?';

  @override
  String get tutorialOfferBody =>
      'Would you like a quick walkthrough of how Moongate works?';

  @override
  String get tutorialOfferDontRemind => 'Don\'t remind me again';

  @override
  String get tutorialOfferNo => 'No thanks';

  @override
  String get tutorialOfferStart => 'Start tutorial';

  @override
  String get tutorialMenuTitle => 'App tutorial';

  @override
  String get tutorialNext => 'Next';

  @override
  String get tutorialDone => 'Done';

  @override
  String get tutorialSkip => 'End';

  @override
  String get tutorialBack => 'Back';

  @override
  String get tutorialLocalBar =>
      'The colour bar shows how Moongate is reaching this printer. Green with a Wi-Fi icon means you are on the same network, a fast, direct local connection.';

  @override
  String get tutorialTunnelBar =>
      'Orange with a cloud icon means you are away from home, connected securely over the internet through your printer\'s tunnel. Moongate switches between the two automatically.';

  @override
  String get tutorialRemoteBuilding =>
      'When you first pair a printer, remote access isn\'t instant. This little cloud marker means the secure tunnel is still building in the background. Once it turns into a green cloud tick, you can reach this printer from anywhere.';

  @override
  String get tutorialHotend => 'This is your hotend, the nozzle temperature.';

  @override
  String get tutorialBed => 'And this is the heated bed.';

  @override
  String get tutorialChamber =>
      'If your printer has a chamber sensor, its temperature shows here too.';

  @override
  String get tutorialTemps =>
      'These are the live temperatures: the hotend (nozzle), the heated bed, and - if your printer has a chamber sensor - the chamber.';

  @override
  String get tutorialEstop =>
      'This is the emergency stop. It needs a double tap to fire, so it can\'t be triggered by accident, and it halts the printer immediately.';

  @override
  String get tutorialWebcam =>
      'Tapping the camera view opens the full printer interface, the live Klipper screen.';

  @override
  String get tutorialPreheatPress =>
      'Press and hold a printer\'s name or its temperatures to display the preheat panel.';

  @override
  String get tutorialPreheatSheet =>
      'Here you can set hotend and bed targets and an optional heat-soak time.';

  @override
  String get tutorialAddPrinter =>
      'Tap the plus button any time to add another printer and pair it.';

  @override
  String get tutorialMenuIcon =>
      'This is the menu. You can open it any time from here.';

  @override
  String get tutorialMenuPrinters =>
      'Add another printer, or remove one you no longer use.';

  @override
  String get tutorialMenuBackup =>
      'Back up your setup to a file, or restore it on another device.';

  @override
  String get tutorialMenuTheme =>
      'Choose a light, dark, or fully custom colour theme.';

  @override
  String get tutorialMenuDisplaySize =>
      'Drag this to make everything bigger or smaller to suit your eyes.';

  @override
  String get tutorialMenuColumns =>
      'Lay your printers out in one, two, or three columns.';

  @override
  String get tutorialMenuCameras =>
      'Set how often the webcam feeds refresh, and turn each printer\'s camera on or off.';

  @override
  String get tutorialMenuAbout =>
      'What\'s new, how pairing works, an icon guide, and where to report a problem all live here.';

  @override
  String get tutorialMenuSupport =>
      'Buying me a coffee helps keep Moongate free for everyone and open source.';

  @override
  String get tutorialMenuSettings =>
      'Settings has two options inside: clear all your printers, or delete all your data and start completely fresh.';

  @override
  String get tutorialMenuLanguage =>
      'And you can switch the app\'s language here - Moongate speaks eight. That\'s the tour, enjoy!';

  @override
  String get notifPauseTooltip => 'Pause monitoring';

  @override
  String get notifResumeTooltip => 'Resume monitoring';

  @override
  String get notifPausedSnack => 'Print monitoring paused';

  @override
  String get notifResumedSnack => 'Print monitoring resumed';

  @override
  String get tutorialPauseButton =>
      'This pauses print monitoring. When your printers will be off for a while, tap it to stop the background checks and save battery, then tap again to resume.';
}
