import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/app_lock_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/pin_service.dart';
import 'pin_pad.dart';
import '../../widgets/app_icons.dart';

/// Configure the optional app lock: enable/disable (with PIN setup/verify),
/// biometric unlock, auto-lock timeout, and changing the PIN. Reached from the
/// dashboard drawer ("App lock") at /settings/app-lock.
class AppLockSettingsScreen extends ConsumerWidget {
  const AppLockSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(appLockEnabledProvider);
    final biometric = ref.watch(biometricUnlockProvider);
    final timeout = ref.watch(autoLockTimeoutProvider);
    final bioAvailable =
        ref.watch(biometricAvailableProvider).valueOrNull ?? false;
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.appLockTitle)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              l.appLockIntro,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(AppIcons.lock_outline),
            title: Text(l.appLockTitle),
            subtitle: Text(l.appLockSubtitle),
            value: enabled,
            onChanged: (v) => _toggleEnabled(context, ref, v),
          ),
          if (enabled) ...[
            const Divider(),
            if (bioAvailable)
              SwitchListTile(
                secondary: const Icon(AppIcons.fingerprint),
                title: Text(l.appLockBiometricTitle),
                subtitle: Text(l.appLockBiometricSubtitle),
                value: biometric,
                onChanged: (v) =>
                    ref.read(biometricUnlockProvider.notifier).set(v),
              ),
            ListTile(
              leading: const Icon(AppIcons.password_outlined),
              title: Text(l.appLockChangePin),
              onTap: () => _changePin(context, ref),
            ),
            ListTile(
              leading: const Icon(AppIcons.timer_outlined),
              title: Text(l.appLockAutoLock),
              subtitle: Text(_timeoutLabel(l, timeout)),
              onTap: () => _pickTimeout(context, ref, timeout),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _toggleEnabled(
      BuildContext context, WidgetRef ref, bool value) async {
    if (value) {
      final pin = await _setNewPin(context);
      if (pin == null) return; // cancelled → the preference stays off
      await ref.read(appLockEnabledProvider.notifier).set(true);
    } else {
      if (!await _verifyCurrent(context)) return;
      await ref.read(appLockEnabledProvider.notifier).set(false);
      await ref.read(biometricUnlockProvider.notifier).set(false);
      await PinService.instance.clearPin();
    }
  }

  Future<void> _changePin(BuildContext context, WidgetRef ref) async {
    if (!await _verifyCurrent(context)) return;
    if (!context.mounted) return;
    final pin = await _setNewPin(context);
    if (pin == null) return;
    if (context.mounted) {
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.appLockPinUpdated)));
    }
  }

  /// Enter then confirm a new PIN; persists it via [PinService]. Returns the
  /// chosen PIN, or null if cancelled.
  Future<String?> _setNewPin(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final pin1 = await showPinSheet(context,
        title: l.appLockChoosePinTitle, subtitle: l.appLockChoosePinSubtitle);
    if (pin1 == null || !context.mounted) return null;
    final pin2 = await showPinSheet(context,
        title: l.appLockConfirmPinTitle,
        expectedLength: pin1.length,
        validator: (p) async => p == pin1 ? null : l.appLockPinsDontMatch);
    if (pin2 == null) return null;
    await PinService.instance.setPin(pin1);
    return pin1;
  }

  /// Prompt for the current PIN, verifying with the throttle. Returns true if
  /// correct.
  Future<bool> _verifyCurrent(BuildContext context) async {
    final len = await PinService.instance.pinLength();
    if (!context.mounted) return false;
    final l = AppLocalizations.of(context);
    final res = await showPinSheet(context,
        title: l.appLockEnterCurrentPin,
        expectedLength: len,
        validator: (p) async {
          final lock = await PinService.instance.remainingLockout();
          if (lock != null) {
            return l.lockTooManyAttempts(lock.inSeconds);
          }
          return await PinService.instance.verifyPin(p) ? null : l.lockWrongPin;
        });
    return res != null;
  }

  Future<void> _pickTimeout(
      BuildContext context, WidgetRef ref, AutoLockTimeout current) async {
    final l = AppLocalizations.of(context);
    final picked = await showDialog<AutoLockTimeout>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l.appLockAutoLock),
        children: AutoLockTimeout.values
            .map((t) => ListTile(
                  title: Text(_timeoutLabel(l, t)),
                  trailing: t == current ? const Icon(AppIcons.check) : null,
                  onTap: () => Navigator.pop(ctx, t),
                ))
            .toList(),
      ),
    );
    if (picked != null) {
      ref.read(autoLockTimeoutProvider.notifier).set(picked);
    }
  }

  /// Localized display label for an [AutoLockTimeout]. Mapped here at the call
  /// site (the enum's own `.label` getter has no [BuildContext]).
  String _timeoutLabel(AppLocalizations l, AutoLockTimeout t) => switch (t) {
        AutoLockTimeout.immediately => l.appLockTimeoutImmediately,
        AutoLockTimeout.oneMinute => l.appLockTimeoutOneMinute,
        AutoLockTimeout.fiveMinutes => l.appLockTimeoutFiveMinutes,
        AutoLockTimeout.fifteenMinutes => l.appLockTimeoutFifteenMinutes,
        AutoLockTimeout.coldLaunchOnly => l.appLockTimeoutColdLaunch,
      };
}
