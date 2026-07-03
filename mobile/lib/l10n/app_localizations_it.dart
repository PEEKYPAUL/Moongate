// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get updateDownloading => 'Download dell\'aggiornamento…';

  @override
  String get updateOpeningInstaller => 'Apertura dell\'installer…';

  @override
  String get updateFailed =>
      'Impossibile completare l\'aggiornamento automaticamente.';

  @override
  String get updateOpenInBrowser => 'Apri nel browser';

  @override
  String get lightingTitle => 'Illuminazione';

  @override
  String get lightingMenuSubtitle =>
      'Controlla le luci delle tue stampanti dalla dashboard';

  @override
  String get lightingBanner =>
      'Scegli quali stampanti hanno una luce controllabile. Per ognuna, attivala e imposta una coppia di macro Accendi + Spegni oppure una singola macro di Commutazione. Facoltativamente scegli una sorgente di stato così che la lampadina mostri lo stato reale.';

  @override
  String get lightingNoPrinters => 'Nessuna stampante da configurare per ora.';

  @override
  String get lightingShowOnTile => 'Mostra sulla scheda';

  @override
  String get lightingNeedMacro =>
      'Imposta una coppia Accendi + Spegni o una macro di Commutazione per attivare.';

  @override
  String get lightingLoadFailed =>
      'Impossibile caricare le macro di questa stampante (potrebbe essere offline). Inserisci i nomi manualmente qui sotto.';

  @override
  String get lightingOnMacro => 'Macro luce ON';

  @override
  String get lightingOffMacro => 'Macro luce OFF';

  @override
  String get lightingToggleMacro => 'Macro di commutazione';

  @override
  String get lightingToggleSection => 'Facoltativo - metodo di commutazione';

  @override
  String get lightingStatusSource => 'Sorgente di stato della luce';

  @override
  String get lightingStatusSourceHelp =>
      'Facoltativo. Un oggetto Klipper (es. output_pin caselight) il cui valore indica a Moongate se la luce è accesa. Lascia vuoto per seguire invece i tuoi tocchi.';

  @override
  String get lightingStatusHint => 'Esempio: output_pin caselight';

  @override
  String get lightingNotSet => 'Non impostato';

  @override
  String get lightingPickMacro => 'Seleziona una macro';

  @override
  String get lightingPickStatusSource => 'Seleziona una sorgente di stato';

  @override
  String get lightingManualHint => 'Digita il nome esatto';

  @override
  String get lightingClear => 'Cancella';

  @override
  String get lightTurnOn => 'Accendi la luce';

  @override
  String get lightTurnOff => 'Spegni la luce';

  @override
  String get lightToggleFailed => 'Impossibile raggiungere la stampante';

  @override
  String get powerTurnOn => 'Accendi';

  @override
  String get powerTurnOff => 'Spegni';

  @override
  String powerConfirmOn(String name) {
    return 'Accendere $name?';
  }

  @override
  String powerConfirmOff(String name) {
    return 'Spegnere $name?';
  }

  @override
  String get powerToggleFailed => 'Impossibile cambiare l\'alimentazione';

  @override
  String get powerLockedWhilePrinting => 'Non spegnibile durante la stampa';

  @override
  String get globalPowerButtonTitle => 'Pulsante di alimentazione globale';

  @override
  String get globalPowerButtonSubtitle =>
      'Un pulsante nella barra superiore per accendere o spegnere tutta la tua flotta';

  @override
  String get globalPowerTooltip => 'Alimenta tutte le stampanti';

  @override
  String get globalPowerSheetTitle => 'Alimenta tutte le stampanti';

  @override
  String get globalPowerOnAll => 'Accendi tutte';

  @override
  String get globalPowerSlideOff => 'scorri per spegnere tutte';

  @override
  String get globalPowerConfirmOnTitle => 'Accendere tutte le stampanti?';

  @override
  String get globalPowerConfirmOnBody =>
      'Questo accende ogni macchina che riusciamo a raggiungere.';

  @override
  String get globalPowerPrintingNote => 'Le stampanti in stampa restano accese';

  @override
  String get globalPowerStateWillSwitchOff => 'verrà spenta';

  @override
  String get globalPowerStateKeptPrinting => 'in stampa, lasciata accesa';

  @override
  String get globalPowerStateOffline => 'offline, saltata';

  @override
  String get globalPowerStateOnOff => 'on / off';

  @override
  String get globalPowerStateOffOnly => 'solo off';

  @override
  String get globalPowerStateOnOnly => 'solo on';

  @override
  String get globalPowerStateToggleOnly => 'solo commutazione';

  @override
  String get globalPowerNothing =>
      'Nessuna macchina ha ancora un controllo dell\'alimentazione configurato';

  @override
  String globalPowerResultOn(int count, int total) {
    return 'Accese $count di $total stampanti';
  }

  @override
  String globalPowerResultOff(int count, int total) {
    return 'Spente $count di $total stampanti';
  }

  @override
  String get powerScreenTitle => 'Interruttore di alimentazione avanzato';

  @override
  String get powerScreenBanner =>
      'Per le stampanti la cui alimentazione è una macro di Klipper anziché un dispositivo di alimentazione di Moonraker. Attivalo e imposta una macro di Spegnimento (il caso più comune), una macro di Accensione, entrambe, oppure una singola di commutazione. Il pulsante di accensione del riquadro usa una qualsiasi di esse.';

  @override
  String get powerUseSwitch => 'Usa le macro';

  @override
  String get powerNeedMacro =>
      'Imposta almeno una macro: una di Spegnimento (o Accensione), oppure una di commutazione.';

  @override
  String get powerOnMacro => 'Macro di accensione';

  @override
  String get powerOffMacro => 'Macro di spegnimento';

  @override
  String get powerToggleSection => 'Oppure una singola macro di commutazione';

  @override
  String get powerToggleMacro => 'Macro di commutazione';

  @override
  String get powerToggleBulkNote =>
      'Una macro di commutazione aziona il pulsante di accensione del riquadro. Per Alimenta tutte le stampanti, imposta una macro di Accensione e/o di Spegnimento.';

  @override
  String get powerMenuTitle => 'Interruttore di alimentazione avanzato';

  @override
  String get powerMenuSubtitle =>
      'Controlla l\'alimentazione della stampante con una macro';

  @override
  String get powerMacroTooltip => 'Alimentazione';

  @override
  String powerMacroToggleConfirm(String name) {
    return 'Commutare l\'alimentazione di $name?';
  }

  @override
  String powerMacroChooseTitle(String name) {
    return 'Cambia l\'alimentazione di $name';
  }

  @override
  String lightChooseTitle(String name) {
    return 'Cambia la luce di $name';
  }

  @override
  String get tileOpacityTitle => 'Opacità dei riquadri';

  @override
  String get tileOpacityDesc =>
      'Quanto sono trasparenti i riquadri (0-100), così da far vedere uno sfondo. Il flusso della videocamera resta opaco.';

  @override
  String get dashboardShowWebcams => 'Webcam';

  @override
  String get dashboardShowWebcamsSubtitle =>
      'Mostra o nascondi la webcam di ogni stampante';

  @override
  String get updateNotesUnavailable =>
      'Impossibile caricare le novità - controlla la connessione o consultale su GitHub.';

  @override
  String get updateViewOnGithub => 'Vedi su GitHub';

  @override
  String get cameraConfigTooltip => 'Imposta URL della telecamera';

  @override
  String get cameraConfigTitle => 'Telecamera personalizzata';

  @override
  String get cameraConfigDescription =>
      'Mostra una telecamera non collegata a Klipper, come un vecchio telefono usato come webcam. Inserisci l\'indirizzo indicato nelle impostazioni webcam di Mainsail.';

  @override
  String get cameraConfigUrlLabel => 'URL della telecamera';

  @override
  String get cameraConfigRemoteNote =>
      'Funziona in Wi-Fi e da remoto tramite la stampante. Da remoto sono raggiungibili solo le telecamere della tua rete domestica (indirizzi privati).';

  @override
  String get cameraConfigInvalid =>
      'Inserisci un indirizzo completo, es. http://192.168.0.107:8080/video';

  @override
  String get cameraConfigUseDefault => 'Usa la telecamera Klipper';

  @override
  String get cameraConfigApply => 'Applica';

  @override
  String get dashboardShowCameraIcons => 'Icone config. telecamera';

  @override
  String get dashboardShowCameraIconsSubtitle =>
      'Mostra l\'ingranaggio su ogni telecamera per impostare un URL personalizzato';

  @override
  String get appTitle => 'Moongate';

  @override
  String get languagePickerTitle => 'Scegli la tua lingua';

  @override
  String get languagePickerSubtitle =>
      'Puoi cambiarla in qualsiasi momento dal menu.';

  @override
  String get languagePickerContinue => 'Continua';

  @override
  String get menuLanguage => 'Lingua';

  @override
  String get languageSystemDefault => 'Predefinita di sistema';

  @override
  String get commonCancel => 'Annulla';

  @override
  String get commonOk => 'OK';

  @override
  String get commonClose => 'Chiudi';

  @override
  String get commonSave => 'Salva';

  @override
  String get commonDone => 'Fatto';

  @override
  String get commonRetry => 'Riprova';

  @override
  String get commonShowKeyboard => 'Mostra tastiera';

  @override
  String get dashboardSignInRetrying =>
      'Riconnessione al cloud - l\'accesso è occupato, nuovo tentativo. Le tue stampanti torneranno automaticamente.';

  @override
  String get commonRemove => 'Rimuovi';

  @override
  String get commonDelete => 'Elimina';

  @override
  String get commonEnable => 'Attiva';

  @override
  String get commonDisable => 'Disattiva';

  @override
  String get settingsTitle => 'Impostazioni';

  @override
  String get settingsRemoveAllTitle =>
      'Rimuovi tutte le stampanti da questo dispositivo';

  @override
  String get settingsRemoveAllSubtitle =>
      'Cancella la cache locale delle stampanti. Il tuo account Supabase viene mantenuto, così il nuovo abbinamento avviene senza problemi.';

  @override
  String get settingsRemoveAllConfirmTitle => 'Rimuovere tutte le stampanti?';

  @override
  String get settingsRemoveAllConfirmBody =>
      'Tutte le stampanti abbinate verranno rimosse da questo dispositivo. Puoi aggiungerle di nuovo eseguendo MOONGATE_PAIR sulla stampante.';

  @override
  String get settingsRemoveAllConfirmAction => 'Rimuovi tutte';

  @override
  String get dashboardAddPrinter => 'Aggiungi stampante';

  @override
  String get dashboardRemovePrinter => 'Rimuovi stampante';

  @override
  String get dashboardMenuTooltip => 'Menu';

  @override
  String get dashboardRemovePrinterTitle => 'Rimuovere la stampante?';

  @override
  String dashboardRemovePrinterBody(String name) {
    return 'Rimuovere \"$name\" da Moongate?';
  }

  @override
  String get dashboardRemoveSupabaseUnreachable =>
      'Rimossa localmente, ma impossibile raggiungere Supabase. Esegui MOONGATE_RESET_OWNER sul Pi se il nuovo abbinamento non riesce.';

  @override
  String get dashboardBackUpConfig => 'Backup configurazione';

  @override
  String get dashboardBackUpConfigSubtitle =>
      'Salva su file prima di reinstallare';

  @override
  String get dashboardRestoreConfig => 'Ripristina configurazione';

  @override
  String get dashboardRestoreConfigSubtitle => 'Carica da un file di backup';

  @override
  String get dashboardThemeHeading => 'Tema';

  @override
  String get dashboardThemeSystem => 'Colori del telefono';

  @override
  String get dashboardThemeDark => 'Scuro';

  @override
  String get dashboardThemeLight => 'Chiaro';

  @override
  String get dashboardThemeCustom => 'Personalizzato';

  @override
  String get dashboardFontHeading => 'Carattere';

  @override
  String get fontStandard => 'Predefinito';

  @override
  String get fontRounded => 'Arrotondato';

  @override
  String get fontSerif => 'Serif';

  @override
  String get fontReadable => 'Alta leggibilità';

  @override
  String get dashboardCustomiseColours => 'Personalizza colori';

  @override
  String get dashboardCustomiseColoursSubtitle =>
      'Modifica i cinque slot del tema - HEX o tavolozza';

  @override
  String get dashboardFontSizeHeading => 'Dimensione del display';

  @override
  String get dashboardLayoutHeading => 'Layout dashboard';

  @override
  String dashboardColumnCount(int count) {
    return '$count col';
  }

  @override
  String get dashboardRotateWithDevice => 'Ruota con il dispositivo';

  @override
  String get dashboardRotateWithDeviceSubtitle =>
      'Sblocca l\'orientamento orizzontale';

  @override
  String get dashboardAutoArrange => 'Disponi automaticamente per stato';

  @override
  String get dashboardAutoArrangeSubtitle =>
      'Ordina i riquadri per attività. Disattiva per trascinarli nel tuo ordine.';

  @override
  String get dashboardShowButtons => 'Mostra i pulsanti della dashboard';

  @override
  String get dashboardShowButtonsSubtitle =>
      'Mostra i pulsanti per aggiungere e riordinare in basso. Aggiungi stampanti dal menu quando sono nascosti.';

  @override
  String get dashboardReorderHint =>
      'Tieni premuto e trascina un riquadro per riordinare';

  @override
  String get dashboardReorderStart => 'Riordina';

  @override
  String get dashboardReorderDone => 'Fatto';

  @override
  String get dashboardCameraFeedHeading => 'Feed camera dashboard';

  @override
  String get dashboardCameraFeedSubtitle =>
      'Con quale frequenza i riquadri aggiornano la camera. Frequenze più basse usano molti meno dati.';

  @override
  String get cameraFeedsMenuTitle => 'Feed videocamera della dashboard';

  @override
  String get cameraFeedsMenuSubtitle => 'Frequenze feed locale e tunnel';

  @override
  String get cameraFeedsIntro =>
      'Con quale frequenza ogni riquadro aggiorna la videocamera. Moongate usa la frequenza Locale quando sei in Wi-Fi (anche fuori casa) e la frequenza Tunnel con i dati mobili, così mantieni un flusso veloce in Wi-Fi e più leggero in mobilità per risparmiare dati.';

  @override
  String get cameraFeedsLocalRate => 'Frequenza feed locale';

  @override
  String get cameraFeedsTunnelRate => 'Frequenza feed tunnel';

  @override
  String get dashboardAboutHeading => 'Informazioni';

  @override
  String get dashboardWhatsNew => 'Novità';

  @override
  String get dashboardWhatsNewSubtitle => 'Le modifiche recenti in breve';

  @override
  String get dashboardHowPairingWorks => 'Come funziona l\'abbinamento';

  @override
  String get dashboardHowPairingWorksSubtitle =>
      'Abbinamento, reinstallazione e ripristino';

  @override
  String get dashboardReportProblem => 'Segnala un problema';

  @override
  String get dashboardReportProblemSubtitle =>
      'Invia una segnalazione di bug o un feedback';

  @override
  String get dashboardAppLock => 'Blocco app';

  @override
  String get dashboardAppLockOn => 'Attivo - sblocco richiesto all\'avvio';

  @override
  String get dashboardAppLockOff => 'Disattivato';

  @override
  String get dashboardBuyMeCoffee => 'Offrimi un caffè';

  @override
  String get dashboardBuyMeCoffeeSubtitle =>
      'Lascia una mancia allo sviluppatore via PayPal';

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
  String get donationPromptTitle => 'Ti piace Moongate?';

  @override
  String get donationPromptBody =>
      'Moongate è un progetto personale gratuito che sviluppo nel tempo libero. Se ti è utile, una piccola mancia aiuta a portarlo avanti - senza pressioni, e non te lo chiederò più.';

  @override
  String get donationPromptLater => 'Forse più tardi';

  @override
  String get dashboardSettings => 'Impostazioni';

  @override
  String dashboardVersion(String version) {
    return 'Moongate v$version';
  }

  @override
  String get dashboardSaveBackupDialogTitle => 'Salva backup Moongate';

  @override
  String get dashboardBackupFailed =>
      'Backup non riuscito - impossibile salvare il file.';

  @override
  String dashboardBackupSuccess(int count) {
    return 'Backup di $count stampante/i eseguito. Questo file può ripristinarle su una nuova installazione - tienilo privato.';
  }

  @override
  String dashboardBackupSuccessListOnly(int count) {
    return 'Backup di $count stampante/i eseguito (solo elenco - impossibile raggiungere il cloud per un codice di ripristino).';
  }

  @override
  String get dashboardInvalidBackupFile =>
      'File di backup non valido - seleziona un file di configurazione Moongate.';

  @override
  String dashboardRestoreReconnected(int added, int count) {
    return '$added stampante/i ripristinata/e - $count riconnessa/e e in ritorno online.';
  }

  @override
  String dashboardRestoreNoneReconnected(int added) {
    return '$added stampante/i ripristinata/e, ma nessuna riconnessa - il codice di ripristino del backup non corrisponde ad alcuna stampante (potrebbe provenire da un backup più vecchio o essere già stato usato). Riabbinale per riportarle online.';
  }

  @override
  String dashboardRestoreListOnly(int added) {
    return '$added stampante/i ripristinata/e (solo elenco). Riabbina ogni stampante per riportarla online.';
  }

  @override
  String get dashboardRestoreApplied =>
      'Dashboard ripristinata in modo da corrispondere al backup.';

  @override
  String get dashboardRestoreReplaceTitle => 'Sostituire la dashboard?';

  @override
  String dashboardRestoreReplaceBody(String names) {
    return 'Queste stampanti sono in questa dashboard ma non nel backup: $names. Il ripristino le rimuoverà in modo che la dashboard corrisponda esattamente al backup. Restano associate: puoi riaggiungerle o ripristinarle in seguito.';
  }

  @override
  String get dashboardRestoreReplaceConfirm => 'Sostituisci';

  @override
  String get dashboardRemoveSheetTitle => 'Rimuovi una stampante';

  @override
  String dashboardPrinterIdShort(String id) {
    return 'id $id…';
  }

  @override
  String get dashboardPairingHelpPluginTitle =>
      'Prima: installa il plugin per Pi';

  @override
  String get dashboardPairingHelpPluginBody =>
      'Moongate richiede il suo plugin sulla stampante Klipper prima dell\'associazione. Se non l\'hai ancora installato, apri la guida rapida.';

  @override
  String get dashboardPairingHelpPluginAction => 'Apri la guida';

  @override
  String get dashboardPairingHelpPairOnceTitle => 'Abbina una sola volta';

  @override
  String get dashboardPairingHelpPairOnceBody =>
      'Scansiona il QR (o inserisci il codice GATE) per aggiungere una stampante - quel collegamento viene salvato in questa app.';

  @override
  String get dashboardPairingHelpUpdatesTitle =>
      'Gli aggiornamenti dell\'app mantengono le stampanti';

  @override
  String get dashboardPairingHelpUpdatesBody =>
      'Aggiornare Moongate non richiede mai un nuovo abbinamento.';

  @override
  String get dashboardPairingHelpReinstallTitle =>
      'Reinstallazione o nuovo telefono?';

  @override
  String get dashboardPairingHelpReinstallBody =>
      'Fai prima un backup (Menu → Backup configurazione), poi Ripristina riporta le stampanti online - senza riabbinamento.';

  @override
  String get dashboardPairingHelpNoBackupTitle => 'Nessun backup?';

  @override
  String get dashboardPairingHelpNoBackupBody =>
      'Esegui MOONGATE_RESET_OWNER nella console della stampante, poi abbina di nuovo.';

  @override
  String get dashboardDontShowAgain => 'Non mostrare più';

  @override
  String dashboardUpdateAvailable(String version) {
    return 'Aggiornamento disponibile - v$version';
  }

  @override
  String get dashboardUpdateLater => 'Più tardi';

  @override
  String get dashboardUpdate => 'Aggiorna';

  @override
  String get dashboardEmptyTitle => 'Nessuna stampante ancora aggiunta';

  @override
  String get dashboardEmptyBody =>
      'Tocca il pulsante qui sotto per abbinare la tua prima stampante.';

  @override
  String get pairingTitle => 'Aggiungi stampante';

  @override
  String get pairingIntro =>
      'Esegui MOONGATE_PAIR nella console Klipper - scansiona il QR o digita il codice GATE mostrato nella console.';

  @override
  String get pairingNameLabel => 'Nome stampante';

  @override
  String get pairingNameHint => 'es. Voron 2.4';

  @override
  String get pairingScanButton => 'Scansiona codice QR';

  @override
  String get pairingScanRecommended => 'Consigliato - si connette all\'istante';

  @override
  String get pairingOr => 'OPPURE';

  @override
  String get pairingGateCodeLabel => 'Codice GATE';

  @override
  String get pairingGateCodeHint =>
      'Digita il codice a 8 cifre mostrato nella tua console Klipper.';

  @override
  String get pairingGateCodeValid => 'Il codice sembra valido ✓';

  @override
  String get pairingGateCodeWarning =>
      'Metodo alternativo. Senza il QR, la stampante può impiegare fino a circa un minuto per connettersi - sta aspettando la connessione del tunnel sicuro. Scansiona il codice QR qui sopra per una connessione istantanea.';

  @override
  String get pairingCameraPermissionNeeded =>
      'Autorizzazione fotocamera necessaria';

  @override
  String get pairingCameraUnavailable => 'Fotocamera non disponibile';

  @override
  String get pairingCancelScan => 'Annulla scansione';

  @override
  String pairingQrScanned(String code) {
    return 'QR scansionato - codice $code';
  }

  @override
  String get pairingRescan => 'Scansiona di nuovo';

  @override
  String get pairingAdvancedTitle =>
      'Avanzate - stampante su una rete personalizzata?';

  @override
  String get pairingAdvancedBody =>
      'La maggior parte delle persone può lasciare vuoto questo campo. Se la tua stampante è dietro un reverse proxy (Traefik, Caddy, NPM) o in Docker, inserisci lo stesso indirizzo che usi per aprire la sua pagina web (Mainsail / Fluidd) nel browser.';

  @override
  String get pairingAddressLabel => 'Indirizzo stampante';

  @override
  String get pairingAddressHint => '192.168.1.50:7125';

  @override
  String get pairingPairButton => 'Abbina stampante';

  @override
  String get pairingRestoreHint =>
      'Stai reinstallando? Ripristina le stampanti salvate da un file di backup. Dovrai comunque riabbinare ognuna per riportarla online.';

  @override
  String get pairingImportButton => 'Importa configurazione da file';

  @override
  String get pairingReportButton =>
      'Problemi con l\'abbinamento? Invia una segnalazione';

  @override
  String get pairingCameraPermissionTitle =>
      'Autorizzazione fotocamera richiesta';

  @override
  String get pairingCameraPermissionBody =>
      'Moongate ha bisogno dell\'accesso alla fotocamera per scansionare i codici QR.\n\nApri Impostazioni → App → Moongate → Autorizzazioni e attiva la Fotocamera, poi torna e riprova.';

  @override
  String get pairingOpenSettings => 'Apri Impostazioni';

  @override
  String get pairingErrorNotMoongateQr =>
      'Non è un codice QR Moongate. Esegui MOONGATE_PAIR sulla stampante per generarne uno.';

  @override
  String get pairingErrorOldQr =>
      'Questo codice QR proviene da una versione precedente di Moongate. Aggiorna prima il Pi alla v0.3.0.';

  @override
  String get pairingErrorNoCode =>
      'Scansiona il codice QR o digita il codice GATE dalla console della stampante.';

  @override
  String get pairingErrorBadAddress =>
      'Quell\'indirizzo della stampante non sembra corretto - prova ad es. 192.168.1.50:7125';

  @override
  String pairingErrorFailed(String error) {
    return 'Abbinamento non riuscito: $error';
  }

  @override
  String get pairingImportInvalidFile =>
      'File di backup non valido - seleziona un file di configurazione Moongate.';

  @override
  String get pairingImportNoNewPrinters =>
      'Nessuna nuova stampante trovata in quel file.';

  @override
  String pairingImportRestoredReconnected(int count, int reconnected) {
    return '$count stampante/i ripristinata/e - $reconnected riconnessa/e, in ritorno online.';
  }

  @override
  String pairingImportRestoredRepair(int count) {
    return '$count stampante/i ripristinata/e - riabbina ogni Pi per riportarlo online.';
  }

  @override
  String get customThemeTitle => 'Tema personalizzato';

  @override
  String get customThemeResetTooltip => 'Ripristina valori predefiniti';

  @override
  String get customThemeResetConfirmTitle =>
      'Ripristinare il tema personalizzato?';

  @override
  String get customThemeResetConfirmBody =>
      'Tutti e cinque gli slot dei colori verranno riportati alla tavolozza predefinita viola su sfondo scuro.';

  @override
  String get customThemeReset => 'Ripristina';

  @override
  String get customThemePreview => 'Anteprima';

  @override
  String get customThemeAccent => 'Colore principale';

  @override
  String get customThemeAccentDesc =>
      'Pulsanti, FAB, barre di avanzamento, link';

  @override
  String get customThemeBackground => 'Sfondo pagina';

  @override
  String get customThemeBackgroundDesc => 'Dietro ogni schermata';

  @override
  String get customThemeSurface => 'Schede e riquadri';

  @override
  String get customThemeSurfaceDesc =>
      'Riquadri dashboard, fogli, menu laterale';

  @override
  String get customThemeText => 'Testo';

  @override
  String get customThemeTextDesc =>
      'Testo del corpo e dei titoli sulle superfici';

  @override
  String get customThemeError => 'Errore / Stop';

  @override
  String get customThemeErrorDesc => 'Azioni distruttive, overlay di errore';

  @override
  String get customThemeEstop => 'Pulsante di arresto di emergenza';

  @override
  String get customThemeEstopDesc =>
      'Anello e icona dell\'arresto di emergenza';

  @override
  String get customThemePresets => 'Preimpostazioni';

  @override
  String get customThemeInvalidHex => 'Non è un colore esadecimale valido';

  @override
  String get customThemeSamplePrinter => 'Stampante di esempio';

  @override
  String get customThemePrinting => 'In stampa';

  @override
  String get tilePauseFailed =>
      'Impossibile raggiungere la stampante - pausa non riuscita';

  @override
  String get tileResumeFailed =>
      'Impossibile raggiungere la stampante - ripresa non riuscita';

  @override
  String get tileStopAgainToCancel =>
      'Premi di nuovo STOP per annullare la stampa';

  @override
  String get tileLocal => 'Locale';

  @override
  String get tileTunnel => 'Tunnel';

  @override
  String get tilePrinting => 'In stampa';

  @override
  String get tilePaused => 'In pausa';

  @override
  String get tileResume => 'Riprendi';

  @override
  String get tilePause => 'Pausa';

  @override
  String get tileConfirmStop => 'Conferma stop';

  @override
  String get tileStopPrint => 'Ferma stampa';

  @override
  String get tileFirmwareRestart => 'Riavvio firmware';

  @override
  String get tileEmergencyStop => 'Arresto di emergenza · doppio tocco';

  @override
  String get tileEmergencyStopFailed =>
      'Impossibile raggiungere la stampante - arresto di emergenza non riuscito';

  @override
  String get tilePrintComplete => 'Stampa completata';

  @override
  String get tilePrintCancelled => 'Stampa annullata';

  @override
  String get tilePrinterError => 'Errore stampante';

  @override
  String get tileKlipperStarting => 'Avvio di Klipper';

  @override
  String get tileReady => 'Pronta';

  @override
  String get tileOffline => 'Offline';

  @override
  String get tileStartingUp => 'Avvio in corso…';

  @override
  String get tileConnected => 'Connessa';

  @override
  String get tileConnecting => 'Connessione…';

  @override
  String get tilePrinterUnreachable => 'Stampante irraggiungibile';

  @override
  String get tileWaitingForHeartbeat => 'In attesa del primo heartbeat';

  @override
  String get tilePrinterIdle => 'Stampante inattiva';

  @override
  String get tileReachingPrinter => 'Contatto con la stampante';

  @override
  String get tileRemoteReady => 'Accesso remoto pronto';

  @override
  String get tileRemoteConnecting => 'Connessione remota…';

  @override
  String get tileIdle => 'Inattiva';

  @override
  String get tileDone => 'Fatto';

  @override
  String get tileCancelled => 'Annullata';

  @override
  String get tileClearJobTooltip => 'Cancella e imposta su inattiva';

  @override
  String get tileClearJobFailed => 'Impossibile reimpostare la stampante';

  @override
  String get dashboardBackgroundTitle => 'Sfondo della dashboard';

  @override
  String get dashboardBackgroundNone => 'Nessuno - colore del tema';

  @override
  String get dashboardBackgroundCustom => 'Immagine personalizzata';

  @override
  String get dashboardBackgroundRemove => 'Rimuovi sfondo';

  @override
  String get dashboardBackgroundSet => 'Sfondo aggiornato';

  @override
  String get uiGuideSectionTileButtons => 'Pulsanti della scheda';

  @override
  String get uiGuideFilesTitle => 'Stampa un file';

  @override
  String get uiGuideFilesDesc =>
      'Sfoglia i file G-code salvati sulla stampante e avviane uno.';

  @override
  String get uiGuideMacrosTitle => 'Macro';

  @override
  String get uiGuideMacrosDesc =>
      'Esegui una delle macro Klipper della stampante.';

  @override
  String get uiGuidePowerTitle => 'Alimentazione';

  @override
  String get uiGuidePowerDesc =>
      'Accendi o spegni la stampante, quando ha un dispositivo di alimentazione.';

  @override
  String get uiGuideLightingTitle => 'Illuminazione';

  @override
  String get uiGuideLightingDesc =>
      'Attiva/disattiva la luce della stampante; la lampadina si illumina quando è accesa.';

  @override
  String get uiGuideCameraViewTitle => 'Fotocamera';

  @override
  String get uiGuideCameraViewDesc =>
      'Apri la fotocamera dal vivo a schermo intero.';

  @override
  String get uiGuideCameraSetupTitle => 'Configurazione fotocamera';

  @override
  String get uiGuideCameraSetupDesc =>
      'Punta una scheda verso una fotocamera non collegata a Klipper.';

  @override
  String get uiGuideClearJobTitle => 'Cancella una stampa terminata';

  @override
  String get uiGuideClearJobDesc =>
      'Tocca la × su una scheda Fatto o Annullata per riportarla su inattiva.';

  @override
  String get tileError => 'Errore';

  @override
  String get tileStarting => 'Avvio';

  @override
  String get tileConnectingBadge => 'Connessione';

  @override
  String get appLockTitle => 'Blocco app';

  @override
  String get appLockIntro =>
      'Richiede un PIN - e facoltativamente l\'impronta digitale o il volto - prima che Moongate si apra. Il blocco compare sempre quando l\'app viene avviata da zero.';

  @override
  String get appLockSubtitle => 'PIN richiesto per aprire l\'app';

  @override
  String get appLockBiometricTitle => 'Sblocco biometrico';

  @override
  String get appLockBiometricSubtitle =>
      'Usa impronta digitale o volto - il PIN resta come riserva';

  @override
  String get appLockChangePin => 'Cambia PIN';

  @override
  String get appLockAutoLock => 'Blocco automatico';

  @override
  String get appLockPinUpdated => 'PIN aggiornato';

  @override
  String get appLockChoosePinTitle => 'Scegli un PIN';

  @override
  String get appLockChoosePinSubtitle => 'Inserisci 4-6 cifre';

  @override
  String get appLockConfirmPinTitle => 'Conferma PIN';

  @override
  String get appLockPinsDontMatch => 'I PIN non corrispondono';

  @override
  String get appLockEnterCurrentPin => 'Inserisci il PIN attuale';

  @override
  String get appLockTimeoutImmediately => 'Immediatamente';

  @override
  String get appLockTimeoutOneMinute => 'Dopo 1 minuto';

  @override
  String get appLockTimeoutFiveMinutes => 'Dopo 5 minuti';

  @override
  String get appLockTimeoutFifteenMinutes => 'Dopo 15 minuti';

  @override
  String get appLockTimeoutColdLaunch => 'Solo all\'avvio dell\'app';

  @override
  String get lockEnterPin => 'Inserisci il tuo PIN';

  @override
  String get lockSubtitle => 'Moongate è bloccata';

  @override
  String lockTooManyAttempts(int seconds) {
    return 'Troppi tentativi. Riprova tra $seconds s';
  }

  @override
  String get lockWrongPin => 'PIN errato';

  @override
  String get lockUseBiometrics => 'Usa la biometria';

  @override
  String get lockForgotPin => 'PIN dimenticato?';

  @override
  String get lockBiometricReason => 'Sblocca Moongate';

  @override
  String get lockResetTitle => 'Reimpostare Moongate?';

  @override
  String get lockResetBody =>
      'Questo rimuove il blocco app e cancella le stampanti abbinate da questo dispositivo per ricominciare da capo. Le tue stampanti non vengono eliminate - riabbinale eseguendo MOONGATE_PAIR su ciascuna.';

  @override
  String get lockResetConfirm => 'Reimposta';

  @override
  String get pinContinue => 'Continua';

  @override
  String printerStartingUpRetry(int seconds) {
    return 'La stampante si sta avviando. Nuovo tentativo tra $seconds s…';
  }

  @override
  String printerCouldNotReach(String error) {
    return 'Impossibile raggiungere la stampante: $error';
  }

  @override
  String get printerAddressCleared => 'Indirizzo personalizzato cancellato';

  @override
  String get printerAddressUpdated => 'Indirizzo stampante aggiornato';

  @override
  String printerTunnelUnreachable(String description) {
    return 'Tunnel Cloudflare irraggiungibile.\n$description';
  }

  @override
  String get printerEdit => 'Modifica stampante';

  @override
  String get printerLocalNetwork => 'Rete locale';

  @override
  String get printerTunnelVia => 'Tunnel tramite Moongate';

  @override
  String get printerCameraTooltip => 'Telecamera';

  @override
  String get cameraConnecting => 'Connessione alla telecamera…';

  @override
  String get cameraNoCamera =>
      'Nessuna telecamera configurata per questa stampante.';

  @override
  String get cameraHintBody =>
      'La webcam non si carica qui da remoto - apri la telecamera Moongate.';

  @override
  String get cameraHintOpen => 'Apri';

  @override
  String get printerUnreachable => 'Stampante irraggiungibile';

  @override
  String get printerUseTunnel => 'Usa il tunnel';

  @override
  String get printerAddressInvalid => 'Prova ad es. 192.168.1.50:7125';

  @override
  String get printerNameLabel => 'Nome stampante';

  @override
  String get printerAddressLabel => 'Indirizzo stampante (avanzato)';

  @override
  String get printerAddressHint => '192.168.1.50:7125';

  @override
  String get printerAddressHelper =>
      'Solo per configurazioni con reverse proxy / Docker. Lascia vuoto per usare il rilevamento automatico.';

  @override
  String get feedbackTitle => 'Segnala un problema';

  @override
  String get feedbackTroublePairing => 'Problemi con l\'abbinamento?';

  @override
  String get feedbackDescription =>
      'Raccontaci cosa sta succedendo. La versione dell\'app, il dispositivo, la rete e i dettagli della stampante vengono allegati automaticamente per aiutarci a individuare il problema.';

  @override
  String get feedbackPairingDescription =>
      'Descrivi cosa succede quando provi ad aggiungere la stampante. I dettagli di rete e rilevamento vengono allegati automaticamente così possiamo capire perché non si connette.';

  @override
  String get feedbackWhichPrinter => 'Quale stampante? (facoltativo)';

  @override
  String get feedbackGeneralOption =>
      'Generale / non specifico di una stampante';

  @override
  String get feedbackCommentLabel => 'Cosa è andato storto?';

  @override
  String get feedbackCommentHint =>
      'es. \"La stampante mostra Connessa / inattiva ma in realtà è pronta - si apre correttamente quando tocco il riquadro.\"';

  @override
  String get feedbackContactLabel => 'Email o contatto (facoltativo)';

  @override
  String get feedbackContactHint => 'Solo se desideri una risposta';

  @override
  String get feedbackSending => 'Invio in corso…';

  @override
  String get feedbackSend => 'Invia segnalazione';

  @override
  String get feedbackSuccess => 'Grazie - la tua segnalazione è stata inviata.';

  @override
  String get feedbackError =>
      'Invio non riuscito - controlla la connessione e riprova.';

  @override
  String get splashTagline => 'Controllo remoto Klipper';

  @override
  String get uiGuideTitle => 'Guida alle icone';

  @override
  String get uiGuideMenuSubtitle => 'Cosa significano le icone della dashboard';

  @override
  String get uiGuideIntro =>
      'Una guida rapida alle icone che vedrai nella dashboard.';

  @override
  String get uiGuideSectionConnection => 'Connessione';

  @override
  String get uiGuideSectionTemperatures => 'Temperature';

  @override
  String get uiGuideSectionControls => 'Controlli di stampa';

  @override
  String get uiGuideSectionStatus => 'Stato';

  @override
  String get uiGuideSectionWebcam => 'Camera e connessione';

  @override
  String get uiGuideLocalTitle => 'Rete locale';

  @override
  String get uiGuideLocalDesc =>
      'Connessa direttamente tramite il tuo Wi-Fi - il percorso più veloce.';

  @override
  String get uiGuideTunnelTitle => 'Remoto (tunnel)';

  @override
  String get uiGuideTunnelDesc =>
      'Connessa da qualsiasi luogo tramite il tunnel sicuro Cloudflare.';

  @override
  String get uiGuideTunnelReadyTitle => 'Remoto pronto';

  @override
  String get uiGuideTunnelReadyDesc =>
      'Il tunnel è attivo, quindi l\'accesso remoto è disponibile.';

  @override
  String get uiGuideTunnelConnectingTitle => 'Connessione remota';

  @override
  String get uiGuideTunnelConnectingDesc =>
      'Il tunnel remoto si sta ancora stabilendo.';

  @override
  String get uiGuideHotendTitle => 'Hotend / ugello';

  @override
  String get uiGuideHotendDesc => 'Temperatura attuale dell\'ugello.';

  @override
  String get uiGuideBedTitle => 'Piano riscaldato';

  @override
  String get uiGuideBedDesc => 'Temperatura attuale del piano.';

  @override
  String get uiGuideChamberTitle => 'Camera';

  @override
  String get uiGuideChamberDesc =>
      'Temperatura della camera - mostrata solo se la tua stampante ne riporta una.';

  @override
  String get uiGuideResumeTitle => 'Riprendi';

  @override
  String get uiGuideResumeDesc => 'Riprende una stampa in pausa.';

  @override
  String get uiGuidePauseTitle => 'Pausa';

  @override
  String get uiGuidePauseDesc => 'Mette in pausa la stampa corrente.';

  @override
  String get uiGuideStopTitle => 'Stop';

  @override
  String get uiGuideStopDesc =>
      'Annulla la stampa - tocca due volte per confermare.';

  @override
  String get uiGuideEstopTitle => 'Arresto di emergenza';

  @override
  String get uiGuideEstopDesc =>
      'Tocca due volte il triangolo rosso per fermare subito la stampante (Klipper M112).';

  @override
  String get uiGuideFirmwareRestartTitle => 'Riavvio firmware';

  @override
  String get uiGuideFirmwareRestartDesc =>
      'Riavvia Klipper quando la stampante è inattiva o in errore.';

  @override
  String get uiGuideStatusReadyTitle => 'Pronta / completata';

  @override
  String get uiGuideStatusReadyDesc =>
      'La stampante è inattiva o ha terminato l\'ultima stampa.';

  @override
  String get uiGuideStatusCancelledTitle => 'Annullata';

  @override
  String get uiGuideStatusCancelledDesc =>
      'L\'ultima stampa è stata annullata.';

  @override
  String get uiGuideStatusErrorTitle => 'Errore';

  @override
  String get uiGuideStatusErrorDesc =>
      'Klipper ha segnalato un errore - apri la stampante per i dettagli.';

  @override
  String get uiGuideStatusStartingTitle => 'Avvio in corso';

  @override
  String get uiGuideStatusStartingDesc =>
      'Klipper si sta avviando; i controlli compaiono quando è pronta.';

  @override
  String get uiGuideOfflineTitle => 'Offline';

  @override
  String get uiGuideOfflineDesc =>
      'La stampante non può essere raggiunta in questo momento.';

  @override
  String get uiGuideNoWebcamTitle => 'Nessuna camera';

  @override
  String get uiGuideNoWebcamDesc =>
      'Nessuna istantanea della webcam è disponibile per questa stampante.';

  @override
  String get uiGuideBack => 'Torna alla dashboard';

  @override
  String get printNotifTitle => 'Notifiche di stampa';

  @override
  String get printNotifSubtitle =>
      'Avanzamento e stato in tempo reale mentre l\'app è in background';

  @override
  String get printNotifPermissionNeeded =>
      'Consenti le notifiche per attivarlo.';

  @override
  String get printNotifPromptTitle => 'Ricevere le notifiche di stampa?';

  @override
  String get printNotifPromptBody =>
      'Vedi lo stato in tempo reale delle tue stampanti - avanzamento, temperature e avvisi quando una stampa inizia, finisce o va in errore. Puoi cambiarlo in qualsiasi momento dal menu.';

  @override
  String get printNotifPromptEnable => 'Attiva';

  @override
  String get printNotifPromptNotNow => 'Non ora';

  @override
  String get printNotifWatching => 'Monitoraggio delle stampanti…';

  @override
  String get printNotifNoPrinters => 'Nessuna stampante';

  @override
  String get printNotifNoneOnline => 'Nessuna stampante online';

  @override
  String get notifOnlineOnlyTitle => 'Mostra solo dispositivi online';

  @override
  String get notifOnlineOnlySubtitle =>
      'Nascondi le macchine offline dalla notifica di stato';

  @override
  String get notifPollIntervalTitle => 'Frequenza di aggiornamento';

  @override
  String get notifContentTitle => 'Contenuto della notifica';

  @override
  String get notifContentSubtitle => 'Scegli e riordina cosa mostrare';

  @override
  String get notifContentIntro =>
      'Scegli quali dettagli appaiono sulla scheda di notifica di ogni stampa e trascinali nell\'ordine che preferisci.';

  @override
  String get notifContentPreview => 'Anteprima';

  @override
  String get notifFieldProgress => 'Avanzamento';

  @override
  String get notifFieldRemaining => 'Tempo rimanente';

  @override
  String get notifFieldEta => 'Ora di fine';

  @override
  String get notifFieldHotend => 'Temp. ugello';

  @override
  String get notifFieldBed => 'Temp. piatto';

  @override
  String get printAlertReady => 'Stampante pronta';

  @override
  String get printStatusReady => 'Pronta';

  @override
  String get printStatusHeating => 'In riscaldamento';

  @override
  String get printStatusIdle => 'Inattiva';

  @override
  String get printStatusOffline => 'Offline';

  @override
  String get printStatusPaused => 'In pausa';

  @override
  String get printStatusComplete => 'Completata';

  @override
  String get printStatusCancelled => 'Annullata';

  @override
  String get printStatusError => 'Errore';

  @override
  String get printStatusStartingUp => 'Avvio…';

  @override
  String get printStatusPrinting => 'In stampa';

  @override
  String get printNotifStarted => 'Stampa avviata';

  @override
  String get printNotifFinished => 'Completato';

  @override
  String get notifClearAction => 'Cancella';

  @override
  String get printAlertStarted => 'Stampa avviata';

  @override
  String get printAlertResumed => 'Stampa ripresa';

  @override
  String get printAlertPaused => 'Stampa in pausa';

  @override
  String get printAlertComplete => 'Stampa completata';

  @override
  String get printAlertCancelled => 'Stampa annullata';

  @override
  String get printAlertError => 'Errore stampante';

  @override
  String get tileOpenFiles => 'Stampa un file';

  @override
  String get gcodeSheetTitle => 'Avvia una stampa';

  @override
  String get gcodeLoading => 'Caricamento file…';

  @override
  String get gcodeEmpty => 'Nessun file G-code su questa stampante';

  @override
  String get gcodeError => 'Impossibile caricare i file';

  @override
  String get gcodeStartButton => 'Avvia stampa';

  @override
  String get gcodeStartAction => 'Avvia';

  @override
  String get gcodeConfirmTitle => 'Avviare la stampa?';

  @override
  String gcodeConfirmBody(String file) {
    return 'Stampare $file?';
  }

  @override
  String gcodeStarted(String file) {
    return 'Stampa di $file avviata';
  }

  @override
  String get gcodeStartFailed => 'Impossibile avviare la stampa';

  @override
  String get tileMacros => 'Macro';

  @override
  String get macrosSheetTitle => 'Macro';

  @override
  String get macrosLoading => 'Caricamento macro…';

  @override
  String get macrosError => 'Impossibile caricare le macro';

  @override
  String get macrosEmpty => 'Nessuna macro su questa stampante';

  @override
  String get macroFavourite => 'Fissa in alto';

  @override
  String get macroUnfavourite => 'Rimuovi dall\'alto';

  @override
  String get macroConfirmTitle => 'Eseguire la macro?';

  @override
  String macroConfirmBody(String macro) {
    return 'Eseguire $macro su questa stampante?';
  }

  @override
  String get macroRunAction => 'Esegui';

  @override
  String macroSent(String macro) {
    return '$macro inviata';
  }

  @override
  String macroFailed(String macro) {
    return 'Impossibile inviare $macro';
  }

  @override
  String get preheatTitle => 'Preriscalda';

  @override
  String get preheatHotend => 'Hotend';

  @override
  String get preheatBed => 'Piano';

  @override
  String get preheatHint =>
      'Lascia vuoto un campo per non modificare quel riscaldatore.';

  @override
  String get preheatSoakLabel => 'Timer di riscaldamento';

  @override
  String get preheatSoakHelp =>
      'Avvisami dopo questi minuti. 0 = nessun timer.';

  @override
  String get preheatMinutes => 'min';

  @override
  String get preheatSet => 'Imposta';

  @override
  String get preheatNotifWarning =>
      'Gli avvisi di riscaldamento richiedono le notifiche di stampa attive.';

  @override
  String get preheatNotifEnable => 'Attiva';

  @override
  String preheatSetConfirm(String summary) {
    return '$summary impostato';
  }

  @override
  String preheatSoakIn(int minutes) {
    return 'avviso di riscaldamento tra $minutes min';
  }

  @override
  String get preheatFailed => 'Impossibile impostare le temperature';

  @override
  String get heatsoakDoneTitle => 'Riscaldamento completato';

  @override
  String heatsoakDoneBody(String printer) {
    return '$printer è in temperatura';
  }

  @override
  String get tutorialOfferTitle => 'Vuoi fare un breve tour?';

  @override
  String get tutorialOfferBody =>
      'Ti va una rapida panoramica su come funziona Moongate?';

  @override
  String get tutorialOfferDontRemind => 'Non ricordarmelo più';

  @override
  String get tutorialOfferNo => 'No, grazie';

  @override
  String get tutorialOfferStart => 'Avvia il tutorial';

  @override
  String get tutorialMenuTitle => 'Tutorial dell\'app';

  @override
  String get tutorialNext => 'Avanti';

  @override
  String get tutorialDone => 'Fatto';

  @override
  String get tutorialSkip => 'Termina';

  @override
  String get tutorialBack => 'Indietro';

  @override
  String get tutorialLocalBar =>
      'La barra colorata mostra come Moongate sta raggiungendo questa stampante. Verde con l\'icona Wi-Fi significa che sei sulla stessa rete, una connessione locale veloce e diretta.';

  @override
  String get tutorialTunnelBar =>
      'Arancione con l\'icona della nuvola significa che sei fuori casa, connesso in modo sicuro tramite internet attraverso il tunnel della tua stampante. Moongate passa automaticamente dall\'una all\'altra.';

  @override
  String get tutorialRemoteBuilding =>
      'Quando abbini una stampante per la prima volta, l\'accesso remoto non è immediato. Questo piccolo simbolo della nuvola indica che il tunnel sicuro si sta ancora creando in background. Quando diventa una nuvola verde con la spunta, potrai raggiungere questa stampante da qualsiasi luogo.';

  @override
  String get tutorialHotend =>
      'Questo è il tuo hotend, la temperatura dell\'ugello.';

  @override
  String get tutorialBed => 'E questo è il piano riscaldato.';

  @override
  String get tutorialChamber =>
      'Se la tua stampante ha un sensore della camera, qui appare anche la sua temperatura.';

  @override
  String get tutorialTemps =>
      'Queste sono le temperature in tempo reale: l\'hotend (l\'ugello), il piano riscaldato e, se la tua stampante ha un sensore della camera, la camera.';

  @override
  String get tutorialEstop =>
      'Questo è l\'arresto di emergenza. Richiede un doppio tocco per attivarsi, così non può essere azionato per sbaglio, e ferma immediatamente la stampante.';

  @override
  String get tutorialWebcam =>
      'Toccando la vista della telecamera si apre l\'interfaccia completa della stampante, la schermata Klipper dal vivo.';

  @override
  String get tutorialPreheatPress =>
      'Tieni premuto il nome di una stampante o le sue temperature per mostrare il pannello di preriscaldamento.';

  @override
  String get tutorialPreheatSheet =>
      'Qui puoi impostare le temperature target di hotend e piano e un tempo di riscaldamento facoltativo.';

  @override
  String get tutorialAddPrinter =>
      'Tocca il pulsante più in qualsiasi momento per aggiungere e abbinare un\'altra stampante.';

  @override
  String get tutorialMenuIcon =>
      'Questo è il menu. Puoi aprirlo da qui in qualsiasi momento.';

  @override
  String get tutorialMenuPrinters =>
      'Aggiungi un\'altra stampante o rimuovine una che non usi più.';

  @override
  String get tutorialMenuBackup =>
      'Esegui il backup della tua configurazione su un file o ripristinala su un altro dispositivo.';

  @override
  String get tutorialMenuTheme =>
      'Scegli un tema di colori chiaro, scuro o completamente personalizzato.';

  @override
  String get tutorialMenuDisplaySize =>
      'Trascina questo per rendere tutto più grande o più piccolo, secondo i tuoi occhi.';

  @override
  String get tutorialMenuColumns =>
      'Disponi le tue stampanti su una, due o tre colonne.';

  @override
  String get tutorialMenuCameras =>
      'Imposta con quale frequenza si aggiornano i feed delle webcam e attiva o disattiva la telecamera di ogni stampante.';

  @override
  String get tutorialMenuAbout =>
      'Le novità, come funziona l\'abbinamento, una guida alle icone e dove segnalare un problema sono tutti qui.';

  @override
  String get tutorialMenuSupport =>
      'Offrirmi un caffè aiuta a mantenere Moongate gratuito per tutti e open source.';

  @override
  String get tutorialMenuSettings =>
      'Le impostazioni hanno due opzioni al loro interno: cancella tutte le tue stampanti, oppure elimina tutti i tuoi dati e ricomincia completamente da capo.';

  @override
  String get tutorialMenuLanguage =>
      'E qui puoi cambiare la lingua dell\'app - Moongate ne parla otto. Questo è il tour, buon divertimento!';

  @override
  String get notifPauseTooltip => 'Sospendi monitoraggio';

  @override
  String get notifResumeTooltip => 'Riprendi monitoraggio';

  @override
  String get notifPausedSnack => 'Monitoraggio di stampa sospeso';

  @override
  String get notifResumedSnack => 'Monitoraggio di stampa ripreso';

  @override
  String get tutorialPauseButton =>
      'Questo sospende il monitoraggio di stampa. Quando le tue stampanti resteranno spente per un po\', toccalo per interrompere i controlli in background e risparmiare batteria, poi tocca di nuovo per riprendere.';
}
