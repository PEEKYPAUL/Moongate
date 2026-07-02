// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Polish (`pl`).
class AppLocalizationsPl extends AppLocalizations {
  AppLocalizationsPl([String locale = 'pl']) : super(locale);

  @override
  String get updateDownloading => 'Pobieranie aktualizacji…';

  @override
  String get updateOpeningInstaller => 'Otwieranie instalatora…';

  @override
  String get updateFailed =>
      'Nie udało się automatycznie ukończyć aktualizacji.';

  @override
  String get updateOpenInBrowser => 'Otwórz w przeglądarce';

  @override
  String get lightingTitle => 'Oświetlenie';

  @override
  String get lightingMenuSubtitle => 'Steruj oświetleniem drukarek z pulpitu';

  @override
  String get lightingBanner =>
      'Wybierz, które drukarki mają sterowane oświetlenie. Dla każdej włącz je i ustaw parę makr Wł + Wył albo pojedyncze makro przełączające. Opcjonalnie wskaż źródło stanu, aby żarówka pokazywała rzeczywisty stan.';

  @override
  String get lightingNoPrinters => 'Brak drukarek do skonfigurowania.';

  @override
  String get lightingShowOnTile => 'Pokaż na kafelku';

  @override
  String get lightingNeedMacro =>
      'Ustaw parę Wł + Wył lub makro przełączające, aby włączyć.';

  @override
  String get lightingLoadFailed =>
      'Nie udało się wczytać makr tej drukarki (może być offline). Wpisz nazwy ręcznie poniżej.';

  @override
  String get lightingOnMacro => 'Makro Światło WŁ';

  @override
  String get lightingOffMacro => 'Makro Światło WYŁ';

  @override
  String get lightingToggleMacro => 'Makro przełączające';

  @override
  String get lightingToggleSection => 'Opcjonalnie - metoda przełączania';

  @override
  String get lightingStatusSource => 'Źródło stanu światła';

  @override
  String get lightingStatusSourceHelp =>
      'Opcjonalnie. Obiekt Klipper (np. output_pin caselight), którego wartość mówi Moongate, czy światło jest włączone. Pozostaw puste, aby zamiast tego śledzić Twoje dotknięcia.';

  @override
  String get lightingStatusHint => 'Przykład: output_pin caselight';

  @override
  String get lightingNotSet => 'Nie ustawiono';

  @override
  String get lightingPickMacro => 'Wybierz makro';

  @override
  String get lightingPickStatusSource => 'Wybierz źródło stanu';

  @override
  String get lightingManualHint => 'Wpisz dokładną nazwę';

  @override
  String get lightingClear => 'Wyczyść';

  @override
  String get lightTurnOn => 'Włącz światło';

  @override
  String get lightTurnOff => 'Wyłącz światło';

  @override
  String get lightToggleFailed => 'Nie można połączyć się z drukarką';

  @override
  String get powerTurnOn => 'Włącz';

  @override
  String get powerTurnOff => 'Wyłącz';

  @override
  String powerConfirmOn(String name) {
    return 'Włączyć $name?';
  }

  @override
  String powerConfirmOff(String name) {
    return 'Wyłączyć $name?';
  }

  @override
  String get powerToggleFailed => 'Nie udało się zmienić zasilania';

  @override
  String get powerLockedWhilePrinting => 'Nie można wyłączyć podczas druku';

  @override
  String get globalPowerButtonTitle => 'Globalny przycisk zasilania';

  @override
  String get globalPowerButtonSubtitle =>
      'Przycisk na górnym pasku do włączania lub wyłączania całej floty';

  @override
  String get globalPowerTooltip => 'Zasil wszystkie drukarki';

  @override
  String get globalPowerSheetTitle => 'Zasil wszystkie drukarki';

  @override
  String get globalPowerOnAll => 'Włącz wszystkie';

  @override
  String get globalPowerSlideOff => 'przesuń, aby wyłączyć wszystkie';

  @override
  String get globalPowerConfirmOnTitle => 'Włączyć wszystkie drukarki?';

  @override
  String get globalPowerConfirmOnBody =>
      'Spowoduje to włączenie każdej osiągalnej maszyny.';

  @override
  String get globalPowerPrintingNote =>
      'Drukarki, które drukują, pozostają włączone';

  @override
  String get globalPowerStateWillSwitchOff => 'zostanie wyłączona';

  @override
  String get globalPowerStateKeptPrinting => 'drukuje, pozostawiona włączona';

  @override
  String get globalPowerStateOffline => 'offline, pominięta';

  @override
  String get globalPowerStateOnOff => 'wł. / wył.';

  @override
  String get globalPowerStateOffOnly => 'tylko wył.';

  @override
  String get globalPowerStateOnOnly => 'tylko wł.';

  @override
  String get globalPowerStateToggleOnly => 'tylko przełączanie';

  @override
  String get globalPowerNothing =>
      'Żadna maszyna nie ma jeszcze skonfigurowanego sterowania zasilaniem';

  @override
  String globalPowerResultOn(int count, int total) {
    return 'Włączono $count z $total drukarek';
  }

  @override
  String globalPowerResultOff(int count, int total) {
    return 'Wyłączono $count z $total drukarek';
  }

  @override
  String get powerScreenTitle => 'Zaawansowany wyłącznik zasilania';

  @override
  String get powerScreenBanner =>
      'Dla drukarek, których zasilanie jest makrem Klippera, a nie urządzeniem zasilania Moonrakera. Włącz i ustaw makro Wyłączania (częsty przypadek), makro Włączania, oba albo pojedyncze makro przełączające. Przycisk zasilania kafelka użyje dowolnego z nich.';

  @override
  String get powerUseSwitch => 'Użyj makr';

  @override
  String get powerNeedMacro =>
      'Ustaw co najmniej jedno makro: makro Wyłączania (lub Włączania) albo makro przełączające.';

  @override
  String get powerOnMacro => 'Makro włączania';

  @override
  String get powerOffMacro => 'Makro wyłączania';

  @override
  String get powerToggleSection => 'Lub pojedyncze makro przełączające';

  @override
  String get powerToggleMacro => 'Makro przełączania zasilania';

  @override
  String get powerToggleBulkNote =>
      'Makro przełączające obsługuje przycisk zasilania kafelka. Aby użyć „Zasil wszystkie drukarki”, ustaw makro Włączania i/lub Wyłączania.';

  @override
  String get powerMenuTitle => 'Zaawansowany wyłącznik zasilania';

  @override
  String get powerMenuSubtitle =>
      'Sterowanie zasilaniem drukarki za pomocą makra';

  @override
  String get powerMacroTooltip => 'Zasilanie';

  @override
  String powerMacroToggleConfirm(String name) {
    return 'Przełączyć zasilanie $name?';
  }

  @override
  String powerMacroChooseTitle(String name) {
    return 'Przełącz zasilanie $name';
  }

