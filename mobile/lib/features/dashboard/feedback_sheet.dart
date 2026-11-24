import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/printer_config.dart';
import '../../services/diagnostics_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/app_icons.dart';

/// Bottom sheet behind "Report a problem" (dashboard drawer) and "Trouble
/// pairing?" (Add Printer screen).
///
/// Collects a free-text comment (+ optional contact and which-printer) and
/// attaches a comprehensive diagnostics snapshot (see [DiagnosticsService])
/// before posting to the submit-feedback Edge Function. [pairingContext] is
/// supplied when launched from the pairing screen, so a user who can't pair -
/// and never reaches the dashboard - can still send a report carrying the live
/// discovery + attempt state.
Future<void> showFeedbackSheet(
  BuildContext context,
  List<PrinterConfig> printers, {
  Map<String, dynamic>? pairingContext,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true, // grow with the keyboard
    showDragHandle: true,
    builder: (_) =>
        _FeedbackSheet(printers: printers, pairingContext: pairingContext),
  );
}

class _FeedbackSheet extends StatefulWidget {
  const _FeedbackSheet({required this.printers, this.pairingContext});
  final List<PrinterConfig> printers;
  final Map<String, dynamic>? pairingContext;

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  final _comment = TextEditingController();
  final _contact = TextEditingController();

  // null = "General / not printer-specific".
  String? _printerName;
  bool _sending = false;

  bool get _fromPairing => widget.pairingContext != null;

  @override
  void initState() {
    super.initState();
    // Pre-select when there's exactly one printer - saves a tap.
    if (widget.printers.length == 1) {
      _printerName = widget.printers.single.name;
    }
    _comment.addListener(() => setState(() {})); // live enable/disable Send
  }

  @override
  void dispose() {
    _comment.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final l = AppLocalizations.of(context);
    final comment = _comment.text.trim();
    if (comment.isEmpty || _sending) return;
    setState(() => _sending = true);

    var diagnostics = <String, dynamic>{};
    try {
      diagnostics = await DiagnosticsService.collect(
        printers: widget.printers,
        pairingContext: widget.pairingContext,
      );
    } catch (_) {/* best-effort - send the comment regardless */}

    // Lift version + platform into the dedicated columns (easy dashboard
    // filtering); the full picture lives in `diagnostics`.
    String? appVersion;
    String? platform;
    final app = diagnostics['app'];
    if (app is Map) appVersion = '${app['version']} (build ${app['build']})';
    final dev = diagnostics['device'];
    if (dev is Map) {
      platform = dev['platform'] == 'android'
          ? '${dev['os']} - ${dev['manufacturer']} ${dev['model']}'
          : dev['os']?.toString();
    }

    try {
      await SupabaseService.instance.submitFeedback(
        comment: comment,
        contact: _contact.text,
        printerName: _printerName,
        appVersion: appVersion,
        platform: platform,
        diagnostics: diagnostics,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.feedbackSuccess)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.feedbackError),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final canSend = _comment.text.trim().isNotEmpty && !_sending;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(AppIcons.bug_report_outlined,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Text(
                      _fromPairing
                          ? l.feedbackTroublePairing
                          : l.feedbackTitle,
                      style: theme.textTheme.titleLarge),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _fromPairing
                    ? l.feedbackPairingDescription
                    : l.feedbackDescription,
                style:
                    theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
              ),
              const SizedBox(height: 16),

              // Which printer - only when there's a choice to make.
              if (widget.printers.isNotEmpty) ...[
                DropdownButtonFormField<String?>(
                  initialValue: _printerName,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l.feedbackWhichPrinter,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(l.feedbackGeneralOption),
                    ),
                    ...widget.printers.map(
                      (p) => DropdownMenuItem<String?>(
                        value: p.name,
                        child: Text(p.name),
                      ),
                    ),
                  ],
                  onChanged:
                      _sending ? null : (v) => setState(() => _printerName = v),
                ),
                const SizedBox(height: 12),
              ],

              TextField(
                controller: _comment,
                enabled: !_sending,
                minLines: 4,
                maxLines: 8,
                maxLength: 5000,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: l.feedbackCommentLabel,
                  hintText: l.feedbackCommentHint,
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              TextField(
                controller: _contact,
                enabled: !_sending,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: l.feedbackContactLabel,
                  hintText: l.feedbackContactHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: canSend ? _send : null,
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(AppIcons.send_outlined),
                label: Text(_sending ? l.feedbackSending : l.feedbackSend),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
