// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get updateDownloading => 'Загрузка обновления…';

  @override
  String get updateOpeningInstaller => 'Открытие установщика…';

  @override
  String get updateFailed => 'Не удалось автоматически завершить обновление.';

  @override
  String get updateOpenInBrowser => 'Открыть в браузере';

  @override
  String get lightingTitle => 'Освещение';

  @override
  String get lightingMenuSubtitle => 'Управляйте подсветкой принтеров с панели';

  @override
  String get lightingBanner =>
      'Выберите, у каких принтеров есть управляемая подсветка. Для каждого включите её и задайте пару макросов «Вкл + Выкл» либо один макрос-переключатель. При желании укажите источник состояния, чтобы лампочка показывала реальное состояние.';

  @override
  String get lightingNoPrinters => 'Пока нет принтеров для настройки.';

  @override
  String get lightingShowOnTile => 'Показывать на плитке';

  @override
  String get lightingNeedMacro =>
      'Задайте пару «Вкл + Выкл» или макрос-переключатель, чтобы включить.';

  @override
  String get lightingLoadFailed =>
      'Не удалось загрузить макросы этого принтера (возможно, он не в сети). Введите имена вручную ниже.';

  @override
  String get lightingOnMacro => 'Макрос «Свет ВКЛ»';

  @override
  String get lightingOffMacro => 'Макрос «Свет ВЫКЛ»';

  @override
  String get lightingToggleMacro => 'Макрос-переключатель';

  @override
  String get lightingToggleSection => 'Необязательно — режим переключения';

  @override
  String get lightingStatusSource => 'Источник состояния света';

  @override
  String get lightingStatusSourceHelp =>
      'Необязательно. Объект Klipper (например, output_pin caselight), по значению которого Moongate определяет, включён ли свет. Оставьте пустым, чтобы отслеживать состояние по вашим нажатиям.';

  @override
  String get lightingStatusHint => 'Например: output_pin caselight';

  @override
  String get lightingNotSet => 'Не задано';

  @override
  String get lightingPickMacro => 'Выберите макрос';

  @override
  String get lightingPickStatusSource => 'Выберите источник состояния';

  @override
  String get lightingManualHint => 'Введите точное имя';

  @override
  String get lightingClear => 'Очистить';

  @override
  String get lightTurnOn => 'Включить свет';

  @override
  String get lightTurnOff => 'Выключить свет';

  @override
  String get lightToggleFailed => 'Не удалось связаться с принтером';

  @override
  String get powerTurnOn => 'Включить';

  @override
  String get powerTurnOff => 'Выключить';

  @override
  String powerConfirmOn(String name) {
    return 'Включить $name?';
  }

  @override
  String powerConfirmOff(String name) {
    return 'Выключить $name?';
  }

  @override
  String get powerToggleFailed => 'Не удалось изменить питание';

  @override
  String get powerLockedWhilePrinting => 'Нельзя выключить во время печати';

  @override
  String get powerScreenTitle => 'Расширенный выключатель питания';

  @override
  String get powerScreenBanner =>
      'Для принтеров, питание которых задаётся макросом Klipper, а не устройством питания Moonraker. Включите и выберите пару «Вкл + Выкл» или один макрос переключения — кнопка питания на плитке будет использовать их.';

  @override
  String get powerUseSwitch => 'Использовать макросы';

  @override
  String get powerNeedMacro =>
      'Задайте пару «Вкл + Выкл» или макрос переключения.';

  @override
  String get powerOnMacro => 'Макрос включения';

  @override
  String get powerOffMacro => 'Макрос выключения';

  @override
  String get powerToggleSection => 'Или один макрос переключения';

  @override
  String get powerToggleMacro => 'Макрос переключения питания';

  @override
  String get powerMenuTitle => 'Расширенный выключатель питания';

  @override
  String get powerMenuSubtitle => 'Управление питанием принтера через макрос';

  @override
  String get powerMacroTooltip => 'Питание';

  @override
  String powerMacroToggleConfirm(String name) {
    return 'Переключить питание $name?';
  }

  @override
  String powerMacroChooseTitle(String name) {
    return 'Переключить питание $name';
  }

  @override
  String lightChooseTitle(String name) {
    return 'Переключить свет $name';
  }

  @override
  String get tileOpacityTitle => 'Непрозрачность плиток';

  @override
  String get tileOpacityDesc =>
      'Насколько прозрачны плитки (0–100), чтобы просвечивал фон. Изображение с камеры остаётся непрозрачным.';

  @override
  String get dashboardShowWebcams => 'Веб-камеры';

  @override
  String get dashboardShowWebcamsSubtitle =>
      'Показать или скрыть веб-камеру каждого принтера';

  @override
  String get updateNotesUnavailable =>
      'Не удалось загрузить список изменений — проверьте подключение или посмотрите на GitHub.';

  @override
  String get updateViewOnGithub => 'Посмотреть на GitHub';

  @override
  String get cameraConfigTooltip => 'Указать URL камеры';

  @override
  String get cameraConfigTitle => 'Своя камера';

  @override
  String get cameraConfigDescription =>
      'Показать камеру, не подключённую к Klipper, — например, старый телефон в роли веб-камеры. Введите адрес, указанный в настройках веб-камеры Mainsail.';

  @override
  String get cameraConfigUrlLabel => 'URL камеры';

  @override
  String get cameraConfigRemoteNote =>
      'Работает по Wi-Fi и удалённо через ваш принтер. Удалённо доступны только камеры в домашней сети (частные адреса).';

  @override
  String get cameraConfigInvalid =>
      'Введите полный адрес, например http://192.168.0.107:8080/video';

  @override
  String get cameraConfigUseDefault => 'Камера Klipper';

  @override
  String get cameraConfigApply => 'Применить';

  @override
  String get dashboardShowCameraIcons => 'Значки настройки камеры';

  @override
  String get dashboardShowCameraIconsSubtitle =>
      'Показывать шестерёнку на каждой камере для своего URL';

  @override
  String get appTitle => 'Moongate';

  @override
  String get languagePickerTitle => 'Выберите язык';

  @override
  String get languagePickerSubtitle =>
      'Вы можете изменить его в любой момент в меню.';

  @override
  String get languagePickerContinue => 'Продолжить';

  @override
  String get menuLanguage => 'Язык';

  @override
  String get languageSystemDefault => 'Системный язык';

  @override
  String get commonCancel => 'Отмена';

  @override
  String get commonOk => 'ОК';

  @override
  String get commonClose => 'Закрыть';

  @override
  String get commonSave => 'Сохранить';

  @override
  String get commonDone => 'Готово';

  @override
  String get commonRetry => 'Повторить';

  @override
  String get commonShowKeyboard => 'Показать клавиатуру';

  @override
  String get dashboardSignInRetrying =>
      'Повторное подключение к облаку — вход занят, повтор. Принтеры вернутся автоматически.';

  @override
  String get commonRemove => 'Удалить';

  @override
  String get commonDelete => 'Удалить';

  @override
  String get commonEnable => 'Включить';

  @override
  String get commonDisable => 'Выключить';

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get settingsRemoveAllTitle =>
      'Удалить все принтеры с этого устройства';

  @override
  String get settingsRemoveAllSubtitle =>
      'Очищает локальный кэш принтеров. Ваш аккаунт Supabase сохраняется, поэтому повторное сопряжение пройдёт без проблем.';

  @override
  String get settingsRemoveAllConfirmTitle => 'Удалить все принтеры?';

  @override
  String get settingsRemoveAllConfirmBody =>
      'Все сопряжённые принтеры будут удалены с этого устройства. Вы можете добавить их снова, выполнив MOONGATE_PAIR на принтере.';

  @override
  String get settingsRemoveAllConfirmAction => 'Удалить все';

  @override
  String get dashboardAddPrinter => 'Добавить принтер';

  @override
  String get dashboardRemovePrinter => 'Удалить принтер';

  @override
  String get dashboardMenuTooltip => 'Меню';

  @override
  String get dashboardRemovePrinterTitle => 'Удалить принтер?';

  @override
  String dashboardRemovePrinterBody(String name) {
    return 'Удалить «$name» из Moongate?';
  }

  @override
  String get dashboardRemoveSupabaseUnreachable =>
      'Удалено локально, но не удалось связаться с Supabase. Если повторное сопряжение не получится, выполните MOONGATE_RESET_OWNER на Pi.';

  @override
  String get dashboardBackUpConfig => 'Резервная копия';

  @override
  String get dashboardBackUpConfigSubtitle =>
      'Сохраните в файл перед переустановкой';

  @override
  String get dashboardRestoreConfig => 'Восстановить';

  @override
  String get dashboardRestoreConfigSubtitle =>
      'Загрузить из файла резервной копии';

  @override
  String get dashboardThemeHeading => 'Тема';

  @override
  String get dashboardThemeSystem => 'Системная';

  @override
  String get dashboardThemeDark => 'Тёмная';

  @override
  String get dashboardThemeLight => 'Светлая';

  @override
  String get dashboardThemeCustom => 'Своя';

  @override
  String get dashboardCustomiseColours => 'Настроить цвета';

  @override
  String get dashboardCustomiseColoursSubtitle =>
      'Измените пять цветов темы — HEX или палитра';

  @override
  String get dashboardFontSizeHeading => 'Размер шрифта';

  @override
  String get dashboardLayoutHeading => 'Вид панели';

  @override
  String dashboardColumnCount(int count) {
    return '$count стлб.';
  }

  @override
  String get dashboardRotateWithDevice => 'Поворот с устройством';

  @override
  String get dashboardRotateWithDeviceSubtitle =>
      'Разблокирует альбомную ориентацию';

  @override
  String get dashboardAutoArrange => 'Автосортировка по статусу';

  @override
  String get dashboardAutoArrangeSubtitle =>
      'Сортировать плитки по активности. Выключите, чтобы перетаскивать их в своём порядке.';

  @override
  String get dashboardReorderHint =>
      'Удерживайте и перетащите плитку, чтобы изменить порядок';

  @override
  String get dashboardReorderStart => 'Изменить порядок';

  @override
  String get dashboardReorderDone => 'Готово';

  @override
  String get dashboardCameraFeedHeading => 'Камера на панели';

  @override
  String get dashboardCameraFeedSubtitle =>
      'Как часто плитки обновляют камеру. Меньшая частота заметно экономит трафик.';

  @override
  String get cameraFeedsMenuTitle => 'Камеры на панели';

  @override
  String get cameraFeedsMenuSubtitle =>
      'Частоты локального и туннельного потоков';

  @override
  String get cameraFeedsIntro =>
      'Как часто каждая плитка обновляет изображение с камеры. Moongate использует локальную частоту, пока вы в Wi-Fi (даже вне дома), и тоннельную частоту при мобильном интернете — чтобы поток оставался быстрым по Wi-Fi и был экономнее по мобильным данным.';

  @override
  String get cameraFeedsLocalRate => 'Частота локального потока';

  @override
  String get cameraFeedsTunnelRate => 'Частота туннельного потока';

  @override
  String get dashboardAboutHeading => 'О приложении';

  @override
  String get dashboardWhatsNew => 'Что нового';

  @override
  String get dashboardWhatsNewSubtitle => 'Последние изменения вкратце';

  @override
  String get dashboardHowPairingWorks => 'Как работает сопряжение';

  @override
  String get dashboardHowPairingWorksSubtitle =>
      'Сопряжение, переустановка и восстановление';

  @override
  String get dashboardReportProblem => 'Сообщить о проблеме';

  @override
  String get dashboardReportProblemSubtitle =>
      'Отправить отчёт об ошибке или отзыв';

  @override
  String get dashboardAppLock => 'Блокировка приложения';

  @override
  String get dashboardAppLockOn => 'Вкл. — разблокировка нужна при запуске';

  @override
  String get dashboardAppLockOff => 'Выкл.';

  @override
  String get dashboardBuyMeCoffee => 'Купить мне кофе';

  @override
  String get dashboardBuyMeCoffeeSubtitle =>
      'Поддержать разработчика через PayPal';

  @override
  String get donationPromptTitle => 'Нравится Moongate?';

  @override
  String get donationPromptBody =>
      'Moongate — это бесплатный личный проект, который я делаю в свободное время. Если он вам полезен, небольшой донат помогает развивать его — без всякого давления, и я спрошу только один раз.';

  @override
  String get donationPromptLater => 'Может позже';

  @override
  String get dashboardSettings => 'Настройки';

  @override
  String dashboardVersion(String version) {
    return 'Moongate v$version';
  }

  @override
  String get dashboardSaveBackupDialogTitle =>
      'Сохранить резервную копию Moongate';

  @override
  String get dashboardBackupFailed =>
      'Не удалось создать резервную копию — файл не сохранён.';

  @override
  String dashboardBackupSuccess(int count) {
    return 'Создана резервная копия принтеров: $count. Этим файлом можно восстановить их после переустановки — храните его в тайне.';
  }

  @override
  String dashboardBackupSuccessListOnly(int count) {
    return 'Создана резервная копия принтеров: $count (только список — не удалось получить код восстановления из облака).';
  }

  @override
  String get dashboardInvalidBackupFile =>
      'Неверный файл резервной копии — выберите файл конфигурации Moongate.';

  @override
  String dashboardRestoreReconnected(int added, int count) {
    return 'Восстановлено принтеров: $added — $count переподключились и снова выходят на связь.';
  }

  @override
  String dashboardRestoreNoneReconnected(int added) {
    return 'Восстановлено принтеров: $added, но ни один не переподключился — код восстановления из резервной копии не подошёл ни к одному принтеру (возможно, он из более старой копии или уже использован). Выполните повторное сопряжение, чтобы вернуть их в сеть.';
  }

  @override
  String dashboardRestoreListOnly(int added) {
    return 'Восстановлено принтеров: $added (только список). Выполните повторное сопряжение каждого принтера, чтобы вернуть его в сеть.';
  }

  @override
  String get dashboardRestoreApplied =>
      'Панель восстановлена в соответствии с резервной копией.';

  @override
  String get dashboardRestoreReplaceTitle => 'Заменить панель?';

  @override
  String dashboardRestoreReplaceBody(String names) {
    return 'Эти принтеры есть на этой панели, но отсутствуют в резервной копии: $names. При восстановлении они будут удалены, чтобы панель точно соответствовала копии. Они останутся привязанными — вы сможете добавить или восстановить их позже.';
  }

  @override
  String get dashboardRestoreReplaceConfirm => 'Заменить';

  @override
  String get dashboardRemoveSheetTitle => 'Удалить принтер';

  @override
  String dashboardPrinterIdShort(String id) {
    return 'id $id…';
  }

  @override
  String get dashboardPairingHelpPairOnceTitle => 'Сопряжение — один раз';

  @override
  String get dashboardPairingHelpPairOnceBody =>
      'Отсканируйте QR (или введите GATE code), чтобы добавить принтер — эта связь сохраняется в приложении.';

  @override
  String get dashboardPairingHelpUpdatesTitle =>
      'Обновления сохраняют ваши принтеры';

  @override
  String get dashboardPairingHelpUpdatesBody =>
      'Обновление Moongate никогда не требует повторного сопряжения.';

  @override
  String get dashboardPairingHelpReinstallTitle =>
      'Переустановка или новый телефон?';

  @override
  String get dashboardPairingHelpReinstallBody =>
      'Сначала создайте резервную копию (Меню → Резервная копия), затем «Восстановить» вернёт принтеры в сеть — без повторного сопряжения.';

  @override
  String get dashboardPairingHelpNoBackupTitle => 'Нет резервной копии?';

  @override
  String get dashboardPairingHelpNoBackupBody =>
      'Выполните MOONGATE_RESET_OWNER в консоли принтера, затем выполните сопряжение заново.';

  @override
  String get dashboardDontShowAgain => 'Больше не показывать';

  @override
  String dashboardUpdateAvailable(String version) {
    return 'Доступно обновление — v$version';
  }

  @override
  String get dashboardUpdateLater => 'Позже';

  @override
  String get dashboardUpdate => 'Обновить';

  @override
  String get dashboardEmptyTitle => 'Принтеры ещё не добавлены';

  @override
  String get dashboardEmptyBody =>
      'Нажмите кнопку ниже, чтобы выполнить сопряжение первого принтера.';

  @override
  String get pairingTitle => 'Добавить принтер';

  @override
  String get pairingIntro =>
      'Выполните MOONGATE_PAIR в консоли Klipper — отсканируйте QR или введите GATE code, показанный в консоли.';

  @override
  String get pairingNameLabel => 'Название принтера';

  @override
  String get pairingNameHint => 'например, Voron 2.4';

  @override
  String get pairingScanButton => 'Сканировать QR-код';

  @override
  String get pairingScanRecommended => 'Рекомендуется — подключается мгновенно';

  @override
  String get pairingOr => 'ИЛИ';

  @override
  String get pairingGateCodeLabel => 'GATE code';

  @override
  String get pairingGateCodeHint =>
      'Введите 8-значный код, показанный в консоли Klipper.';

  @override
  String get pairingGateCodeValid => 'Код выглядит верно ✓';

  @override
  String get pairingGateCodeWarning =>
      'Альтернативный способ. Без QR принтер может подключаться примерно до минуты — он ожидает установления защищённого туннеля. Для мгновенного подключения отсканируйте QR-код выше.';

  @override
  String get pairingCameraPermissionNeeded => 'Требуется доступ к камере';

  @override
  String get pairingCameraUnavailable => 'Камера недоступна';

  @override
  String get pairingCancelScan => 'Отменить сканирование';

  @override
  String pairingQrScanned(String code) {
    return 'QR отсканирован — код $code';
  }

  @override
  String get pairingRescan => 'Сканировать снова';

  @override
  String get pairingAdvancedTitle => 'Дополнительно — принтер в особой сети?';

  @override
  String get pairingAdvancedBody =>
      'Большинству можно оставить это поле пустым. Если ваш принтер за обратным прокси (Traefik, Caddy, NPM) или в Docker, введите тот же адрес, по которому открываете его веб-страницу (Mainsail / Fluidd) в браузере.';

  @override
  String get pairingAddressLabel => 'Адрес принтера';

  @override
  String get pairingAddressHint => '192.168.1.50:7125';

  @override
  String get pairingPairButton => 'Сопрячь принтер';

  @override
  String get pairingRestoreHint =>
      'Переустанавливаете? Восстановите сохранённые принтеры из файла резервной копии. Каждый из них всё равно потребуется сопрячь заново, чтобы вернуть в сеть.';

  @override
  String get pairingImportButton => 'Импортировать конфигурацию из файла';

  @override
  String get pairingReportButton => 'Проблемы с сопряжением? Отправить отчёт';

  @override
  String get pairingCameraPermissionTitle => 'Требуется доступ к камере';

  @override
  String get pairingCameraPermissionBody =>
      'Moongate нужен доступ к камере для сканирования QR-кодов.\n\nОткройте Настройки → Приложения → Moongate → Разрешения и включите Камеру, затем вернитесь и попробуйте снова.';

  @override
  String get pairingOpenSettings => 'Открыть настройки';

  @override
  String get pairingErrorNotMoongateQr =>
      'Это не QR-код Moongate. Выполните MOONGATE_PAIR на принтере, чтобы создать его.';

  @override
  String get pairingErrorOldQr =>
      'Этот QR-код от более старой версии Moongate. Сначала обновите Pi до v0.3.0.';

  @override
  String get pairingErrorNoCode =>
      'Отсканируйте QR-код или введите GATE code из консоли принтера.';

  @override
  String get pairingErrorBadAddress =>
      'Этот адрес принтера выглядит неверно — попробуйте, например, 192.168.1.50:7125';

  @override
  String pairingErrorFailed(String error) {
    return 'Сбой сопряжения: $error';
  }

  @override
  String get pairingImportInvalidFile =>
      'Неверный файл резервной копии — выберите файл конфигурации Moongate.';

  @override
  String get pairingImportNoNewPrinters =>
      'В этом файле не найдено новых принтеров.';

  @override
  String pairingImportRestoredReconnected(int count, int reconnected) {
    return 'Восстановлено принтеров: $count — $reconnected переподключились и выходят на связь.';
  }

  @override
  String pairingImportRestoredRepair(int count) {
    return 'Восстановлено принтеров: $count — выполните повторное сопряжение каждого Pi, чтобы вернуть его в сеть.';
  }

  @override
  String get customThemeTitle => 'Своя тема';

  @override
  String get customThemeResetTooltip => 'Сбросить к значениям по умолчанию';

  @override
  String get customThemeResetConfirmTitle => 'Сбросить свою тему?';

  @override
  String get customThemeResetConfirmBody =>
      'Все пять цветов будут возвращены к стандартной палитре «фиолетовый на тёмном».';

  @override
  String get customThemeReset => 'Сбросить';

  @override
  String get customThemePreview => 'Предпросмотр';

  @override
  String get customThemeAccent => 'Акцент';

  @override
  String get customThemeAccentDesc =>
      'Кнопки, FAB, индикаторы прогресса, ссылки';

  @override
  String get customThemeBackground => 'Фон страницы';

  @override
  String get customThemeBackgroundDesc => 'Позади каждого экрана';

  @override
  String get customThemeSurface => 'Карточки и плитки';

  @override
  String get customThemeSurfaceDesc => 'Плитки панели, шторки, боковое меню';

  @override
  String get customThemeText => 'Текст';

  @override
  String get customThemeTextDesc =>
      'Основной текст и заголовки на поверхностях';

  @override
  String get customThemeError => 'Ошибка / Стоп';

  @override
  String get customThemeErrorDesc => 'Необратимые действия, наложения ошибок';

  @override
  String get customThemeEstop => 'Кнопка аварийной остановки';

  @override
  String get customThemeEstopDesc => 'Кольцо и значок аварийной остановки';

  @override
  String get customThemePresets => 'Пресеты';

  @override
  String get customThemeInvalidHex => 'Недопустимый шестнадцатеричный цвет';

  @override
  String get customThemeSamplePrinter => 'Пример принтера';

  @override
  String get customThemePrinting => 'Печать';

  @override
  String get tilePauseFailed =>
      'Не удалось связаться с принтером — пауза не выполнена';

  @override
  String get tileResumeFailed =>
      'Не удалось связаться с принтером — возобновление не выполнено';

  @override
  String get tileStopAgainToCancel =>
      'Нажмите СТОП ещё раз, чтобы отменить печать';

  @override
  String get tileLocal => 'Локально';

  @override
  String get tileTunnel => 'Туннель';

  @override
  String get tilePrinting => 'Печать';

  @override
  String get tilePaused => 'Пауза';

  @override
  String get tileResume => 'Возобновить';

  @override
  String get tilePause => 'Пауза';

  @override
  String get tileConfirmStop => 'Подтвердить остановку';

  @override
  String get tileStopPrint => 'Остановить печать';

  @override
  String get tileFirmwareRestart => 'Перезапуск прошивки';

  @override
  String get tileEmergencyStop => 'Аварийная остановка · двойное нажатие';

  @override
  String get tileEmergencyStopFailed =>
      'Не удалось связаться с принтером — аварийная остановка не выполнена';

  @override
  String get tilePrintComplete => 'Печать завершена';

  @override
  String get tilePrintCancelled => 'Печать отменена';

  @override
  String get tilePrinterError => 'Ошибка принтера';

  @override
  String get tileKlipperStarting => 'Klipper запускается';

  @override
  String get tileReady => 'Готов';

  @override
  String get tileOffline => 'Не в сети';

  @override
  String get tileStartingUp => 'Запуск…';

  @override
  String get tileConnected => 'Подключено';

  @override
  String get tileConnecting => 'Подключение…';

  @override
  String get tilePrinterUnreachable => 'Принтер недоступен';

  @override
  String get tileWaitingForHeartbeat => 'Ожидание первого сигнала';

  @override
  String get tilePrinterIdle => 'Принтер бездействует';

  @override
  String get tileReachingPrinter => 'Связь с принтером';

  @override
  String get tileRemoteReady => 'Удалённый доступ готов';

  @override
  String get tileRemoteConnecting => 'Удалённое подключение…';

  @override
  String get tileIdle => 'Ожидание';

  @override
  String get tileDone => 'Готово';

  @override
  String get tileCancelled => 'Отменено';

  @override
  String get tileClearJobTooltip => 'Очистить и вернуть в ожидание';

  @override
  String get tileClearJobFailed => 'Не удалось сбросить принтер';

  @override
  String get dashboardBackgroundTitle => 'Фон панели';

  @override
  String get dashboardBackgroundNone => 'Нет — цвет темы';

  @override
  String get dashboardBackgroundCustom => 'Своё изображение';

  @override
  String get dashboardBackgroundRemove => 'Убрать фон';

  @override
  String get dashboardBackgroundSet => 'Фон обновлён';

  @override
  String get uiGuideSectionTileButtons => 'Кнопки плитки';

  @override
  String get uiGuideFilesTitle => 'Печать файла';

  @override
  String get uiGuideFilesDesc =>
      'Просмотрите файлы G-code на принтере и запустите один из них.';

  @override
  String get uiGuideMacrosTitle => 'Макросы';

  @override
  String get uiGuideMacrosDesc =>
      'Запустите один из макросов Klipper принтера.';

  @override
  String get uiGuidePowerTitle => 'Питание';

  @override
  String get uiGuidePowerDesc =>
      'Включите или выключите принтер, если у него есть устройство питания.';

  @override
  String get uiGuideLightingTitle => 'Освещение';

  @override
  String get uiGuideLightingDesc =>
      'Переключите подсветку принтера; лампочка горит, когда она включена.';

  @override
  String get uiGuideCameraViewTitle => 'Камера';

  @override
  String get uiGuideCameraViewDesc => 'Откройте камеру в полноэкранном режиме.';

  @override
  String get uiGuideCameraSetupTitle => 'Настройка камеры';

  @override
  String get uiGuideCameraSetupDesc =>
      'Направьте плитку на камеру, не подключённую к Klipper.';

  @override
  String get uiGuideClearJobTitle => 'Очистить завершённую печать';

  @override
  String get uiGuideClearJobDesc =>
      'Нажмите × на плитке «Готово» или «Отменено», чтобы вернуть её в ожидание.';

  @override
  String get tileError => 'Ошибка';

  @override
  String get tileStarting => 'Запуск';

  @override
  String get tileConnectingBadge => 'Подключение';

  @override
  String get appLockTitle => 'Блокировка приложения';

  @override
  String get appLockIntro =>
      'Требовать PIN-код — и при желании отпечаток пальца или лицо — перед открытием Moongate. Блокировка всегда появляется при новом запуске приложения.';

  @override
  String get appLockSubtitle => 'PIN-код нужен для открытия приложения';

  @override
  String get appLockBiometricTitle => 'Биометрическая разблокировка';

  @override
  String get appLockBiometricSubtitle =>
      'Используйте отпечаток или лицо — PIN-код остаётся запасным';

  @override
  String get appLockChangePin => 'Изменить PIN-код';

  @override
  String get appLockAutoLock => 'Автоблокировка';

  @override
  String get appLockPinUpdated => 'PIN-код обновлён';

  @override
  String get appLockChoosePinTitle => 'Задайте PIN-код';

  @override
  String get appLockChoosePinSubtitle => 'Введите 4–6 цифр';

  @override
  String get appLockConfirmPinTitle => 'Подтвердите PIN-код';

  @override
  String get appLockPinsDontMatch => 'PIN-коды не совпадают';

  @override
  String get appLockEnterCurrentPin => 'Введите текущий PIN-код';

  @override
  String get appLockTimeoutImmediately => 'Сразу';

  @override
  String get appLockTimeoutOneMinute => 'Через 1 минуту';

  @override
  String get appLockTimeoutFiveMinutes => 'Через 5 минут';

  @override
  String get appLockTimeoutFifteenMinutes => 'Через 15 минут';

  @override
  String get appLockTimeoutColdLaunch => 'Только при запуске приложения';

  @override
  String get lockEnterPin => 'Введите PIN-код';

  @override
  String get lockSubtitle => 'Moongate заблокирован';

  @override
  String lockTooManyAttempts(int seconds) {
    return 'Слишком много попыток. Повторите через $seconds с';
  }

  @override
  String get lockWrongPin => 'Неверный PIN-код';

  @override
  String get lockUseBiometrics => 'Использовать биометрию';

  @override
  String get lockForgotPin => 'Забыли PIN-код?';

  @override
  String get lockBiometricReason => 'Разблокировать Moongate';

  @override
  String get lockResetTitle => 'Сбросить Moongate?';

  @override
  String get lockResetBody =>
      'Это снимет блокировку приложения и удалит сопряжённые принтеры с этого устройства, чтобы начать заново. Ваши принтеры не удаляются — выполните их повторное сопряжение, запустив MOONGATE_PAIR на каждом.';

  @override
  String get lockResetConfirm => 'Сбросить';

  @override
  String get pinContinue => 'Продолжить';

  @override
  String printerStartingUpRetry(int seconds) {
    return 'Принтер запускается. Повтор через $seconds с…';
  }

  @override
  String printerCouldNotReach(String error) {
    return 'Не удалось связаться с принтером: $error';
  }

  @override
  String get printerAddressCleared => 'Свой адрес сброшен';

  @override
  String get printerAddressUpdated => 'Адрес принтера обновлён';

  @override
  String printerTunnelUnreachable(String description) {
    return 'Туннель Cloudflare недоступен.\n$description';
  }

  @override
  String get printerEdit => 'Изменить принтер';

  @override
  String get printerLocalNetwork => 'Локальная сеть';

  @override
  String get printerTunnelVia => 'Туннель через Moongate';

  @override
  String get printerCameraTooltip => 'Камера';

  @override
  String get cameraConnecting => 'Подключение к камере…';

  @override
  String get cameraNoCamera => 'Для этого принтера камера не настроена.';

  @override
  String get cameraHintBody =>
      'Веб-камера не загружается здесь удалённо — откройте камеру Moongate.';

  @override
  String get cameraHintOpen => 'Открыть';

  @override
  String get printerUnreachable => 'Принтер недоступен';

  @override
  String get printerUseTunnel => 'Использовать туннель';

  @override
  String get printerAddressInvalid => 'Попробуйте, например, 192.168.1.50:7125';

  @override
  String get printerNameLabel => 'Название принтера';

  @override
  String get printerAddressLabel => 'Адрес принтера (дополнительно)';

  @override
  String get printerAddressHint => '192.168.1.50:7125';

  @override
  String get printerAddressHelper =>
      'Только для конфигураций с обратным прокси / Docker. Оставьте пустым, чтобы использовать автоматическое обнаружение.';

  @override
  String get feedbackTitle => 'Сообщить о проблеме';

  @override
  String get feedbackTroublePairing => 'Проблемы с сопряжением?';

  @override
  String get feedbackDescription =>
      'Расскажите, что происходит. Версия приложения, устройство, сеть и данные принтера прикрепляются автоматически, чтобы помочь нам разобраться.';

  @override
  String get feedbackPairingDescription =>
      'Опишите, что происходит при попытке добавить принтер. Данные о вашей сети и обнаружении прикрепляются автоматически, чтобы мы видели, почему он не подключается.';

  @override
  String get feedbackWhichPrinter => 'Какой принтер? (необязательно)';

  @override
  String get feedbackGeneralOption => 'Общее / не привязано к принтеру';

  @override
  String get feedbackCommentLabel => 'Что пошло не так?';

  @override
  String get feedbackCommentHint =>
      'например, «Принтер показывает Подключено / ожидание, но на самом деле он готов — открывается нормально при нажатии на плитку.»';

  @override
  String get feedbackContactLabel => 'Email или контакт (необязательно)';

  @override
  String get feedbackContactHint => 'Только если хотите получить ответ';

  @override
  String get feedbackSending => 'Отправка…';

  @override
  String get feedbackSend => 'Отправить отчёт';

  @override
  String get feedbackSuccess => 'Спасибо — ваш отчёт отправлен.';

  @override
  String get feedbackError =>
      'Не удалось отправить — проверьте подключение и попробуйте снова.';

  @override
  String get splashTagline => 'Удалённое управление Klipper';

  @override
  String get uiGuideTitle => 'Описание значков';

  @override
  String get uiGuideMenuSubtitle => 'Что означают значки на панели';

  @override
  String get uiGuideIntro =>
      'Краткое описание значков, которые вы увидите на панели.';

  @override
  String get uiGuideSectionConnection => 'Подключение';

  @override
  String get uiGuideSectionTemperatures => 'Температуры';

  @override
  String get uiGuideSectionControls => 'Управление печатью';

  @override
  String get uiGuideSectionStatus => 'Статус';

  @override
  String get uiGuideSectionWebcam => 'Камера и подключение';

  @override
  String get uiGuideLocalTitle => 'Локальная сеть';

  @override
  String get uiGuideLocalDesc =>
      'Подключено напрямую через вашу Wi-Fi — самый быстрый путь.';

  @override
  String get uiGuideTunnelTitle => 'Удалённо (туннель)';

  @override
  String get uiGuideTunnelDesc =>
      'Подключено откуда угодно через защищённый туннель Cloudflare.';

  @override
  String get uiGuideTunnelReadyTitle => 'Удалённый доступ готов';

  @override
  String get uiGuideTunnelReadyDesc =>
      'Туннель поднят, поэтому удалённый доступ доступен.';

  @override
  String get uiGuideTunnelConnectingTitle => 'Удалённое подключение';

  @override
  String get uiGuideTunnelConnectingDesc =>
      'Удалённый туннель ещё устанавливается.';

  @override
  String get uiGuideHotendTitle => 'Хотэнд / сопло';

  @override
  String get uiGuideHotendDesc => 'Текущая температура сопла.';

  @override
  String get uiGuideBedTitle => 'Подогреваемый стол';

  @override
  String get uiGuideBedDesc => 'Текущая температура стола.';

  @override
  String get uiGuideChamberTitle => 'Камера';

  @override
  String get uiGuideChamberDesc =>
      'Температура камеры — показывается, только если ваш принтер её сообщает.';

  @override
  String get uiGuideResumeTitle => 'Возобновить';

  @override
  String get uiGuideResumeDesc => 'Возобновить приостановленную печать.';

  @override
  String get uiGuidePauseTitle => 'Пауза';

  @override
  String get uiGuidePauseDesc => 'Приостановить текущую печать.';

  @override
  String get uiGuideStopTitle => 'Стоп';

  @override
  String get uiGuideStopDesc =>
      'Отменить печать — нажмите дважды для подтверждения.';

  @override
  String get uiGuideFirmwareRestartTitle => 'Перезапуск прошивки';

  @override
  String get uiGuideFirmwareRestartDesc =>
      'Перезапустить Klipper, когда принтер бездействует или в состоянии ошибки.';

  @override
  String get uiGuideStatusReadyTitle => 'Готов / завершено';

  @override
  String get uiGuideStatusReadyDesc =>
      'Принтер бездействует или завершил последнюю печать.';

  @override
  String get uiGuideStatusCancelledTitle => 'Отменено';

  @override
  String get uiGuideStatusCancelledDesc => 'Последняя печать была отменена.';

  @override
  String get uiGuideStatusErrorTitle => 'Ошибка';

  @override
  String get uiGuideStatusErrorDesc =>
      'Klipper сообщил об ошибке — откройте принтер для подробностей.';

  @override
  String get uiGuideStatusStartingTitle => 'Запуск';

  @override
  String get uiGuideStatusStartingDesc =>
      'Klipper запускается; элементы управления появятся, когда он будет готов.';

  @override
  String get uiGuideOfflineTitle => 'Не в сети';

  @override
  String get uiGuideOfflineDesc => 'Сейчас не удаётся связаться с принтером.';

  @override
  String get uiGuideNoWebcamTitle => 'Нет камеры';

  @override
  String get uiGuideNoWebcamDesc =>
      'Для этого принтера нет снимка с веб-камеры.';

  @override
  String get uiGuideBack => 'Назад к панели';

  @override
  String get printNotifTitle => 'Уведомления о печати';

  @override
  String get printNotifSubtitle =>
      'Прогресс и статус в реальном времени, когда приложение свёрнуто';

  @override
  String get printNotifPermissionNeeded =>
      'Разрешите уведомления, чтобы включить это.';

  @override
  String get printNotifPromptTitle => 'Получать уведомления о печати?';

  @override
  String get printNotifPromptBody =>
      'Смотрите статус принтеров в реальном времени — прогресс, температуры и оповещения о начале, завершении или ошибке печати. Это можно изменить в любой момент в меню.';

  @override
  String get printNotifPromptEnable => 'Включить';

  @override
  String get printNotifPromptNotNow => 'Не сейчас';

  @override
  String get printNotifWatching => 'Отслеживание принтеров…';

  @override
  String get printNotifNoPrinters => 'Нет принтеров';

  @override
  String get notifPollIntervalTitle => 'Частота обновления';

  @override
  String get notifContentTitle => 'Содержимое уведомления';

  @override
  String get notifContentSubtitle => 'Выберите и измените порядок';

  @override
  String get notifContentIntro =>
      'Выберите, какие данные показывать в уведомлении о печати, и перетащите их в нужном порядке.';

  @override
  String get notifContentPreview => 'Предпросмотр';

  @override
  String get notifFieldProgress => 'Прогресс';

  @override
  String get notifFieldRemaining => 'Осталось времени';

  @override
  String get notifFieldEta => 'Время окончания';

  @override
  String get notifFieldHotend => 'Темп. сопла';

  @override
  String get notifFieldBed => 'Темп. стола';

  @override
  String get printAlertReady => 'Принтер готов';

  @override
  String get printStatusReady => 'Готов';

  @override
  String get printStatusHeating => 'Нагрев';

  @override
  String get printStatusIdle => 'Ожидание';

  @override
  String get printStatusOffline => 'Офлайн';

  @override
  String get printStatusPaused => 'Пауза';

  @override
  String get printStatusComplete => 'Завершено';

  @override
  String get printStatusCancelled => 'Отменено';

  @override
  String get printStatusError => 'Ошибка';

  @override
  String get printStatusStartingUp => 'Запуск…';

  @override
  String get printAlertStarted => 'Печать начата';

  @override
  String get printAlertResumed => 'Печать возобновлена';

  @override
  String get printAlertPaused => 'Печать приостановлена';

  @override
  String get printAlertComplete => 'Печать завершена';

  @override
  String get printAlertCancelled => 'Печать отменена';

  @override
  String get printAlertError => 'Ошибка принтера';

  @override
  String get tileOpenFiles => 'Печать файла';

  @override
  String get gcodeSheetTitle => 'Начать печать';

  @override
  String get gcodeLoading => 'Загрузка файлов…';

  @override
  String get gcodeEmpty => 'На этом принтере нет файлов G-code';

  @override
  String get gcodeError => 'Не удалось загрузить файлы';

  @override
  String get gcodeStartButton => 'Начать печать';

  @override
  String get gcodeStartAction => 'Начать';

  @override
  String get gcodeConfirmTitle => 'Начать печать?';

  @override
  String gcodeConfirmBody(String file) {
    return 'Напечатать $file?';
  }

  @override
  String gcodeStarted(String file) {
    return 'Печать $file начата';
  }

  @override
  String get gcodeStartFailed => 'Не удалось начать печать';

  @override
  String get tileMacros => 'Макросы';

  @override
  String get macrosSheetTitle => 'Макросы';

  @override
  String get macrosLoading => 'Загрузка макросов…';

  @override
  String get macrosError => 'Не удалось загрузить макросы';

  @override
  String get macrosEmpty => 'На этом принтере нет макросов';

  @override
  String get macroFavourite => 'Закрепить вверху';

  @override
  String get macroUnfavourite => 'Открепить';

  @override
  String get macroConfirmTitle => 'Выполнить макрос?';

  @override
  String macroConfirmBody(String macro) {
    return 'Выполнить $macro на этом принтере?';
  }

  @override
  String get macroRunAction => 'Выполнить';

  @override
  String macroSent(String macro) {
    return '$macro отправлен';
  }

  @override
  String macroFailed(String macro) {
    return 'Не удалось отправить $macro';
  }
}