  @override
  String lightChooseTitle(String name) {
    return 'Przełącz światło $name';
  }

  @override
  String get tileOpacityTitle => 'Krycie kafelków';

  @override
  String get tileOpacityDesc =>
      'Jak przezroczyste są kafelki (0-100), aby prześwitywało tło. Obraz z kamery pozostaje nieprzezroczysty.';

  @override
  String get dashboardShowWebcams => 'Kamery';

  @override
  String get dashboardShowWebcamsSubtitle =>
      'Pokaż lub ukryj kamerę każdej drukarki';

  @override
  String get updateNotesUnavailable =>
      'Nie udało się wczytać nowości - sprawdź połączenie lub zobacz je na GitHubie.';

  @override
  String get updateViewOnGithub => 'Zobacz na GitHubie';

  @override
  String get cameraConfigTooltip => 'Ustaw adres URL kamery';

  @override
  String get cameraConfigTitle => 'Własna kamera';

  @override
  String get cameraConfigDescription =>
      'Pokaż kamerę, która nie jest połączona z Klipperem - na przykład stary telefon używany jako kamera. Wpisz adres widoczny w ustawieniach kamery w Mainsail.';

  @override
  String get cameraConfigUrlLabel => 'Adres URL kamery';

  @override
  String get cameraConfigRemoteNote =>
      'Działa w sieci Wi-Fi oraz zdalnie przez drukarkę. Zdalnie dostępne są tylko kamery w sieci domowej (adresy prywatne).';

  @override
  String get cameraConfigInvalid =>
      'Wpisz pełny adres, np. http://192.168.0.107:8080/video';

  @override
  String get cameraConfigUseDefault => 'Użyj kamery Klipper';

  @override
  String get cameraConfigApply => 'Zastosuj';

  @override
  String get dashboardShowCameraIcons => 'Ikony konfiguracji kamery';

  @override
  String get dashboardShowCameraIconsSubtitle =>
      'Pokaż koło zębate na każdej kamerze do ustawienia własnego URL';

  @override
  String get appTitle => 'Moongate';

  @override
  String get languagePickerTitle => 'Wybierz język';

  @override
  String get languagePickerSubtitle =>
      'Możesz to zmienić w dowolnej chwili w menu.';

  @override
  String get languagePickerContinue => 'Dalej';

  @override
  String get menuLanguage => 'Język';

  @override
  String get languageSystemDefault => 'Domyślny systemu';

  @override
  String get commonCancel => 'Anuluj';

  @override
  String get commonOk => 'OK';

  @override
  String get commonClose => 'Zamknij';

  @override
  String get commonSave => 'Zapisz';

  @override
  String get commonDone => 'Gotowe';

  @override
  String get commonRetry => 'Ponów';

  @override
  String get commonShowKeyboard => 'Pokaż klawiaturę';

  @override
  String get dashboardSignInRetrying =>
      'Ponowne łączenie z chmurą - logowanie jest zajęte, ponawianie. Twoje drukarki wrócą automatycznie.';

  @override
  String get commonRemove => 'Usuń';

  @override
  String get commonDelete => 'Usuń';

  @override
  String get commonEnable => 'Włącz';

  @override
  String get commonDisable => 'Wyłącz';

  @override
  String get settingsTitle => 'Ustawienia';

  @override
  String get settingsRemoveAllTitle =>
      'Usuń wszystkie drukarki z tego urządzenia';

  @override
  String get settingsRemoveAllSubtitle =>
      'Czyści lokalną pamięć podręczną drukarek. Twoje konto Supabase pozostaje zachowane, dzięki czemu ponowne parowanie przebiega bezproblemowo.';

  @override
  String get settingsRemoveAllConfirmTitle => 'Usunąć wszystkie drukarki?';

  @override
  String get settingsRemoveAllConfirmBody =>
      'Wszystkie sparowane drukarki zostaną usunięte z tego urządzenia. Możesz dodać je ponownie, uruchamiając MOONGATE_PAIR na drukarce.';

  @override
  String get settingsRemoveAllConfirmAction => 'Usuń wszystkie';

  @override
  String get dashboardAddPrinter => 'Dodaj drukarkę';

  @override
  String get dashboardRemovePrinter => 'Usuń drukarkę';

  @override
  String get dashboardMenuTooltip => 'Menu';

  @override
  String get dashboardRemovePrinterTitle => 'Usunąć drukarkę?';

  @override
  String dashboardRemovePrinterBody(String name) {
    return 'Usunąć „$name” z Moongate?';
  }

  @override
  String get dashboardRemoveSupabaseUnreachable =>
      'Usunięto lokalnie, ale nie udało się połączyć z Supabase. Uruchom MOONGATE_RESET_OWNER na Pi, jeśli ponowne parowanie się nie powiedzie.';

  @override
  String get dashboardBackUpConfig => 'Utwórz kopię zapasową';

  @override
  String get dashboardBackUpConfigSubtitle =>
      'Zapisz do pliku przed ponowną instalacją';

  @override
  String get dashboardRestoreConfig => 'Przywróć konfigurację';

  @override
  String get dashboardRestoreConfigSubtitle =>
      'Wczytaj z pliku kopii zapasowej';

  @override
  String get dashboardThemeHeading => 'Motyw';

  @override
  String get dashboardThemeSystem => 'Kolory telefonu';

  @override
  String get dashboardThemeDark => 'Ciemny';

  @override
  String get dashboardThemeLight => 'Jasny';

  @override
  String get dashboardThemeCustom => 'Niestandardowy';

  @override
  String get dashboardFontHeading => 'Czcionka';

  @override
  String get fontStandard => 'Domyślna';

  @override
  String get fontRounded => 'Zaokrąglona';

  @override
  String get fontSerif => 'Szeryfowa';

  @override
  String get fontReadable => 'Wysoka czytelność';

  @override
  String get dashboardCustomiseColours => 'Dostosuj kolory';

  @override
  String get dashboardCustomiseColoursSubtitle =>
      'Edytuj pięć slotów motywu - HEX lub paleta';

  @override
  String get dashboardFontSizeHeading => 'Rozmiar interfejsu';

  @override
  String get dashboardLayoutHeading => 'Układ pulpitu';

  @override
  String dashboardColumnCount(int count) {
    return '$count kol.';
  }

  @override
  String get dashboardRotateWithDevice => 'Obracaj z urządzeniem';

  @override
  String get dashboardRotateWithDeviceSubtitle =>
      'Odblokowuje orientację poziomą';

  @override
  String get dashboardAutoArrange => 'Automatyczne sortowanie wg statusu';

  @override
  String get dashboardAutoArrangeSubtitle =>
      'Sortuj kafelki wg aktywności. Wyłącz, aby przeciągać je we własnej kolejności.';

  @override
  String get dashboardShowButtons => 'Pokaż przyciski pulpitu';

  @override
  String get dashboardShowButtonsSubtitle =>
      'Pokazuje przyciski dodawania i zmiany kolejności na dole. Gdy ukryte, dodawaj drukarki z menu.';

