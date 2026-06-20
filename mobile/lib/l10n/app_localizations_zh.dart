// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get updateDownloading => '正在下载更新…';

  @override
  String get updateOpeningInstaller => '正在打开安装程序…';

  @override
  String get updateFailed => '无法自动完成更新。';

  @override
  String get updateOpenInBrowser => '在浏览器中打开';

  @override
  String get lightingTitle => '照明';

  @override
  String get lightingMenuSubtitle => '在仪表板上控制打印机的照明';

  @override
  String get lightingBanner =>
      '选择哪些打印机有可控制的灯。为每台打印机开启并设置“开 + 关”宏对，或单个“切换”宏。也可选择一个状态来源，让灯泡显示真实的开关状态。';

  @override
  String get lightingNoPrinters => '暂无可设置的打印机。';

  @override
  String get lightingShowOnTile => '在磁贴上显示';

  @override
  String get lightingNeedMacro => '设置“开 + 关”宏对或一个“切换”宏以启用。';

  @override
  String get lightingLoadFailed => '无法加载此打印机的宏（可能已离线）。请在下方手动输入名称。';

  @override
  String get lightingOnMacro => '开灯宏';

  @override
  String get lightingOffMacro => '关灯宏';

  @override
  String get lightingToggleMacro => '切换宏';

  @override
  String get lightingToggleSection => '可选 — 切换方式';

  @override
  String get lightingStatusSource => '灯光状态来源';

  @override
  String get lightingStatusSourceHelp =>
      '可选。一个 Klipper 对象（例如 output_pin caselight），其值会告诉 Moongate 灯是否已开启。留空则改为根据你的点按来跟踪状态。';

  @override
  String get lightingStatusHint => '示例：output_pin caselight';

  @override
  String get lightingNotSet => '未设置';

  @override
  String get lightingPickMacro => '选择一个宏';

  @override
  String get lightingPickStatusSource => '选择状态来源';

  @override
  String get lightingManualHint => '输入准确名称';

  @override
  String get lightingClear => '清除';

  @override
  String get lightTurnOn => '开灯';

  @override
  String get lightTurnOff => '关灯';

  @override
  String get lightToggleFailed => '无法连接打印机';

  @override
  String get powerTurnOn => '开机';

  @override
  String get powerTurnOff => '关机';

  @override
  String powerConfirmOn(String name) {
    return '要开启 $name 吗？';
  }

  @override
  String powerConfirmOff(String name) {
    return '要关闭 $name 吗？';
  }

  @override
  String get powerToggleFailed => '无法切换电源';

  @override
  String get powerLockedWhilePrinting => '打印时无法关机';

  @override
  String get powerScreenTitle => '高级电源开关';

  @override
  String get powerScreenBanner =>
      '适用于电源由 Klipper 宏（而非 Moonraker 电源设备）控制的打印机。开启后选择一对开/关宏，或单个切换宏——磁贴的电源按钮将使用它们。';

  @override
  String get powerUseSwitch => '使用宏';

  @override
  String get powerNeedMacro => '设置一对开/关宏，或一个切换宏。';

  @override
  String get powerOnMacro => '开机宏';

  @override
  String get powerOffMacro => '关机宏';

  @override
  String get powerToggleSection => '或单个切换宏';

  @override
  String get powerToggleMacro => '电源切换宏';

  @override
  String get powerMenuTitle => '高级电源开关';

  @override
  String get powerMenuSubtitle => '用宏控制打印机电源';

  @override
  String get powerMacroTooltip => '电源';

  @override
  String powerMacroToggleConfirm(String name) {
    return '切换 $name 的电源？';
  }

  @override
  String powerMacroChooseTitle(String name) {
    return '切换 $name 的电源';
  }

  @override
  String lightChooseTitle(String name) {
    return '切换 $name 的灯光';
  }

  @override
  String get tileOpacityTitle => '磁贴不透明度';

  @override
  String get tileOpacityDesc => '磁贴的透明程度（0–100），让背景透出。摄像头画面保持不透明。';

  @override
  String get dashboardShowWebcams => '摄像头';

  @override
  String get dashboardShowWebcamsSubtitle => '显示或隐藏每台打印机的摄像头';

  @override
  String get updateNotesUnavailable => '无法加载更新内容，请检查网络连接，或在 GitHub 上查看。';

  @override
  String get updateViewOnGithub => '在 GitHub 上查看';

  @override
  String get cameraConfigTooltip => '设置摄像头网址';

  @override
  String get cameraConfigTitle => '自定义摄像头';

  @override
  String get cameraConfigDescription =>
      '显示未连接到 Klipper 的摄像头，例如用作网络摄像头的旧手机。请输入 Mainsail 摄像头设置中显示的地址。';

  @override
  String get cameraConfigUrlLabel => '摄像头网址';

  @override
  String get cameraConfigRemoteNote =>
      '可在 Wi-Fi 下使用，也可通过打印机远程访问。远程时只能访问家庭网络中的摄像头（专用地址）。';

  @override
  String get cameraConfigInvalid =>
      '请输入完整地址，例如 http://192.168.0.107:8080/video';

  @override
  String get cameraConfigUseDefault => '使用 Klipper 摄像头';

  @override
  String get cameraConfigApply => '应用';

  @override
  String get dashboardShowCameraIcons => '摄像头配置图标';

  @override
  String get dashboardShowCameraIconsSubtitle => '在每个摄像头上显示齿轮以设置自定义网址';

  @override
  String get appTitle => 'Moongate';

  @override
  String get languagePickerTitle => '选择您的语言';

  @override
  String get languagePickerSubtitle => '您可以随时在菜单中更改。';

  @override
  String get languagePickerContinue => '继续';

  @override
  String get menuLanguage => '语言';

  @override
  String get languageSystemDefault => '跟随系统';

  @override
  String get commonCancel => '取消';

  @override
  String get commonOk => '确定';

  @override
  String get commonClose => '关闭';

  @override
  String get commonSave => '保存';

  @override
  String get commonDone => '完成';

  @override
  String get commonRetry => '重试';

  @override
  String get commonShowKeyboard => '显示键盘';

  @override
  String get dashboardSignInRetrying => '正在重新连接云端——登录繁忙，正在重试。您的打印机将自动恢复。';

  @override
  String get commonRemove => '移除';

  @override
  String get commonDelete => '删除';

  @override
  String get commonEnable => '启用';

  @override
  String get commonDisable => '禁用';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsRemoveAllTitle => '从此设备移除所有打印机';

  @override
  String get settingsRemoveAllSubtitle =>
      '清除本地打印机缓存。保留您的 Supabase 账户，以便重新配对时顺畅无阻。';

  @override
  String get settingsRemoveAllConfirmTitle => '移除所有打印机？';

  @override
  String get settingsRemoveAllConfirmBody =>
      '所有已配对的打印机都将从此设备移除。您可以在打印机上运行 MOONGATE_PAIR 重新添加它们。';

  @override
  String get settingsRemoveAllConfirmAction => '全部移除';

  @override
  String get dashboardAddPrinter => '添加打印机';

  @override
  String get dashboardRemovePrinter => '移除打印机';

  @override
  String get dashboardMenuTooltip => '菜单';

  @override
  String get dashboardRemovePrinterTitle => '移除打印机？';

  @override
  String dashboardRemovePrinterBody(String name) {
    return '要从 Moongate 移除“$name”吗？';
  }

  @override
  String get dashboardRemoveSupabaseUnreachable =>
      '已在本地移除，但无法连接 Supabase。如果重新配对失败，请在 Pi 上运行 MOONGATE_RESET_OWNER。';

  @override
  String get dashboardBackUpConfig => '备份配置';

  @override
  String get dashboardBackUpConfigSubtitle => '重新安装前保存到文件';

  @override
  String get dashboardRestoreConfig => '恢复配置';

  @override
  String get dashboardRestoreConfigSubtitle => '从备份文件加载';

  @override
  String get dashboardThemeHeading => '主题';

  @override
  String get dashboardThemeSystem => '跟随系统';

  @override
  String get dashboardThemeDark => '深色';

  @override
  String get dashboardThemeLight => '浅色';

  @override
  String get dashboardThemeCustom => '自定义';

  @override
  String get dashboardCustomiseColours => '自定义配色';

  @override
  String get dashboardCustomiseColoursSubtitle => '编辑五个主题色槽 — HEX 或调色板';

  @override
  String get dashboardFontSizeHeading => '字体大小';

  @override
  String get dashboardLayoutHeading => '仪表盘布局';

  @override
  String dashboardColumnCount(int count) {
    return '$count 列';
  }

  @override
  String get dashboardRotateWithDevice => '随设备旋转';

  @override
  String get dashboardRotateWithDeviceSubtitle => '解锁横屏方向';

  @override
  String get dashboardAutoArrange => '按状态自动排列';

  @override
  String get dashboardAutoArrangeSubtitle => '按活动状态排序磁贴。关闭后可拖动磁贴自定义顺序。';

  @override
  String get dashboardReorderHint => '按住并拖动磁贴即可重新排序';

  @override
  String get dashboardReorderStart => '重新排序';

  @override
  String get dashboardReorderDone => '完成';

  @override
  String get dashboardCameraFeedHeading => '仪表盘摄像头画面';

  @override
  String get dashboardCameraFeedSubtitle => '磁贴刷新摄像头的频率。频率越低，流量消耗越少。';

  @override
  String get cameraFeedsMenuTitle => '仪表板摄像头画面';

  @override
  String get cameraFeedsMenuSubtitle => '本地与隧道画面频率';

  @override
  String get cameraFeedsIntro =>
      '每个磁贴刷新摄像头画面的频率。只要连接 Wi-Fi（即使在外、通过隧道访问），都会使用“本地”速率；使用移动数据时则使用“隧道”速率——这样在 Wi-Fi 下更流畅，在移动网络下更省流量。';

  @override
  String get cameraFeedsLocalRate => '本地画面刷新频率';

  @override
  String get cameraFeedsTunnelRate => '隧道画面刷新频率';

  @override
  String get dashboardAboutHeading => '关于';

  @override
  String get dashboardWhatsNew => '更新内容';

  @override
  String get dashboardWhatsNewSubtitle => '一览最近的更改';

  @override
  String get dashboardHowPairingWorks => '配对原理';

  @override
  String get dashboardHowPairingWorksSubtitle => '配对、重新安装与恢复';

  @override
  String get dashboardReportProblem => '反馈问题';

  @override
  String get dashboardReportProblemSubtitle => '发送错误报告或反馈';

  @override
  String get dashboardAppLock => '应用锁';

  @override
  String get dashboardAppLockOn => '已开启 — 启动时需要解锁';

  @override
  String get dashboardAppLockOff => '已关闭';

  @override
  String get dashboardBuyMeCoffee => '请我喝杯咖啡';

  @override
  String get dashboardBuyMeCoffeeSubtitle => '通过 PayPal 给开发者打赏';

  @override
  String get donationPromptTitle => '喜欢 Moongate 吗？';

  @override
  String get donationPromptBody =>
      'Moongate 是我利用业余时间开发的免费项目。如果它对你有帮助，一点小小的打赏能帮助它继续发展——绝不强求，而且我只会问这一次。';

  @override
  String get donationPromptLater => '以后再说';

  @override
  String get dashboardSettings => '设置';

  @override
  String dashboardVersion(String version) {
    return 'Moongate v$version';
  }

  @override
  String get dashboardSaveBackupDialogTitle => '保存 Moongate 备份';

  @override
  String get dashboardBackupFailed => '备份失败 — 无法保存文件。';

  @override
  String dashboardBackupSuccess(int count) {
    return '已备份 $count 台打印机。此文件可在新安装时恢复它们 — 请妥善保管。';
  }

  @override
  String dashboardBackupSuccessListOnly(int count) {
    return '已备份 $count 台打印机（仅列表 — 无法连接云端获取恢复码）。';
  }

  @override
  String get dashboardInvalidBackupFile => '备份文件无效 — 请选择 Moongate 配置文件。';

  @override
  String dashboardRestoreReconnected(int added, int count) {
    return '已恢复 $added 台打印机 — $count 台已重新连接，正在恢复在线。';
  }

  @override
  String dashboardRestoreNoneReconnected(int added) {
    return '已恢复 $added 台打印机，但没有任何一台重新连接 — 备份的恢复码与任何打印机都不匹配（可能来自较旧的备份，或已被使用）。请重新配对以使它们恢复在线。';
  }

  @override
  String dashboardRestoreListOnly(int added) {
    return '已恢复 $added 台打印机（仅列表）。请重新配对每台打印机以使其恢复在线。';
  }

  @override
  String get dashboardRestoreApplied => '已恢复仪表板以匹配你的备份。';

  @override
  String get dashboardRestoreReplaceTitle => '替换仪表板？';

  @override
  String dashboardRestoreReplaceBody(String names) {
    return '以下打印机在此仪表板上，但不在备份中：$names。恢复将移除它们，使仪表板与备份完全一致。它们仍保持配对——你可以稍后重新添加或恢复。';
  }

  @override
  String get dashboardRestoreReplaceConfirm => '替换';

  @override
  String get dashboardRemoveSheetTitle => '移除打印机';

  @override
  String dashboardPrinterIdShort(String id) {
    return 'ID $id…';
  }

  @override
  String get dashboardPairingHelpPairOnceTitle => '只需配对一次';

  @override
  String get dashboardPairingHelpPairOnceBody =>
      '扫描二维码（或输入 GATE code）即可添加打印机 — 该连接会保存在此应用中。';

  @override
  String get dashboardPairingHelpUpdatesTitle => '应用更新不影响您的打印机';

  @override
  String get dashboardPairingHelpUpdatesBody => '更新 Moongate 无需重新配对。';

  @override
  String get dashboardPairingHelpReinstallTitle => '重新安装或更换新手机？';

  @override
  String get dashboardPairingHelpReinstallBody =>
      '请先备份（菜单 → 备份配置），然后“恢复”即可使您的打印机重新上线 — 无需重新配对。';

  @override
  String get dashboardPairingHelpNoBackupTitle => '没有备份？';

  @override
  String get dashboardPairingHelpNoBackupBody =>
      '在打印机的控制台运行 MOONGATE_RESET_OWNER，然后重新配对。';

  @override
  String get dashboardDontShowAgain => '不再显示';

  @override
  String dashboardUpdateAvailable(String version) {
    return '有可用更新 — v$version';
  }

  @override
  String get dashboardUpdateLater => '稍后';

  @override
  String get dashboardUpdate => '更新';

  @override
  String get dashboardEmptyTitle => '尚未添加打印机';

  @override
  String get dashboardEmptyBody => '点击下方按钮配对您的第一台打印机。';

  @override
  String get pairingTitle => '添加打印机';

  @override
  String get pairingIntro =>
      '在您的 Klipper 控制台运行 MOONGATE_PAIR — 扫描二维码或输入控制台上显示的 GATE code。';

  @override
  String get pairingNameLabel => '打印机名称';

  @override
  String get pairingNameHint => '例如 Voron 2.4';

  @override
  String get pairingScanButton => '扫描二维码';

  @override
  String get pairingScanRecommended => '推荐 — 即时连接';

  @override
  String get pairingOr => '或';

  @override
  String get pairingGateCodeLabel => 'GATE code';

  @override
  String get pairingGateCodeHint => '输入您的 Klipper 控制台中显示的 8 位代码。';

  @override
  String get pairingGateCodeValid => '代码有效 ✓';

  @override
  String get pairingGateCodeWarning =>
      '替代方法。不使用二维码时，打印机最多可能需要约一分钟才能连接——它正在等待安全隧道建立。请扫描上方的二维码以即时连接。';

  @override
  String get pairingCameraPermissionNeeded => '需要摄像头权限';

  @override
  String get pairingCameraUnavailable => '摄像头不可用';

  @override
  String get pairingCancelScan => '取消扫描';

  @override
  String pairingQrScanned(String code) {
    return '二维码已扫描 — 代码 $code';
  }

  @override
  String get pairingRescan => '重新扫描';

  @override
  String get pairingAdvancedTitle => '高级 — 打印机在自定义网络上？';

  @override
  String get pairingAdvancedBody =>
      '大多数人可以将此项留空。如果您的打印机位于反向代理（Traefik、Caddy、NPM）之后或在 Docker 中，请输入您在浏览器中打开其网页（Mainsail / Fluidd）所用的相同地址。';

  @override
  String get pairingAddressLabel => '打印机地址';

  @override
  String get pairingAddressHint => '192.168.1.50:7125';

  @override
  String get pairingPairButton => '配对打印机';

  @override
  String get pairingRestoreHint => '正在重新安装？从备份文件恢复您保存的打印机。您仍需重新配对每一台以使其上线。';

  @override
  String get pairingImportButton => '从文件导入配置';

  @override
  String get pairingReportButton => '配对遇到问题？发送报告';

  @override
  String get pairingCameraPermissionTitle => '需要摄像头权限';

  @override
  String get pairingCameraPermissionBody =>
      'Moongate 需要摄像头访问权限来扫描二维码。\n\n打开 设置 → 应用 → Moongate → 权限 并启用摄像头，然后返回重试。';

  @override
  String get pairingOpenSettings => '打开设置';

  @override
  String get pairingErrorNotMoongateQr =>
      '这不是 Moongate 二维码。请在打印机上运行 MOONGATE_PAIR 生成一个。';

  @override
  String get pairingErrorOldQr => '此二维码来自较旧的 Moongate 版本。请先将 Pi 更新到 v0.3.0。';

  @override
  String get pairingErrorNoCode => '请扫描二维码，或输入打印机控制台中的 GATE code。';

  @override
  String get pairingErrorBadAddress => '该打印机地址似乎不正确 — 请尝试例如 192.168.1.50:7125';

  @override
  String pairingErrorFailed(String error) {
    return '配对失败：$error';
  }

  @override
  String get pairingImportInvalidFile => '备份文件无效 — 请选择 Moongate 配置文件。';

  @override
  String get pairingImportNoNewPrinters => '在该文件中未找到新的打印机。';

  @override
  String pairingImportRestoredReconnected(int count, int reconnected) {
    return '已恢复 $count 台打印机 — $reconnected 台已重新连接，正在恢复在线。';
  }

  @override
  String pairingImportRestoredRepair(int count) {
    return '已恢复 $count 台打印机 — 请重新配对每台 Pi 以使其上线。';
  }

  @override
  String get customThemeTitle => '自定义主题';

  @override
  String get customThemeResetTooltip => '恢复默认值';

  @override
  String get customThemeResetConfirmTitle => '重置自定义主题？';

  @override
  String get customThemeResetConfirmBody => '所有五个色槽都将恢复为默认的深色背景紫色配色。';

  @override
  String get customThemeReset => '重置';

  @override
  String get customThemePreview => '预览';

  @override
  String get customThemeAccent => '强调色';

  @override
  String get customThemeAccentDesc => '按钮、悬浮按钮、进度条、链接';

  @override
  String get customThemeBackground => '页面背景';

  @override
  String get customThemeBackgroundDesc => '位于每个屏幕之后';

  @override
  String get customThemeSurface => '卡片与磁贴';

  @override
  String get customThemeSurfaceDesc => '仪表盘磁贴、底部面板、抽屉';

  @override
  String get customThemeText => '文字';

  @override
  String get customThemeTextDesc => '界面上的正文和标题文字';

  @override
  String get customThemeError => '错误 / 停止';

  @override
  String get customThemeErrorDesc => '破坏性操作、错误浮层';

  @override
  String get customThemeEstop => '急停按钮';

  @override
  String get customThemeEstopDesc => '急停按钮的圆环和图标';

  @override
  String get customThemePresets => '预设';

  @override
  String get customThemeInvalidHex => '不是有效的十六进制颜色';

  @override
  String get customThemeSamplePrinter => '示例打印机';

  @override
  String get customThemePrinting => '正在打印';

  @override
  String get tilePauseFailed => '无法连接打印机 — 暂停失败';

  @override
  String get tileResumeFailed => '无法连接打印机 — 恢复失败';

  @override
  String get tileStopAgainToCancel => '再次按下停止以取消打印';

  @override
  String get tileLocal => '本地';

  @override
  String get tileTunnel => '隧道';

  @override
  String get tilePrinting => '正在打印';

  @override
  String get tilePaused => '已暂停';

  @override
  String get tileResume => '恢复';

  @override
  String get tilePause => '暂停';

  @override
  String get tileConfirmStop => '确认停止';

  @override
  String get tileStopPrint => '停止打印';

  @override
  String get tileFirmwareRestart => '固件重启';

  @override
  String get tileEmergencyStop => '紧急停止 · 双击';

  @override
  String get tileEmergencyStopFailed => '无法连接打印机 — 紧急停止失败';

  @override
  String get tilePrintComplete => '打印完成';

  @override
  String get tilePrintCancelled => '打印已取消';

  @override
  String get tilePrinterError => '打印机错误';

  @override
  String get tileKlipperStarting => 'Klipper 正在启动';

  @override
  String get tileReady => '就绪';

  @override
  String get tileOffline => '离线';

  @override
  String get tileStartingUp => '正在启动…';

  @override
  String get tileConnected => '已连接';

  @override
  String get tileConnecting => '正在连接…';

  @override
  String get tilePrinterUnreachable => '无法连接打印机';

  @override
  String get tileWaitingForHeartbeat => '正在等待首次心跳';

  @override
  String get tilePrinterIdle => '打印机空闲';

  @override
  String get tileReachingPrinter => '正在连接打印机';

  @override
  String get tileRemoteReady => '远程访问就绪';

  @override
  String get tileRemoteConnecting => '远程连接中…';

  @override
  String get tileIdle => '空闲';

  @override
  String get tileDone => '完成';

  @override
  String get tileCancelled => '已取消';

  @override
  String get tileClearJobTooltip => '清除并恢复为空闲';

  @override
  String get tileClearJobFailed => '无法重置打印机';

  @override
  String get dashboardBackgroundTitle => '仪表板背景';

  @override
  String get dashboardBackgroundNone => '无 — 主题颜色';

  @override
  String get dashboardBackgroundCustom => '自定义图片';

  @override
  String get dashboardBackgroundRemove => '移除背景';

  @override
  String get dashboardBackgroundSet => '背景已更新';

  @override
  String get uiGuideSectionTileButtons => '磁贴按钮';

  @override
  String get uiGuideFilesTitle => '打印文件';

  @override
  String get uiGuideFilesDesc => '浏览打印机中存储的 G-code 文件并开始打印。';

  @override
  String get uiGuideMacrosTitle => '宏';

  @override
  String get uiGuideMacrosDesc => '运行打印机的某个 Klipper 宏。';

  @override
  String get uiGuidePowerTitle => '电源';

  @override
  String get uiGuidePowerDesc => '在打印机配有电源设备时开关打印机。';

  @override
  String get uiGuideLightingTitle => '照明';

  @override
  String get uiGuideLightingDesc => '切换打印机灯光；灯泡亮起表示已开启。';

  @override
  String get uiGuideCameraViewTitle => '摄像头';

  @override
  String get uiGuideCameraViewDesc => '全屏打开实时摄像头。';

  @override
  String get uiGuideCameraSetupTitle => '摄像头设置';

  @override
  String get uiGuideCameraSetupDesc => '将磁贴指向未接入 Klipper 的摄像头。';

  @override
  String get uiGuideClearJobTitle => '清除已完成的打印';

  @override
  String get uiGuideClearJobDesc => '点按“完成”或“已取消”磁贴上的 × 即可将其恢复为空闲。';

  @override
  String get tileError => '错误';

  @override
  String get tileStarting => '正在启动';

  @override
  String get tileConnectingBadge => '正在连接';

  @override
  String get appLockTitle => '应用锁';

  @override
  String get appLockIntro =>
      '在打开 Moongate 前要求输入 PIN 码 — 也可选择使用指纹或面容。每次全新启动应用时都会显示该锁。';

  @override
  String get appLockSubtitle => '打开应用需要 PIN 码';

  @override
  String get appLockBiometricTitle => '生物识别解锁';

  @override
  String get appLockBiometricSubtitle => '使用指纹或面容 — PIN 码作为后备方式保留';

  @override
  String get appLockChangePin => '更改 PIN 码';

  @override
  String get appLockAutoLock => '自动锁定';

  @override
  String get appLockPinUpdated => 'PIN 码已更新';

  @override
  String get appLockChoosePinTitle => '设置 PIN 码';

  @override
  String get appLockChoosePinSubtitle => '输入 4–6 位数字';

  @override
  String get appLockConfirmPinTitle => '确认 PIN 码';

  @override
  String get appLockPinsDontMatch => 'PIN 码不一致';

  @override
  String get appLockEnterCurrentPin => '输入当前 PIN 码';

  @override
  String get appLockTimeoutImmediately => '立即';

  @override
  String get appLockTimeoutOneMinute => '1 分钟后';

  @override
  String get appLockTimeoutFiveMinutes => '5 分钟后';

  @override
  String get appLockTimeoutFifteenMinutes => '15 分钟后';

  @override
  String get appLockTimeoutColdLaunch => '仅在应用启动时';

  @override
  String get lockEnterPin => '输入您的 PIN 码';

  @override
  String get lockSubtitle => 'Moongate 已锁定';

  @override
  String lockTooManyAttempts(int seconds) {
    return '尝试次数过多。请在 $seconds 秒后重试';
  }

  @override
  String get lockWrongPin => 'PIN 码错误';

  @override
  String get lockUseBiometrics => '使用生物识别';

  @override
  String get lockForgotPin => '忘记 PIN 码？';

  @override
  String get lockBiometricReason => '解锁 Moongate';

  @override
  String get lockResetTitle => '重置 Moongate？';

  @override
  String get lockResetBody =>
      '此操作将移除应用锁并清除此设备上已配对的打印机，以便您重新开始。您的打印机不会被删除 — 在每台打印机上运行 MOONGATE_PAIR 即可重新配对。';

  @override
  String get lockResetConfirm => '重置';

  @override
  String get pinContinue => '继续';

  @override
  String printerStartingUpRetry(int seconds) {
    return '打印机正在启动。将在 $seconds 秒后重试…';
  }

  @override
  String printerCouldNotReach(String error) {
    return '无法连接打印机：$error';
  }

  @override
  String get printerAddressCleared => '已清除自定义地址';

  @override
  String get printerAddressUpdated => '已更新打印机地址';

  @override
  String printerTunnelUnreachable(String description) {
    return '无法连接 Cloudflare 隧道。\n$description';
  }

  @override
  String get printerEdit => '编辑打印机';

  @override
  String get printerLocalNetwork => '本地网络';

  @override
  String get printerTunnelVia => '通过 Moongate 隧道';

  @override
  String get printerCameraTooltip => '摄像头';

  @override
  String get cameraConnecting => '正在连接摄像头…';

  @override
  String get cameraNoCamera => '未为此打印机配置摄像头。';

  @override
  String get cameraHintBody => '网络摄像头在此处无法远程加载 — 打开 Moongate 摄像头。';

  @override
  String get cameraHintOpen => '打开';

  @override
  String get printerUnreachable => '无法连接打印机';

  @override
  String get printerUseTunnel => '使用隧道';

  @override
  String get printerAddressInvalid => '请尝试例如 192.168.1.50:7125';

  @override
  String get printerNameLabel => '打印机名称';

  @override
  String get printerAddressLabel => '打印机地址（高级）';

  @override
  String get printerAddressHint => '192.168.1.50:7125';

  @override
  String get printerAddressHelper => '仅适用于反向代理 / Docker 配置。留空则使用自动发现。';

  @override
  String get feedbackTitle => '反馈问题';

  @override
  String get feedbackTroublePairing => '配对遇到问题？';

  @override
  String get feedbackDescription =>
      '告诉我们发生了什么。您的应用版本、设备、网络和打印机信息会自动附上，以帮助我们排查问题。';

  @override
  String get feedbackPairingDescription =>
      '描述您尝试添加打印机时发生的情况。您的网络和发现信息会自动附上，以便我们了解它为何无法连接。';

  @override
  String get feedbackWhichPrinter => '哪台打印机？（可选）';

  @override
  String get feedbackGeneralOption => '通用 / 与具体打印机无关';

  @override
  String get feedbackCommentLabel => '出了什么问题？';

  @override
  String get feedbackCommentHint => '例如“打印机显示已连接 / 空闲，但实际上已就绪 — 点击磁贴后可正常打开。”';

  @override
  String get feedbackContactLabel => '邮箱或联系方式（可选）';

  @override
  String get feedbackContactHint => '仅当您希望收到回复时填写';

  @override
  String get feedbackSending => '正在发送…';

  @override
  String get feedbackSend => '发送报告';

  @override
  String get feedbackSuccess => '谢谢 — 您的报告已发送。';

  @override
  String get feedbackError => '无法发送 — 请检查您的网络连接后重试。';

  @override
  String get splashTagline => 'Klipper 远程控制';

  @override
  String get uiGuideTitle => '图标指南';

  @override
  String get uiGuideMenuSubtitle => '仪表盘图标的含义';

  @override
  String get uiGuideIntro => '快速了解您将在仪表盘上看到的图标。';

  @override
  String get uiGuideSectionConnection => '连接';

  @override
  String get uiGuideSectionTemperatures => '温度';

  @override
  String get uiGuideSectionControls => '打印控制';

  @override
  String get uiGuideSectionStatus => '状态';

  @override
  String get uiGuideSectionWebcam => '摄像头与连接';

  @override
  String get uiGuideLocalTitle => '本地网络';

  @override
  String get uiGuideLocalDesc => '通过您的 Wi-Fi 直接连接 — 最快的路径。';

  @override
  String get uiGuideTunnelTitle => '远程（隧道）';

  @override
  String get uiGuideTunnelDesc => '通过安全的 Cloudflare 隧道从任何地方连接。';

  @override
  String get uiGuideTunnelReadyTitle => '远程就绪';

  @override
  String get uiGuideTunnelReadyDesc => '隧道已建立，可使用远程访问。';

  @override
  String get uiGuideTunnelConnectingTitle => '远程连接中';

  @override
  String get uiGuideTunnelConnectingDesc => '远程隧道仍在建立中。';

  @override
  String get uiGuideHotendTitle => '热端 / 喷嘴';

  @override
  String get uiGuideHotendDesc => '当前喷嘴温度。';

  @override
  String get uiGuideBedTitle => '热床';

  @override
  String get uiGuideBedDesc => '当前热床温度。';

  @override
  String get uiGuideChamberTitle => '腔体';

  @override
  String get uiGuideChamberDesc => '腔体温度 — 仅当您的打印机上报时显示。';

  @override
  String get uiGuideResumeTitle => '恢复';

  @override
  String get uiGuideResumeDesc => '恢复已暂停的打印。';

  @override
  String get uiGuidePauseTitle => '暂停';

  @override
  String get uiGuidePauseDesc => '暂停当前打印。';

  @override
  String get uiGuideStopTitle => '停止';

  @override
  String get uiGuideStopDesc => '取消打印 — 点击两次以确认。';

  @override
  String get uiGuideFirmwareRestartTitle => '固件重启';

  @override
  String get uiGuideFirmwareRestartDesc => '在打印机空闲或出错时重启 Klipper。';

  @override
  String get uiGuideStatusReadyTitle => '就绪 / 完成';

  @override
  String get uiGuideStatusReadyDesc => '打印机处于空闲状态，或已完成上一次打印。';

  @override
  String get uiGuideStatusCancelledTitle => '已取消';

  @override
  String get uiGuideStatusCancelledDesc => '上一次打印已取消。';

  @override
  String get uiGuideStatusErrorTitle => '错误';

  @override
  String get uiGuideStatusErrorDesc => 'Klipper 报告了一个错误 — 打开打印机查看详情。';

  @override
  String get uiGuideStatusStartingTitle => '正在启动';

  @override
  String get uiGuideStatusStartingDesc => 'Klipper 正在启动；就绪后会显示控制按钮。';

  @override
  String get uiGuideOfflineTitle => '离线';

  @override
  String get uiGuideOfflineDesc => '目前无法连接到打印机。';

  @override
  String get uiGuideNoWebcamTitle => '无摄像头';

  @override
  String get uiGuideNoWebcamDesc => '此打印机没有可用的摄像头快照。';

  @override
  String get uiGuideBack => '返回仪表盘';

  @override
  String get printNotifTitle => '打印通知';

  @override
  String get printNotifSubtitle => '应用在后台时显示实时进度和状态';

  @override
  String get printNotifPermissionNeeded => '需要允许通知才能开启。';

  @override
  String get printNotifPromptTitle => '接收打印通知？';

  @override
  String get printNotifPromptBody =>
      '查看打印机的实时状态——进度、温度，以及打印开始、完成或出错时的提醒。你可以随时在菜单中更改。';

  @override
  String get printNotifPromptEnable => '开启';

  @override
  String get printNotifPromptNotNow => '暂不';

  @override
  String get printNotifWatching => '正在监控你的打印机…';

  @override
  String get printNotifNoPrinters => '没有打印机';

  @override
  String get notifPollIntervalTitle => '更新频率';

  @override
  String get notifContentTitle => '通知内容';

  @override
  String get notifContentSubtitle => '选择并排序显示内容';

  @override
  String get notifContentIntro => '选择实时打印通知中显示的信息，并拖动以排列顺序。';

  @override
  String get notifContentPreview => '预览';

  @override
  String get notifFieldProgress => '进度';

  @override
  String get notifFieldRemaining => '剩余时间';

  @override
  String get notifFieldEta => '完成时间';

  @override
  String get notifFieldHotend => '喷头温度';

  @override
  String get notifFieldBed => '热床温度';

  @override
  String get printAlertReady => '打印机就绪';

  @override
  String get printStatusReady => '就绪';

  @override
  String get printStatusHeating => '加热中';

  @override
  String get printStatusIdle => '空闲';

  @override
  String get printStatusOffline => '离线';

  @override
  String get printStatusPaused => '已暂停';

  @override
  String get printStatusComplete => '已完成';

  @override
  String get printStatusCancelled => '已取消';

  @override
  String get printStatusError => '错误';

  @override
  String get printStatusStartingUp => '正在启动…';

  @override
  String get printAlertStarted => '开始打印';

  @override
  String get printAlertResumed => '已恢复打印';

  @override
  String get printAlertPaused => '打印已暂停';

  @override
  String get printAlertComplete => '打印完成';

  @override
  String get printAlertCancelled => '打印已取消';

  @override
  String get printAlertError => '打印机错误';

  @override
  String get tileOpenFiles => '打印文件';

  @override
  String get gcodeSheetTitle => '开始打印';

  @override
  String get gcodeLoading => '正在加载文件…';

  @override
  String get gcodeEmpty => '此打印机上没有 G-code 文件';

  @override
  String get gcodeError => '无法加载文件';

  @override
  String get gcodeStartButton => '开始打印';

  @override
  String get gcodeStartAction => '开始';

  @override
  String get gcodeConfirmTitle => '开始打印？';

  @override
  String gcodeConfirmBody(String file) {
    return '要打印 $file 吗？';
  }

  @override
  String gcodeStarted(String file) {
    return '已开始打印 $file';
  }

  @override
  String get gcodeStartFailed => '无法开始打印';

  @override
  String get tileMacros => '宏';

  @override
  String get macrosSheetTitle => '宏';

  @override
  String get macrosLoading => '正在加载宏…';

  @override
  String get macrosError => '无法加载宏';

  @override
  String get macrosEmpty => '此打印机上没有宏';

  @override
  String get macroFavourite => '置顶';

  @override
  String get macroUnfavourite => '取消置顶';

  @override
  String get macroConfirmTitle => '运行宏？';

  @override
  String macroConfirmBody(String macro) {
    return '在此打印机上运行 $macro？';
  }

  @override
  String get macroRunAction => '运行';

  @override
  String macroSent(String macro) {
    return '已发送 $macro';
  }

  @override
  String macroFailed(String macro) {
    return '无法发送 $macro';
  }
}
