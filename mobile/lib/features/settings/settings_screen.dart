import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/auth_service.dart';
import '../../services/vpn_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _ttlDays = 30;
  bool _disconnectOnBackground = true;

  static const _ttlOptions = [1, 7, 30, 0]; // 0 = never
  static const _ttlLabels = ['1 day', '7 days', '30 days', 'Never'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _ttlDays = prefs.getInt('ttl_days') ?? 30;
      _disconnectOnBackground =
          prefs.getBool('disconnect_on_background') ?? true;
    });
  }

  Future<void> _saveTtl(int days) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('ttl_days', days);
    setState(() => _ttlDays = days);
  }

  Future<void> _saveDisconnectPref(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('disconnect_on_background', value);
    setState(() => _disconnectOnBackground = value);
  }

  Future<void> _signOut() async {
    await VpnService.instance.disconnect();
    await AuthService.instance.signOut();
    if (!mounted) return;
    context.go('/pair');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const ListTile(
            title: Text('Session token expiry',
                style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
                'How long before you need to re-pair the app with your printer.'),
          ),
          ..._ttlOptions.asMap().entries.map((e) {
            final days = e.value;
            final label = _ttlLabels[e.key];
            return RadioListTile<int>(
              title: Text(label),
              value: days,
              groupValue: _ttlDays,
              onChanged: (v) => _saveTtl(v!),
            );
          }),
          const Divider(),
          SwitchListTile(
            title: const Text('Disconnect VPN when app is minimised'),
            subtitle: const Text(
                'Recommended — prevents background battery drain.'),
            value: _disconnectOnBackground,
            onChanged: _saveDisconnectPref,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text('Remove printer & sign out',
                style: TextStyle(color: Colors.redAccent)),
            onTap: _signOut,
          ),
        ],
      ),
    );
  }
}