  @override
  String get dashboardReorderHint =>
      'Przytrzymaj i przeciągnij kafelek, aby zmienić kolejność';

  @override
  String get dashboardReorderStart => 'Zmień kolejność';

  @override
  String get dashboardReorderDone => 'Gotowe';

  @override
  String get dashboardCameraFeedHeading => 'Podgląd kamery na pulpicie';

  @override
  String get dashboardCameraFeedSubtitle =>
      'Jak często kafelki odświeżają obraz z kamery. Niższe częstotliwości zużywają znacznie mniej danych.';

  @override
  String get cameraFeedsMenuTitle => 'Podglądy kamer pulpitu';

  @override
  String get cameraFeedsMenuSubtitle => 'Częstotliwości lokalna i tunelowa';

  @override
  String get cameraFeedsIntro =>
      'Jak często każdy kafelek odświeża obraz z kamery. Moongate używa częstotliwości lokalnej, gdy jesteś w Wi-Fi (także poza domem), i częstotliwości tunelu przy danych komórkowych - dzięki czemu obraz w Wi-Fi jest szybki, a w sieci komórkowej lżejszy, by oszczędzać dane.';

  @override
  String get cameraFeedsLocalRate => 'Częstotliwość lokalnego podglądu';

  @override
  String get cameraFeedsTunnelRate => 'Częstotliwość podglądu przez tunel';

  @override
  String get dashboardAboutHeading => 'Informacje';

  @override
  String get dashboardWhatsNew => 'Co nowego';

  @override
  String get dashboardWhatsNewSubtitle => 'Najnowsze zmiany w skrócie';

  @override
  String get dashboardHowPairingWorks => 'Jak działa parowanie';

  @override
  String get dashboardHowPairingWorksSubtitle =>
      'Parowanie, ponowna instalacja i przywracanie';

  @override
  String get dashboardReportProblem => 'Zgłoś problem';

  @override
  String get dashboardReportProblemSubtitle =>
      'Wyślij raport o błędzie lub opinię';

  @override
  String get dashboardAppLock => 'Blokada aplikacji';

  @override
  String get dashboardAppLockOn =>
      'Wł. - odblokowanie wymagane przy uruchomieniu';

  @override
  String get dashboardAppLockOff => 'Wył.';

  @override
  String get dashboardBuyMeCoffee => 'Postaw mi kawę';

  @override
  String get dashboardBuyMeCoffeeSubtitle => 'Wesprzyj dewelopera przez PayPal';

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
  String get donationPromptTitle => 'Podoba Ci się Moongate?';

  @override
  String get donationPromptBody =>
      'Moongate to darmowy projekt, który tworzę po godzinach. Jeśli jest dla Ciebie przydatny, drobny napiwek pomaga go rozwijać - bez presji, zapytam tylko ten jeden raz.';

  @override
  String get donationPromptLater => 'Może później';

  @override
  String get dashboardSettings => 'Ustawienia';

  @override
  String dashboardVersion(String version) {
    return 'Moongate v$version';
  }

  @override
  String get dashboardSaveBackupDialogTitle => 'Zapisz kopię zapasową Moongate';

  @override
  String get dashboardBackupFailed =>
      'Tworzenie kopii zapasowej nie powiodło się - nie udało się zapisać pliku.';

  @override
  String dashboardBackupSuccess(int count) {
    return 'Utworzono kopię zapasową $count drukarek. Ten plik pozwala przywrócić je po nowej instalacji - przechowuj go w bezpiecznym miejscu.';
  }

  @override
  String dashboardBackupSuccessListOnly(int count) {
    return 'Utworzono kopię zapasową $count drukarek (tylko lista - nie udało się połączyć z chmurą po kod przywracania).';
  }

  @override
  String get dashboardInvalidBackupFile =>
      'Nieprawidłowy plik kopii zapasowej - wybierz plik konfiguracji Moongate.';

  @override
  String dashboardRestoreReconnected(int added, int count) {
    return 'Przywrócono $added drukarek - $count połączono ponownie i wracają online.';
  }

  @override
  String dashboardRestoreNoneReconnected(int added) {
    return 'Przywrócono $added drukarek, ale żadnej nie połączono ponownie - kod przywracania z kopii zapasowej nie pasował do żadnej drukarki (może pochodzić ze starszej kopii lub został już użyty). Sparuj je ponownie, aby przywrócić je online.';
  }

  @override
  String dashboardRestoreListOnly(int added) {
    return 'Przywrócono $added drukarek (tylko lista). Sparuj ponownie każdą drukarkę, aby przywrócić ją online.';
  }

  @override
  String get dashboardRestoreApplied =>
      'Pulpit przywrócony zgodnie z kopią zapasową.';

  @override
  String get dashboardRestoreReplaceTitle => 'Zastąpić pulpit?';

  @override
  String dashboardRestoreReplaceBody(String names) {
    return 'Te drukarki są na tym pulpicie, ale nie ma ich w kopii zapasowej: $names. Przywracanie usunie je, aby pulpit dokładnie odpowiadał kopii. Pozostaną sparowane - możesz je później dodać ponownie lub przywrócić.';
  }

  @override
  String get dashboardRestoreReplaceConfirm => 'Zastąp';

  @override
  String get dashboardRemoveSheetTitle => 'Usuń drukarkę';

  @override
  String dashboardPrinterIdShort(String id) {
    return 'id $id…';
  }

  @override
  String get dashboardPairingHelpPluginTitle =>
      'Najpierw: zainstaluj wtyczkę Pi';

  @override
  String get dashboardPairingHelpPluginBody =>
      'Moongate wymaga swojej wtyczki na drukarce Klipper przed parowaniem. Jeśli jeszcze jej nie zainstalowano, otwórz przewodnik szybkiego startu.';

  @override
  String get dashboardPairingHelpPluginAction => 'Otwórz przewodnik';

  @override
  String get dashboardPairingHelpPairOnceTitle => 'Sparuj raz';

  @override
  String get dashboardPairingHelpPairOnceBody =>
      'Zeskanuj kod QR (lub wpisz kod GATE), aby dodać drukarkę - to powiązanie zostaje zapisane w tej aplikacji.';

  @override
  String get dashboardPairingHelpUpdatesTitle =>
      'Aktualizacje aplikacji zachowują drukarki';

  @override
  String get dashboardPairingHelpUpdatesBody =>
      'Aktualizacja Moongate nigdy nie wymaga ponownego parowania.';

  @override
  String get dashboardPairingHelpReinstallTitle =>
      'Ponowna instalacja lub nowy telefon?';

  @override
  String get dashboardPairingHelpReinstallBody =>
      'Najpierw utwórz kopię zapasową (Menu → Utwórz kopię zapasową), a następnie Przywróć przywraca drukarki online - bez ponownego parowania.';

  @override
  String get dashboardPairingHelpNoBackupTitle => 'Brak kopii zapasowej?';

