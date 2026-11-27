/// v0.9.84: which web interface the printer page opens when the Pi serves
/// more than one (Mainsail on 80 and Fluidd on 81 is the KIAUH two-UI
/// layout). The plugin (0.6.32+) lists them in /status `frontends`; the user
/// picks one from the printer page's switch button and the pick persists per
/// printer ([PrinterConfig.preferredUi]). At home the page loads the chosen
/// port directly; over the tunnel the app sets an `mg_ui=<type>` cookie and
/// the Pi's auth proxy routes to that port. Pure functions, unit-tested in
/// test/frontend_choice_test.dart.
library;

import '../models/printer_config.dart';

/// The `frontends` list from a plugin /status answer. Empty on plugins
/// before 0.6.32 and until the plugin's first probe has run.
List<PrinterFrontend> parseFrontendList(Map<String, dynamic>? moongateResult) {
  if (moongateResult == null) return const [];
  return PrinterFrontend.listFromJson(moongateResult['frontends']);
}

/// True when the printer page should show the switch: two or more
/// interfaces reported. A one-UI printer looks exactly as before.
bool frontendSwitchAvailable(List<PrinterFrontend> frontends) =>
    frontends.length >= 2;

/// The port a base URL names, with the scheme's default when it names none
/// (`http://192.168.1.50` -> 80), so it can be matched against the plugin's
/// `frontends` ports.
int portOfUrl(String url) {
  final u = Uri.tryParse(url);
  if (u == null || !u.hasScheme) return 80;
  if (u.hasPort) return u.port;
  return u.scheme == 'https' ? 443 : 80;
}

/// The interface the printer page is on, or about to open: the persisted
/// pick when the printer still lists it, else the one on the Pi's advertised
/// port ([defaultPort], the port of the lanUrl the plugin hands out), else
/// the first listed. Null when nothing is listed (older plugin).
PrinterFrontend? currentFrontend(
  List<PrinterFrontend> frontends,
  String? preferredUi, {
  required int defaultPort,
}) {
  if (frontends.isEmpty) return null;
  if (preferredUi != null) {
    for (final f in frontends) {
      if (f.type == preferredUi) return f;
    }
  }
  for (final f in frontends) {
    if (f.port == defaultPort) return f;
  }
  return frontends.first;
}

/// The interface the switch button offers: with exactly two listed, the one
/// that is NOT [current] (the button shows that UI's logo and one tap
/// toggles); with three or more the button opens a picker instead, so
/// there is no single "other" and this returns null.
PrinterFrontend? otherFrontend(
    List<PrinterFrontend> frontends, PrinterFrontend? current) {
  if (frontends.length != 2 || current == null) return null;
  for (final f in frontends) {
    if (f.type != current.type) return f;
  }
  return null;
}

/// [lanUrl] re-pointed at [port]: `http://192.168.1.50` + 81 ->
/// `http://192.168.1.50:81`; port 80 on http (443 on https) drops the suffix
/// so the result matches the form the plugin's local_ip + http_port
/// produces. A URL that already names [port] comes back unchanged.
String lanUrlForPort(String lanUrl, int port) {
  final u = Uri.tryParse(lanUrl);
  if (u == null || !u.hasScheme || u.host.isEmpty) return lanUrl;
  final isDefault = (u.scheme == 'http' && port == 80) ||
      (u.scheme == 'https' && port == 443);
  final host = u.host.contains(':') ? '[${u.host}]' : u.host;
  return isDefault ? '${u.scheme}://$host' : '${u.scheme}://$host:$port';
}

/// The URL the printer page loads at home for [printer]'s pick: [lanUrl]
/// itself unless the printer lists two or more interfaces and the pick (or
/// the default) sits on another port. The LAN liveness probe still runs on
/// the plain [lanUrl]: that is where Moonraker answers either way.
String lanUrlForChoice(String lanUrl, PrinterConfig printer) {
  final chosen = chosenFrontend(printer, defaultPort: portOfUrl(lanUrl));
  if (chosen == null) return lanUrl;
  return lanUrlForPort(lanUrl, chosen.port);
}

/// The interface [printer] should open, from its persisted list and pick;
/// null when there is no choice to make (fewer than two listed), in which
/// case the page loads exactly as before v0.9.84.
PrinterFrontend? chosenFrontend(PrinterConfig printer,
    {required int defaultPort}) {
  if (!frontendSwitchAvailable(printer.frontends)) return null;
  return currentFrontend(printer.frontends, printer.preferredUi,
      defaultPort: defaultPort);
}

/// The value of the tunnel's `mg_ui` cookie for [printer]: the chosen
/// interface's type, or 'default' (the proxy's MG_MAINSAIL upstream, which
/// is what every pre-v0.9.84 session got) when there is nothing to choose.
String mgUiCookieValue(PrinterConfig printer, {required int defaultPort}) =>
    chosenFrontend(printer, defaultPort: defaultPort)?.type ?? 'default';

/// User-facing name of an interface type.
String frontendDisplayName(String type) => switch (type) {
      'mainsail'  => 'Mainsail',
      'fluidd'    => 'Fluidd',
      'octoprint' => 'OctoPrint',
      _ => type.isEmpty ? type : type[0].toUpperCase() + type.substring(1),
    };

/// The monochrome logo mark asset for a type, or null for one we have no
/// mark for (the caller falls back to a glyph from the icon set).
String? frontendMarkAsset(String type) => switch (type) {
      'mainsail' => 'assets/icons/mainsail_mark.svg',
      'fluidd'   => 'assets/icons/fluidd_mark.svg',
      _          => null,
    };

/// The logo the dashboard tile and single-printer view show for a printer:
/// the pick when one is persisted, else what the root page sniff found
/// ([detected], live, else the persisted [PrinterConfig.uiType]). The
/// sniff reads the Pi's default port, so without this a Fluidd pick would
/// still show the Mainsail sail while the printer is off.
String? effectiveUiType(PrinterConfig printer, String? detected) =>
    printer.preferredUi ?? detected ?? printer.uiType;
