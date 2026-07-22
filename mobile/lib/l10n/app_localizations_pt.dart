// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get updateDownloading => 'Baixando atualização…';

  @override
  String get updateOpeningInstaller => 'Abrindo o instalador…';

  @override
  String get updateFailed =>
      'Não foi possível concluir a atualização automaticamente.';

  @override
  String get updateOpenInBrowser => 'Abrir no navegador';

  @override
  String get lightingTitle => 'Iluminação';

  @override
  String get lightingMenuSubtitle =>
      'Controle a luz das suas impressoras a partir do painel';

  @override
  String get lightingBanner =>
      'Escolha quais impressoras têm uma luz que você pode controlar. Para cada uma, ative e defina um par de macros de Ligar + Desligar, ou uma única macro de Alternar. Opcionalmente, escolha uma fonte de estado para que a lâmpada mostre o estado real.';

  @override
  String get lightingNoPrinters => 'Ainda não há impressoras para configurar.';

  @override
  String get lightingShowOnTile => 'Mostrar no cartão';

  @override
  String get lightingNeedMacro =>
      'Defina um par de Ligar + Desligar ou uma macro de Alternar para ativar.';

  @override
  String get lightingLoadFailed =>
      'Não foi possível carregar as macros desta impressora (ela pode estar offline). Digite os nomes manualmente abaixo.';

  @override
  String get lightingOnMacro => 'Macro de luz LIGADA';

  @override
  String get lightingOffMacro => 'Macro de luz DESLIGADA';

  @override
  String get lightingToggleMacro => 'Macro de alternar';

  @override
  String get lightingToggleSection => 'Opcional - método de alternar';

  @override
  String get lightingStatusSource => 'Fonte de estado da luz';

  @override
  String get lightingStatusSourceHelp =>
      'Opcional. O objeto do Klipper que relata o estado da luz - p. ex., output_pin caselight (não um pino bruto como PE3). Deixe em branco para apenas seguir seus toques.';

  @override
  String get lightingStatusHint => 'Exemplo: output_pin caselight';

  @override
  String get lightingNotSet => 'Não definido';

  @override
  String get lightingPickMacro => 'Selecione uma macro';

  @override
  String get lightingPickStatusSource => 'Selecione o pino de estado da luz';

  @override
  String get lightingManualHint => 'Digite o nome exato';

  @override
  String get lightingClear => 'Limpar';

  @override
  String get lightTurnOn => 'Ligar a luz';

  @override
  String get lightTurnOff => 'Desligar a luz';

  @override
  String get lightToggleFailed => 'Não foi possível conectar à impressora';

  @override
  String get powerTurnOn => 'Ligar';

  @override
  String get powerTurnOff => 'Desligar';

  @override
  String powerConfirmOn(String name) {
    return 'Ligar $name?';
  }

  @override
  String powerConfirmOff(String name) {
    return 'Desligar $name?';
  }

  @override
  String get powerToggleFailed =>
      'Não foi possível alterar a energia da impressora';

  @override
  String get powerLockedWhilePrinting =>
      'Não é possível desligar enquanto imprime';

  @override
  String get globalPowerButtonTitle => 'Botão de energia global';

  @override
  String get globalPowerButtonSubtitle =>
      'Um botão na barra superior para ligar ou desligar toda a sua frota';

  @override
  String get globalPowerTooltip => 'Ligar/desligar todas as máquinas';

  @override
  String get globalPowerSheetTitle => 'Ligar/desligar todas as máquinas';

  @override
  String get globalPowerOnAll => 'Ligar todas';

  @override
  String get globalPowerSlideOff => 'deslize para desligar todas';

  @override
  String get globalPowerConfirmOnTitle => 'Ligar todas as máquinas?';

  @override
  String get globalPowerConfirmOnBody =>
      'Isso liga todas as máquinas que podemos alcançar.';

  @override
  String get globalPowerPrintingNote =>
      'Máquinas que estão imprimindo são mantidas ligadas';

  @override
  String get globalPowerStateWillSwitchOff => 'será desligada';

  @override
  String get globalPowerStateKeptPrinting => 'imprimindo, mantida ligada';

  @override
  String get globalPowerStateOffline => 'offline, ignorada';

  @override
  String get globalPowerStateOnOff => 'ligar / desligar';

  @override
  String get globalPowerStateOffOnly => 'apenas desligar';

  @override
  String get globalPowerStateOnOnly => 'apenas ligar';

  @override
  String get globalPowerStateToggleOnly => 'apenas alternar';

  @override
  String get globalPowerNothing =>
      'Nenhuma máquina tem controle de energia configurado ainda';

  @override
  String globalPowerResultOn(int count, int total) {
    return 'Ligou $count de $total máquinas';
  }

  @override
  String globalPowerResultOff(int count, int total) {
    return 'Desligou $count de $total máquinas';
  }

  @override
  String get powerScreenTitle => 'Interruptor de energia avançado';

  @override
  String get powerScreenBanner =>
      'Para impressoras cuja energia é uma macro do Klipper em vez de um dispositivo de energia do Moonraker. Ative e defina uma macro de Desligar (o caso comum), uma macro de Ligar, ambas, ou uma única de alternar. O botão de energia do cartão usa qualquer uma delas.';

  @override
  String get powerUseSwitch => 'Usar macros';

  @override
  String get powerNeedMacro =>
      'Defina pelo menos uma macro: uma macro de Desligar (ou Ligar), ou de alternar.';

  @override
  String get powerOnMacro => 'Macro de Ligar';

  @override
  String get powerOffMacro => 'Macro de Desligar';

  @override
  String get powerToggleSection => 'Ou uma única macro de alternar';

  @override
  String get powerToggleMacro => 'Macro de alternar energia';

  @override
  String get powerToggleBulkNote =>
      'Uma macro de alternar aciona o botão de energia do cartão. Para Ligar/desligar todas as máquinas, defina uma macro de Ligar e/ou Desligar.';

  @override
  String get powerMenuTitle => 'Interruptor de energia avançado';

  @override
  String get powerMenuSubtitle =>
      'Controle a energia da impressora com uma macro';

  @override
  String get powerMacroTooltip => 'Energia';

  @override
  String powerMacroToggleConfirm(String name) {
    return 'Alternar a energia de $name?';
  }

  @override
  String powerMacroChooseTitle(String name) {
    return 'Alternar a energia de $name';
  }

  @override
  String lightChooseTitle(String name) {
    return 'Alternar a luz de $name';
  }

  @override
  String get tileOpacityTitle => 'Opacidade do cartão';

  @override
  String get tileOpacityDesc =>
      'O quão transparentes os cartões são (0-100), para que o fundo apareça. A transmissão da câmera permanece sólida.';

  @override
  String get dashboardShowWebcams => 'Webcams';

  @override
  String get dashboardShowWebcamsSubtitle =>
      'Mostrar ou ocultar a webcam de cada impressora';

  @override
  String get updateNotesUnavailable =>
      'Não foi possível carregar as novidades - verifique sua conexão ou veja no GitHub.';

  @override
  String get updateViewOnGithub => 'Ver no GitHub';

  @override
  String get cameraConfigTooltip => 'Definir URL da câmera';

  @override
  String get cameraConfigTitle => 'Câmera personalizada';

  @override
  String get cameraConfigDescription =>
      'Mostra uma câmera que não está conectada ao Klipper - como um telefone antigo usado como webcam. Digite o endereço mostrado nas configurações de webcam do Mainsail.';

  @override
  String get cameraConfigUrlLabel => 'URL da câmera';

  @override
  String get cameraConfigRemoteNote =>
      'Funciona no Wi-Fi e remotamente através da sua impressora. Apenas câmeras na sua rede doméstica (endereços privados) podem ser acessadas remotamente.';

  @override
  String get cameraConfigInvalid =>
      'Digite um endereço completo, p. ex., http://192.168.0.107:8080/video';

  @override
  String get cameraConfigUseDefault => 'Usar câmera do Klipper';

  @override
  String get cameraConfigApply => 'Aplicar';

  @override
  String get dashboardShowCameraIcons => 'Ícones de config. de câmera';

  @override
  String get dashboardShowCameraIconsSubtitle =>
      'Mostrar a engrenagem em cada câmera para definir uma URL personalizada';

  @override
  String get appTitle => 'Moongate';

  @override
  String get languagePickerTitle => 'Escolha o seu idioma';

  @override
  String get languagePickerSubtitle =>
      'Você pode alterar isso a qualquer momento pelo menu.';

  @override
  String get languagePickerContinue => 'Continuar';

  @override
  String get menuLanguage => 'Idioma';

  @override
  String get languageSystemDefault => 'Padrão do sistema';

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonOk => 'OK';

  @override
  String get commonClose => 'Fechar';

  @override
  String get commonSave => 'Salvar';

  @override
  String get commonDone => 'Concluído';

  @override
  String get commonRetry => 'Tentar novamente';

  @override
  String get commonShowKeyboard => 'Mostrar teclado';

  @override
  String get dashboardSignInRetrying =>
      'Reconectando à nuvem - o login está ocupado, tentando novamente. Suas impressoras voltarão automaticamente.';

  @override
  String get commonRemove => 'Remover';

  @override
  String get commonDelete => 'Excluir';

  @override
  String get commonEnable => 'Ativar';

  @override
  String get commonDisable => 'Desativar';

  @override
  String get settingsTitle => 'Configurações';

  @override
  String get settingsRemoveAllTitle =>
      'Remover todas as impressoras deste dispositivo';

  @override
  String get settingsRemoveAllSubtitle =>
      'Limpa o cache local de impressoras. Sua conta no Supabase é mantida para que o novo pareamento funcione perfeitamente.';

  @override
  String get settingsRemoveAllConfirmTitle => 'Remover todas as impressoras?';

  @override
  String get settingsRemoveAllConfirmBody =>
      'Todas as impressoras pareadas serão removidas deste dispositivo. Você pode adicioná-las novamente executando MOONGATE_PAIR na impressora.';

  @override
  String get settingsRemoveAllConfirmAction => 'Remover todas';

  @override
  String get dashboardAddPrinter => 'Adicionar impressora';

  @override
  String get dashboardRemovePrinter => 'Remover impressora';

  @override
  String get dashboardMenuTooltip => 'Menu';

  @override
  String get dashboardRemovePrinterTitle => 'Remover impressora?';

  @override
  String dashboardRemovePrinterBody(String name) {
    return 'Remover \"$name\" do Moongate?';
  }

  @override
  String get dashboardRemoveSupabaseUnreachable =>
      'Removida localmente, mas não foi possível alcançar o Supabase. Execute MOONGATE_RESET_OWNER no Pi se o novo pareamento falhar.';

  @override
  String get dashboardBackUpConfig => 'Fazer backup da configuração';

  @override
  String get dashboardBackUpConfigSubtitle =>
      'Salvar em um arquivo antes de reinstalar';

  @override
  String get dashboardRestoreConfig => 'Restaurar configuração';

  @override
  String get dashboardRestoreConfigSubtitle =>
      'Carregar de um arquivo de backup';

  @override
  String get dashboardThemeHeading => 'Tema';

  @override
  String get dashboardThemeSystem => 'Cores do telefone';

  @override
  String get dashboardThemeDark => 'Escuro';

  @override
  String get dashboardThemeLight => 'Claro';

  @override
  String get dashboardThemeCustom => 'Personalizado';

  @override
  String get dashboardFontHeading => 'Fonte';

  @override
  String get fontStandard => 'Padrão';

  @override
  String get fontRounded => 'Arredondada';

  @override
  String get fontSerif => 'Com serifa';

  @override
  String get fontReadable => 'Alta legibilidade';

  @override
  String get dashboardCustomiseColours => 'Personalizar cores';

  @override
  String get dashboardCustomiseColoursSubtitle =>
      'Edite os cinco espaços de cores do tema - HEX ou paleta';

  @override
  String get dashboardFontSizeHeading => 'Tamanho de exibição';

  @override
  String get dashboardLayoutHeading => 'Layout do painel';

  @override
  String dashboardColumnCount(int count) {
    return '$count col';
  }

  @override
  String get dashboardRotateWithDevice => 'Girar com o dispositivo';

  @override
  String get dashboardRotateWithDeviceSubtitle =>
      'Desbloqueia a orientação paisagem';

  @override
  String get dashboardAutoArrange => 'Organizar automaticamente por status';

  @override
  String get dashboardAutoArrangeSubtitle =>
      'Classifique os cartões por atividade. Desative para arrastar os cartões para a sua própria ordem.';

  @override
  String get dashboardShowButtons => 'Mostrar botões do painel';

  @override
  String get dashboardShowButtonsSubtitle =>
      'Mostre os botões de adicionar e reordenar na parte inferior. Adicione impressoras pelo menu quando estiverem ocultos.';

  @override
  String get dashboardShowEta => 'Mostrar tempo restante';

  @override
  String get dashboardShowEtaSubtitle =>
      'Os cartões que estão imprimindo mostram o tempo restante ao lado das temperaturas.';

  @override
  String get dashboardEtaFormatRemaining => 'Tempo restante';

  @override
  String get dashboardEtaFormatFinish => 'Hora de término';

  @override
  String get dashboardReorderHint =>
      'Segure e arraste um cartão para reordenar';

  @override
  String get dashboardReorderStart => 'Reordenar';

  @override
  String get dashboardReorderDone => 'Concluído';

  @override
  String get dashboardCameraFeedHeading => 'Feed da câmera do painel';

  @override
  String get dashboardCameraFeedSubtitle =>
      'Com que frequência os cartões atualizam a câmera. Taxas menores usam muito menos dados.';

  @override
  String get cameraFeedsMenuTitle => 'Feeds de câmera do painel';

  @override
  String get cameraFeedsMenuSubtitle => 'Taxas de feed local e do túnel';

  @override
  String get cameraFeedsIntro =>
      'Com que frequência cada cartão atualiza sua câmera. O Moongate usa a taxa Local enquanto você está no Wi-Fi (mesmo fora de casa), e a taxa do Túnel nos dados móveis - mantendo um feed rápido no Wi-Fi e um mais leve no celular para economizar dados.';

  @override
  String get cameraFeedsLocalRate => 'Taxa de atualização do feed local';

  @override
  String get cameraFeedsTunnelRate => 'Taxa de atualização do feed do túnel';

  @override
  String get dashboardAboutHeading => 'Sobre';

  @override
  String get dashboardWhatsNew => 'O que há de novo';

  @override
  String get dashboardWhatsNewSubtitle =>
      'Mudanças recentes em um piscar de olhos';

  @override
  String get dashboardHowPairingWorks => 'Como funciona o pareamento';

  @override
  String get dashboardHowPairingWorksSubtitle =>
      'Pareamento, reinstalação e restauração';

  @override
  String get dashboardReportProblem => 'Relatar um problema';

  @override
  String get dashboardReportProblemSubtitle =>
      'Enviar um relatório de bug ou feedback';

  @override
  String get dashboardAppLock => 'Bloqueio do app';

  @override
  String get dashboardAppLockOn => 'Ativado - requer desbloqueio ao iniciar';

  @override
  String get dashboardAppLockOff => 'Desativado';

  @override
  String get dashboardBuyMeCoffee => 'Pague-me um café';

  @override
  String get dashboardBuyMeCoffeeSubtitle =>
      'Dê uma gorjeta ao desenvolvedor via PayPal';

  @override
  String get dashboardDeleteData => 'Excluir meus dados';

  @override
  String get dashboardDeleteDataSubtitle =>
      'Apague sua conta e impressoras da nuvem';

  @override
  String get deleteDataConfirmTitle => 'Excluir meus dados?';

  @override
  String get deleteDataConfirmBody =>
      'Isso exclui permanentemente sua conta anônima e remove suas impressoras e configurações de notificação da nuvem. Suas impressoras precisarão ser pareadas novamente. Isso não pode ser desfeito.';

  @override
  String get deleteDataDone => 'Seus dados foram excluídos';

  @override
  String get deleteDataError =>
      'Não foi possível excluir seus dados. Por favor, tente novamente.';

  @override
  String get donationPromptTitle => 'Gostando do Moongate?';

  @override
  String get donationPromptBody =>
      'O Moongate é um projeto paralelo gratuito que eu construo no meu tempo livre. Se é útil para você, uma pequena gorjeta ajuda a mantê-lo - sem pressão, e eu não perguntarei novamente.';

  @override
  String get donationPromptLater => 'Talvez mais tarde';

  @override
  String get dashboardSettings => 'Configurações';

  @override
  String dashboardVersion(String version) {
    return 'Moongate v$version';
  }

  @override
  String get dashboardSaveBackupDialogTitle => 'Salvar backup do Moongate';

  @override
  String get dashboardBackupFailed =>
      'Falha no backup - não foi possível salvar o arquivo.';

  @override
  String dashboardBackupSuccess(int count) {
    return 'Backup feito de $count impressora(s). Este arquivo pode restaurá-las em uma nova instalação - mantenha-o privado.';
  }

  @override
  String dashboardBackupSuccessListOnly(int count) {
    return 'Backup feito de $count impressora(s) (apenas a lista - não foi possível conectar à nuvem para obter um código de restauração).';
  }

  @override
  String get dashboardInvalidBackupFile =>
      'Arquivo de backup inválido - por favor, escolha um arquivo de configuração do Moongate.';

  @override
  String dashboardRestoreReconnected(int added, int count) {
    return '$added impressora(s) restaurada(s) - $count reconectada(s) e voltando a ficar online.';
  }

  @override
  String dashboardRestoreNoneReconnected(int added) {
    return '$added impressora(s) restaurada(s), mas nenhuma reconectada - o código de restauração do backup não correspondeu a nenhuma impressora (pode ser de um backup mais antigo, ou já usado). Pareie-as novamente para colocá-las online.';
  }

  @override
  String dashboardRestoreListOnly(int added) {
    return '$added impressora(s) restaurada(s) (apenas a lista). Pareie cada impressora novamente para colocá-la online.';
  }

  @override
  String get dashboardRestoreApplied =>
      'Painel restaurado para corresponder ao seu backup.';

  @override
  String get dashboardRestoreExtrasTitle => 'Manter suas impressoras atuais?';

  @override
  String dashboardRestoreExtrasBody(String names) {
    return 'Estas impressoras estão neste painel, mas não no backup: $names. Você pode mantê-las junto com as impressoras restauradas ou removê-las para que o painel corresponda exatamente ao backup. As impressoras removidas permanecem pareadas - você pode adicioná-las novamente ou restaurá-las mais tarde.';
  }

  @override
  String get dashboardRestoreExtrasKeep => 'Mantê-las';

  @override
  String get dashboardRestoreExtrasRemove => 'Removê-las';

  @override
  String get dashboardRemoveSheetTitle => 'Remover uma impressora';

  @override
  String dashboardPrinterIdShort(String id) {
    return 'id $id…';
  }

  @override
  String get dashboardPairingHelpPluginTitle =>
      'Primeiro: instale o plugin no Pi';

  @override
  String get dashboardPairingHelpPluginBody =>
      'O Moongate exige que o plugin dele esteja em execução na sua impressora Klipper antes do pareamento. Após a instalação, execute a macro MOONGATE_PAIR (ou digite-a no console do Mainsail/Fluidd) para obter um código de pareamento ou uma URL para pareamento por código QR.';

  @override
  String get dashboardPairingHelpPluginAction =>
      'Abrir o guia de início rápido';

  @override
  String get pluginUpdateTooltip => 'Atualização do plugin disponível';

  @override
  String get pluginUpdateTitle => 'Atualização do plugin disponível';

  @override
  String pluginUpdateBody(String current, String latest) {
    return 'Esta impressora está executando o plugin Moongate $current. A versão $latest está disponível.';
  }

  @override
  String get pluginUpdateVersionUnknown => 'uma versão antiga';

  @override
  String get pluginUpdateNow => 'Atualizar agora';

  @override
  String get pluginUpdateManual =>
      'Esta versão do plugin ainda não pode ser atualizada pelo app. Na interface web da impressora: Mainsail (ou Fluidd) → Software Updates → Moongate → Update.';

  @override
  String get pluginUpdateBusyPrinting =>
      'Esta impressora está imprimindo. Atualize quando a impressão terminar.';

  @override
  String get pluginUpdateStarted =>
      'Atualização iniciada. Ela roda em segundo plano na impressora - o ícone desaparece quando terminar (cerca de um minuto).';

  @override
  String get pluginUpdateFailed =>
      'Não foi possível iniciar a atualização. Use a interface web da impressora: Software Updates → Moongate → Update.';

  @override
  String get dashboardPairingHelpPairOnceTitle => 'Pareie uma vez';

  @override
  String get dashboardPairingHelpPairOnceBody =>
      'Escaneie o QR (ou digite o código GATE) para adicionar uma impressora - esse link é salvo neste app.';

  @override
  String get dashboardPairingHelpUpdatesTitle =>
      'Atualizações do app mantêm suas impressoras';

  @override
  String get dashboardPairingHelpUpdatesBody =>
      'Atualizar o Moongate nunca requer parear novamente.';

  @override
  String get dashboardPairingHelpReinstallTitle =>
      'Reinstalando ou celular novo?';

  @override
  String get dashboardPairingHelpReinstallBody =>
      'Faça um backup primeiro (Menu → Fazer backup da configuração), depois Restaurar traz suas impressoras de volta online - sem parear novamente.';

  @override
  String get dashboardPairingHelpNoBackupTitle => 'Sem backup?';

  @override
  String get dashboardPairingHelpNoBackupBody =>
      'Execute MOONGATE_RESET_OWNER no console da impressora, e depois pareie novamente.';

  @override
  String get dashboardDontShowAgain => 'Não mostrar isso novamente';

  @override
  String dashboardUpdateAvailable(String version) {
    return 'Atualização disponível - v$version';
  }

  @override
  String get dashboardUpdateLater => 'Mais tarde';

  @override
  String get dashboardUpdate => 'Atualizar';

  @override
  String get dashboardEmptyTitle => 'Nenhuma impressora adicionada ainda';

  @override
  String get dashboardEmptyBody =>
      'Toque no botão abaixo para parear sua primeira impressora.';

  @override
  String get pairingTitle => 'Adicionar Impressora';

  @override
  String get pairingIntro =>
      'Execute MOONGATE_PAIR no console do seu Klipper - escaneie o QR ou digite o código GATE mostrado no console.';

  @override
  String get pairingNameLabel => 'Nome da impressora';

  @override
  String get pairingNameHint => 'p. ex., Voron 2.4';

  @override
  String get pairingScanButton => 'Escanear código QR';

  @override
  String get pairingScanRecommended => 'Recomendado - conecta instantaneamente';

  @override
  String get pairingOr => 'OU';

  @override
  String get pairingGateCodeLabel => 'Código GATE';

  @override
  String get pairingGateCodeHint =>
      'Digite o código de 8 dígitos mostrado no console do seu Klipper.';

  @override
  String get pairingGateCodeValid => 'O código parece válido ✓';

  @override
  String get pairingGateCodeWarning =>
      'Método alternativo. Sem o QR, a impressora pode levar até cerca de um minuto para ficar online - ela está aguardando o túnel seguro conectar. Escaneie o código QR acima para uma conexão instantânea.';

  @override
  String get pairingCameraPermissionNeeded => 'Permissão da câmera necessária';

  @override
  String get pairingCameraUnavailable => 'Câmera indisponível';

  @override
  String get pairingCancelScan => 'Cancelar escaneamento';

  @override
  String pairingQrScanned(String code) {
    return 'QR escaneado - código $code';
  }

  @override
  String get pairingRescan => 'Escanear novamente';

  @override
  String get pairingAdvancedTitle =>
      'Avançado - impressora em uma rede personalizada?';

  @override
  String get pairingAdvancedBody =>
      'A maioria das pessoas pode deixar isso em branco. Se sua impressora estiver atrás de um proxy reverso (Traefik, Caddy, NPM) ou no Docker, insira o mesmo endereço que você usa para abrir a página web dela (Mainsail / Fluidd) em um navegador.';

  @override
  String get pairingAddressLabel => 'Endereço da impressora';

  @override
  String get pairingAddressHint => '192.168.1.50:7125';

  @override
  String get pairingPairButton => 'Parear impressora';

  @override
  String get pairingModeCloud => 'Nuvem Moongate';

  @override
  String get pairingModeDirect => 'Direto (LAN/VPN)';

  @override
  String get pairingDirectIntro =>
      'Conecta diretamente à impressora pela sua rede ou pela sua própria VPN - sem conta na nuvem, funciona offline. A impressora deve ser instalada no modo somente LAN.';

  @override
  String get pairingDirectScanHint =>
      'Escaneie o QR do MOONGATE_PAIR ou digite o endereço abaixo';

  @override
  String get pairingDirectAddressHelper =>
      'O endereço que você usa para o Mainsail / Fluidd na sua rede';

  @override
  String get pairingAddButton => 'Adicionar impressora';

  @override
  String pairingLanScanned(String url) {
    return 'Impressora LAN escaneada - $url';
  }

  @override
  String pairingNameHintCycled(String name) {
    return 'ex.: $name';
  }

  @override
  String get pairingNameHintExamples =>
      'Voron 2.4|RatRig 300|Wilma|2.4 V3309|Printy McPrintface';

  @override
  String get pairingErrorNoName =>
      'Primeiro dê um nome à sua impressora - é assim que você vai identificá-la no painel.';

  @override
  String get pairingDirectCaveatsTitle => 'Limitações do modo direto';

  @override
  String get pairingDirectCaveats =>
      '• Notificações de impressão não funcionarão\n• Fora de casa, o app só se conecta pela sua própria VPN\n• A rede do seu celular (ou a sub-rede da VPN) deve estar em trusted_clients do Moonraker\n• Dê à impressora um endereço fixo (reserva DHCP) - o app o armazena';

  @override
  String get pairingErrorNoAddress =>
      'Digite o endereço da impressora ou escaneie o código QR dela.';

  @override
  String get pairingRestoreHint =>
      'Reinstalando? Restaure suas impressoras salvas de um arquivo de backup. Você ainda precisará parear cada uma novamente para colocá-la online.';

  @override
  String get pairingImportButton => 'Importar configuração de arquivo';

  @override
  String get pairingReportButton => 'Problemas ao parear? Enviar um relatório';

  @override
  String get pairingCameraPermissionTitle => 'Permissão da câmera necessária';

  @override
  String get pairingCameraPermissionBody =>
      'O Moongate precisa de acesso à câmera para escanear códigos QR.\n\nAbra Configurações → Apps → Moongate → Permissões e ative a Câmera, depois volte e tente novamente.';

  @override
  String get pairingOpenSettings => 'Abrir Configurações';

  @override
  String get pairingErrorNotMoongateQr =>
      'Não é um código QR do Moongate. Execute MOONGATE_PAIR na impressora para gerar um.';

  @override
  String get pairingErrorOldQr =>
      'Este código QR é de uma versão mais antiga do Moongate. Atualize o Pi para v0.3.0 primeiro.';

  @override
  String get pairingErrorNoCode =>
      'Escaneie o código QR, ou digite o código GATE a partir do console da impressora.';

  @override
  String get pairingErrorBadAddress =>
      'Esse endereço da impressora não parece certo - tente p. ex., 192.168.1.50:7125';

  @override
  String pairingErrorFailed(String error) {
    return 'Falha no pareamento: $error';
  }

  @override
  String get pairingImportInvalidFile =>
      'Arquivo de backup inválido - por favor, escolha um arquivo de configuração do Moongate.';

  @override
  String get pairingImportNoNewPrinters =>
      'Nenhuma impressora nova encontrada nesse arquivo.';

  @override
  String pairingImportRestoredReconnected(int count, int reconnected) {
    return '$count impressora(s) restaurada(s) - $reconnected reconectada(s), voltando a ficar online.';
  }

  @override
  String pairingImportRestoredRepair(int count) {
    return '$count impressora(s) restaurada(s) - pareie cada Pi novamente para colocá-lo online.';
  }

  @override
  String get customThemeTitle => 'Tema personalizado';

  @override
  String get customThemeResetTooltip => 'Redefinir para os padrões';

  @override
  String get customThemeResetConfirmTitle => 'Redefinir tema personalizado?';

  @override
  String get customThemeResetConfirmBody =>
      'Todos os cinco espaços de cores serão revertidos para a paleta padrão de roxo sobre escuro.';

  @override
  String get customThemeReset => 'Redefinir';

  @override
  String get customThemePreview => 'Pré-visualização';

  @override
  String get customThemeAccent => 'Destaque';

  @override
  String get customThemeAccentDesc => 'Botões, FAB, barras de progresso, links';

  @override
  String get customThemeBackground => 'Fundo da página';

  @override
  String get customThemeBackgroundDesc => 'Atrás de cada tela';

  @override
  String get customThemeSurface => 'Cartões e painéis';

  @override
  String get customThemeSurfaceDesc =>
      'Cartões do painel, painéis, menu lateral';

  @override
  String get customThemeText => 'Texto';

  @override
  String get customThemeTextDesc => 'Texto do corpo e títulos em superfícies';

  @override
  String get customThemeError => 'Erro / Parar';

  @override
  String get customThemeErrorDesc => 'Ações destrutivas, sobreposições de erro';

  @override
  String get customThemeEstop => 'Botão de EMERGÊNCIA';

  @override
  String get customThemeEstopDesc => 'Anel e ícone de parada de emergência';

  @override
  String get customThemePresets => 'Predefinições';

  @override
  String get customThemeInvalidHex => 'Não é uma cor hexadecimal válida';

  @override
  String get customThemeSamplePrinter => 'Impressora de exemplo';

  @override
  String get customThemePrinting => 'Imprimindo';

  @override
  String get tilePauseFailed =>
      'Não foi possível alcançar a impressora - falha ao pausar';

  @override
  String get tileResumeFailed =>
      'Não foi possível alcançar a impressora - falha ao retomar';

  @override
  String get tileStopAgainToCancel =>
      'Pressione PARAR novamente para cancelar a impressão';

  @override
  String get tileLocal => 'Local';

  @override
  String get tileTunnel => 'Túnel';

  @override
  String get tilePrinting => 'Imprimindo';

  @override
  String get tilePaused => 'Pausado';

  @override
  String get tileResume => 'Retomar';

  @override
  String get tilePause => 'Pausar';

  @override
  String get tileConfirmStop => 'Confirmar parada';

  @override
  String get tileStopPrint => 'Parar impressão';

  @override
  String get tileFirmwareRestart => 'Reiniciar firmware';

  @override
  String get tileEmergencyStop => 'Parada de emergência · toque duplo';

  @override
  String get tileEmergencyStopFailed =>
      'Não foi possível alcançar a impressora - falha na parada de emergência';

  @override
  String get tilePrintComplete => 'Impressão concluída';

  @override
  String get tilePrintCancelled => 'Impressão cancelada';

  @override
  String get tilePrinterError => 'Erro na impressora';

  @override
  String get tileKlipperStarting => 'Klipper iniciando';

  @override
  String get tileReady => 'Pronto';

  @override
  String get tileOffline => 'Offline';

  @override
  String get tileStartingUp => 'Iniciando…';

  @override
  String get tileConnected => 'Conectado';

  @override
  String get tileConnecting => 'Conectando…';

  @override
  String get tilePrinterUnreachable => 'Impressora inacessível';

  @override
  String get tileWaitingForHeartbeat => 'Aguardando o primeiro sinal';

  @override
  String get tilePrinterIdle => 'Impressora inativa';

  @override
  String get tileReachingPrinter => 'Alcançando a impressora';

  @override
  String get tileRemoteReady => 'Acesso remoto pronto';

  @override
  String get tileRemoteConnecting => 'Conectando remotamente…';

  @override
  String get tileIdle => 'Inativo';

  @override
  String get tileDone => 'Concluído';

  @override
  String get tileCancelled => 'Cancelado';

  @override
  String get tileClearJobTooltip => 'Limpar e definir como inativo';

  @override
  String get tileClearJobFailed => 'Não foi possível redefinir a impressora';

  @override
  String get dashboardBackgroundTitle => 'Fundo do painel';

  @override
  String get dashboardBackgroundNone => 'Nenhum - cor do tema';

  @override
  String get dashboardBackgroundCustom => 'Imagem personalizada';

  @override
  String get dashboardBackgroundRemove => 'Remover fundo';

  @override
  String get dashboardBackgroundSet => 'Fundo atualizado';

  @override
  String get uiGuideSectionTileButtons => 'Botões do cartão';

  @override
  String get uiGuideFilesTitle => 'Imprimir um arquivo';

  @override
  String get uiGuideFilesDesc =>
      'Navegue pelos arquivos G-code salvos na impressora e inicie um.';

  @override
  String get uiGuideMacrosTitle => 'Macros';

  @override
  String get uiGuideMacrosDesc =>
      'Execute uma das macros do Klipper da impressora.';

  @override
  String get uiGuidePowerTitle => 'Energia';

  @override
  String get uiGuidePowerDesc =>
      'Ligue ou desligue a impressora, quando ela tiver um dispositivo de energia.';

  @override
  String get uiGuideLightingTitle => 'Iluminação';

  @override
  String get uiGuideLightingDesc =>
      'Alterne a luz da impressora; a lâmpada brilha quando está acesa.';

  @override
  String get uiGuideCameraViewTitle => 'Câmera';

  @override
  String get uiGuideCameraViewDesc => 'Abra a câmera ao vivo em tela cheia.';

  @override
  String get uiGuideCameraSetupTitle => 'Configuração da câmera';

  @override
  String get uiGuideCameraSetupDesc =>
      'Aponte um cartão para uma câmera que não está conectada ao Klipper.';

  @override
  String get uiGuideClearJobTitle => 'Limpar uma impressão concluída';

  @override
  String get uiGuideClearJobDesc =>
      'Toque no × em um cartão Concluído ou Cancelado para defini-lo de volta para Inativo.';

  @override
  String get tileError => 'Erro';

  @override
  String get tileStarting => 'Iniciando';

  @override
  String get tileConnectingBadge => 'Conectando';

  @override
  String get appLockTitle => 'Bloqueio do app';

  @override
  String get appLockIntro =>
      'Exija um PIN - e opcionalmente sua impressão digital ou rosto - antes que o Moongate seja aberto. O bloqueio sempre aparece quando o app é iniciado novamente.';

  @override
  String get appLockSubtitle => 'PIN necessário para abrir o app';

  @override
  String get appLockBiometricTitle => 'Desbloqueio biométrico';

  @override
  String get appLockBiometricSubtitle =>
      'Use impressão digital ou rosto - o PIN fica como uma alternativa';

  @override
  String get appLockChangePin => 'Alterar PIN';

  @override
  String get appLockAutoLock => 'Bloqueio automático';

  @override
  String get appLockPinUpdated => 'PIN atualizado';

  @override
  String get appLockChoosePinTitle => 'Escolha um PIN';

  @override
  String get appLockChoosePinSubtitle => 'Digite de 4 a 6 dígitos';

  @override
  String get appLockConfirmPinTitle => 'Confirmar PIN';

  @override
  String get appLockPinsDontMatch => 'Os PINs não coincidem';

  @override
  String get appLockEnterCurrentPin => 'Digite o PIN atual';

  @override
  String get appLockTimeoutImmediately => 'Imediatamente';

  @override
  String get appLockTimeoutOneMinute => 'Após 1 minuto';

  @override
  String get appLockTimeoutFiveMinutes => 'Após 5 minutos';

  @override
  String get appLockTimeoutFifteenMinutes => 'Após 15 minutos';

  @override
  String get appLockTimeoutColdLaunch => 'Apenas ao iniciar o app';

  @override
  String get lockEnterPin => 'Digite seu PIN';

  @override
  String get lockSubtitle => 'O Moongate está bloqueado';

  @override
  String lockTooManyAttempts(int seconds) {
    return 'Muitas tentativas. Tente novamente em ${seconds}s';
  }

  @override
  String get lockWrongPin => 'PIN incorreto';

  @override
  String get lockUseBiometrics => 'Usar biometria';

  @override
  String get lockForgotPin => 'Esqueceu o PIN?';

  @override
  String get lockBiometricReason => 'Desbloquear Moongate';

  @override
  String get lockResetTitle => 'Redefinir Moongate?';

  @override
  String get lockResetBody =>
      'Isso remove o bloqueio do app e limpa as impressoras pareadas deste dispositivo para que você possa começar de novo. Suas impressoras não são excluídas - pareie-as novamente executando MOONGATE_PAIR em cada uma.';

  @override
  String get lockResetConfirm => 'Redefinir';

  @override
  String get pinContinue => 'Continuar';

  @override
  String printerStartingUpRetry(int seconds) {
    return 'A impressora está iniciando. Tentando novamente em ${seconds}s…';
  }

  @override
  String printerCouldNotReach(String error) {
    return 'Não foi possível alcançar a impressora: $error';
  }

  @override
  String get printerDirectModeToggle => 'Modo direto (LAN/VPN)';

  @override
  String get printerDirectModeSubtitle =>
      'Fale com esta impressora apenas pela sua rede ou VPN - sem nuvem. Precisa do endereço da impressora, instalada no modo somente LAN.';

  @override
  String get printerDirectModeNeedsAddress =>
      'O modo direto precisa do endereço da impressora';

  @override
  String get printerDirectModeOn =>
      'Modo direto ativado - esta impressora agora se conecta apenas pela sua rede';

  @override
  String get printerDirectModeOff =>
      'Modo direto desativado - conexão com a nuvem restaurada';

  @override
  String get printerAddressCleared => 'Endereço personalizado limpo';

  @override
  String get printerAddressUpdated => 'Endereço da impressora atualizado';

  @override
  String printerTunnelUnreachable(String description) {
    return 'Túnel da Cloudflare inacessível.\n$description';
  }

  @override
  String printerWebUiRetry(int seconds) {
    return 'A interface web da impressora ainda não está respondendo. Isso é normal por cerca de um minuto depois de ligar. Tentando novamente em ${seconds}s…';
  }

  @override
  String get printerLocalOnlyNoLan =>
      'O acesso remoto está desligado (Somente local) e esta impressora não está acessível na sua rede.';

  @override
  String get localOnlyButtonTitle => 'Botão somente local';

  @override
  String get localOnlyButtonSubtitle =>
      'Um botão na barra superior que desliga as conexões remotas (túnel), conectando somente as impressoras da sua rede';

  @override
  String get localOnlyTooltip => 'Somente local';

  @override
  String get localOnlySnackOn =>
      'Conexões remotas desligadas - somente rede local';

  @override
  String get localOnlySnackOff => 'Conexões remotas religadas';

  @override
  String get printerEdit => 'Editar impressora';

  @override
  String get printerLocalNetwork => 'Rede local';

  @override
  String get printerTunnelVia => 'Túnel via Moongate';

  @override
  String get printerCameraTooltip => 'Câmera';

  @override
  String get cameraConnecting => 'Conectando à câmera…';

  @override
  String get cameraNoCamera =>
      'Nenhuma câmera configurada para esta impressora.';

  @override
  String get cameraHintBody =>
      'A webcam não carregará remotamente aqui - abra a câmera do Moongate.';

  @override
  String get cameraHintOpen => 'Abrir';

  @override
  String get webcamWakingUp => 'A câmera está acordando…';

  @override
  String get printerUnreachable => 'Impressora inacessível';

  @override
  String get printerUseTunnel => 'Usar túnel';

  @override
  String get printerAddressInvalid => 'Tente p. ex., 192.168.1.50:7125';

  @override
  String get printerNameLabel => 'Nome da impressora';

  @override
  String get printerAddressLabel => 'Endereço da impressora (avançado)';

  @override
  String get printerAddressHint => '192.168.1.50:7125';

  @override
  String get printerAddressHelper =>
      'Apenas para configurações de proxy reverso / Docker. Deixe em branco para usar a descoberta automática.';

  @override
  String get feedbackTitle => 'Relatar um problema';

  @override
  String get feedbackTroublePairing => 'Problemas ao parear?';

  @override
  String get feedbackDescription =>
      'Conte-nos o que está acontecendo. A versão do seu app, o dispositivo, a rede e os detalhes da impressora são anexados automaticamente para nos ajudar a rastrear o problema.';

  @override
  String get feedbackPairingDescription =>
      'Descreva o que acontece quando você tenta adicionar a impressora. Seus detalhes de rede e descoberta são anexados automaticamente para que possamos ver por que ela não está se conectando.';

  @override
  String get feedbackWhichPrinter => 'Qual impressora? (opcional)';

  @override
  String get feedbackGeneralOption =>
      'Geral / não específico de uma impressora';

  @override
  String get feedbackCommentLabel => 'O que deu errado?';

  @override
  String get feedbackCommentHint =>
      'p. ex., \"A impressora mostra Conectado / inativo, mas na verdade está pronta - abre normalmente quando toco no cartão.\"';

  @override
  String get feedbackContactLabel => 'Email ou contato (opcional)';

  @override
  String get feedbackContactHint => 'Apenas se você quiser uma resposta';

  @override
  String get feedbackSending => 'Enviando…';

  @override
  String get feedbackSend => 'Enviar relatório';

  @override
  String get feedbackSuccess => 'Obrigado - seu relatório foi enviado.';

  @override
  String get feedbackError =>
      'Não foi possível enviar - verifique sua conexão e tente novamente.';

  @override
  String get splashTagline => 'Controle remoto do Klipper';

  @override
  String get uiGuideTitle => 'Guia de ícones';

  @override
  String get uiGuideMenuSubtitle => 'O que significam os ícones do painel';

  @override
  String get uiGuideIntro =>
      'Um guia rápido dos ícones que você verá no painel.';

  @override
  String get uiGuideSectionConnection => 'Conexão';

  @override
  String get uiGuideSectionTemperatures => 'Temperaturas';

  @override
  String get uiGuideSectionControls => 'Controles de impressão';

  @override
  String get uiGuideSectionStatus => 'Status';

  @override
  String get uiGuideSectionWebcam => 'Câmera e conexão';

  @override
  String get uiGuideLocalTitle => 'Rede local';

  @override
  String get uiGuideLocalDesc =>
      'Conectado diretamente pelo seu Wi-Fi - o caminho mais rápido.';

  @override
  String get uiGuideTunnelTitle => 'Remoto (túnel)';

  @override
  String get uiGuideTunnelDesc =>
      'Conectado de qualquer lugar através do túnel seguro da Cloudflare.';

  @override
  String get uiGuideTunnelReadyTitle => 'Remoto pronto';

  @override
  String get uiGuideTunnelReadyDesc =>
      'O túnel está ativo, então o acesso remoto está disponível.';

  @override
  String get uiGuideTunnelConnectingTitle => 'Conectando remotamente';

  @override
  String get uiGuideTunnelConnectingDesc =>
      'O túnel remoto ainda está sendo estabelecido.';

  @override
  String get uiGuideHotendTitle => 'Hotend / bico';

  @override
  String get uiGuideHotendDesc => 'Temperatura atual do bico.';

  @override
  String get uiGuideBedTitle => 'Mesa aquecida';

  @override
  String get uiGuideBedDesc => 'Temperatura atual da mesa.';

  @override
  String get uiGuideChamberTitle => 'Câmara';

  @override
  String get uiGuideChamberDesc =>
      'Temperatura da câmara - mostrada apenas se a sua impressora relatar uma.';

  @override
  String get uiGuideResumeTitle => 'Retomar';

  @override
  String get uiGuideResumeDesc => 'Retoma uma impressão pausada.';

  @override
  String get uiGuidePauseTitle => 'Pausar';

  @override
  String get uiGuidePauseDesc => 'Pausa a impressão atual.';

  @override
  String get uiGuideStopTitle => 'Parar';

  @override
  String get uiGuideStopDesc =>
      'Cancela a impressão - toque duas vezes para confirmar.';

  @override
  String get uiGuideEstopTitle => 'Parada de emergência';

  @override
  String get uiGuideEstopDesc =>
      'Dê um toque duplo no triângulo vermelho para parar a impressora imediatamente (Klipper M112).';

  @override
  String get uiGuideFirmwareRestartTitle => 'Reiniciar firmware';

  @override
  String get uiGuideFirmwareRestartDesc =>
      'Reinicie o Klipper quando a impressora estiver inativa ou em erro.';

  @override
  String get uiGuideStatusReadyTitle => 'Pronto / concluído';

  @override
  String get uiGuideStatusReadyDesc =>
      'A impressora está inativa, ou terminou sua última impressão.';

  @override
  String get uiGuideStatusCancelledTitle => 'Cancelado';

  @override
  String get uiGuideStatusCancelledDesc => 'A última impressão foi cancelada.';

  @override
  String get uiGuideStatusErrorTitle => 'Erro';

  @override
  String get uiGuideStatusErrorDesc =>
      'O Klipper relatou um erro - abra a impressora para mais detalhes.';

  @override
  String get uiGuideStatusStartingTitle => 'Iniciando';

  @override
  String get uiGuideStatusStartingDesc =>
      'O Klipper está iniciando; os controles aparecem quando ele estiver pronto.';

  @override
  String get uiGuideOfflineTitle => 'Offline';

  @override
  String get uiGuideOfflineDesc =>
      'A impressora não pode ser alcançada no momento.';

  @override
  String get uiGuideNoWebcamTitle => 'Sem câmera';

  @override
  String get uiGuideNoWebcamDesc =>
      'Nenhum instantâneo da webcam está disponível para esta impressora.';

  @override
  String get uiGuideBack => 'Voltar ao painel';

  @override
  String get printNotifTitle => 'Notificações de impressão';

  @override
  String get printNotifSubtitle =>
      'Progresso ao vivo e status enquanto o app está em segundo plano';

  @override
  String get printNotifPermissionNeeded =>
      'Permita as notificações para ativar isso.';

  @override
  String get printNotifPromptTitle => 'Receber notificações de impressão?';

  @override
  String get printNotifPromptBody =>
      'Veja o status ao vivo das suas impressoras - progresso, temperaturas e alertas quando uma impressão começa, termina ou falha. Você pode alterar isso a qualquer momento no menu.';

  @override
  String get printNotifPromptEnable => 'Ativar';

  @override
  String get printNotifPromptNotNow => 'Agora não';

  @override
  String get printNotifWatching => 'Observando suas impressoras…';

  @override
  String get printNotifNoPrinters => 'Nenhuma impressora';

  @override
  String get printNotifNoneOnline => 'Nenhuma impressora online';

  @override
  String get notifOnlineOnlyTitle => 'Mostrar apenas dispositivos online';

  @override
  String get notifOnlineOnlySubtitle =>
      'Oculte máquinas offline da notificação de status';

  @override
  String get notifPollIntervalTitle => 'Frequência de atualização';

  @override
  String get notifContentTitle => 'Conteúdo da notificação';

  @override
  String get notifContentSubtitle => 'Escolha e reordene o que é mostrado';

  @override
  String get notifRosterTitle => 'Barra de status de todas as impressoras';

  @override
  String get notifRosterShownSubtitle =>
      'Visível. Toque para ocultar apenas esta barra nas configurações de notificação do seu telefone - os cartões de impressão continuam chegando.';

  @override
  String get notifRosterHiddenSubtitle =>
      'Oculta nas configurações de notificação do seu telefone. Toque para exibi-la novamente.';

  @override
  String get notifContentIntro =>
      'Escolha quais detalhes aparecem no cartão de notificação de cada impressão, e arraste-os para a ordem que desejar.';

  @override
  String get notifContentPreview => 'Visualização';

  @override
  String get notifFieldProgress => 'Progresso';

  @override
  String get notifFieldRemaining => 'Tempo restante';

  @override
  String get notifFieldEta => 'Hora de término';

  @override
  String get notifFieldHotend => 'Temp. do hotend';

  @override
  String get notifFieldBed => 'Temp. da mesa';

  @override
  String get printAlertReady => 'Impressora pronta';

  @override
  String get printStatusReady => 'Pronto';

  @override
  String get printStatusHeating => 'Aquecendo';

  @override
  String get printStatusIdle => 'Inativo';

  @override
  String get printStatusOffline => 'Offline';

  @override
  String get printStatusPaused => 'Pausado';

  @override
  String get printStatusComplete => 'Concluído';

  @override
  String get printStatusCancelled => 'Cancelado';

  @override
  String get printStatusError => 'Erro';

  @override
  String get printStatusStartingUp => 'Iniciando';

  @override
  String get printStatusPrinting => 'Imprimindo';

  @override
  String get printNotifStarted => 'Impressão iniciada';

  @override
  String get printNotifFinished => 'Concluído';

  @override
  String get notifClearAction => 'Limpar';

  @override
  String get printAlertStarted => 'Começou a imprimir';

  @override
  String get printAlertResumed => 'Impressão retomada';

  @override
  String get printAlertPaused => 'Impressão pausada';

  @override
  String get printAlertComplete => 'Impressão concluída';

  @override
  String get printAlertCancelled => 'Impressão cancelada';

  @override
  String get printAlertError => 'Erro na impressora';

  @override
  String get tileOpenFiles => 'Imprimir um arquivo';

  @override
  String get gcodeSheetTitle => 'Iniciar uma impressão';

  @override
  String get gcodeLoading => 'Carregando arquivos…';

  @override
  String get gcodeEmpty => 'Não há arquivos G-code nesta impressora';

  @override
  String get gcodeError => 'Não foi possível carregar os arquivos';

  @override
  String get gcodeStartButton => 'Iniciar impressão';

  @override
  String get gcodeStartAction => 'Iniciar';

  @override
  String get gcodeConfirmTitle => 'Iniciar impressão?';

  @override
  String gcodeConfirmBody(String file) {
    return 'Iniciar a impressão de $file?';
  }

  @override
  String gcodeStarted(String file) {
    return 'Impressão de $file iniciada';
  }

  @override
  String get gcodeStartFailed => 'Não foi possível iniciar a impressão';

  @override
  String get tileMacros => 'Macros';

  @override
  String get macrosSheetTitle => 'Macros';

  @override
  String get macrosLoading => 'Carregando macros…';

  @override
  String get macrosError => 'Não foi possível carregar as macros';

  @override
  String get macrosEmpty => 'Nenhuma macro nesta impressora';

  @override
  String get macroFavourite => 'Fixar no topo';

  @override
  String get macroUnfavourite => 'Desafixar';

  @override
  String get macroConfirmTitle => 'Executar macro?';

  @override
  String macroConfirmBody(String macro) {
    return 'Executar $macro nesta impressora?';
  }

  @override
  String get macroRunAction => 'Executar';

  @override
  String macroSent(String macro) {
    return 'Enviou $macro';
  }

  @override
  String macroFailed(String macro) {
    return 'Não foi possível enviar $macro';
  }

  @override
  String get preheatTitle => 'Preaquecer';

  @override
  String get preheatHotend => 'Hotend';

  @override
  String get preheatBed => 'Mesa';

  @override
  String get preheatHint =>
      'Deixe uma caixa vazia para manter esse aquecedor inalterado.';

  @override
  String get preheatSoakLabel => 'Temporizador de aquecimento';

  @override
  String get preheatSoakHelp =>
      'Avise-me após estes minutos. 0 = sem temporizador.';

  @override
  String get preheatMinutes => 'min';

  @override
  String get preheatSet => 'Definir';

  @override
  String get preheatNotifWarning =>
      'Os alertas de aquecimento exigem que as notificações de impressão estejam ativadas.';

  @override
  String get preheatNotifEnable => 'Ativar';

  @override
  String preheatSetConfirm(String summary) {
    return 'Definido $summary';
  }

  @override
  String preheatSoakIn(int minutes) {
    return 'alerta de aquecimento em $minutes min';
  }

  @override
  String get preheatFailed => 'Não foi possível definir as temperaturas';

  @override
  String get heatsoakDoneTitle => 'Aquecimento concluído';

  @override
  String heatsoakDoneBody(String printer) {
    return '$printer está na temperatura';
  }

  @override
  String get tutorialOfferTitle => 'Fazer um tour rápido?';

  @override
  String get tutorialOfferBody =>
      'Gostaria de um passo a passo rápido de como o Moongate funciona?';

  @override
  String get tutorialOfferDontRemind => 'Não me lembre novamente';

  @override
  String get tutorialOfferNo => 'Não, obrigado';

  @override
  String get tutorialOfferStart => 'Iniciar tutorial';

  @override
  String get tutorialMenuTitle => 'Tutorial do app';

  @override
  String get tutorialNext => 'Próximo';

  @override
  String get tutorialDone => 'Concluído';

  @override
  String get tutorialSkip => 'Fim';

  @override
  String get tutorialBack => 'Voltar';

  @override
  String get tutorialLocalBar =>
      'A barra de cores mostra como o Moongate está alcançando esta impressora. Verde com um ícone de Wi-Fi significa que você está na mesma rede, uma conexão local direta e rápida.';

  @override
  String get tutorialTunnelBar =>
      'Laranja com um ícone de nuvem significa que você está fora de casa, conectado de forma segura pela internet através do túnel da sua impressora. O Moongate alterna entre os dois automaticamente.';

  @override
  String get tutorialRemoteBuilding =>
      'Quando você parea uma impressora pela primeira vez, o acesso remoto não é instantâneo. Este pequeno marcador de nuvem significa que o túnel seguro ainda está sendo estabelecido em segundo plano. Assim que se transformar em uma nuvem verde com um visto, você poderá alcançar esta impressora de qualquer lugar.';

  @override
  String get tutorialHotend => 'Este é o seu hotend, a temperatura do bico.';

  @override
  String get tutorialBed => 'E esta é a mesa aquecida.';

  @override
  String get tutorialChamber =>
      'Se a sua impressora tiver um sensor de câmara, a temperatura dele também será mostrada aqui.';

  @override
  String get tutorialTemps =>
      'Estas são as temperaturas ao vivo: o hotend (bico), a mesa aquecida e - se a sua impressora tiver um sensor de câmara - a câmara.';

  @override
  String get tutorialEstop =>
      'Esta é a parada de emergência. Ela precisa de um toque duplo para disparar, assim não pode ser acionada por acidente, e interrompe a impressora imediatamente.';

  @override
  String get tutorialWebcam =>
      'Tocar na visualização da câmera abre a interface completa da impressora, a tela ao vivo do Klipper.';

  @override
  String get tutorialPreheatPress =>
      'Pressione e segure o nome de uma impressora ou suas temperaturas para exibir o painel de preaquecimento.';

  @override
  String get tutorialPreheatSheet =>
      'Aqui você pode definir alvos para o hotend e a mesa, além de um tempo opcional de aquecimento.';

  @override
  String get tutorialAddPrinter =>
      'Toque no botão de adição a qualquer momento para adicionar outra impressora e pareá-la.';

  @override
  String get tutorialMenuIcon =>
      'Este é o menu. Você pode abri-lo a qualquer momento a partir daqui.';

  @override
  String get tutorialMenuPrinters =>
      'Adicione outra impressora, ou remova uma que você não usa mais.';

  @override
  String get tutorialMenuBackup =>
      'Faça backup da sua configuração em um arquivo, ou restaure-a em outro dispositivo.';

  @override
  String get tutorialMenuTheme =>
      'Escolha um tema de cores claro, escuro ou totalmente personalizado.';

  @override
  String get tutorialMenuDisplaySize =>
      'Arraste isso para deixar tudo maior ou menor de acordo com os seus olhos.';

  @override
  String get tutorialMenuColumns =>
      'Disponha suas impressoras em uma, duas ou três colunas.';

  @override
  String get tutorialMenuCameras =>
      'Defina com que frequência as câmeras são atualizadas, e ligue ou desligue a câmera de cada impressora.';

  @override
  String get tutorialMenuAbout =>
      'O que há de novo, como o pareamento funciona, um guia de ícones e onde relatar um problema ficam todos aqui.';

  @override
  String get tutorialMenuSupport =>
      'Pagar um café para mim ajuda a manter o Moongate gratuito para todos e de código aberto.';

  @override
  String get tutorialMenuSettings =>
      'Configurações tem duas opções dentro: limpar todas as suas impressoras, ou excluir todos os seus dados e começar completamente do zero.';

  @override
  String get tutorialMenuLanguage =>
      'E você pode alterar o idioma do app aqui - o Moongate fala nove. Esse é o tour, aproveite!';

  @override
  String get notifPauseTooltip => 'Pausar monitoramento';

  @override
  String get notifResumeTooltip => 'Retomar monitoramento';

  @override
  String get notifPausedSnack => 'Monitoramento de impressão pausado';

  @override
  String get notifResumedSnack => 'Monitoramento de impressão retomado';

  @override
  String get tutorialPauseButton =>
      'Isso pausa o monitoramento da impressão. Quando suas impressoras forem ficar desligadas por um tempo, toque nele para interromper as verificações em segundo plano e economizar bateria; toque novamente para retomar.';
}