  @override
  String get dashboardPairingHelpNoBackupBody =>
      'Uruchom MOONGATE_RESET_OWNER w konsoli drukarki, a następnie sparuj ponownie.';

  @override
  String get dashboardDontShowAgain => 'Nie pokazuj ponownie';

  @override
  String dashboardUpdateAvailable(String version) {
    return 'Dostępna aktualizacja - v$version';
  }

  @override
  String get dashboardUpdateLater => 'Później';

  @override
  String get dashboardUpdate => 'Aktualizuj';

  @override
  String get dashboardEmptyTitle => 'Nie dodano jeszcze żadnych drukarek';

  @override
  String get dashboardEmptyBody =>
      'Naciśnij przycisk poniżej, aby sparować pierwszą drukarkę.';

  @override
  String get pairingTitle => 'Dodaj drukarkę';

  @override
  String get pairingIntro =>
      'Uruchom MOONGATE_PAIR w konsoli Klipper - zeskanuj kod QR lub wpisz kod GATE wyświetlony w konsoli.';

  @override
  String get pairingNameLabel => 'Nazwa drukarki';

  @override
  String get pairingNameHint => 'np. Voron 2.4';

  @override
  String get pairingScanButton => 'Zeskanuj kod QR';

  @override
  String get pairingScanRecommended => 'Zalecane - łączy natychmiast';

  @override
  String get pairingOr => 'LUB';

  @override
  String get pairingGateCodeLabel => 'Kod GATE';

  @override
  String get pairingGateCodeHint =>
      'Wpisz 8-cyfrowy kod wyświetlony w konsoli Klipper.';

  @override
  String get pairingGateCodeValid => 'Kod wygląda poprawnie ✓';

  @override
  String get pairingGateCodeWarning =>
      'Metoda alternatywna. Bez kodu QR drukarka może potrzebować nawet około minuty, aby się połączyć - czeka na nawiązanie bezpiecznego tunelu. Zeskanuj kod QR powyżej, aby połączyć się natychmiast.';

  @override
  String get pairingCameraPermissionNeeded => 'Wymagane uprawnienie do kamery';

  @override
  String get pairingCameraUnavailable => 'Kamera niedostępna';

  @override
  String get pairingCancelScan => 'Anuluj skanowanie';

  @override
  String pairingQrScanned(String code) {
    return 'Zeskanowano kod QR - kod $code';
  }

  @override
  String get pairingRescan => 'Skanuj ponownie';

  @override
  String get pairingAdvancedTitle =>
      'Zaawansowane - drukarka w niestandardowej sieci?';

  @override
  String get pairingAdvancedBody =>
      'Większość osób może pozostawić to pole puste. Jeśli Twoja drukarka działa za reverse proxy (Traefik, Caddy, NPM) lub w Dockerze, wpisz ten sam adres, którego używasz do otwierania jej strony WWW (Mainsail / Fluidd) w przeglądarce.';

  @override
  String get pairingAddressLabel => 'Adres drukarki';

  @override
  String get pairingAddressHint => '192.168.1.50:7125';

  @override
  String get pairingPairButton => 'Sparuj drukarkę';

  @override
  String get pairingRestoreHint =>
      'Ponowna instalacja? Przywróć zapisane drukarki z pliku kopii zapasowej. Każdą z nich trzeba będzie sparować ponownie, aby przywrócić ją online.';

  @override
  String get pairingImportButton => 'Importuj konfigurację z pliku';

  @override
  String get pairingReportButton => 'Problem z parowaniem? Wyślij raport';

  @override
  String get pairingCameraPermissionTitle => 'Wymagane uprawnienie do kamery';

  @override
  String get pairingCameraPermissionBody =>
      'Moongate potrzebuje dostępu do kamery, aby skanować kody QR.\n\nOtwórz Ustawienia → Aplikacje → Moongate → Uprawnienia i włącz Kamerę, a następnie wróć i spróbuj ponownie.';

  @override
  String get pairingOpenSettings => 'Otwórz ustawienia';

  @override
  String get pairingErrorNotMoongateQr =>
      'To nie jest kod QR Moongate. Uruchom MOONGATE_PAIR na drukarce, aby go wygenerować.';

  @override
  String get pairingErrorOldQr =>
      'Ten kod QR pochodzi ze starszej wersji Moongate. Najpierw zaktualizuj Pi do wersji v0.3.0.';

  @override
  String get pairingErrorNoCode =>
      'Zeskanuj kod QR lub wpisz kod GATE z konsoli drukarki.';

  @override
  String get pairingErrorBadAddress =>
      'Ten adres drukarki wygląda nieprawidłowo - spróbuj np. 192.168.1.50:7125';

  @override
  String pairingErrorFailed(String error) {
    return 'Parowanie nie powiodło się: $error';
  }

  @override
  String get pairingImportInvalidFile =>
      'Nieprawidłowy plik kopii zapasowej - wybierz plik konfiguracji Moongate.';

  @override
  String get pairingImportNoNewPrinters =>
      'Nie znaleziono nowych drukarek w tym pliku.';

  @override
  String pairingImportRestoredReconnected(int count, int reconnected) {
    return 'Przywrócono $count drukarek - $reconnected połączono ponownie, wracają online.';
  }

  @override
  String pairingImportRestoredRepair(int count) {
    return 'Przywrócono $count drukarek - sparuj ponownie każde Pi, aby przywrócić je online.';
  }

  @override
  String get customThemeTitle => 'Motyw niestandardowy';

  @override
  String get customThemeResetTooltip => 'Przywróć ustawienia domyślne';

  @override
  String get customThemeResetConfirmTitle => 'Zresetować motyw niestandardowy?';

  @override
  String get customThemeResetConfirmBody =>
      'Wszystkie pięć slotów kolorów zostanie przywróconych do domyślnej palety fioletu na ciemnym tle.';

  @override
  String get customThemeReset => 'Resetuj';

  @override
  String get customThemePreview => 'Podgląd';

  @override
  String get customThemeAccent => 'Akcent';

  @override
  String get customThemeAccentDesc => 'Przyciski, FAB, paski postępu, linki';

  @override
  String get customThemeBackground => 'Tło strony';

  @override
  String get customThemeBackgroundDesc => 'Za każdym ekranem';

  @override
  String get customThemeSurface => 'Karty i kafelki';

  @override
  String get customThemeSurfaceDesc => 'Kafelki pulpitu, arkusze, panel boczny';

  @override
  String get customThemeText => 'Tekst';

  @override
  String get customThemeTextDesc =>
      'Tekst treści i nagłówków na powierzchniach';

  @override
  String get customThemeError => 'Błąd / Stop';

  @override
  String get customThemeErrorDesc => 'Działania destrukcyjne, nakładki błędów';

  @override
  String get customThemeEstop => 'Przycisk awaryjnego zatrzymania';

