// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get updateDownloading => 'Update wird heruntergeladen…';

  @override
  String get updateOpeningInstaller => 'Installation wird geöffnet…';

  @override
  String get updateFailed =>
      'Update konnte nicht automatisch abgeschlossen werden.';

  @override
  String get updateOpenInBrowser => 'Im Browser öffnen';

  @override
  String get lightingTitle => 'Beleuchtung';

  @override
  String get lightingMenuSubtitle =>
      'Steuere die Beleuchtung deiner Drucker vom Dashboard';

  @override
  String get lightingBanner =>
      'Wähle, welche Drucker eine steuerbare Beleuchtung haben. Aktiviere sie jeweils und lege entweder ein An-/Aus-Makropaar oder ein einzelnes Umschalt-Makro fest. Optional kannst du eine Statusquelle wählen, damit die Glühbirne den echten An-/Aus-Zustand anzeigt.';

  @override
  String get lightingNoPrinters => 'Noch keine Drucker zum Einrichten.';

  @override
  String get lightingShowOnTile => 'Auf Kachel anzeigen';

  @override
  String get lightingNeedMacro =>
      'Lege ein An-/Aus-Paar oder ein Umschalt-Makro fest, um zu aktivieren.';

  @override
  String get lightingLoadFailed =>
      'Makros dieses Druckers konnten nicht geladen werden (evtl. offline). Namen unten manuell eingeben.';

  @override
  String get lightingOnMacro => 'Makro für Licht AN';

  @override
  String get lightingOffMacro => 'Makro für Licht AUS';

  @override
  String get lightingToggleMacro => 'Umschalt-Makro';

  @override
  String get lightingToggleSection => 'Optional - Umschalt-Methode';

  @override
  String get lightingStatusSource => 'Lichtstatus-Quelle';

  @override
  String get lightingStatusSourceHelp =>
      'Optional. Ein Klipper-Objekt (z. B. output_pin caselight), dessen Wert Moongate mitteilt, ob das Licht an ist. Leer lassen, um den Zustand stattdessen anhand deiner Schaltvorgänge zu verfolgen.';

  @override
  String get lightingStatusHint => 'Beispiel: output_pin caselight';

  @override
  String get lightingNotSet => 'Nicht festgelegt';

  @override
  String get lightingPickMacro => 'Makro auswählen';

  @override
  String get lightingPickStatusSource => 'Statusquelle auswählen';

  @override
  String get lightingManualHint => 'Genauen Namen eingeben';

  @override
  String get lightingClear => 'Löschen';

  @override
  String get lightTurnOn => 'Licht einschalten';

  @override
  String get lightTurnOff => 'Licht ausschalten';

  @override
  String get lightToggleFailed => 'Drucker nicht erreichbar';

  @override
  String get powerTurnOn => 'Einschalten';

  @override
  String get powerTurnOff => 'Ausschalten';

  @override
  String powerConfirmOn(String name) {
    return '$name einschalten?';
  }

  @override
  String powerConfirmOff(String name) {
    return '$name ausschalten?';
  }

  @override
  String get powerToggleFailed => 'Stromzufuhr konnte nicht geändert werden';

  @override
  String get powerLockedWhilePrinting =>
      'Während des Drucks nicht ausschaltbar';

  @override
  String get globalPowerButtonTitle => 'Globale Ein/Aus-Taste';

  @override
  String get globalPowerButtonSubtitle =>
      'Eine Taste in der oberen Leiste, um deine gesamte Flotte ein- oder auszuschalten';

  @override
  String get globalPowerTooltip => 'Alle Drucker schalten';

  @override
  String get globalPowerSheetTitle => 'Alle Drucker schalten';

  @override
  String get globalPowerOnAll => 'Alle einschalten';

  @override
  String get globalPowerSlideOff => 'wischen, um alle auszuschalten';

  @override
  String get globalPowerConfirmOnTitle => 'Alle Drucker einschalten?';

  @override
  String get globalPowerConfirmOnBody =>
      'Dies schaltet jede erreichbare Maschine ein.';

  @override
  String get globalPowerPrintingNote =>
      'Druckende Drucker bleiben eingeschaltet';

  @override
  String get globalPowerStateWillSwitchOff => 'wird ausgeschaltet';

  @override
  String get globalPowerStateKeptPrinting => 'druckt, bleibt an';

  @override
  String get globalPowerStateOffline => 'offline, übersprungen';

  @override
  String get globalPowerStateOnOff => 'ein/aus';

  @override
  String get globalPowerStateOffOnly => 'nur aus';

  @override
  String get globalPowerStateOnOnly => 'nur ein';

  @override
  String get globalPowerStateToggleOnly => 'nur Umschalten';

  @override
  String get globalPowerNothing =>
      'Für noch keine Maschine ist eine Stromsteuerung eingerichtet';

  @override
  String globalPowerResultOn(int count, int total) {
    return '$count von $total Druckern eingeschaltet';
  }

  @override
  String globalPowerResultOff(int count, int total) {
    return '$count von $total Druckern ausgeschaltet';
  }

  @override
  String get powerScreenTitle => 'Erweiterter Netzschalter';

  @override
  String get powerScreenBanner =>
      'Für Drucker, deren Stromversorgung ein Klipper-Makro statt eines Moonraker-Stromgeräts ist. Aktiviere sie und lege ein Ausschalt-Makro fest (der häufige Fall), ein Einschalt-Makro, beide oder ein einzelnes Umschalt-Makro. Die Ein/Aus-Taste der Kachel nutzt jedes davon.';

  @override
  String get powerUseSwitch => 'Makros verwenden';

  @override
  String get powerNeedMacro =>
      'Lege mindestens ein Makro fest: ein Ausschalt-Makro (oder Einschalt-Makro) oder ein Umschalt-Makro.';

  @override
  String get powerOnMacro => 'Einschalt-Makro';

  @override
  String get powerOffMacro => 'Ausschalt-Makro';

  @override
  String get powerToggleSection => 'Oder ein einzelnes Umschalt-Makro';

  @override
  String get powerToggleMacro => 'Umschalt-Makro';

  @override
  String get powerToggleBulkNote =>
      'Ein Umschalt-Makro bedient die Ein/Aus-Taste der Kachel. Für „Alle Drucker schalten“ lege ein Einschalt- und/oder ein Ausschalt-Makro fest.';

  @override
  String get powerMenuTitle => 'Erweiterter Netzschalter';

  @override
  String get powerMenuSubtitle => 'Druckerstrom per Makro steuern';

  @override
  String get powerMacroTooltip => 'Strom';

  @override
  String powerMacroToggleConfirm(String name) {
    return 'Strom von $name umschalten?';
  }

  @override
  String powerMacroChooseTitle(String name) {
    return 'Strom von $name schalten';
  }

  @override
  String lightChooseTitle(String name) {
    return 'Licht von $name schalten';
  }

  @override
  String get tileOpacityTitle => 'Kachel-Deckkraft';

  @override
  String get tileOpacityDesc =>
      'Wie durchsichtig die Kacheln sind (0-100), damit ein Hintergrund durchscheint. Das Kamerabild bleibt deckend.';

  @override
  String get dashboardShowWebcams => 'Webcams';

  @override
  String get dashboardShowWebcamsSubtitle =>
      'Jede Drucker-Webcam ein- oder ausblenden';

  @override
  String get updateNotesUnavailable =>
      'Neuigkeiten konnten nicht geladen werden - prüfe deine Verbindung oder sieh sie dir auf GitHub an.';

  @override
  String get updateViewOnGithub => 'Auf GitHub ansehen';

  @override
  String get cameraConfigTooltip => 'Kamera-URL festlegen';

  @override
  String get cameraConfigTitle => 'Eigene Kamera';

  @override
  String get cameraConfigDescription =>
      'Zeige eine Kamera, die nicht mit Klipper verbunden ist - etwa ein altes Handy als Webcam. Gib die Adresse ein, die in den Webcam-Einstellungen von Mainsail steht.';

  @override
  String get cameraConfigUrlLabel => 'Kamera-URL';

  @override
  String get cameraConfigRemoteNote =>
      'Funktioniert im WLAN und aus der Ferne über deinen Drucker. Aus der Ferne sind nur Kameras in deinem Heimnetzwerk (private Adressen) erreichbar.';

  @override
  String get cameraConfigInvalid =>
      'Gib eine vollständige Adresse ein, z. B. http://192.168.0.107:8080/video';

  @override
  String get cameraConfigUseDefault => 'Klipper-Kamera verwenden';

  @override
  String get cameraConfigApply => 'Übernehmen';

  @override
  String get dashboardShowCameraIcons => 'Kamera-Konfigsymbole';

  @override
  String get dashboardShowCameraIconsSubtitle =>
      'Zahnrad auf jeder Kamera zum Festlegen einer eigenen URL anzeigen';

  @override
  String get appTitle => 'Moongate';

  @override
  String get languagePickerTitle => 'Sprache auswählen';

  @override
  String get languagePickerSubtitle =>
      'Du kannst dies jederzeit im Menü ändern.';

  @override
  String get languagePickerContinue => 'Weiter';

  @override
  String get menuLanguage => 'Sprache';

  @override
  String get languageSystemDefault => 'Systemstandard';

  @override
  String get commonCancel => 'Abbrechen';

  @override
  String get commonOk => 'OK';

  @override
  String get commonClose => 'Schließen';

  @override
  String get commonSave => 'Speichern';

  @override
  String get commonDone => 'Fertig';

  @override
  String get commonRetry => 'Erneut versuchen';

  @override
  String get commonShowKeyboard => 'Tastatur anzeigen';

  @override
  String get dashboardSignInRetrying =>
      'Verbindung zur Cloud wird wiederhergestellt - die Anmeldung ist ausgelastet, neuer Versuch. Deine Drucker kommen automatisch zurück.';

  @override
  String get commonRemove => 'Entfernen';

  @override
  String get commonDelete => 'Löschen';

  @override
  String get commonEnable => 'Aktivieren';

  @override
  String get commonDisable => 'Deaktivieren';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get settingsRemoveAllTitle =>
      'Alle Drucker von diesem Gerät entfernen';

  @override
  String get settingsRemoveAllSubtitle =>
      'Leert den lokalen Druckercache. Dein Supabase-Konto bleibt erhalten, damit die erneute Kopplung reibungslos funktioniert.';

  @override
  String get settingsRemoveAllConfirmTitle => 'Alle Drucker entfernen?';

  @override
  String get settingsRemoveAllConfirmBody =>
      'Alle gekoppelten Drucker werden von diesem Gerät entfernt. Du kannst sie erneut hinzufügen, indem du MOONGATE_PAIR auf dem Drucker ausführst.';

  @override
  String get settingsRemoveAllConfirmAction => 'Alle entfernen';

  @override
  String get dashboardAddPrinter => 'Drucker hinzufügen';

  @override
  String get dashboardRemovePrinter => 'Drucker entfernen';

  @override
  String get dashboardMenuTooltip => 'Menü';

  @override
  String get dashboardRemovePrinterTitle => 'Drucker entfernen?';

  @override
  String dashboardRemovePrinterBody(String name) {
    return '„$name“ aus Moongate entfernen?';
  }

  @override
  String get dashboardRemoveSupabaseUnreachable =>
      'Lokal entfernt, aber Supabase war nicht erreichbar. Führe MOONGATE_RESET_OWNER auf dem Pi aus, falls die erneute Kopplung fehlschlägt.';

  @override
  String get dashboardBackUpConfig => 'Konfiguration sichern';

  @override
  String get dashboardBackUpConfigSubtitle =>
      'Vor der Neuinstallation in einer Datei speichern';

  @override
  String get dashboardRestoreConfig => 'Konfiguration wiederherstellen';

  @override
  String get dashboardRestoreConfigSubtitle =>
      'Aus einer Sicherungsdatei laden';

  @override
  String get dashboardThemeHeading => 'Design';

  @override
  String get dashboardThemeSystem => 'Systemfarben';

  @override
  String get dashboardThemeDark => 'Dunkel';

  @override
  String get dashboardThemeLight => 'Hell';

  @override
  String get dashboardThemeCustom => 'Benutzerdefiniert';

  @override
  String get dashboardFontHeading => 'Schriftart';

  @override
  String get fontStandard => 'Standard';

  @override
  String get fontRounded => 'Abgerundet';

  @override
  String get fontSerif => 'Serif';

  @override
  String get fontReadable => 'Gut lesbar';

  @override
  String get dashboardCustomiseColours => 'Farben anpassen';

  @override
  String get dashboardCustomiseColoursSubtitle =>
      'Bearbeite die fünf Design-Slots - HEX oder Palette';

  @override
  String get dashboardFontSizeHeading => 'Anzeigegröße';

  @override
  String get dashboardLayoutHeading => 'Dashboard-Layout';

  @override
  String dashboardColumnCount(int count) {
    return '$count Sp.';
  }

  @override
  String get dashboardRotateWithDevice => 'Mit Gerät drehen';

  @override
  String get dashboardRotateWithDeviceSubtitle => 'Aktiviert das Querformat';

  @override
  String get dashboardAutoArrange => 'Automatisch nach Status anordnen';

  @override
  String get dashboardAutoArrangeSubtitle =>
      'Kacheln nach Aktivität sortieren. Zum eigenen Anordnen ausschalten und Kacheln ziehen.';

  @override
  String get dashboardShowButtons => 'Dashboard-Schaltflächen anzeigen';

  @override
  String get dashboardShowButtonsSubtitle =>
      'Zeigt die Schaltflächen zum Hinzufügen und Umsortieren unten an. Drucker über das Menü hinzufügen, wenn ausgeblendet.';

  @override
  String get dashboardShowEta => 'Restzeit anzeigen';

  @override
  String get dashboardShowEtaSubtitle =>
      'Druckende Kacheln zeigen die verbleibende Zeit neben den Temperaturen.';

  @override
  String get dashboardEtaFormatRemaining => 'Restzeit';

  @override
  String get dashboardEtaFormatFinish => 'Fertig um';

  @override
  String get dashboardReorderHint => 'Kachel halten und ziehen zum Umsortieren';

  @override
  String get dashboardReorderStart => 'Anordnen';

  @override
  String get dashboardReorderDone => 'Fertig';

  @override
  String get dashboardCameraFeedHeading => 'Dashboard-Kamerabild';

  @override
  String get dashboardCameraFeedSubtitle =>
      'Wie oft Kacheln das Kamerabild aktualisieren. Niedrigere Raten verbrauchen deutlich weniger Daten.';

  @override
  String get cameraFeedsMenuTitle => 'Dashboard-Kamerafeeds';

  @override
  String get cameraFeedsMenuSubtitle => 'Lokale & Tunnel-Feed-Raten';

  @override
  String get cameraFeedsIntro =>
      'Wie oft jede Kachel ihr Kamerabild aktualisiert. Moongate nutzt die lokale Rate, solange du im WLAN bist (auch unterwegs), und die Tunnel-Rate bei mobilen Daten - so bleibt das Bild im WLAN schnell und schont unterwegs dein Datenvolumen.';

  @override
  String get cameraFeedsLocalRate => 'Rate des lokalen Feeds';

  @override
  String get cameraFeedsTunnelRate => 'Rate des Tunnel-Feeds';

  @override
  String get dashboardAboutHeading => 'Über';

  @override
  String get dashboardWhatsNew => 'Neuigkeiten';

  @override
  String get dashboardWhatsNewSubtitle => 'Aktuelle Änderungen auf einen Blick';

  @override
  String get dashboardHowPairingWorks => 'So funktioniert die Kopplung';

  @override
  String get dashboardHowPairingWorksSubtitle =>
      'Kopplung, Neuinstallation & Wiederherstellung';

  @override
  String get dashboardReportProblem => 'Problem melden';

  @override
  String get dashboardReportProblemSubtitle =>
      'Fehlerbericht oder Feedback senden';

  @override
  String get dashboardAppLock => 'App-Sperre';

  @override
  String get dashboardAppLockOn => 'Ein - Entsperren beim Start erforderlich';

  @override
  String get dashboardAppLockOff => 'Aus';

  @override
  String get dashboardBuyMeCoffee => 'Spendiere mir einen Kaffee';

  @override
  String get dashboardBuyMeCoffeeSubtitle =>
      'Unterstütze den Entwickler per PayPal';

  @override
  String get dashboardDeleteData => 'Meine Daten löschen';

  @override
  String get dashboardDeleteDataSubtitle =>
      'Dein Konto und deine Drucker aus der Cloud löschen';

  @override
  String get deleteDataConfirmTitle => 'Meine Daten löschen?';

  @override
  String get deleteDataConfirmBody =>
      'Dadurch wird dein anonymes Konto dauerhaft gelöscht und deine Drucker und Benachrichtigungseinstellungen werden aus der Cloud entfernt. Deine Drucker müssen erneut gekoppelt werden. Das lässt sich nicht rückgängig machen.';

  @override
  String get deleteDataDone => 'Deine Daten wurden gelöscht';

  @override
  String get deleteDataError =>
      'Deine Daten konnten nicht gelöscht werden. Bitte versuche es erneut.';

  @override
  String get donationPromptTitle => 'Gefällt dir Moongate?';

  @override
  String get donationPromptBody =>
      'Moongate ist ein kostenloses Hobbyprojekt, das ich in meiner Freizeit entwickle. Wenn es dir hilft, hält ein kleiner Beitrag die Entwicklung am Laufen - ganz ohne Druck, und ich frage nur dieses eine Mal.';

  @override
  String get donationPromptLater => 'Vielleicht später';

  @override
  String get dashboardSettings => 'Einstellungen';

  @override
  String dashboardVersion(String version) {
    return 'Moongate v$version';
  }

  @override
  String get dashboardSaveBackupDialogTitle => 'Moongate-Sicherung speichern';

  @override
  String get dashboardBackupFailed =>
      'Sicherung fehlgeschlagen - die Datei konnte nicht gespeichert werden.';

  @override
  String dashboardBackupSuccess(int count) {
    return '$count Drucker gesichert. Mit dieser Datei kannst du sie bei einer Neuinstallation wiederherstellen - bewahre sie privat auf.';
  }

  @override
  String dashboardBackupSuccessListOnly(int count) {
    return '$count Drucker gesichert (nur Liste - Cloud für einen Wiederherstellungscode nicht erreichbar).';
  }

  @override
  String get dashboardInvalidBackupFile =>
      'Ungültige Sicherungsdatei - bitte wähle eine Moongate-Konfigurationsdatei.';

  @override
  String dashboardRestoreReconnected(int added, int count) {
    return '$added Drucker wiederhergestellt - $count wieder verbunden und kommen online.';
  }

  @override
  String dashboardRestoreNoneReconnected(int added) {
    return '$added Drucker wiederhergestellt, aber keiner wurde wieder verbunden - der Wiederherstellungscode der Sicherung passte zu keinem Drucker (er stammt möglicherweise aus einer älteren Sicherung oder wurde bereits verwendet). Koppele sie erneut, um sie online zu bringen.';
  }

  @override
  String dashboardRestoreListOnly(int added) {
    return '$added Drucker wiederhergestellt (nur Liste). Koppele jeden Drucker erneut, um ihn online zu bringen.';
  }

  @override
  String get dashboardRestoreApplied =>
      'Dashboard entsprechend deinem Backup wiederhergestellt.';

  @override
  String get dashboardRestoreExtrasTitle => 'Aktuelle Drucker behalten?';

  @override
  String dashboardRestoreExtrasBody(String names) {
    return 'Diese Drucker sind auf diesem Dashboard, aber nicht im Backup: $names. Du kannst sie neben den wiederhergestellten Druckern behalten oder sie entfernen, damit das Dashboard exakt dem Backup entspricht. Entfernte Drucker bleiben gekoppelt - du kannst sie später wieder hinzufügen oder wiederherstellen.';
  }

  @override
  String get dashboardRestoreExtrasKeep => 'Behalten';

  @override
  String get dashboardRestoreExtrasRemove => 'Entfernen';

  @override
  String get dashboardRemoveSheetTitle => 'Drucker entfernen';

  @override
  String dashboardPrinterIdShort(String id) {
    return 'ID $id…';
  }

  @override
  String get dashboardPairingHelpPluginTitle =>
      'Zuerst: Pi-Plugin installieren';

  @override
  String get dashboardPairingHelpPluginBody =>
      'Moongate benötigt sein laufendes Plugin auf deinem Klipper-Drucker, bevor du koppeln kannst. Führe nach der Installation das Makro MOONGATE_PAIR aus (oder gib es in der Mainsail-/Fluidd-Konsole ein), um einen Kopplungscode oder eine URL für die Kopplung per QR-Code zu erhalten.';

  @override
  String get dashboardPairingHelpPluginAction =>
      'Schnellstart-Anleitung öffnen';

  @override
  String get pluginUpdateTooltip => 'Plugin-Update verfügbar';

  @override
  String get pluginUpdateTitle => 'Plugin-Update verfügbar';

  @override
  String pluginUpdateBody(String current, String latest) {
    return 'Auf diesem Drucker läuft Moongate-Plugin $current. Version $latest ist verfügbar.';
  }

  @override
  String get pluginUpdateVersionUnknown => 'eine alte Version';

  @override
  String get pluginUpdateNow => 'Jetzt aktualisieren';

  @override
  String get pluginUpdateManual =>
      'Diese Plugin-Version kann noch nicht aus der App aktualisiert werden. Im Web-Interface des Druckers: Mainsail (oder Fluidd) → Software Updates → Moongate → Update.';

  @override
  String get pluginUpdateBusyPrinting =>
      'Dieser Drucker druckt gerade. Aktualisiere, sobald der Druck fertig ist.';

  @override
  String get pluginUpdateStarted =>
      'Update gestartet. Es läuft im Hintergrund auf dem Drucker - das Symbol verschwindet, sobald es fertig ist (etwa eine Minute).';

  @override
  String get pluginUpdateFailed =>
      'Update konnte nicht gestartet werden. Nutze das Web-Interface des Druckers: Software Updates → Moongate → Update.';

  @override
  String get dashboardPairingHelpPairOnceTitle => 'Einmal koppeln';

  @override
  String get dashboardPairingHelpPairOnceBody =>
      'Scanne den QR-Code (oder gib den GATE-Code ein), um einen Drucker hinzuzufügen - diese Verbindung wird in dieser App gespeichert.';

  @override
  String get dashboardPairingHelpUpdatesTitle =>
      'App-Updates behalten deine Drucker';

  @override
  String get dashboardPairingHelpUpdatesBody =>
      'Ein Update von Moongate erfordert nie eine erneute Kopplung.';

  @override
  String get dashboardPairingHelpReinstallTitle =>
      'Neuinstallation oder neues Telefon?';

  @override
  String get dashboardPairingHelpReinstallBody =>
      'Sichere zuerst (Menü → Konfiguration sichern), dann bringt die Wiederherstellung deine Drucker wieder online - ohne erneute Kopplung.';

  @override
  String get dashboardPairingHelpNoBackupTitle => 'Keine Sicherung?';

  @override
  String get dashboardPairingHelpNoBackupBody =>
      'Führe MOONGATE_RESET_OWNER in der Konsole des Druckers aus und koppele ihn dann erneut.';

  @override
  String get dashboardDontShowAgain => 'Nicht mehr anzeigen';

  @override
  String dashboardUpdateAvailable(String version) {
    return 'Update verfügbar - v$version';
  }

  @override
  String get dashboardUpdateLater => 'Später';

  @override
  String get dashboardUpdate => 'Aktualisieren';

  @override
  String get dashboardEmptyTitle => 'Noch keine Drucker hinzugefügt';

  @override
  String get dashboardEmptyBody =>
      'Tippe auf die Schaltfläche unten, um deinen ersten Drucker zu koppeln.';

  @override
  String get pairingTitle => 'Drucker hinzufügen';

  @override
  String get pairingIntro =>
      'Führe MOONGATE_PAIR in deiner Klipper-Konsole aus - scanne den QR-Code oder gib den in der Konsole angezeigten GATE-Code ein.';

  @override
  String get pairingNameLabel => 'Druckername';

  @override
  String get pairingNameHint => 'z. B. Voron 2.4';

  @override
  String get pairingScanButton => 'QR-Code scannen';

  @override
  String get pairingScanRecommended => 'Empfohlen - verbindet sofort';

  @override
  String get pairingOr => 'ODER';

  @override
  String get pairingGateCodeLabel => 'GATE-Code';

  @override
  String get pairingGateCodeHint =>
      'Gib den 8-stelligen Code aus deiner Klipper-Konsole ein.';

  @override
  String get pairingGateCodeValid => 'Code sieht gültig aus ✓';

  @override
  String get pairingGateCodeWarning =>
      'Alternative Methode. Ohne den QR-Code kann es bis zu etwa einer Minute dauern, bis der Drucker online ist - er wartet auf die Verbindung des sicheren Tunnels. Scanne den QR-Code oben für eine sofortige Verbindung.';

  @override
  String get pairingCameraPermissionNeeded => 'Kameraberechtigung erforderlich';

  @override
  String get pairingCameraUnavailable => 'Kamera nicht verfügbar';

  @override
  String get pairingCancelScan => 'Scan abbrechen';

  @override
  String pairingQrScanned(String code) {
    return 'QR-Code gescannt - Code $code';
  }

  @override
  String get pairingRescan => 'Erneut scannen';

  @override
  String get pairingAdvancedTitle =>
      'Erweitert - Drucker in einem benutzerdefinierten Netzwerk?';

  @override
  String get pairingAdvancedBody =>
      'Die meisten können dies leer lassen. Wenn dein Drucker hinter einem Reverse-Proxy (Traefik, Caddy, NPM) oder in Docker läuft, gib dieselbe Adresse ein, die du zum Öffnen seiner Weboberfläche (Mainsail / Fluidd) im Browser verwendest.';

  @override
  String get pairingAddressLabel => 'Druckeradresse';

  @override
  String get pairingAddressHint => '192.168.1.50:7125';

  @override
  String get pairingPairButton => 'Drucker koppeln';

  @override
  String get pairingModeCloud => 'Moongate-Cloud';

  @override
  String get pairingModeDirect => 'Direkt (LAN/VPN)';

  @override
  String get pairingDirectIntro =>
      'Verbindet sich direkt über dein Netzwerk oder dein eigenes VPN mit dem Drucker - kein Cloud-Konto, funktioniert offline. Der Drucker muss im LAN-only-Modus installiert sein.';

  @override
  String get pairingDirectScanHint =>
      'Scanne den QR-Code von MOONGATE_PAIR oder gib unten die Adresse ein';

  @override
  String get pairingDirectAddressHelper =>
      'Die Adresse, unter der du Mainsail / Fluidd in deinem Netzwerk öffnest';

  @override
  String get pairingAddButton => 'Drucker hinzufügen';

  @override
  String pairingLanScanned(String url) {
    return 'LAN-Drucker gescannt - $url';
  }

  @override
  String pairingNameHintCycled(String name) {
    return 'z. B. $name';
  }

  @override
  String get pairingNameHintExamples =>
      'Voron 2.4|RatRig 300|Wilma|2.4 V3309|Drucki McDruckgesicht';

  @override
  String get pairingErrorNoName =>
      'Gib deinem Drucker zuerst einen Namen - so erkennst du ihn auf dem Dashboard.';

  @override
  String get pairingDirectCaveatsTitle => 'Einschränkungen im Direktmodus';

  @override
  String get pairingDirectCaveats =>
      '• Druckbenachrichtigungen funktionieren nicht\n• Unterwegs verbindet sich die App nur über dein eigenes VPN\n• Das Netzwerk deines Handys (oder das VPN-Subnetz) muss in Moonrakers trusted_clients stehen\n• Gib dem Drucker eine feste Adresse (DHCP-Reservierung) - die App speichert sie';

  @override
  String get pairingErrorNoAddress =>
      'Gib die Adresse des Druckers ein oder scanne seinen QR-Code.';

  @override
  String get pairingRestoreHint =>
      'Neuinstallation? Stelle deine gespeicherten Drucker aus einer Sicherungsdatei wieder her. Du musst trotzdem jeden erneut koppeln, um ihn online zu bringen.';

  @override
  String get pairingImportButton => 'Konfiguration aus Datei importieren';

  @override
  String get pairingReportButton => 'Probleme beim Koppeln? Bericht senden';

  @override
  String get pairingCameraPermissionTitle => 'Kameraberechtigung erforderlich';

  @override
  String get pairingCameraPermissionBody =>
      'Moongate benötigt Kamerazugriff, um QR-Codes zu scannen.\n\nÖffne Einstellungen → Apps → Moongate → Berechtigungen und aktiviere die Kamera, komme dann zurück und versuche es erneut.';

  @override
  String get pairingOpenSettings => 'Einstellungen öffnen';

  @override
  String get pairingErrorNotMoongateQr =>
      'Kein Moongate-QR-Code. Führe MOONGATE_PAIR auf dem Drucker aus, um einen zu erzeugen.';

  @override
  String get pairingErrorOldQr =>
      'Dieser QR-Code stammt von einer älteren Moongate-Version. Aktualisiere zuerst den Pi auf v0.3.0.';

  @override
  String get pairingErrorNoCode =>
      'Scanne den QR-Code oder gib den GATE-Code aus der Druckerkonsole ein.';

  @override
  String get pairingErrorBadAddress =>
      'Diese Druckeradresse sieht nicht richtig aus - versuche z. B. 192.168.1.50:7125';

  @override
  String pairingErrorFailed(String error) {
    return 'Kopplung fehlgeschlagen: $error';
  }

  @override
  String get pairingImportInvalidFile =>
      'Ungültige Sicherungsdatei - bitte wähle eine Moongate-Konfigurationsdatei.';

  @override
  String get pairingImportNoNewPrinters =>
      'Keine neuen Drucker in dieser Datei gefunden.';

  @override
  String pairingImportRestoredReconnected(int count, int reconnected) {
    return '$count Drucker wiederhergestellt - $reconnected wieder verbunden, kommen online.';
  }

  @override
  String pairingImportRestoredRepair(int count) {
    return '$count Drucker wiederhergestellt - koppele jeden Pi erneut, um ihn online zu bringen.';
  }

  @override
  String get customThemeTitle => 'Benutzerdefiniertes Design';

  @override
  String get customThemeResetTooltip => 'Auf Standard zurücksetzen';

  @override
  String get customThemeResetConfirmTitle =>
      'Benutzerdefiniertes Design zurücksetzen?';

  @override
  String get customThemeResetConfirmBody =>
      'Alle fünf Farb-Slots werden auf die Standardpalette Lila auf Dunkel zurückgesetzt.';

  @override
  String get customThemeReset => 'Zurücksetzen';

  @override
  String get customThemePreview => 'Vorschau';

  @override
  String get customThemeAccent => 'Akzent';

  @override
  String get customThemeAccentDesc =>
      'Schaltflächen, FAB, Fortschrittsbalken, Links';

  @override
  String get customThemeBackground => 'Seitenhintergrund';

  @override
  String get customThemeBackgroundDesc => 'Hinter jedem Bildschirm';

  @override
  String get customThemeSurface => 'Karten & Kacheln';

  @override
  String get customThemeSurfaceDesc =>
      'Dashboard-Kacheln, Menüblätter, Navigationsleiste';

  @override
  String get customThemeText => 'Text';

  @override
  String get customThemeTextDesc =>
      'Fließ- und Überschriftentext auf Oberflächen';

  @override
  String get customThemeError => 'Fehler / Stopp';

  @override
  String get customThemeErrorDesc => 'Destruktive Aktionen, Fehler-Overlays';

  @override
  String get customThemeEstop => 'Not-Aus-Taste';

  @override
  String get customThemeEstopDesc => 'Ring und Symbol des Not-Aus';

  @override
  String get customThemePresets => 'Vorlagen';

  @override
  String get customThemeInvalidHex => 'Keine gültige Hex-Farbe';

  @override
  String get customThemeSamplePrinter => 'Beispieldrucker';

  @override
  String get customThemePrinting => 'Druckt';

  @override
  String get tilePauseFailed =>
      'Drucker nicht erreichbar - Pausieren fehlgeschlagen';

  @override
  String get tileResumeFailed =>
      'Drucker nicht erreichbar - Fortsetzen fehlgeschlagen';

  @override
  String get tileStopAgainToCancel =>
      'Drücke erneut STOPP, um den Druck abzubrechen';

  @override
  String get tileLocal => 'Lokal';

  @override
  String get tileTunnel => 'Tunnel';

  @override
  String get tilePrinting => 'Druckt';

  @override
  String get tilePaused => 'Pausiert';

  @override
  String get tileResume => 'Fortsetzen';

  @override
  String get tilePause => 'Pausieren';

  @override
  String get tileConfirmStop => 'Stopp bestätigen';

  @override
  String get tileStopPrint => 'Druck stoppen';

  @override
  String get tileFirmwareRestart => 'Firmware-Neustart';

  @override
  String get tileEmergencyStop => 'Notstopp · doppelt tippen';

  @override
  String get tileEmergencyStopFailed =>
      'Drucker nicht erreichbar - Notstopp fehlgeschlagen';

  @override
  String get tilePrintComplete => 'Druck abgeschlossen';

  @override
  String get tilePrintCancelled => 'Druck abgebrochen';

  @override
  String get tilePrinterError => 'Druckerfehler';

  @override
  String get tileKlipperStarting => 'Klipper startet';

  @override
  String get tileReady => 'Bereit';

  @override
  String get tileOffline => 'Offline';

  @override
  String get tileStartingUp => 'Startet…';

  @override
  String get tileConnected => 'Verbunden';

  @override
  String get tileConnecting => 'Verbinden…';

  @override
  String get tilePrinterUnreachable => 'Drucker nicht erreichbar';

  @override
  String get tileWaitingForHeartbeat => 'Warte auf ersten Heartbeat';

  @override
  String get tilePrinterIdle => 'Drucker im Leerlauf';

  @override
  String get tileReachingPrinter => 'Drucker wird erreicht';

  @override
  String get tileRemoteReady => 'Fernzugriff bereit';

  @override
  String get tileRemoteConnecting => 'Fernzugriff verbindet…';

  @override
  String get tileIdle => 'Leerlauf';

  @override
  String get tileDone => 'Fertig';

  @override
  String get tileCancelled => 'Abgebrochen';

  @override
  String get tileClearJobTooltip => 'Löschen und auf Leerlauf setzen';

  @override
  String get tileClearJobFailed => 'Drucker konnte nicht zurückgesetzt werden';

  @override
  String get dashboardBackgroundTitle => 'Dashboard-Hintergrund';

  @override
  String get dashboardBackgroundNone => 'Keiner - Themenfarbe';

  @override
  String get dashboardBackgroundCustom => 'Eigenes Bild';

  @override
  String get dashboardBackgroundRemove => 'Hintergrund entfernen';

  @override
  String get dashboardBackgroundSet => 'Hintergrund aktualisiert';

  @override
  String get uiGuideSectionTileButtons => 'Kachel-Schaltflächen';

  @override
  String get uiGuideFilesTitle => 'Datei drucken';

  @override
  String get uiGuideFilesDesc =>
      'Die gespeicherten G-Code-Dateien des Druckers durchsuchen und eine starten.';

  @override
  String get uiGuideMacrosTitle => 'Makros';

  @override
  String get uiGuideMacrosDesc =>
      'Eines der Klipper-Makros des Druckers ausführen.';

  @override
  String get uiGuidePowerTitle => 'Stromversorgung';

  @override
  String get uiGuidePowerDesc =>
      'Den Drucker ein- oder ausschalten, sofern ein Power-Gerät vorhanden ist.';

  @override
  String get uiGuideLightingTitle => 'Beleuchtung';

  @override
  String get uiGuideLightingDesc =>
      'Das Licht des Druckers umschalten; die Glühbirne leuchtet, wenn es an ist.';

  @override
  String get uiGuideCameraViewTitle => 'Kamera';

  @override
  String get uiGuideCameraViewDesc => 'Die Live-Kamera im Vollbild öffnen.';

  @override
  String get uiGuideCameraSetupTitle => 'Kamera-Einrichtung';

  @override
  String get uiGuideCameraSetupDesc =>
      'Eine Kachel auf eine Kamera richten, die nicht mit Klipper verbunden ist.';

  @override
  String get uiGuideClearJobTitle => 'Abgeschlossenen Druck löschen';

  @override
  String get uiGuideClearJobDesc =>
      'Tippe auf das × einer Fertig- oder Abgebrochen-Kachel, um sie wieder auf Leerlauf zu setzen.';

  @override
  String get tileError => 'Fehler';

  @override
  String get tileStarting => 'Startet';

  @override
  String get tileConnectingBadge => 'Verbinden';

  @override
  String get appLockTitle => 'App-Sperre';

  @override
  String get appLockIntro =>
      'Erfordere eine PIN - und optional deinen Fingerabdruck oder dein Gesicht -, bevor Moongate geöffnet wird. Die Sperre erscheint immer, wenn die App neu gestartet wird.';

  @override
  String get appLockSubtitle => 'PIN zum Öffnen der App erforderlich';

  @override
  String get appLockBiometricTitle => 'Biometrisches Entsperren';

  @override
  String get appLockBiometricSubtitle =>
      'Fingerabdruck oder Gesicht verwenden - PIN bleibt als Ausweichlösung';

  @override
  String get appLockChangePin => 'PIN ändern';

  @override
  String get appLockAutoLock => 'Automatische Sperre';

  @override
  String get appLockPinUpdated => 'PIN aktualisiert';

  @override
  String get appLockChoosePinTitle => 'PIN wählen';

  @override
  String get appLockChoosePinSubtitle => '4-6 Ziffern eingeben';

  @override
  String get appLockConfirmPinTitle => 'PIN bestätigen';

  @override
  String get appLockPinsDontMatch => 'PINs stimmen nicht überein';

  @override
  String get appLockEnterCurrentPin => 'Aktuelle PIN eingeben';

  @override
  String get appLockTimeoutImmediately => 'Sofort';

  @override
  String get appLockTimeoutOneMinute => 'Nach 1 Minute';

  @override
  String get appLockTimeoutFiveMinutes => 'Nach 5 Minuten';

  @override
  String get appLockTimeoutFifteenMinutes => 'Nach 15 Minuten';

  @override
  String get appLockTimeoutColdLaunch => 'Nur beim App-Start';

  @override
  String get lockEnterPin => 'Gib deine PIN ein';

  @override
  String get lockSubtitle => 'Moongate ist gesperrt';

  @override
  String lockTooManyAttempts(int seconds) {
    return 'Zu viele Versuche. Versuche es in ${seconds}s erneut';
  }

  @override
  String get lockWrongPin => 'Falsche PIN';

  @override
  String get lockUseBiometrics => 'Biometrie verwenden';

  @override
  String get lockForgotPin => 'PIN vergessen?';

  @override
  String get lockBiometricReason => 'Moongate entsperren';

  @override
  String get lockResetTitle => 'Moongate zurücksetzen?';

  @override
  String get lockResetBody =>
      'Dies entfernt die App-Sperre und löscht die gekoppelten Drucker von diesem Gerät, damit du neu beginnen kannst. Deine Drucker werden nicht gelöscht - koppele sie erneut, indem du MOONGATE_PAIR auf jedem ausführst.';

  @override
  String get lockResetConfirm => 'Zurücksetzen';

  @override
  String get pinContinue => 'Weiter';

  @override
  String printerStartingUpRetry(int seconds) {
    return 'Drucker startet. Erneuter Versuch in ${seconds}s…';
  }

  @override
  String printerCouldNotReach(String error) {
    return 'Drucker nicht erreichbar: $error';
  }

  @override
  String get printerDirectModeToggle => 'Direktmodus (LAN/VPN)';

  @override
  String get printerDirectModeSubtitle =>
      'Mit diesem Drucker nur über dein Netzwerk oder VPN sprechen - keine Cloud. Braucht die Druckeradresse und einen im LAN-only-Modus installierten Drucker.';

  @override
  String get printerDirectModeNeedsAddress =>
      'Der Direktmodus braucht die Druckeradresse';

  @override
  String get printerDirectModeOn =>
      'Direktmodus an - dieser Drucker verbindet sich jetzt nur über dein Netzwerk';

  @override
  String get printerDirectModeOff =>
      'Direktmodus aus - Cloud-Verbindung wiederhergestellt';

  @override
  String get printerAddressCleared => 'Benutzerdefinierte Adresse entfernt';

  @override
  String get printerAddressUpdated => 'Druckeradresse aktualisiert';

  @override
  String printerTunnelUnreachable(String description) {
    return 'Cloudflare-Tunnel nicht erreichbar.\n$description';
  }

  @override
  String printerWebUiRetry(int seconds) {
    return 'Die Weboberfläche des Druckers antwortet noch nicht. Kurz nach dem Einschalten ist das für etwa eine Minute normal. Erneuter Versuch in ${seconds}s…';
  }

  @override
  String get printerLocalOnlyNoLan =>
      'Der Fernzugriff ist ausgeschaltet (Nur lokal) und dieser Drucker ist in deinem Netzwerk nicht erreichbar.';

  @override
  String get localOnlyButtonTitle => 'Nur-lokal-Taste';

  @override
  String get localOnlyButtonSubtitle =>
      'Eine Taste in der oberen Leiste, die Fernverbindungen (Tunnel) ausschaltet, sodass sich nur Drucker in deinem Netzwerk verbinden';

  @override
  String get localOnlyTooltip => 'Nur lokal';

  @override
  String get localOnlySnackOn => 'Fernverbindungen aus - nur lokales Netzwerk';

  @override
  String get localOnlySnackOff => 'Fernverbindungen wieder an';

  @override
  String get printerEdit => 'Drucker bearbeiten';

  @override
  String get printerLocalNetwork => 'Lokales Netzwerk';

  @override
  String get printerTunnelVia => 'Tunnel über Moongate';

  @override
  String get printerCameraTooltip => 'Kamera';

  @override
  String get cameraConnecting => 'Verbinde mit Kamera…';

  @override
  String get cameraNoCamera =>
      'Für diesen Drucker ist keine Kamera konfiguriert.';

  @override
  String get cameraHintBody =>
      'Webcam lädt hier aus der Ferne nicht - Moongate-Kamera öffnen.';

  @override
  String get cameraHintOpen => 'Öffnen';

  @override
  String get webcamWakingUp => 'Kamera wacht auf…';

  @override
  String get printerUnreachable => 'Drucker nicht erreichbar';

  @override
  String get printerUseTunnel => 'Tunnel verwenden';

  @override
  String get printerAddressInvalid => 'Versuche z. B. 192.168.1.50:7125';

  @override
  String get printerNameLabel => 'Druckername';

  @override
  String get printerAddressLabel => 'Druckeradresse (erweitert)';

  @override
  String get printerAddressHint => '192.168.1.50:7125';

  @override
  String get printerAddressHelper =>
      'Nur für Reverse-Proxy- / Docker-Konfigurationen. Leer lassen, um die automatische Erkennung zu verwenden.';

  @override
  String get feedbackTitle => 'Problem melden';

  @override
  String get feedbackTroublePairing => 'Probleme beim Koppeln?';

  @override
  String get feedbackDescription =>
      'Beschreibe, was passiert. Deine App-Version, dein Gerät sowie Netzwerk- und Druckerdetails werden automatisch angehängt, um uns bei der Eingrenzung zu helfen.';

  @override
  String get feedbackPairingDescription =>
      'Beschreibe, was passiert, wenn du versuchst, den Drucker hinzuzufügen. Deine Netzwerk- und Erkennungsdetails werden automatisch angehängt, damit wir sehen können, warum keine Verbindung zustande kommt.';

  @override
  String get feedbackWhichPrinter => 'Welcher Drucker? (optional)';

  @override
  String get feedbackGeneralOption => 'Allgemein / nicht druckerspezifisch';

  @override
  String get feedbackCommentLabel => 'Was ist schiefgelaufen?';

  @override
  String get feedbackCommentHint =>
      'z. B. „Drucker zeigt Verbunden / Leerlauf, ist aber tatsächlich bereit - öffnet einwandfrei, wenn ich auf die Kachel tippe.“';

  @override
  String get feedbackContactLabel => 'E-Mail oder Kontakt (optional)';

  @override
  String get feedbackContactHint => 'Nur wenn du eine Antwort möchtest';

  @override
  String get feedbackSending => 'Wird gesendet…';

  @override
  String get feedbackSend => 'Bericht senden';

  @override
  String get feedbackSuccess => 'Danke - dein Bericht wurde gesendet.';

  @override
  String get feedbackError =>
      'Senden fehlgeschlagen - prüfe deine Verbindung und versuche es erneut.';

  @override
  String get splashTagline => 'Klipper-Fernsteuerung';

  @override
  String get uiGuideTitle => 'Symbolübersicht';

  @override
  String get uiGuideMenuSubtitle => 'Was die Dashboard-Symbole bedeuten';

  @override
  String get uiGuideIntro =>
      'Eine kurze Übersicht der Symbole, die du auf dem Dashboard siehst.';

  @override
  String get uiGuideSectionConnection => 'Verbindung';

  @override
  String get uiGuideSectionTemperatures => 'Temperaturen';

  @override
  String get uiGuideSectionControls => 'Drucksteuerung';

  @override
  String get uiGuideSectionStatus => 'Status';

  @override
  String get uiGuideSectionWebcam => 'Kamera & Verbindung';

  @override
  String get uiGuideLocalTitle => 'Lokales Netzwerk';

  @override
  String get uiGuideLocalDesc =>
      'Direkt über dein Wi-Fi verbunden - der schnellste Weg.';

  @override
  String get uiGuideTunnelTitle => 'Fern (Tunnel)';

  @override
  String get uiGuideTunnelDesc =>
      'Von überall über den sicheren Cloudflare-Tunnel verbunden.';

  @override
  String get uiGuideTunnelReadyTitle => 'Fernzugriff bereit';

  @override
  String get uiGuideTunnelReadyDesc =>
      'Der Tunnel steht, daher ist Fernzugriff verfügbar.';

  @override
  String get uiGuideTunnelConnectingTitle => 'Fernzugriff verbindet';

  @override
  String get uiGuideTunnelConnectingDesc =>
      'Der Fern-Tunnel wird noch aufgebaut.';

  @override
  String get uiGuideHotendTitle => 'Hotend / Düse';

  @override
  String get uiGuideHotendDesc => 'Aktuelle Düsentemperatur.';

  @override
  String get uiGuideBedTitle => 'Heizbett';

  @override
  String get uiGuideBedDesc => 'Aktuelle Betttemperatur.';

  @override
  String get uiGuideChamberTitle => 'Kammer';

  @override
  String get uiGuideChamberDesc =>
      'Kammertemperatur - wird nur angezeigt, wenn dein Drucker eine meldet.';

  @override
  String get uiGuideResumeTitle => 'Fortsetzen';

  @override
  String get uiGuideResumeDesc => 'Einen pausierten Druck fortsetzen.';

  @override
  String get uiGuidePauseTitle => 'Pausieren';

  @override
  String get uiGuidePauseDesc => 'Den aktuellen Druck pausieren.';

  @override
  String get uiGuideStopTitle => 'Stopp';

  @override
  String get uiGuideStopDesc =>
      'Den Druck abbrechen - zweimal tippen zum Bestätigen.';

  @override
  String get uiGuideEstopTitle => 'Not-Aus';

  @override
  String get uiGuideEstopDesc =>
      'Doppeltippen Sie auf das rote Dreieck, um den Drucker sofort zu stoppen (Klipper M112).';

  @override
  String get uiGuideFirmwareRestartTitle => 'Firmware-Neustart';

  @override
  String get uiGuideFirmwareRestartDesc =>
      'Klipper neu starten, wenn der Drucker im Leerlauf oder im Fehlerzustand ist.';

  @override
  String get uiGuideStatusReadyTitle => 'Bereit / abgeschlossen';

  @override
  String get uiGuideStatusReadyDesc =>
      'Der Drucker ist im Leerlauf oder hat seinen letzten Druck beendet.';

  @override
  String get uiGuideStatusCancelledTitle => 'Abgebrochen';

  @override
  String get uiGuideStatusCancelledDesc =>
      'Der letzte Druck wurde abgebrochen.';

  @override
  String get uiGuideStatusErrorTitle => 'Fehler';

  @override
  String get uiGuideStatusErrorDesc =>
      'Klipper hat einen Fehler gemeldet - öffne den Drucker für Details.';

  @override
  String get uiGuideStatusStartingTitle => 'Startet';

  @override
  String get uiGuideStatusStartingDesc =>
      'Klipper startet; die Steuerung erscheint, sobald es bereit ist.';

  @override
  String get uiGuideOfflineTitle => 'Offline';

  @override
  String get uiGuideOfflineDesc =>
      'Der Drucker ist im Moment nicht erreichbar.';

  @override
  String get uiGuideNoWebcamTitle => 'Keine Kamera';

  @override
  String get uiGuideNoWebcamDesc =>
      'Für diesen Drucker ist kein Webcam-Schnappschuss verfügbar.';

  @override
  String get uiGuideBack => 'Zurück zum Dashboard';

  @override
  String get printNotifTitle => 'Druckbenachrichtigungen';

  @override
  String get printNotifSubtitle =>
      'Live-Fortschritt und Status, während die App im Hintergrund ist';

  @override
  String get printNotifPermissionNeeded =>
      'Benachrichtigungen erlauben, um dies zu aktivieren.';

  @override
  String get printNotifPromptTitle => 'Druckbenachrichtigungen erhalten?';

  @override
  String get printNotifPromptBody =>
      'Sieh den Live-Status deiner Drucker - Fortschritt, Temperaturen und Hinweise, wenn ein Druck startet, endet oder fehlschlägt. Du kannst dies jederzeit im Menü ändern.';

  @override
  String get printNotifPromptEnable => 'Aktivieren';

  @override
  String get printNotifPromptNotNow => 'Nicht jetzt';

  @override
  String get printNotifWatching => 'Drucker werden überwacht…';

  @override
  String get printNotifNoPrinters => 'Keine Drucker';

  @override
  String get printNotifNoneOnline => 'Keine Drucker online';

  @override
  String get notifOnlineOnlyTitle => 'Nur Online-Geräte anzeigen';

  @override
  String get notifOnlineOnlySubtitle =>
      'Offline-Geräte aus der Statusbenachrichtigung ausblenden';

  @override
  String get notifPollIntervalTitle => 'Aktualisierungsintervall';

  @override
  String get notifContentTitle => 'Benachrichtigungsinhalt';

  @override
  String get notifContentSubtitle => 'Wählen & anordnen, was angezeigt wird';

  @override
  String get notifRosterTitle => 'Statusleiste aller Drucker';

  @override
  String get notifRosterShownSubtitle =>
      'Sichtbar. Tippe, um nur diese Leiste in den Benachrichtigungseinstellungen deines Telefons auszublenden - die Druckkarten kommen weiterhin.';

  @override
  String get notifRosterHiddenSubtitle =>
      'In den Benachrichtigungseinstellungen deines Telefons ausgeblendet. Tippe, um sie wieder anzuzeigen.';

  @override
  String get notifContentIntro =>
      'Wähle, welche Details auf der Benachrichtigungskarte jedes Drucks erscheinen, und ziehe sie in die gewünschte Reihenfolge.';

  @override
  String get notifContentPreview => 'Vorschau';

  @override
  String get notifFieldProgress => 'Fortschritt';

  @override
  String get notifFieldRemaining => 'Restzeit';

  @override
  String get notifFieldEta => 'Endzeit';

  @override
  String get notifFieldHotend => 'Hotend-Temp.';

  @override
  String get notifFieldBed => 'Bett-Temp.';

  @override
  String get printAlertReady => 'Drucker bereit';

  @override
  String get printStatusReady => 'Bereit';

  @override
  String get printStatusHeating => 'Heizt auf';

  @override
  String get printStatusIdle => 'Inaktiv';

  @override
  String get printStatusOffline => 'Offline';

  @override
  String get printStatusPaused => 'Pausiert';

  @override
  String get printStatusComplete => 'Fertig';

  @override
  String get printStatusCancelled => 'Abgebrochen';

  @override
  String get printStatusError => 'Fehler';

  @override
  String get printStatusStartingUp => 'Startet…';

  @override
  String get printStatusPrinting => 'Druckt';

  @override
  String get printNotifStarted => 'Druck gestartet';

  @override
  String get printNotifFinished => 'Fertig';

  @override
  String get notifClearAction => 'Löschen';

  @override
  String get printAlertStarted => 'Druck gestartet';

  @override
  String get printAlertResumed => 'Druck fortgesetzt';

  @override
  String get printAlertPaused => 'Druck pausiert';

  @override
  String get printAlertComplete => 'Druck fertig';

  @override
  String get printAlertCancelled => 'Druck abgebrochen';

  @override
  String get printAlertError => 'Druckerfehler';

  @override
  String get tileOpenFiles => 'Datei drucken';

  @override
  String get gcodeSheetTitle => 'Druck starten';

  @override
  String get gcodeLoading => 'Dateien werden geladen …';

  @override
  String get gcodeEmpty => 'Keine G-Code-Dateien auf diesem Drucker';

  @override
  String get gcodeError => 'Dateien konnten nicht geladen werden';

  @override
  String get gcodeStartButton => 'Druck starten';

  @override
  String get gcodeStartAction => 'Starten';

  @override
  String get gcodeConfirmTitle => 'Druck starten?';

  @override
  String gcodeConfirmBody(String file) {
    return 'Druck von $file starten?';
  }

  @override
  String gcodeStarted(String file) {
    return 'Druck von $file gestartet';
  }

  @override
  String get gcodeStartFailed => 'Druck konnte nicht gestartet werden';

  @override
  String get tileMacros => 'Makros';

  @override
  String get macrosSheetTitle => 'Makros';

  @override
  String get macrosLoading => 'Makros werden geladen…';

  @override
  String get macrosError => 'Makros konnten nicht geladen werden';

  @override
  String get macrosEmpty => 'Keine Makros auf diesem Drucker';

  @override
  String get macroFavourite => 'Oben anheften';

  @override
  String get macroUnfavourite => 'Nicht mehr anheften';

  @override
  String get macroConfirmTitle => 'Makro ausführen?';

  @override
  String macroConfirmBody(String macro) {
    return '$macro auf diesem Drucker ausführen?';
  }

  @override
  String get macroRunAction => 'Ausführen';

  @override
  String macroSent(String macro) {
    return '$macro gesendet';
  }

  @override
  String macroFailed(String macro) {
    return '$macro konnte nicht gesendet werden';
  }

  @override
  String get preheatTitle => 'Vorheizen';

  @override
  String get preheatHotend => 'Hotend';

  @override
  String get preheatBed => 'Bett';

  @override
  String get preheatHint =>
      'Ein Feld leer lassen, um diesen Heizer unverändert zu lassen.';

  @override
  String get preheatSoakLabel => 'Heat-Soak-Timer';

  @override
  String get preheatSoakHelp =>
      'Nach so vielen Minuten benachrichtigen. 0 = kein Timer.';

  @override
  String get preheatMinutes => 'Min.';

  @override
  String get preheatSet => 'Setzen';

  @override
  String get preheatNotifWarning =>
      'Heat-Soak-Hinweise erfordern aktivierte Druckbenachrichtigungen.';

  @override
  String get preheatNotifEnable => 'Aktivieren';

  @override
  String preheatSetConfirm(String summary) {
    return '$summary gesetzt';
  }

  @override
  String preheatSoakIn(int minutes) {
    return 'Heat-Soak-Hinweis in $minutes Min.';
  }

  @override
  String get preheatFailed => 'Temperaturen konnten nicht gesetzt werden';

  @override
  String get heatsoakDoneTitle => 'Heat-Soak abgeschlossen';

  @override
  String heatsoakDoneBody(String printer) {
    return '$printer hat die Temperatur erreicht';
  }

  @override
  String get tutorialOfferTitle => 'Kurze Tour gefällig?';

  @override
  String get tutorialOfferBody =>
      'Möchtest du eine kurze Einführung, wie Moongate funktioniert?';

  @override
  String get tutorialOfferDontRemind => 'Nicht mehr erinnern';

  @override
  String get tutorialOfferNo => 'Nein danke';

  @override
  String get tutorialOfferStart => 'Tutorial starten';

  @override
  String get tutorialMenuTitle => 'App-Tutorial';

  @override
  String get tutorialNext => 'Weiter';

  @override
  String get tutorialDone => 'Fertig';

  @override
  String get tutorialSkip => 'Beenden';

  @override
  String get tutorialBack => 'Zurück';

  @override
  String get tutorialLocalBar =>
      'Der Farbbalken zeigt, wie Moongate diesen Drucker erreicht. Grün mit einem Wi-Fi-Symbol bedeutet, dass du im selben Netzwerk bist - eine schnelle, direkte lokale Verbindung.';

  @override
  String get tutorialTunnelBar =>
      'Orange mit einem Wolkensymbol bedeutet, dass du unterwegs bist und sicher über das Internet durch den Tunnel deines Druckers verbunden bist. Moongate wechselt automatisch zwischen beiden.';

  @override
  String get tutorialRemoteBuilding =>
      'Wenn du einen Drucker zum ersten Mal koppelst, ist der Fernzugriff nicht sofort verfügbar. Diese kleine Wolkenmarkierung bedeutet, dass der sichere Tunnel im Hintergrund noch aufgebaut wird. Sobald daraus ein grünes Wolken-Häkchen wird, erreichst du diesen Drucker von überall.';

  @override
  String get tutorialHotend => 'Das ist dein Hotend, die Düsentemperatur.';

  @override
  String get tutorialBed => 'Und das ist das beheizte Bett.';

  @override
  String get tutorialChamber =>
      'Wenn dein Drucker einen Kammersensor hat, wird dessen Temperatur hier ebenfalls angezeigt.';

  @override
  String get tutorialTemps =>
      'Das sind die Live-Temperaturen: das Hotend (Düse), das beheizte Bett und - falls dein Drucker einen Kammersensor hat - die Kammer.';

  @override
  String get tutorialEstop =>
      'Das ist der Notstopp. Er muss doppelt getippt werden, damit er nicht versehentlich ausgelöst wird, und er hält den Drucker sofort an.';

  @override
  String get tutorialWebcam =>
      'Ein Tippen auf die Kameraansicht öffnet die vollständige Druckeroberfläche, den Live-Klipper-Bildschirm.';

  @override
  String get tutorialPreheatPress =>
      'Halte den Namen eines Druckers oder seine Temperaturen gedrückt, um das Vorheiz-Panel anzuzeigen.';

  @override
  String get tutorialPreheatSheet =>
      'Hier kannst du Zieltemperaturen für Hotend und Bett sowie optional eine Heat-Soak-Zeit festlegen.';

  @override
  String get tutorialAddPrinter =>
      'Tippe jederzeit auf die Plus-Schaltfläche, um einen weiteren Drucker hinzuzufügen und zu koppeln.';

  @override
  String get tutorialMenuIcon =>
      'Das ist das Menü. Du kannst es von hier aus jederzeit öffnen.';

  @override
  String get tutorialMenuPrinters =>
      'Füge einen weiteren Drucker hinzu oder entferne einen, den du nicht mehr nutzt.';

  @override
  String get tutorialMenuBackup =>
      'Sichere deine Einrichtung in einer Datei oder stelle sie auf einem anderen Gerät wieder her.';

  @override
  String get tutorialMenuTheme =>
      'Wähle ein helles, dunkles oder vollständig eigenes Farbdesign.';

  @override
  String get tutorialMenuDisplaySize =>
      'Ziehe hier, um alles größer oder kleiner zu machen, passend für deine Augen.';

  @override
  String get tutorialMenuColumns =>
      'Ordne deine Drucker in einer, zwei oder drei Spalten an.';

  @override
  String get tutorialMenuCameras =>
      'Lege fest, wie oft die Webcam-Feeds aktualisiert werden, und schalte die Kamera jedes Druckers ein oder aus.';

  @override
  String get tutorialMenuAbout =>
      'Neuigkeiten, wie das Koppeln funktioniert, eine Symbolübersicht und wo du ein Problem melden kannst, findest du alles hier.';

  @override
  String get tutorialMenuSupport =>
      'Mir einen Kaffee zu spendieren hilft, Moongate für alle kostenlos und quelloffen zu halten.';

  @override
  String get tutorialMenuSettings =>
      'In den Einstellungen gibt es zwei Optionen: alle Drucker löschen oder alle deine Daten löschen und ganz neu beginnen.';

  @override
  String get tutorialMenuLanguage =>
      'Und hier kannst du die Sprache der App ändern - Moongate spricht neun. Das war die Tour, viel Spaß!';

  @override
  String get notifPauseTooltip => 'Überwachung pausieren';

  @override
  String get notifResumeTooltip => 'Überwachung fortsetzen';

  @override
  String get notifPausedSnack => 'Drucküberwachung pausiert';

  @override
  String get notifResumedSnack => 'Drucküberwachung fortgesetzt';

  @override
  String get tutorialPauseButton =>
      'Dies pausiert die Drucküberwachung. Wenn deine Drucker eine Weile aus sind, tippe darauf, um die Hintergrundabfragen zu stoppen und Akku zu sparen. Tippe erneut, um fortzusetzen.';
}
