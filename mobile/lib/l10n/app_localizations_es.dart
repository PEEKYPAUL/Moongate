// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get updateDownloading => 'Descargando actualización…';

  @override
  String get updateOpeningInstaller => 'Abriendo el instalador…';

  @override
  String get updateFailed =>
      'No se pudo completar la actualización automáticamente.';

  @override
  String get updateOpenInBrowser => 'Abrir en el navegador';

  @override
  String get lightingTitle => 'Iluminación';

  @override
  String get lightingMenuSubtitle =>
      'Controla la luz de tus impresoras desde el panel';

  @override
  String get lightingBanner =>
      'Elige qué impresoras tienen una luz que puedes controlar. Para cada una, actívala y define una pareja de macros Encender + Apagar, o una sola macro de Alternar. Opcionalmente elige una fuente de estado para que la bombilla muestre el estado real.';

  @override
  String get lightingNoPrinters => 'Aún no hay impresoras para configurar.';

  @override
  String get lightingShowOnTile => 'Mostrar en la tarjeta';

  @override
  String get lightingNeedMacro =>
      'Define una pareja Encender + Apagar o una macro de Alternar para activar.';

  @override
  String get lightingLoadFailed =>
      'No se pudieron cargar las macros de esta impresora (puede estar desconectada). Escribe los nombres manualmente abajo.';

  @override
  String get lightingOnMacro => 'Macro de luz ENCENDIDA';

  @override
  String get lightingOffMacro => 'Macro de luz APAGADA';

  @override
  String get lightingToggleMacro => 'Macro de alternar';

  @override
  String get lightingToggleSection => 'Opcional: método de alternar';

  @override
  String get lightingStatusSource => 'Fuente de estado de la luz';

  @override
  String get lightingStatusSourceHelp =>
      'Opcional. Un objeto de Klipper (p. ej. output_pin caselight) cuyo valor le indica a Moongate si la luz está encendida. Déjalo vacío para seguir tus toques en su lugar.';

  @override
  String get lightingStatusHint => 'Ejemplo: output_pin caselight';

  @override
  String get lightingNotSet => 'Sin definir';

  @override
  String get lightingPickMacro => 'Seleccionar una macro';

  @override
  String get lightingPickStatusSource => 'Seleccionar una fuente de estado';

  @override
  String get lightingManualHint => 'Escribe el nombre exacto';

  @override
  String get lightingClear => 'Borrar';

  @override
  String get lightTurnOn => 'Encender la luz';

  @override
  String get lightTurnOff => 'Apagar la luz';

  @override
  String get lightToggleFailed => 'No se pudo conectar con la impresora';

  @override
  String get powerTurnOn => 'Encender';

  @override
  String get powerTurnOff => 'Apagar';

  @override
  String powerConfirmOn(String name) {
    return '¿Encender $name?';
  }

  @override
  String powerConfirmOff(String name) {
    return '¿Apagar $name?';
  }

  @override
  String get powerToggleFailed => 'No se pudo cambiar la alimentación';

  @override
  String get powerLockedWhilePrinting => 'No se puede apagar mientras imprime';

  @override
  String get globalPowerButtonTitle => 'Botón de alimentación global';

  @override
  String get globalPowerButtonSubtitle =>
      'Un botón en la barra superior para encender o apagar toda tu flota';

  @override
  String get globalPowerTooltip => 'Alimentar todas las impresoras';

  @override
  String get globalPowerSheetTitle => 'Alimentar todas las impresoras';

  @override
  String get globalPowerOnAll => 'Encender todas';

  @override
  String get globalPowerSlideOff => 'desliza para apagar todas';

  @override
  String get globalPowerConfirmOnTitle => '¿Encender todas las impresoras?';

  @override
  String get globalPowerConfirmOnBody =>
      'Esto enciende todas las máquinas que podemos alcanzar.';

  @override
  String get globalPowerPrintingNote =>
      'Las impresoras que están imprimiendo se dejan encendidas';

  @override
  String get globalPowerStateWillSwitchOff => 'se apagará';

  @override
  String get globalPowerStateKeptPrinting => 'imprimiendo, se deja encendida';

  @override
  String get globalPowerStateOffline => 'sin conexión, omitida';

  @override
  String get globalPowerStateOnOff => 'encender / apagar';

  @override
  String get globalPowerStateOffOnly => 'solo apagar';

  @override
  String get globalPowerStateOnOnly => 'solo encender';

  @override
  String get globalPowerStateToggleOnly => 'solo alternar';

  @override
  String get globalPowerNothing =>
      'Aún no hay ninguna máquina con control de alimentación configurado';

  @override
  String globalPowerResultOn(int count, int total) {
    return 'Se encendieron $count de $total impresoras';
  }

  @override
  String globalPowerResultOff(int count, int total) {
    return 'Se apagaron $count de $total impresoras';
  }

  @override
  String get powerScreenTitle => 'Interruptor de alimentación avanzado';

  @override
  String get powerScreenBanner =>
      'Para impresoras cuya alimentación es una macro de Klipper en lugar de un dispositivo de alimentación de Moonraker. Actívalo y define una macro de Apagado (el caso habitual), una macro de Encendido, ambas, o una sola de alternancia. El botón de encendido de la tarjeta usa cualquiera de ellas.';

  @override
  String get powerUseSwitch => 'Usar macros';

  @override
  String get powerNeedMacro =>
      'Define al menos una macro: una de Apagado (o Encendido), o una de alternancia.';

  @override
  String get powerOnMacro => 'Macro de encendido';

  @override
  String get powerOffMacro => 'Macro de apagado';

  @override
  String get powerToggleSection => 'O una sola macro de alternancia';

  @override
  String get powerToggleMacro => 'Macro de alternancia';

  @override
  String get powerToggleBulkNote =>
      'Una macro de alternancia acciona el botón de encendido de la tarjeta. Para Alimentar todas las impresoras, define una macro de Encendido o de Apagado.';

  @override
  String get powerMenuTitle => 'Interruptor de alimentación avanzado';

  @override
  String get powerMenuSubtitle =>
      'Controlar la alimentación de la impresora con una macro';

  @override
  String get powerMacroTooltip => 'Alimentación';

  @override
  String powerMacroToggleConfirm(String name) {
    return '¿Cambiar la alimentación de $name?';
  }

  @override
  String powerMacroChooseTitle(String name) {
    return 'Cambiar la alimentación de $name';
  }

  @override
  String lightChooseTitle(String name) {
    return 'Cambiar la luz de $name';
  }

  @override
  String get tileOpacityTitle => 'Opacidad de las tarjetas';

  @override
  String get tileOpacityDesc =>
      'Cuán transparentes son las tarjetas (0-100), para que se vea un fondo. La cámara permanece opaca.';

  @override
  String get dashboardShowWebcams => 'Cámaras';

  @override
  String get dashboardShowWebcamsSubtitle =>
      'Mostrar u ocultar la cámara de cada impresora';

  @override
  String get updateNotesUnavailable =>
      'No se pudieron cargar las novedades: revisa tu conexión o consúltalas en GitHub.';

  @override
  String get updateViewOnGithub => 'Ver en GitHub';

  @override
  String get cameraConfigTooltip => 'Definir URL de la cámara';

  @override
  String get cameraConfigTitle => 'Cámara personalizada';

  @override
  String get cameraConfigDescription =>
      'Muestra una cámara que no está conectada a Klipper, como un teléfono antiguo usado como webcam. Introduce la dirección que aparece en los ajustes de webcam de Mainsail.';

  @override
  String get cameraConfigUrlLabel => 'URL de la cámara';

  @override
  String get cameraConfigRemoteNote =>
      'Funciona por Wi-Fi y de forma remota a través de tu impresora. De forma remota solo se pueden ver cámaras de tu red doméstica (direcciones privadas).';

  @override
  String get cameraConfigInvalid =>
      'Introduce una dirección completa, p. ej. http://192.168.0.107:8080/video';

  @override
  String get cameraConfigUseDefault => 'Usar cámara de Klipper';

  @override
  String get cameraConfigApply => 'Aplicar';

  @override
  String get dashboardShowCameraIcons => 'Iconos de config. de cámara';

  @override
  String get dashboardShowCameraIconsSubtitle =>
      'Mostrar el engranaje en cada cámara para definir una URL personalizada';

  @override
  String get appTitle => 'Moongate';

  @override
  String get languagePickerTitle => 'Elige tu idioma';

  @override
  String get languagePickerSubtitle =>
      'Puedes cambiarlo en cualquier momento desde el menú.';

  @override
  String get languagePickerContinue => 'Continuar';

  @override
  String get menuLanguage => 'Idioma';

  @override
  String get languageSystemDefault => 'Predeterminado del sistema';

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonOk => 'Aceptar';

  @override
  String get commonClose => 'Cerrar';

  @override
  String get commonSave => 'Guardar';

  @override
  String get commonDone => 'Listo';

  @override
  String get commonRetry => 'Reintentar';

  @override
  String get commonShowKeyboard => 'Mostrar teclado';

  @override
  String get dashboardSignInRetrying =>
      'Reconectando con la nube: el inicio de sesión está ocupado, reintentando. Tus impresoras volverán automáticamente.';

  @override
  String get commonRemove => 'Quitar';

  @override
  String get commonDelete => 'Eliminar';

  @override
  String get commonEnable => 'Activar';

  @override
  String get commonDisable => 'Desactivar';

  @override
  String get settingsTitle => 'Ajustes';

  @override
  String get settingsRemoveAllTitle =>
      'Quitar todas las impresoras de este dispositivo';

  @override
  String get settingsRemoveAllSubtitle =>
      'Borra la caché local de impresoras. Tu cuenta de Supabase se conserva para que volver a vincular funcione sin problemas.';

  @override
  String get settingsRemoveAllConfirmTitle => '¿Quitar todas las impresoras?';

  @override
  String get settingsRemoveAllConfirmBody =>
      'Se quitarán de este dispositivo todas las impresoras vinculadas. Puedes volver a añadirlas ejecutando MOONGATE_PAIR en la impresora.';

  @override
  String get settingsRemoveAllConfirmAction => 'Quitar todas';

  @override
  String get dashboardAddPrinter => 'Añadir impresora';

  @override
  String get dashboardRemovePrinter => 'Quitar impresora';

  @override
  String get dashboardMenuTooltip => 'Menú';

  @override
  String get dashboardRemovePrinterTitle => '¿Quitar impresora?';

  @override
  String dashboardRemovePrinterBody(String name) {
    return '¿Quitar \"$name\" de Moongate?';
  }

  @override
  String get dashboardRemoveSupabaseUnreachable =>
      'Se quitó localmente, pero no se pudo conectar con Supabase. Ejecuta MOONGATE_RESET_OWNER en la Pi si falla la nueva vinculación.';

  @override
  String get dashboardBackUpConfig => 'Copia de seguridad';

  @override
  String get dashboardBackUpConfigSubtitle =>
      'Guarda en un archivo antes de reinstalar';

  @override
  String get dashboardRestoreConfig => 'Restaurar configuración';

  @override
  String get dashboardRestoreConfigSubtitle =>
      'Carga desde un archivo de copia de seguridad';

  @override
  String get dashboardThemeHeading => 'Tema';

  @override
  String get dashboardThemeSystem => 'Colores del teléfono';

  @override
  String get dashboardThemeDark => 'Oscuro';

  @override
  String get dashboardThemeLight => 'Claro';

  @override
  String get dashboardThemeCustom => 'Personalizado';

  @override
  String get dashboardFontHeading => 'Fuente';

  @override
  String get fontStandard => 'Predeterminada';

  @override
  String get fontRounded => 'Redondeada';

  @override
  String get fontSerif => 'Serif';

  @override
  String get fontReadable => 'Alta legibilidad';

  @override
  String get dashboardCustomiseColours => 'Personalizar colores';

  @override
  String get dashboardCustomiseColoursSubtitle =>
      'Edita los cinco espacios de color del tema - HEX o paleta';

  @override
  String get dashboardFontSizeHeading => 'Tamaño de visualización';

  @override
  String get dashboardLayoutHeading => 'Diseño del panel';

  @override
  String dashboardColumnCount(int count) {
    return '$count col';
  }

  @override
  String get dashboardRotateWithDevice => 'Girar con el dispositivo';

  @override
  String get dashboardRotateWithDeviceSubtitle =>
      'Permite la orientación horizontal';

  @override
  String get dashboardAutoArrange => 'Ordenar automáticamente por estado';

  @override
  String get dashboardAutoArrangeSubtitle =>
      'Ordena las casillas por actividad. Desactívalo para arrastrarlas a tu propio orden.';

  @override
  String get dashboardShowButtons => 'Mostrar botones del panel';

  @override
  String get dashboardShowButtonsSubtitle =>
      'Muestra los botones de añadir y reordenar en la parte inferior. Añade impresoras desde el menú cuando están ocultos.';

  @override
  String get dashboardShowEta => 'Mostrar tiempo restante';

  @override
  String get dashboardShowEtaSubtitle =>
      'Las casillas que están imprimiendo muestran el tiempo restante junto a las temperaturas.';

  @override
  String get dashboardEtaFormatRemaining => 'Tiempo restante';

  @override
  String get dashboardEtaFormatFinish => 'Hora de fin';

  @override
  String get dashboardReorderHint =>
      'Mantén y arrastra una casilla para reordenar';

  @override
  String get dashboardReorderStart => 'Reordenar';

  @override
  String get dashboardReorderDone => 'Listo';

  @override
  String get dashboardCameraFeedHeading => 'Cámara del panel';

  @override
  String get dashboardCameraFeedSubtitle =>
      'Con qué frecuencia las casillas actualizan la cámara. Las frecuencias más bajas usan muchos menos datos.';

  @override
  String get cameraFeedsMenuTitle => 'Cámaras del panel';

  @override
  String get cameraFeedsMenuSubtitle => 'Frecuencias de feed local y túnel';

  @override
  String get cameraFeedsIntro =>
      'Con qué frecuencia cada casilla actualiza su cámara. Moongate usa la velocidad Local mientras estás en Wi-Fi (incluso fuera de casa) y la velocidad Túnel con datos móviles, para mantener un flujo rápido en Wi-Fi y más ligero en datos móviles y ahorrar datos.';

  @override
  String get cameraFeedsLocalRate => 'Frecuencia del feed local';

  @override
  String get cameraFeedsTunnelRate => 'Frecuencia del feed por túnel';

  @override
  String get dashboardAboutHeading => 'Acerca de';

  @override
  String get dashboardWhatsNew => 'Novedades';

  @override
  String get dashboardWhatsNewSubtitle => 'Cambios recientes de un vistazo';

  @override
  String get dashboardHowPairingWorks => 'Cómo funciona la vinculación';

  @override
  String get dashboardHowPairingWorksSubtitle =>
      'Vinculación, reinstalación y restauración';

  @override
  String get dashboardReportProblem => 'Informar de un problema';

  @override
  String get dashboardReportProblemSubtitle =>
      'Envía un informe de error o comentarios';

  @override
  String get dashboardAppLock => 'Bloqueo de la app';

  @override
  String get dashboardAppLockOn =>
      'Activado - se requiere desbloqueo al iniciar';

  @override
  String get dashboardAppLockOff => 'Desactivado';

  @override
  String get dashboardBuyMeCoffee => 'Invítame a un café';

  @override
  String get dashboardBuyMeCoffeeSubtitle =>
      'Da una propina al desarrollador vía PayPal';

  @override
  String get dashboardDeleteData => 'Eliminar mis datos';

  @override
  String get dashboardDeleteDataSubtitle =>
      'Borra tu cuenta y tus impresoras de la nube';

  @override
  String get deleteDataConfirmTitle => '¿Eliminar mis datos?';

  @override
  String get deleteDataConfirmBody =>
      'Esto elimina permanentemente tu cuenta anónima y quita tus impresoras y ajustes de notificaciones de la nube. Tendrás que volver a vincular las impresoras. No se puede deshacer.';

  @override
  String get deleteDataDone => 'Tus datos se han eliminado';

  @override
  String get deleteDataError =>
      'No se pudieron eliminar tus datos. Inténtalo de nuevo.';

  @override
  String get donationPromptTitle => '¿Te gusta Moongate?';

  @override
  String get donationPromptBody =>
      'Moongate es un proyecto personal gratuito que hago en mi tiempo libre. Si te resulta útil, una pequeña propina ayuda a mantenerlo - sin presión, y no volveré a preguntar.';

  @override
  String get donationPromptLater => 'Quizás luego';

  @override
  String get dashboardSettings => 'Ajustes';

  @override
  String dashboardVersion(String version) {
    return 'Moongate v$version';
  }

  @override
  String get dashboardSaveBackupDialogTitle =>
      'Guardar copia de seguridad de Moongate';

  @override
  String get dashboardBackupFailed =>
      'Error en la copia de seguridad - no se pudo guardar el archivo.';

  @override
  String dashboardBackupSuccess(int count) {
    return 'Se hizo copia de seguridad de $count impresora(s). Este archivo puede restaurarlas en una instalación nueva - mantenlo privado.';
  }

  @override
  String dashboardBackupSuccessListOnly(int count) {
    return 'Se hizo copia de seguridad de $count impresora(s) (solo la lista - no se pudo conectar con la nube para obtener un código de restauración).';
  }

  @override
  String get dashboardInvalidBackupFile =>
      'Archivo de copia de seguridad no válido - elige un archivo de configuración de Moongate.';

  @override
  String dashboardRestoreReconnected(int added, int count) {
    return 'Se restauraron $added impresora(s) - $count reconectadas y volviendo a estar en línea.';
  }

  @override
  String dashboardRestoreNoneReconnected(int added) {
    return 'Se restauraron $added impresora(s), pero ninguna se reconectó - el código de restauración de la copia no coincidió con ninguna impresora (puede ser de una copia anterior o ya usado). Vuelve a vincularlas para ponerlas en línea.';
  }

  @override
  String dashboardRestoreListOnly(int added) {
    return 'Se restauraron $added impresora(s) (solo la lista). Vuelve a vincular cada impresora para ponerla en línea.';
  }

  @override
  String get dashboardRestoreApplied =>
      'Panel restaurado para coincidir con tu copia de seguridad.';

  @override
  String get dashboardRestoreExtrasTitle =>
      '¿Conservar tus impresoras actuales?';

  @override
  String dashboardRestoreExtrasBody(String names) {
    return 'Estas impresoras están en este panel pero no en la copia de seguridad: $names. Puedes conservarlas junto a las impresoras restauradas o quitarlas para que el panel coincida exactamente con la copia. Las impresoras quitadas siguen emparejadas: puedes volver a añadirlas o restaurarlas más tarde.';
  }

  @override
  String get dashboardRestoreExtrasKeep => 'Conservarlas';

  @override
  String get dashboardRestoreExtrasRemove => 'Quitarlas';

  @override
  String get dashboardRemoveSheetTitle => 'Quitar una impresora';

  @override
  String dashboardPrinterIdShort(String id) {
    return 'id $id…';
  }

  @override
  String get dashboardPairingHelpPluginTitle =>
      'Primero: instala el complemento de Pi';

  @override
  String get dashboardPairingHelpPluginBody =>
      'Moongate necesita que su complemento esté en ejecución en tu impresora Klipper antes de emparejar. Tras la instalación, ejecuta la macro MOONGATE_PAIR (o escríbela en la consola de Mainsail/Fluidd) para obtener un código de emparejamiento o una URL para emparejar con código QR.';

  @override
  String get dashboardPairingHelpPluginAction =>
      'Abrir la guía de inicio rápido';

  @override
  String get pluginUpdateTooltip => 'Actualización del complemento disponible';

  @override
  String get pluginUpdateTitle => 'Actualización del complemento disponible';

  @override
  String pluginUpdateBody(String current, String latest) {
    return 'Esta impresora ejecuta el complemento Moongate $current. La versión $latest está disponible.';
  }

  @override
  String get pluginUpdateVersionUnknown => 'una versión antigua';

  @override
  String get pluginUpdateNow => 'Actualizar ahora';

  @override
  String get pluginUpdateManual =>
      'Esta versión del complemento aún no puede actualizarse desde la app. En la interfaz web de la impresora: Mainsail (o Fluidd) → Software Updates → Moongate → Update.';

  @override
  String get pluginUpdateBusyPrinting =>
      'Esta impresora está imprimiendo. Actualiza cuando termine la impresión.';

  @override
  String get pluginUpdateStarted =>
      'Actualización iniciada. Se ejecuta en segundo plano en la impresora - el icono desaparecerá cuando termine (alrededor de un minuto).';

  @override
  String get pluginUpdateFailed =>
      'No se pudo iniciar la actualización. Usa la interfaz web de la impresora: Software Updates → Moongate → Update.';

  @override
  String get dashboardPairingHelpPairOnceTitle => 'Vincula una vez';

  @override
  String get dashboardPairingHelpPairOnceBody =>
      'Escanea el QR (o introduce el código GATE) para añadir una impresora - ese enlace se guarda en esta app.';

  @override
  String get dashboardPairingHelpUpdatesTitle =>
      'Las actualizaciones de la app conservan tus impresoras';

  @override
  String get dashboardPairingHelpUpdatesBody =>
      'Actualizar Moongate nunca requiere volver a vincular.';

  @override
  String get dashboardPairingHelpReinstallTitle =>
      '¿Reinstalando o nuevo teléfono?';

  @override
  String get dashboardPairingHelpReinstallBody =>
      'Haz primero una copia de seguridad (Menú → Copia de seguridad); luego Restaurar pone tus impresoras de nuevo en línea - sin volver a vincular.';

  @override
  String get dashboardPairingHelpNoBackupTitle => '¿Sin copia de seguridad?';

  @override
  String get dashboardPairingHelpNoBackupBody =>
      'Ejecuta MOONGATE_RESET_OWNER en la consola de la impresora y vuelve a vincular.';

  @override
  String get dashboardDontShowAgain => 'No volver a mostrar esto';

  @override
  String dashboardUpdateAvailable(String version) {
    return 'Actualización disponible - v$version';
  }

  @override
  String get dashboardUpdateLater => 'Más tarde';

  @override
  String get dashboardUpdate => 'Actualizar';

  @override
  String get dashboardEmptyTitle => 'Aún no se han añadido impresoras';

  @override
  String get dashboardEmptyBody =>
      'Toca el botón de abajo para vincular tu primera impresora.';

  @override
  String get pairingTitle => 'Añadir impresora';

  @override
  String get pairingIntro =>
      'Ejecuta MOONGATE_PAIR en tu consola de Klipper - escanea el QR o escribe el código GATE que se muestra en la consola.';

  @override
  String get pairingNameLabel => 'Nombre de la impresora';

  @override
  String get pairingNameHint => 'p. ej. Voron 2.4';

  @override
  String get pairingScanButton => 'Escanear código QR';

  @override
  String get pairingScanRecommended => 'Recomendado - conecta al instante';

  @override
  String get pairingOr => 'O';

  @override
  String get pairingGateCodeLabel => 'Código GATE';

  @override
  String get pairingGateCodeHint =>
      'Escribe el código de 8 dígitos que aparece en tu consola de Klipper.';

  @override
  String get pairingGateCodeValid => 'El código parece válido ✓';

  @override
  String get pairingGateCodeWarning =>
      'Método alternativo. Sin el QR, la impresora puede tardar hasta aproximadamente un minuto en conectarse - está esperando a que se establezca el túnel seguro. Escanea el código QR de arriba para una conexión instantánea.';

  @override
  String get pairingCameraPermissionNeeded => 'Se necesita permiso de cámara';

  @override
  String get pairingCameraUnavailable => 'Cámara no disponible';

  @override
  String get pairingCancelScan => 'Cancelar escaneo';

  @override
  String pairingQrScanned(String code) {
    return 'QR escaneado - código $code';
  }

  @override
  String get pairingRescan => 'Volver a escanear';

  @override
  String get pairingAdvancedTitle =>
      'Avanzado - ¿impresora en una red personalizada?';

  @override
  String get pairingAdvancedBody =>
      'La mayoría puede dejar esto en blanco. Si tu impresora está detrás de un proxy inverso (Traefik, Caddy, NPM) o en Docker, introduce la misma dirección que usas para abrir su página web (Mainsail / Fluidd) en un navegador.';

  @override
  String get pairingAddressLabel => 'Dirección de la impresora';

  @override
  String get pairingAddressHint => '192.168.1.50:7125';

  @override
  String get pairingPairButton => 'Vincular impresora';

  @override
  String get pairingModeCloud => 'Nube de Moongate';

  @override
  String get pairingModeDirect => 'Directo (LAN/VPN)';

  @override
  String get pairingDirectIntro =>
      'Conecta directamente con la impresora a través de tu red o tu propia VPN - sin cuenta en la nube, funciona sin internet. La impresora debe instalarse en modo solo LAN.';

  @override
  String get pairingDirectScanHint =>
      'Escanea el QR de MOONGATE_PAIR o introduce la dirección abajo';

  @override
  String get pairingDirectAddressHelper =>
      'La dirección que usas para Mainsail / Fluidd en tu red';

  @override
  String get pairingAddButton => 'Añadir impresora';

  @override
  String pairingLanScanned(String url) {
    return 'Impresora LAN escaneada - $url';
  }

  @override
  String pairingNameHintCycled(String name) {
    return 'p. ej. $name';
  }

  @override
  String get pairingNameHintExamples =>
      'Voron 2.4|RatRig 300|Wilma|2.4 V3309|Printy McPrintface';

  @override
  String get pairingErrorNoName =>
      'Ponle primero un nombre a tu impresora - así la identificarás en el panel.';

  @override
  String get pairingDirectCaveatsTitle => 'Limitaciones del modo directo';

  @override
  String get pairingDirectCaveats =>
      '• Las notificaciones de impresión no funcionarán\n• Fuera de casa, la app solo se conecta a través de tu propia VPN\n• La red de tu móvil (o la subred VPN) debe estar en trusted_clients de Moonraker\n• Asigna a la impresora una dirección fija (reserva DHCP) - la app la guarda';

  @override
  String get pairingErrorNoAddress =>
      'Introduce la dirección de la impresora o escanea su código QR.';

  @override
  String get pairingRestoreHint =>
      '¿Reinstalando? Restaura tus impresoras guardadas desde un archivo de copia de seguridad. Aún tendrás que volver a vincular cada una para ponerla en línea.';

  @override
  String get pairingImportButton => 'Importar configuración desde archivo';

  @override
  String get pairingReportButton =>
      '¿Problemas para vincular? Envía un informe';

  @override
  String get pairingCameraPermissionTitle => 'Se requiere permiso de cámara';

  @override
  String get pairingCameraPermissionBody =>
      'Moongate necesita acceso a la cámara para escanear códigos QR.\n\nAbre Ajustes → Apps → Moongate → Permisos y activa Cámara; luego vuelve e inténtalo de nuevo.';

  @override
  String get pairingOpenSettings => 'Abrir Ajustes';

  @override
  String get pairingErrorNotMoongateQr =>
      'No es un código QR de Moongate. Ejecuta MOONGATE_PAIR en la impresora para generar uno.';

  @override
  String get pairingErrorOldQr =>
      'Este código QR es de una versión anterior de Moongate. Actualiza primero la Pi a v0.3.0.';

  @override
  String get pairingErrorNoCode =>
      'Escanea el código QR o escribe el código GATE de la consola de la impresora.';

  @override
  String get pairingErrorBadAddress =>
      'Esa dirección de impresora no parece correcta - prueba p. ej. 192.168.1.50:7125';

  @override
  String pairingErrorFailed(String error) {
    return 'Error de vinculación: $error';
  }

  @override
  String get pairingImportInvalidFile =>
      'Archivo de copia de seguridad no válido - elige un archivo de configuración de Moongate.';

  @override
  String get pairingImportNoNewPrinters =>
      'No se encontraron impresoras nuevas en ese archivo.';

  @override
  String pairingImportRestoredReconnected(int count, int reconnected) {
    return 'Se restauraron $count impresora(s) - $reconnected reconectadas, volviendo a estar en línea.';
  }

  @override
  String pairingImportRestoredRepair(int count) {
    return 'Se restauraron $count impresora(s) - vuelve a vincular cada Pi para ponerla en línea.';
  }

  @override
  String get customThemeTitle => 'Tema personalizado';

  @override
  String get customThemeResetTooltip =>
      'Restablecer a los valores predeterminados';

  @override
  String get customThemeResetConfirmTitle =>
      '¿Restablecer el tema personalizado?';

  @override
  String get customThemeResetConfirmBody =>
      'Los cinco espacios de color volverán a la paleta predeterminada de morado sobre oscuro.';

  @override
  String get customThemeReset => 'Restablecer';

  @override
  String get customThemePreview => 'Vista previa';

  @override
  String get customThemeAccent => 'Acento';

  @override
  String get customThemeAccentDesc =>
      'Botones, FAB, barras de progreso, enlaces';

  @override
  String get customThemeBackground => 'Fondo de página';

  @override
  String get customThemeBackgroundDesc => 'Detrás de cada pantalla';

  @override
  String get customThemeSurface => 'Tarjetas y casillas';

  @override
  String get customThemeSurfaceDesc =>
      'Casillas del panel, hojas, menú lateral';

  @override
  String get customThemeText => 'Texto';

  @override
  String get customThemeTextDesc =>
      'Texto de cuerpo y títulos sobre las superficies';

  @override
  String get customThemeError => 'Error / Parar';

  @override
  String get customThemeErrorDesc =>
      'Acciones destructivas, superposiciones de error';

  @override
  String get customThemeEstop => 'Botón de parada de emergencia';

  @override
  String get customThemeEstopDesc => 'Anillo e icono de parada de emergencia';

  @override
  String get customThemePresets => 'Preajustes';

  @override
  String get customThemeInvalidHex => 'No es un color hexadecimal válido';

  @override
  String get customThemeSamplePrinter => 'Impresora de ejemplo';

  @override
  String get customThemePrinting => 'Imprimiendo';

  @override
  String get tilePauseFailed =>
      'No se pudo conectar con la impresora - falló la pausa';

  @override
  String get tileResumeFailed =>
      'No se pudo conectar con la impresora - falló la reanudación';

  @override
  String get tileStopAgainToCancel =>
      'Pulsa PARAR de nuevo para cancelar la impresión';

  @override
  String get tileLocal => 'Local';

  @override
  String get tileTunnel => 'Túnel';

  @override
  String get tilePrinting => 'Imprimiendo';

  @override
  String get tilePaused => 'En pausa';

  @override
  String get tileResume => 'Reanudar';

  @override
  String get tilePause => 'Pausar';

  @override
  String get tileConfirmStop => 'Confirmar parada';

  @override
  String get tileStopPrint => 'Parar impresión';

  @override
  String get tileFirmwareRestart => 'Reiniciar firmware';

  @override
  String get tileEmergencyStop => 'Parada de emergencia · doble toque';

  @override
  String get tileEmergencyStopFailed =>
      'No se pudo conectar con la impresora - falló la parada de emergencia';

  @override
  String get tilePrintComplete => 'Impresión completada';

  @override
  String get tilePrintCancelled => 'Impresión cancelada';

  @override
  String get tilePrinterError => 'Error de la impresora';

  @override
  String get tileKlipperStarting => 'Klipper iniciándose';

  @override
  String get tileReady => 'Lista';

  @override
  String get tileOffline => 'Sin conexión';

  @override
  String get tileStartingUp => 'Iniciando…';

  @override
  String get tileConnected => 'Conectada';

  @override
  String get tileConnecting => 'Conectando…';

  @override
  String get tilePrinterUnreachable => 'Impresora inaccesible';

  @override
  String get tileWaitingForHeartbeat => 'Esperando la primera señal';

  @override
  String get tilePrinterIdle => 'Impresora inactiva';

  @override
  String get tileReachingPrinter => 'Contactando con la impresora';

  @override
  String get tileRemoteReady => 'Acceso remoto listo';

  @override
  String get tileRemoteConnecting => 'Conectando en remoto…';

  @override
  String get tileIdle => 'Inactiva';

  @override
  String get tileDone => 'Hecho';

  @override
  String get tileCancelled => 'Cancelada';

  @override
  String get tileClearJobTooltip => 'Borrar y poner como inactiva';

  @override
  String get tileClearJobFailed => 'No se pudo restablecer la impresora';

  @override
  String get dashboardBackgroundTitle => 'Fondo del panel';

  @override
  String get dashboardBackgroundNone => 'Ninguno - color del tema';

  @override
  String get dashboardBackgroundCustom => 'Imagen personalizada';

  @override
  String get dashboardBackgroundRemove => 'Quitar fondo';

  @override
  String get dashboardBackgroundSet => 'Fondo actualizado';

  @override
  String get uiGuideSectionTileButtons => 'Botones de la tarjeta';

  @override
  String get uiGuideFilesTitle => 'Imprimir un archivo';

  @override
  String get uiGuideFilesDesc =>
      'Explora los archivos G-code guardados en la impresora e inicia uno.';

  @override
  String get uiGuideMacrosTitle => 'Macros';

  @override
  String get uiGuideMacrosDesc =>
      'Ejecuta una de las macros de Klipper de la impresora.';

  @override
  String get uiGuidePowerTitle => 'Encendido';

  @override
  String get uiGuidePowerDesc =>
      'Enciende o apaga la impresora, cuando tiene un dispositivo de encendido.';

  @override
  String get uiGuideLightingTitle => 'Iluminación';

  @override
  String get uiGuideLightingDesc =>
      'Activa o desactiva la luz de la impresora; la bombilla se ilumina cuando está encendida.';

  @override
  String get uiGuideCameraViewTitle => 'Cámara';

  @override
  String get uiGuideCameraViewDesc =>
      'Abre la cámara en vivo a pantalla completa.';

  @override
  String get uiGuideCameraSetupTitle => 'Configuración de cámara';

  @override
  String get uiGuideCameraSetupDesc =>
      'Apunta una tarjeta a una cámara que no está conectada a Klipper.';

  @override
  String get uiGuideClearJobTitle => 'Borrar una impresión finalizada';

  @override
  String get uiGuideClearJobDesc =>
      'Toca la × en una tarjeta Hecho o Cancelada para volver a ponerla como inactiva.';

  @override
  String get tileError => 'Error';

  @override
  String get tileStarting => 'Iniciando';

  @override
  String get tileConnectingBadge => 'Conectando';

  @override
  String get appLockTitle => 'Bloqueo de la app';

  @override
  String get appLockIntro =>
      'Requiere un PIN -y opcionalmente tu huella o rostro- antes de que Moongate se abra. El bloqueo siempre aparece cuando la app se inicia de nuevo.';

  @override
  String get appLockSubtitle => 'Se requiere PIN para abrir la app';

  @override
  String get appLockBiometricTitle => 'Desbloqueo biométrico';

  @override
  String get appLockBiometricSubtitle =>
      'Usa huella o rostro - el PIN queda como alternativa';

  @override
  String get appLockChangePin => 'Cambiar PIN';

  @override
  String get appLockAutoLock => 'Bloqueo automático';

  @override
  String get appLockPinUpdated => 'PIN actualizado';

  @override
  String get appLockChoosePinTitle => 'Elige un PIN';

  @override
  String get appLockChoosePinSubtitle => 'Introduce de 4 a 6 dígitos';

  @override
  String get appLockConfirmPinTitle => 'Confirmar PIN';

  @override
  String get appLockPinsDontMatch => 'Los PIN no coinciden';

  @override
  String get appLockEnterCurrentPin => 'Introduce el PIN actual';

  @override
  String get appLockTimeoutImmediately => 'Inmediatamente';

  @override
  String get appLockTimeoutOneMinute => 'Después de 1 minuto';

  @override
  String get appLockTimeoutFiveMinutes => 'Después de 5 minutos';

  @override
  String get appLockTimeoutFifteenMinutes => 'Después de 15 minutos';

  @override
  String get appLockTimeoutColdLaunch => 'Solo al iniciar la app';

  @override
  String get lockEnterPin => 'Introduce tu PIN';

  @override
  String get lockSubtitle => 'Moongate está bloqueado';

  @override
  String lockTooManyAttempts(int seconds) {
    return 'Demasiados intentos. Inténtalo de nuevo en $seconds s';
  }

  @override
  String get lockWrongPin => 'PIN incorrecto';

  @override
  String get lockUseBiometrics => 'Usar biometría';

  @override
  String get lockForgotPin => '¿Olvidaste el PIN?';

  @override
  String get lockBiometricReason => 'Desbloquear Moongate';

  @override
  String get lockResetTitle => '¿Restablecer Moongate?';

  @override
  String get lockResetBody =>
      'Esto quita el bloqueo de la app y borra las impresoras vinculadas de este dispositivo para que puedas empezar de nuevo. Tus impresoras no se eliminan - vuelve a vincularlas ejecutando MOONGATE_PAIR en cada una.';

  @override
  String get lockResetConfirm => 'Restablecer';

  @override
  String get pinContinue => 'Continuar';

  @override
  String printerStartingUpRetry(int seconds) {
    return 'La impresora se está iniciando. Reintentando en $seconds s…';
  }

  @override
  String printerCouldNotReach(String error) {
    return 'No se pudo conectar con la impresora: $error';
  }

  @override
  String get printerDirectModeToggle => 'Modo directo (LAN/VPN)';

  @override
  String get printerDirectModeSubtitle =>
      'Habla con esta impresora solo a través de tu red o VPN - sin nube. Necesita la dirección de la impresora y que esté instalada en modo solo LAN.';

  @override
  String get printerDirectModeNeedsAddress =>
      'El modo directo necesita la dirección de la impresora';

  @override
  String get printerDirectModeOn =>
      'Modo directo activado - esta impresora ahora se conecta solo por tu red';

  @override
  String get printerDirectModeOff =>
      'Modo directo desactivado - conexión a la nube restaurada';

  @override
  String get printerAddressCleared => 'Dirección personalizada borrada';

  @override
  String get printerAddressUpdated => 'Dirección de la impresora actualizada';

  @override
  String printerTunnelUnreachable(String description) {
    return 'Túnel de Cloudflare inaccesible.\n$description';
  }

  @override
  String printerWebUiRetry(int seconds) {
    return 'La interfaz web de la impresora aún no responde. Es normal durante un minuto aproximadamente tras el encendido. Reintentando en $seconds s…';
  }

  @override
  String get printerLocalOnlyNoLan =>
      'El acceso remoto está desactivado (Solo local) y esta impresora no está accesible en tu red.';

  @override
  String get localOnlyButtonTitle => 'Botón de solo local';

  @override
  String get localOnlyButtonSubtitle =>
      'Un botón en la barra superior que desactiva las conexiones remotas (túnel), de modo que solo se conectan las impresoras de tu red';

  @override
  String get localOnlyTooltip => 'Solo local';

  @override
  String get localOnlySnackOn =>
      'Conexiones remotas desactivadas - solo red local';

  @override
  String get localOnlySnackOff => 'Conexiones remotas reactivadas';

  @override
  String get printerEdit => 'Editar impresora';

  @override
  String get printerLocalNetwork => 'Red local';

  @override
  String get printerTunnelVia => 'Túnel vía Moongate';

  @override
  String get printerCameraTooltip => 'Cámara';

  @override
  String get cameraConnecting => 'Conectando con la cámara…';

  @override
  String get cameraNoCamera =>
      'No hay ninguna cámara configurada para esta impresora.';

  @override
  String get cameraHintBody =>
      'La cámara no se carga aquí en remoto - abre la cámara de Moongate.';

  @override
  String get cameraHintOpen => 'Abrir';

  @override
  String get webcamWakingUp => 'La cámara se está activando…';

  @override
  String get printerUnreachable => 'Impresora inaccesible';

  @override
  String get printerUseTunnel => 'Usar túnel';

  @override
  String get printerAddressInvalid => 'Prueba p. ej. 192.168.1.50:7125';

  @override
  String get printerNameLabel => 'Nombre de la impresora';

  @override
  String get printerAddressLabel => 'Dirección de la impresora (avanzado)';

  @override
  String get printerAddressHint => '192.168.1.50:7125';

  @override
  String get printerAddressHelper =>
      'Solo para configuraciones con proxy inverso / Docker. Déjalo en blanco para usar la detección automática.';

  @override
  String get feedbackTitle => 'Informar de un problema';

  @override
  String get feedbackTroublePairing => '¿Problemas para vincular?';

  @override
  String get feedbackDescription =>
      'Cuéntanos qué está pasando. La versión de tu app, el dispositivo, la red y los datos de la impresora se adjuntan automáticamente para ayudarnos a localizarlo.';

  @override
  String get feedbackPairingDescription =>
      'Describe qué ocurre cuando intentas añadir la impresora. Tus datos de red y de detección se adjuntan automáticamente para que podamos ver por qué no se conecta.';

  @override
  String get feedbackWhichPrinter => '¿Qué impresora? (opcional)';

  @override
  String get feedbackGeneralOption =>
      'General / no específico de una impresora';

  @override
  String get feedbackCommentLabel => '¿Qué salió mal?';

  @override
  String get feedbackCommentHint =>
      'p. ej. \"La impresora muestra Conectada / inactiva pero en realidad está lista - se abre bien cuando toco la casilla.\"';

  @override
  String get feedbackContactLabel => 'Correo o contacto (opcional)';

  @override
  String get feedbackContactHint => 'Solo si quieres una respuesta';

  @override
  String get feedbackSending => 'Enviando…';

  @override
  String get feedbackSend => 'Enviar informe';

  @override
  String get feedbackSuccess => 'Gracias - tu informe se ha enviado.';

  @override
  String get feedbackError =>
      'No se pudo enviar - comprueba tu conexión e inténtalo de nuevo.';

  @override
  String get splashTagline => 'Control remoto de Klipper';

  @override
  String get uiGuideTitle => 'Guía de iconos';

  @override
  String get uiGuideMenuSubtitle => 'Qué significan los iconos del panel';

  @override
  String get uiGuideIntro =>
      'Una guía rápida de los iconos que verás en el panel.';

  @override
  String get uiGuideSectionConnection => 'Conexión';

  @override
  String get uiGuideSectionTemperatures => 'Temperaturas';

  @override
  String get uiGuideSectionControls => 'Controles de impresión';

  @override
  String get uiGuideSectionStatus => 'Estado';

  @override
  String get uiGuideSectionWebcam => 'Cámara y conexión';

  @override
  String get uiGuideLocalTitle => 'Red local';

  @override
  String get uiGuideLocalDesc =>
      'Conectada directamente por tu Wi-Fi - la ruta más rápida.';

  @override
  String get uiGuideTunnelTitle => 'Remoto (túnel)';

  @override
  String get uiGuideTunnelDesc =>
      'Conectada desde cualquier lugar a través del túnel seguro de Cloudflare.';

  @override
  String get uiGuideTunnelReadyTitle => 'Remoto listo';

  @override
  String get uiGuideTunnelReadyDesc =>
      'El túnel está activo, así que el acceso remoto está disponible.';

  @override
  String get uiGuideTunnelConnectingTitle => 'Conectando en remoto';

  @override
  String get uiGuideTunnelConnectingDesc =>
      'El túnel remoto aún se está estableciendo.';

  @override
  String get uiGuideHotendTitle => 'Hotend / boquilla';

  @override
  String get uiGuideHotendDesc => 'Temperatura actual de la boquilla.';

  @override
  String get uiGuideBedTitle => 'Cama caliente';

  @override
  String get uiGuideBedDesc => 'Temperatura actual de la cama.';

  @override
  String get uiGuideChamberTitle => 'Cámara interna';

  @override
  String get uiGuideChamberDesc =>
      'Temperatura de la cámara interna - se muestra solo si tu impresora la reporta.';

  @override
  String get uiGuideResumeTitle => 'Reanudar';

  @override
  String get uiGuideResumeDesc => 'Reanuda una impresión en pausa.';

  @override
  String get uiGuidePauseTitle => 'Pausar';

  @override
  String get uiGuidePauseDesc => 'Pausa la impresión actual.';

  @override
  String get uiGuideStopTitle => 'Parar';

  @override
  String get uiGuideStopDesc =>
      'Cancela la impresión - toca dos veces para confirmar.';

  @override
  String get uiGuideEstopTitle => 'Parada de emergencia';

  @override
  String get uiGuideEstopDesc =>
      'Toca dos veces el triángulo rojo para detener la impresora de inmediato (Klipper M112).';

  @override
  String get uiGuideFirmwareRestartTitle => 'Reiniciar firmware';

  @override
  String get uiGuideFirmwareRestartDesc =>
      'Reinicia Klipper cuando la impresora está inactiva o con error.';

  @override
  String get uiGuideStatusReadyTitle => 'Lista / completada';

  @override
  String get uiGuideStatusReadyDesc =>
      'La impresora está inactiva o terminó su última impresión.';

  @override
  String get uiGuideStatusCancelledTitle => 'Cancelada';

  @override
  String get uiGuideStatusCancelledDesc => 'La última impresión se canceló.';

  @override
  String get uiGuideStatusErrorTitle => 'Error';

  @override
  String get uiGuideStatusErrorDesc =>
      'Klipper informó de un error - abre la impresora para ver los detalles.';

  @override
  String get uiGuideStatusStartingTitle => 'Iniciando';

  @override
  String get uiGuideStatusStartingDesc =>
      'Klipper se está iniciando; los controles aparecen cuando esté lista.';

  @override
  String get uiGuideOfflineTitle => 'Sin conexión';

  @override
  String get uiGuideOfflineDesc =>
      'No se puede contactar con la impresora ahora mismo.';

  @override
  String get uiGuideNoWebcamTitle => 'Sin cámara';

  @override
  String get uiGuideNoWebcamDesc =>
      'No hay ninguna instantánea de cámara disponible para esta impresora.';

  @override
  String get uiGuideBack => 'Volver al panel';

  @override
  String get printNotifTitle => 'Notificaciones de impresión';

  @override
  String get printNotifSubtitle =>
      'Progreso y estado en vivo mientras la app está en segundo plano';

  @override
  String get printNotifPermissionNeeded =>
      'Permite las notificaciones para activar esto.';

  @override
  String get printNotifPromptTitle => '¿Recibir notificaciones de impresión?';

  @override
  String get printNotifPromptBody =>
      'Mira el estado en vivo de tus impresoras - progreso, temperaturas y avisos cuando una impresión empieza, termina o falla. Puedes cambiar esto cuando quieras en el menú.';

  @override
  String get printNotifPromptEnable => 'Activar';

  @override
  String get printNotifPromptNotNow => 'Ahora no';

  @override
  String get printNotifWatching => 'Vigilando tus impresoras…';

  @override
  String get printNotifNoPrinters => 'Sin impresoras';

  @override
  String get printNotifNoneOnline => 'No hay impresoras en línea';

  @override
  String get notifOnlineOnlyTitle => 'Mostrar solo dispositivos en línea';

  @override
  String get notifOnlineOnlySubtitle =>
      'Ocultar las máquinas sin conexión de la notificación de estado';

  @override
  String get notifPollIntervalTitle => 'Frecuencia de actualización';

  @override
  String get notifContentTitle => 'Contenido de la notificación';

  @override
  String get notifContentSubtitle => 'Elige y reordena lo que se muestra';

  @override
  String get notifRosterTitle => 'Barra de estado de todas las impresoras';

  @override
  String get notifRosterShownSubtitle =>
      'Visible. Toca para ocultar solo esta barra en los ajustes de notificaciones de tu teléfono: las tarjetas de impresión siguen llegando.';

  @override
  String get notifRosterHiddenSubtitle =>
      'Oculta en los ajustes de notificaciones de tu teléfono. Toca para volver a mostrarla.';

  @override
  String get notifContentIntro =>
      'Elige qué detalles aparecen en la tarjeta de notificación de cada impresión y arrástralos en el orden que quieras.';

  @override
  String get notifContentPreview => 'Vista previa';

  @override
  String get notifFieldProgress => 'Progreso';

  @override
  String get notifFieldRemaining => 'Tiempo restante';

  @override
  String get notifFieldEta => 'Hora de fin';

  @override
  String get notifFieldHotend => 'Temp. fusor';

  @override
  String get notifFieldBed => 'Temp. cama';

  @override
  String get printAlertReady => 'Impresora lista';

  @override
  String get printStatusReady => 'Lista';

  @override
  String get printStatusHeating => 'Calentando';

  @override
  String get printStatusIdle => 'Inactiva';

  @override
  String get printStatusOffline => 'Sin conexión';

  @override
  String get printStatusPaused => 'En pausa';

  @override
  String get printStatusComplete => 'Completada';

  @override
  String get printStatusCancelled => 'Cancelada';

  @override
  String get printStatusError => 'Error';

  @override
  String get printStatusStartingUp => 'Iniciando…';

  @override
  String get printStatusPrinting => 'Imprimiendo';

  @override
  String get printNotifStarted => 'Impresión iniciada';

  @override
  String get printNotifFinished => 'Finalizado';

  @override
  String get notifClearAction => 'Borrar';

  @override
  String get printAlertStarted => 'Impresión iniciada';

  @override
  String get printAlertResumed => 'Impresión reanudada';

  @override
  String get printAlertPaused => 'Impresión en pausa';

  @override
  String get printAlertComplete => 'Impresión completada';

  @override
  String get printAlertCancelled => 'Impresión cancelada';

  @override
  String get printAlertError => 'Error de impresora';

  @override
  String get tileOpenFiles => 'Imprimir un archivo';

  @override
  String get gcodeSheetTitle => 'Iniciar una impresión';

  @override
  String get gcodeLoading => 'Cargando archivos…';

  @override
  String get gcodeEmpty => 'No hay archivos G-code en esta impresora';

  @override
  String get gcodeError => 'No se pudieron cargar los archivos';

  @override
  String get gcodeStartButton => 'Iniciar impresión';

  @override
  String get gcodeStartAction => 'Iniciar';

  @override
  String get gcodeConfirmTitle => '¿Iniciar impresión?';

  @override
  String gcodeConfirmBody(String file) {
    return '¿Imprimir $file?';
  }

  @override
  String gcodeStarted(String file) {
    return 'Impresión de $file iniciada';
  }

  @override
  String get gcodeStartFailed => 'No se pudo iniciar la impresión';

  @override
  String get tileMacros => 'Macros';

  @override
  String get macrosSheetTitle => 'Macros';

  @override
  String get macrosLoading => 'Cargando macros…';

  @override
  String get macrosError => 'No se pudieron cargar las macros';

  @override
  String get macrosEmpty => 'No hay macros en esta impresora';

  @override
  String get macroFavourite => 'Fijar arriba';

  @override
  String get macroUnfavourite => 'Dejar de fijar';

  @override
  String get macroConfirmTitle => '¿Ejecutar macro?';

  @override
  String macroConfirmBody(String macro) {
    return '¿Ejecutar $macro en esta impresora?';
  }

  @override
  String get macroRunAction => 'Ejecutar';

  @override
  String macroSent(String macro) {
    return '$macro enviada';
  }

  @override
  String macroFailed(String macro) {
    return 'No se pudo enviar $macro';
  }

  @override
  String get preheatTitle => 'Precalentar';

  @override
  String get preheatHotend => 'Hotend';

  @override
  String get preheatBed => 'Cama';

  @override
  String get preheatHint =>
      'Deja un campo vacío para no cambiar ese calentador.';

  @override
  String get preheatSoakLabel => 'Temporizador de calentamiento';

  @override
  String get preheatSoakHelp =>
      'Avísame después de estos minutos. 0 = sin temporizador.';

  @override
  String get preheatMinutes => 'min';

  @override
  String get preheatSet => 'Aplicar';

  @override
  String get preheatNotifWarning =>
      'Los avisos de calentamiento requieren activar las notificaciones de impresión.';

  @override
  String get preheatNotifEnable => 'Activar';

  @override
  String preheatSetConfirm(String summary) {
    return '$summary aplicado';
  }

  @override
  String preheatSoakIn(int minutes) {
    return 'aviso de calentamiento en $minutes min';
  }

  @override
  String get preheatFailed => 'No se pudieron establecer las temperaturas';

  @override
  String get heatsoakDoneTitle => 'Calentamiento completado';

  @override
  String heatsoakDoneBody(String printer) {
    return '$printer está a temperatura';
  }

  @override
  String get tutorialOfferTitle => '¿Quieres un recorrido rápido?';

  @override
  String get tutorialOfferBody =>
      '¿Te gustaría ver un breve recorrido de cómo funciona Moongate?';

  @override
  String get tutorialOfferDontRemind => 'No volver a recordármelo';

  @override
  String get tutorialOfferNo => 'No, gracias';

  @override
  String get tutorialOfferStart => 'Empezar tutorial';

  @override
  String get tutorialMenuTitle => 'Tutorial de la app';

  @override
  String get tutorialNext => 'Siguiente';

  @override
  String get tutorialDone => 'Listo';

  @override
  String get tutorialSkip => 'Finalizar';

  @override
  String get tutorialBack => 'Atrás';

  @override
  String get tutorialLocalBar =>
      'La barra de color muestra cómo Moongate está llegando a esta impresora. Verde con un icono de Wi-Fi significa que estás en la misma red, una conexión local directa y rápida.';

  @override
  String get tutorialTunnelBar =>
      'Naranja con un icono de nube significa que estás fuera de casa, conectado de forma segura por internet a través del túnel de tu impresora. Moongate cambia entre ambas automáticamente.';

  @override
  String get tutorialRemoteBuilding =>
      'Cuando vinculas una impresora por primera vez, el acceso remoto no es instantáneo. Esta pequeña marca de nube significa que el túnel seguro aún se está estableciendo en segundo plano. Cuando se convierta en una nube verde con tic, podrás llegar a esta impresora desde cualquier lugar.';

  @override
  String get tutorialHotend =>
      'Este es tu hotend, la temperatura de la boquilla.';

  @override
  String get tutorialBed => 'Y esta es la cama caliente.';

  @override
  String get tutorialChamber =>
      'Si tu impresora tiene un sensor de cámara interna, su temperatura también aparece aquí.';

  @override
  String get tutorialTemps =>
      'Estas son las temperaturas en directo: el hotend (la boquilla), la cama caliente y, si tu impresora tiene un sensor de cámara interna, la cámara.';

  @override
  String get tutorialEstop =>
      'Esta es la parada de emergencia. Necesita un doble toque para activarse, así que no puede dispararse por accidente, y detiene la impresora de inmediato.';

  @override
  String get tutorialWebcam =>
      'Al tocar la vista de la cámara se abre la interfaz completa de la impresora, la pantalla en vivo de Klipper.';

  @override
  String get tutorialPreheatPress =>
      'Mantén pulsado el nombre de una impresora o sus temperaturas para mostrar el panel de precalentamiento.';

  @override
  String get tutorialPreheatSheet =>
      'Aquí puedes fijar los objetivos del hotend y la cama y un tiempo de calentamiento opcional.';

  @override
  String get tutorialAddPrinter =>
      'Toca el botón más en cualquier momento para añadir otra impresora y vincularla.';

  @override
  String get tutorialMenuIcon =>
      'Este es el menú. Puedes abrirlo en cualquier momento desde aquí.';

  @override
  String get tutorialMenuPrinters =>
      'Añade otra impresora, o quita una que ya no uses.';

  @override
  String get tutorialMenuBackup =>
      'Haz una copia de seguridad de tu configuración en un archivo, o restáurala en otro dispositivo.';

  @override
  String get tutorialMenuTheme =>
      'Elige un tema de color claro, oscuro o totalmente personalizado.';

  @override
  String get tutorialMenuDisplaySize =>
      'Arrastra esto para hacer todo más grande o más pequeño según tu vista.';

  @override
  String get tutorialMenuColumns =>
      'Distribuye tus impresoras en una, dos o tres columnas.';

  @override
  String get tutorialMenuCameras =>
      'Define con qué frecuencia se actualizan las cámaras, y enciende o apaga la cámara de cada impresora.';

  @override
  String get tutorialMenuAbout =>
      'Las novedades, cómo funciona la vinculación, una guía de iconos y dónde informar de un problema están todos aquí.';

  @override
  String get tutorialMenuSupport =>
      'Invitarme a un café ayuda a mantener Moongate gratis para todos y de código abierto.';

  @override
  String get tutorialMenuSettings =>
      'Ajustes tiene dos opciones dentro: borrar todas tus impresoras, o eliminar todos tus datos y empezar completamente de cero.';

  @override
  String get tutorialMenuLanguage =>
      'Y aquí puedes cambiar el idioma de la app - Moongate habla nueve. ¡Eso es todo el recorrido, disfruta!';

  @override
  String get notifPauseTooltip => 'Pausar supervisión';

  @override
  String get notifResumeTooltip => 'Reanudar supervisión';

  @override
  String get notifPausedSnack => 'Supervisión de impresión en pausa';

  @override
  String get notifResumedSnack => 'Supervisión de impresión reanudada';

  @override
  String get tutorialPauseButton =>
      'Esto pausa la supervisión de impresión. Cuando tus impresoras vayan a estar apagadas un tiempo, tócalo para detener las comprobaciones en segundo plano y ahorrar batería; toca de nuevo para reanudar.';
}