  @override
  String get customThemeEstopDesc => 'Pierścień i ikona awaryjnego zatrzymania';

  @override
  String get customThemePresets => 'Gotowe ustawienia';

  @override
  String get customThemeInvalidHex => 'Nieprawidłowy kolor szesnastkowy';

  @override
  String get customThemeSamplePrinter => 'Przykładowa drukarka';

  @override
  String get customThemePrinting => 'Drukowanie';

  @override
  String get tilePauseFailed =>
      'Nie można połączyć z drukarką - wstrzymanie nie powiodło się';

  @override
  String get tileResumeFailed =>
      'Nie można połączyć z drukarką - wznowienie nie powiodło się';

  @override
  String get tileStopAgainToCancel =>
      'Naciśnij STOP ponownie, aby anulować wydruk';

  @override
  String get tileLocal => 'Lokalnie';

  @override
  String get tileTunnel => 'Tunel';

  @override
  String get tilePrinting => 'Drukowanie';

  @override
  String get tilePaused => 'Wstrzymano';

  @override
  String get tileResume => 'Wznów';

  @override
  String get tilePause => 'Wstrzymaj';

  @override
  String get tileConfirmStop => 'Potwierdź zatrzymanie';

  @override
  String get tileStopPrint => 'Zatrzymaj wydruk';

  @override
  String get tileFirmwareRestart => 'Restart firmware';

  @override
  String get tileEmergencyStop => 'Zatrzymanie awaryjne · dotknij dwukrotnie';

  @override
  String get tileEmergencyStopFailed =>
      'Nie można połączyć z drukarką - zatrzymanie awaryjne nie powiodło się';

  @override
  String get tilePrintComplete => 'Wydruk ukończony';

  @override
  String get tilePrintCancelled => 'Wydruk anulowany';

  @override
  String get tilePrinterError => 'Błąd drukarki';

  @override
  String get tileKlipperStarting => 'Klipper uruchamia się';

  @override
  String get tileReady => 'Gotowa';

  @override
  String get tileOffline => 'Offline';

  @override
  String get tileStartingUp => 'Uruchamianie…';

  @override
  String get tileConnected => 'Połączono';

  @override
  String get tileConnecting => 'Łączenie…';

  @override
  String get tilePrinterUnreachable => 'Drukarka nieosiągalna';

  @override
  String get tileWaitingForHeartbeat => 'Oczekiwanie na pierwszy sygnał';

  @override
  String get tilePrinterIdle => 'Drukarka bezczynna';

  @override
  String get tileReachingPrinter => 'Łączenie z drukarką';

  @override
  String get tileRemoteReady => 'Zdalny dostęp gotowy';

  @override
  String get tileRemoteConnecting => 'Łączenie zdalne…';

  @override
  String get tileIdle => 'Bezczynna';

  @override
  String get tileDone => 'Gotowe';

  @override
  String get tileCancelled => 'Anulowano';

  @override
  String get tileClearJobTooltip => 'Wyczyść i ustaw jako bezczynną';

  @override
  String get tileClearJobFailed => 'Nie udało się zresetować drukarki';

  @override
  String get dashboardBackgroundTitle => 'Tło pulpitu';

  @override
  String get dashboardBackgroundNone => 'Brak - kolor motywu';

  @override
  String get dashboardBackgroundCustom => 'Własny obraz';

  @override
  String get dashboardBackgroundRemove => 'Usuń tło';

  @override
  String get dashboardBackgroundSet => 'Zaktualizowano tło';

  @override
  String get uiGuideSectionTileButtons => 'Przyciski kafelka';

  @override
  String get uiGuideFilesTitle => 'Wydrukuj plik';

  @override
  String get uiGuideFilesDesc =>
      'Przeglądaj pliki G-code zapisane w drukarce i uruchom jeden.';

  @override
  String get uiGuideMacrosTitle => 'Makra';

  @override
  String get uiGuideMacrosDesc => 'Uruchom jedno z makr Klipper drukarki.';

  @override
  String get uiGuidePowerTitle => 'Zasilanie';

  @override
  String get uiGuidePowerDesc =>
      'Włącz lub wyłącz drukarkę, gdy ma urządzenie zasilające.';

  @override
  String get uiGuideLightingTitle => 'Oświetlenie';

  @override
  String get uiGuideLightingDesc =>
      'Przełącz światło drukarki; żarówka świeci, gdy jest włączone.';

  @override
  String get uiGuideCameraViewTitle => 'Kamera';

  @override
  String get uiGuideCameraViewDesc =>
      'Otwórz kamerę na żywo na pełnym ekranie.';

  @override
  String get uiGuideCameraSetupTitle => 'Konfiguracja kamery';

  @override
  String get uiGuideCameraSetupDesc =>
      'Skieruj kafelek na kamerę niepodłączoną do Klippera.';

  @override
  String get uiGuideClearJobTitle => 'Wyczyść ukończony wydruk';

  @override
  String get uiGuideClearJobDesc =>
      'Dotknij × na kafelku Gotowe lub Anulowano, aby ustawić go jako bezczynny.';

  @override
  String get tileError => 'Błąd';

  @override
  String get tileStarting => 'Uruchamianie';

  @override
  String get tileConnectingBadge => 'Łączenie';

  @override
  String get appLockTitle => 'Blokada aplikacji';

  @override
  String get appLockIntro =>
      'Wymagaj kodu PIN - i opcjonalnie odcisku palca lub twarzy - zanim Moongate się otworzy. Blokada zawsze pojawia się przy świeżym uruchomieniu aplikacji.';

  @override
  String get appLockSubtitle => 'Kod PIN wymagany do otwarcia aplikacji';

  @override
  String get appLockBiometricTitle => 'Odblokowanie biometryczne';

  @override
  String get appLockBiometricSubtitle =>
      'Użyj odcisku palca lub twarzy - PIN pozostaje opcją awaryjną';

  @override
  String get appLockChangePin => 'Zmień PIN';

  @override
  String get appLockAutoLock => 'Automatyczna blokada';

  @override
  String get appLockPinUpdated => 'Zaktualizowano PIN';

  @override
  String get appLockChoosePinTitle => 'Wybierz PIN';

  @override
  String get appLockChoosePinSubtitle => 'Wpisz od 4 do 6 cyfr';

  @override
  String get appLockConfirmPinTitle => 'Potwierdź PIN';

  @override
  String get appLockPinsDontMatch => 'Kody PIN nie pasują';

  @override
  String get appLockEnterCurrentPin => 'Wpisz bieżący PIN';

  @override
  String get appLockTimeoutImmediately => 'Natychmiast';

  @override
  String get appLockTimeoutOneMinute => 'Po 1 minucie';

  @override
  String get appLockTimeoutFiveMinutes => 'Po 5 minutach';

  @override
  String get appLockTimeoutFifteenMinutes => 'Po 15 minutach';

  @override
  String get appLockTimeoutColdLaunch => 'Tylko przy uruchomieniu aplikacji';

  @override
  String get lockEnterPin => 'Wpisz swój PIN';

  @override
  String get lockSubtitle => 'Moongate jest zablokowane';

  @override
  String lockTooManyAttempts(int seconds) {
    return 'Zbyt wiele prób. Spróbuj ponownie za $seconds s';
  }

  @override
  String get lockWrongPin => 'Nieprawidłowy PIN';

  @override
  String get lockUseBiometrics => 'Użyj biometrii';

  @override
  String get lockForgotPin => 'Nie pamiętasz PIN-u?';

  @override
  String get lockBiometricReason => 'Odblokuj Moongate';

  @override
  String get lockResetTitle => 'Zresetować Moongate?';

  @override
  String get lockResetBody =>
      'Spowoduje to usunięcie blokady aplikacji i sparowanych drukarek z tego urządzenia, dzięki czemu możesz zacząć od nowa. Twoje drukarki nie zostaną usunięte - sparuj je ponownie, uruchamiając MOONGATE_PAIR na każdej z nich.';

  @override
  String get lockResetConfirm => 'Resetuj';

  @override
  String get pinContinue => 'Dalej';

  @override
  String printerStartingUpRetry(int seconds) {
    return 'Drukarka się uruchamia. Ponawianie za $seconds s…';
  }

  @override
  String printerCouldNotReach(String error) {
    return 'Nie można połączyć z drukarką: $error';
  }

  @override
  String get printerAddressCleared => 'Wyczyszczono niestandardowy adres';

  @override
  String get printerAddressUpdated => 'Zaktualizowano adres drukarki';

  @override
  String printerTunnelUnreachable(String description) {
    return 'Tunel Cloudflare nieosiągalny.\n$description';
  }

  @override
  String get printerEdit => 'Edytuj drukarkę';

  @override
  String get printerLocalNetwork => 'Sieć lokalna';

  @override
  String get printerTunnelVia => 'Tunel przez Moongate';

  @override
  String get printerCameraTooltip => 'Kamera';

  @override
  String get cameraConnecting => 'Łączenie z kamerą…';

  @override
  String get cameraNoCamera => 'Brak skonfigurowanej kamery dla tej drukarki.';

  @override
  String get cameraHintBody =>
      'Kamera nie ładuje się tutaj zdalnie - otwórz kamerę Moongate.';

  @override
  String get cameraHintOpen => 'Otwórz';

  @override
  String get printerUnreachable => 'Drukarka nieosiągalna';

  @override
  String get printerUseTunnel => 'Użyj tunelu';

  @override
  String get printerAddressInvalid => 'Spróbuj np. 192.168.1.50:7125';

  @override
  String get printerNameLabel => 'Nazwa drukarki';

  @override
  String get printerAddressLabel => 'Adres drukarki (zaawansowane)';

  @override
  String get printerAddressHint => '192.168.1.50:7125';

  @override
  String get printerAddressHelper =>
      'Tylko dla konfiguracji z reverse proxy / Dockerem. Pozostaw puste, aby używać automatycznego wykrywania.';

  @override
  String get feedbackTitle => 'Zgłoś problem';

  @override
  String get feedbackTroublePairing => 'Problem z parowaniem?';

  @override
  String get feedbackDescription =>
      'Powiedz nam, co się dzieje. Wersja aplikacji, urządzenie, sieć i szczegóły drukarki są dołączane automatycznie, aby pomóc nam zlokalizować problem.';

  @override
  String get feedbackPairingDescription =>
      'Opisz, co się dzieje, gdy próbujesz dodać drukarkę. Szczegóły Twojej sieci i wykrywania są dołączane automatycznie, abyśmy mogli zobaczyć, dlaczego nie udaje się połączyć.';

  @override
  String get feedbackWhichPrinter => 'Której drukarki dotyczy? (opcjonalnie)';

  @override
  String get feedbackGeneralOption =>
      'Ogólne / niezwiązane z konkretną drukarką';

  @override
  String get feedbackCommentLabel => 'Co poszło nie tak?';

  @override
  String get feedbackCommentHint =>
      'np. „Drukarka pokazuje Połączono / bezczynna, ale tak naprawdę jest gotowa - otwiera się normalnie, gdy naciskam kafelek.”';

  @override
  String get feedbackContactLabel => 'E-mail lub kontakt (opcjonalnie)';

  @override
  String get feedbackContactHint => 'Tylko jeśli chcesz otrzymać odpowiedź';

  @override
  String get feedbackSending => 'Wysyłanie…';

  @override
  String get feedbackSend => 'Wyślij raport';

  @override
  String get feedbackSuccess => 'Dziękujemy - Twój raport został wysłany.';

  @override
  String get feedbackError =>
      'Nie udało się wysłać - sprawdź połączenie i spróbuj ponownie.';

  @override
  String get splashTagline => 'Zdalne sterowanie Klipper';

  @override
  String get uiGuideTitle => 'Przewodnik po ikonach';

  @override
  String get uiGuideMenuSubtitle => 'Co oznaczają ikony na pulpicie';

  @override
  String get uiGuideIntro =>
      'Krótki przewodnik po ikonach, które zobaczysz na pulpicie.';

  @override
  String get uiGuideSectionConnection => 'Połączenie';

  @override
  String get uiGuideSectionTemperatures => 'Temperatury';

  @override
  String get uiGuideSectionControls => 'Sterowanie wydrukiem';

  @override
  String get uiGuideSectionStatus => 'Stan';

  @override
  String get uiGuideSectionWebcam => 'Kamera i połączenie';

  @override
  String get uiGuideLocalTitle => 'Sieć lokalna';

  @override
  String get uiGuideLocalDesc =>
      'Połączono bezpośrednio przez Twoje Wi-Fi - najszybsza ścieżka.';

  @override
  String get uiGuideTunnelTitle => 'Zdalnie (tunel)';

  @override
  String get uiGuideTunnelDesc =>
      'Połączono z dowolnego miejsca przez bezpieczny tunel Cloudflare.';

  @override
  String get uiGuideTunnelReadyTitle => 'Zdalny dostęp gotowy';

  @override
  String get uiGuideTunnelReadyDesc =>
      'Tunel jest aktywny, więc zdalny dostęp jest dostępny.';

  @override
  String get uiGuideTunnelConnectingTitle => 'Łączenie zdalne';

  @override
  String get uiGuideTunnelConnectingDesc => 'Zdalny tunel wciąż się nawiązuje.';

  @override
  String get uiGuideHotendTitle => 'Hotend / dysza';

  @override
  String get uiGuideHotendDesc => 'Bieżąca temperatura dyszy.';

  @override
  String get uiGuideBedTitle => 'Podgrzewany stół';

  @override
  String get uiGuideBedDesc => 'Bieżąca temperatura stołu.';

  @override
  String get uiGuideChamberTitle => 'Komora';

  @override
  String get uiGuideChamberDesc =>
      'Temperatura komory - wyświetlana tylko, jeśli Twoja drukarka ją raportuje.';

  @override
  String get uiGuideResumeTitle => 'Wznów';

  @override
  String get uiGuideResumeDesc => 'Wznów wstrzymany wydruk.';

  @override
  String get uiGuidePauseTitle => 'Wstrzymaj';

  @override
  String get uiGuidePauseDesc => 'Wstrzymaj bieżący wydruk.';

  @override
  String get uiGuideStopTitle => 'Stop';

  @override
  String get uiGuideStopDesc =>
      'Anuluj wydruk - naciśnij dwukrotnie, aby potwierdzić.';

  @override
  String get uiGuideEstopTitle => 'Zatrzymanie awaryjne';

  @override
  String get uiGuideEstopDesc =>
      'Dotknij dwukrotnie czerwonego trójkąta, aby natychmiast zatrzymać drukarkę (Klipper M112).';

  @override
  String get uiGuideFirmwareRestartTitle => 'Restart firmware';

  @override
  String get uiGuideFirmwareRestartDesc =>
      'Zrestartuj Klipper, gdy drukarka jest bezczynna lub w stanie błędu.';

  @override
  String get uiGuideStatusReadyTitle => 'Gotowa / ukończono';

  @override
  String get uiGuideStatusReadyDesc =>
      'Drukarka jest bezczynna lub ukończyła ostatni wydruk.';

  @override
  String get uiGuideStatusCancelledTitle => 'Anulowano';

  @override
  String get uiGuideStatusCancelledDesc => 'Ostatni wydruk został anulowany.';

  @override
  String get uiGuideStatusErrorTitle => 'Błąd';

  @override
  String get uiGuideStatusErrorDesc =>
      'Klipper zgłosił błąd - otwórz drukarkę, aby zobaczyć szczegóły.';

  @override
  String get uiGuideStatusStartingTitle => 'Uruchamianie';

  @override
  String get uiGuideStatusStartingDesc =>
      'Klipper się uruchamia; elementy sterujące pojawią się, gdy będzie gotowy.';

  @override
  String get uiGuideOfflineTitle => 'Offline';

  @override
  String get uiGuideOfflineDesc => 'Drukarka jest w tej chwili nieosiągalna.';

  @override
  String get uiGuideNoWebcamTitle => 'Brak kamery';

  @override
  String get uiGuideNoWebcamDesc =>
      'Dla tej drukarki nie jest dostępny obraz z kamery.';

  @override
  String get uiGuideBack => 'Powrót do pulpitu';

  @override
  String get printNotifTitle => 'Powiadomienia o druku';

  @override
  String get printNotifSubtitle =>
      'Postęp i status na żywo, gdy aplikacja działa w tle';

  @override
  String get printNotifPermissionNeeded =>
      'Zezwól na powiadomienia, aby to włączyć.';

  @override
  String get printNotifPromptTitle => 'Otrzymywać powiadomienia o druku?';

  @override
  String get printNotifPromptBody =>
      'Zobacz status drukarek na żywo - postęp, temperatury oraz alerty, gdy druk się rozpocznie, zakończy lub wystąpi błąd. Możesz to zmienić w dowolnej chwili w menu.';

  @override
  String get printNotifPromptEnable => 'Włącz';

  @override
  String get printNotifPromptNotNow => 'Nie teraz';

  @override
  String get printNotifWatching => 'Monitorowanie drukarek…';

  @override
  String get printNotifNoPrinters => 'Brak drukarek';

  @override
  String get printNotifNoneOnline => 'Brak drukarek online';

  @override
  String get notifOnlineOnlyTitle => 'Pokaż tylko urządzenia online';

  @override
  String get notifOnlineOnlySubtitle =>
      'Ukryj maszyny offline z powiadomienia o stanie';

  @override
  String get notifPollIntervalTitle => 'Częstotliwość aktualizacji';

  @override
  String get notifContentTitle => 'Zawartość powiadomienia';

  @override
  String get notifContentSubtitle => 'Wybierz i zmień kolejność';

  @override
  String get notifContentIntro =>
      'Wybierz, które informacje pojawiają się na karcie powiadomienia każdego wydruku, i przeciągnij je w żądanej kolejności.';

  @override
  String get notifContentPreview => 'Podgląd';

  @override
  String get notifFieldProgress => 'Postęp';

  @override
  String get notifFieldRemaining => 'Pozostały czas';

  @override
  String get notifFieldEta => 'Czas zakończenia';

  @override
  String get notifFieldHotend => 'Temp. dyszy';

  @override
  String get notifFieldBed => 'Temp. stołu';

  @override
  String get printAlertReady => 'Drukarka gotowa';

  @override
  String get printStatusReady => 'Gotowa';

  @override
  String get printStatusHeating => 'Nagrzewanie';

  @override
  String get printStatusIdle => 'Bezczynna';

  @override
  String get printStatusOffline => 'Offline';

  @override
  String get printStatusPaused => 'Wstrzymana';

  @override
  String get printStatusComplete => 'Ukończono';

  @override
  String get printStatusCancelled => 'Anulowano';

  @override
  String get printStatusError => 'Błąd';

  @override
  String get printStatusStartingUp => 'Uruchamianie…';

  @override
  String get printStatusPrinting => 'Drukowanie';

  @override
  String get printNotifStarted => 'Rozpoczęto drukowanie';

  @override
  String get printNotifFinished => 'Zakończono';

  @override
  String get notifClearAction => 'Wyczyść';

  @override
  String get printAlertStarted => 'Rozpoczęto druk';

  @override
  String get printAlertResumed => 'Wznowiono druk';

  @override
  String get printAlertPaused => 'Druk wstrzymany';

  @override
  String get printAlertComplete => 'Druk ukończony';

  @override
  String get printAlertCancelled => 'Druk anulowany';

  @override
  String get printAlertError => 'Błąd drukarki';

  @override
  String get tileOpenFiles => 'Drukuj plik';

  @override
  String get gcodeSheetTitle => 'Rozpocznij druk';

  @override
  String get gcodeLoading => 'Wczytywanie plików…';

  @override
  String get gcodeEmpty => 'Brak plików G-code na tej drukarce';

  @override
  String get gcodeError => 'Nie udało się wczytać plików';

  @override
  String get gcodeStartButton => 'Rozpocznij druk';

  @override
  String get gcodeStartAction => 'Rozpocznij';

  @override
  String get gcodeConfirmTitle => 'Rozpocząć druk?';

  @override
  String gcodeConfirmBody(String file) {
    return 'Wydrukować $file?';
  }

  @override
  String gcodeStarted(String file) {
    return 'Rozpoczęto druk $file';
  }

  @override
  String get gcodeStartFailed => 'Nie udało się rozpocząć druku';

  @override
  String get tileMacros => 'Makra';

  @override
  String get macrosSheetTitle => 'Makra';

  @override
  String get macrosLoading => 'Ładowanie makr…';

  @override
  String get macrosError => 'Nie można załadować makr';

  @override
  String get macrosEmpty => 'Brak makr na tej drukarce';

  @override
  String get macroFavourite => 'Przypnij na górze';

  @override
  String get macroUnfavourite => 'Odepnij';

  @override
  String get macroConfirmTitle => 'Uruchomić makro?';

  @override
  String macroConfirmBody(String macro) {
    return 'Uruchomić $macro na tej drukarce?';
  }

  @override
  String get macroRunAction => 'Uruchom';

  @override
  String macroSent(String macro) {
    return 'Wysłano $macro';
  }

  @override
  String macroFailed(String macro) {
    return 'Nie można wysłać $macro';
  }

  @override
  String get preheatTitle => 'Nagrzewanie';

  @override
  String get preheatHotend => 'Hotend';

  @override
  String get preheatBed => 'Stół';

  @override
  String get preheatHint =>
      'Pozostaw pole puste, aby nie zmieniać tej grzałki.';

  @override
  String get preheatSoakLabel => 'Minutnik nagrzewania';

  @override
  String get preheatSoakHelp =>
      'Powiadom mnie po tylu minutach. 0 = bez minutnika.';

  @override
  String get preheatMinutes => 'min';

  @override
  String get preheatSet => 'Ustaw';

  @override
  String get preheatNotifWarning =>
      'Alerty nagrzewania wymagają włączonych powiadomień o druku.';

  @override
  String get preheatNotifEnable => 'Włącz';

  @override
  String preheatSetConfirm(String summary) {
    return 'Ustawiono $summary';
  }

  @override
  String preheatSoakIn(int minutes) {
    return 'alert nagrzewania za $minutes min';
  }

  @override
  String get preheatFailed => 'Nie udało się ustawić temperatur';

  @override
  String get heatsoakDoneTitle => 'Nagrzewanie zakończone';

  @override
  String heatsoakDoneBody(String printer) {
    return '$printer osiągnął temperaturę';
  }

  @override
  String get tutorialOfferTitle => 'Chcesz szybkie wprowadzenie?';

  @override
  String get tutorialOfferBody =>
      'Czy chcesz krótkie wprowadzenie do tego, jak działa Moongate?';

  @override
  String get tutorialOfferDontRemind => 'Nie przypominaj mi ponownie';

  @override
  String get tutorialOfferNo => 'Nie, dziękuję';

  @override
  String get tutorialOfferStart => 'Rozpocznij samouczek';

  @override
  String get tutorialMenuTitle => 'Samouczek aplikacji';

  @override
  String get tutorialNext => 'Dalej';

  @override
  String get tutorialDone => 'Gotowe';

  @override
  String get tutorialSkip => 'Zakończ';

  @override
  String get tutorialBack => 'Wstecz';

  @override
  String get tutorialLocalBar =>
      'Kolorowy pasek pokazuje, jak Moongate łączy się z tą drukarką. Zielony z ikoną Wi-Fi oznacza, że jesteś w tej samej sieci - szybkie, bezpośrednie połączenie lokalne.';

  @override
  String get tutorialTunnelBar =>
      'Pomarańczowy z ikoną chmury oznacza, że jesteś poza domem i łączysz się bezpiecznie przez internet za pomocą tunelu drukarki. Moongate przełącza się między nimi automatycznie.';

  @override
  String get tutorialRemoteBuilding =>
      'Po pierwszym sparowaniu drukarki dostęp zdalny nie jest natychmiastowy. Ten mały znacznik chmury oznacza, że bezpieczny tunel jest wciąż budowany w tle. Gdy zmieni się w zielony znacznik chmury, będziesz mógł połączyć się z tą drukarką z dowolnego miejsca.';

  @override
  String get tutorialHotend => 'To Twoja głowica - temperatura dyszy.';

  @override
  String get tutorialBed => 'A to podgrzewany stół.';

  @override
  String get tutorialChamber =>
      'Jeśli Twoja drukarka ma czujnik komory, jej temperatura również pojawia się tutaj.';

  @override
  String get tutorialTemps =>
      'To temperatury na żywo: głowica (dysza), podgrzewany stół oraz - jeśli Twoja drukarka ma czujnik komory - komora.';

  @override
  String get tutorialEstop =>
      'To zatrzymanie awaryjne. Wymaga dwukrotnego dotknięcia, aby zadziałało, więc nie da się go uruchomić przypadkowo, i natychmiast zatrzymuje drukarkę.';

  @override
  String get tutorialWebcam =>
      'Dotknięcie podglądu kamery otwiera pełny interfejs drukarki - ekran Klipper na żywo.';

  @override
  String get tutorialPreheatPress =>
      'Naciśnij i przytrzymaj nazwę drukarki lub jej temperatury, aby wyświetlić panel nagrzewania.';

  @override
  String get tutorialPreheatSheet =>
      'Tutaj możesz ustawić docelowe temperatury głowicy i stołu oraz opcjonalny czas nagrzewania.';

  @override
  String get tutorialAddPrinter =>
      'Dotknij przycisku plus w dowolnej chwili, aby dodać kolejną drukarkę i ją sparować.';

  @override
  String get tutorialMenuIcon =>
      'To menu. Możesz je otworzyć stąd w dowolnej chwili.';

  @override
  String get tutorialMenuPrinters =>
      'Dodaj kolejną drukarkę lub usuń tę, której już nie używasz.';

  @override
  String get tutorialMenuBackup =>
      'Utwórz kopię zapasową swojej konfiguracji do pliku lub przywróć ją na innym urządzeniu.';

  @override
  String get tutorialMenuTheme =>
      'Wybierz jasny, ciemny lub w pełni niestandardowy motyw kolorów.';

  @override
  String get tutorialMenuDisplaySize =>
      'Przeciągnij to, aby powiększyć lub pomniejszyć wszystko według uznania.';

  @override
  String get tutorialMenuColumns =>
      'Ułóż swoje drukarki w jednej, dwóch lub trzech kolumnach.';

  @override
  String get tutorialMenuCameras =>
      'Ustaw, jak często odświeżają się obrazy z kamer, i włącz lub wyłącz kamerę każdej drukarki.';

  @override
  String get tutorialMenuAbout =>
      'Co nowego, jak działa parowanie, przewodnik po ikonach i gdzie zgłosić problem - wszystko znajdziesz tutaj.';

  @override
  String get tutorialMenuSupport =>
      'Postawienie mi kawy pomaga utrzymać Moongate darmowym dla wszystkich i otwartoźródłowym.';

  @override
  String get tutorialMenuSettings =>
      'Ustawienia mają dwie opcje: wyczyść wszystkie swoje drukarki lub usuń wszystkie dane i zacznij całkowicie od nowa.';

  @override
  String get tutorialMenuLanguage =>
      'A tutaj możesz zmienić język aplikacji - Moongate mówi w ośmiu. To koniec wprowadzenia, miłego korzystania!';
}
