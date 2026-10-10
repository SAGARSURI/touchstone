import 'package:flutter/material.dart';

import '../components/section_header.dart';
import '../components/settings_tile.dart';

/// Level 2: list tiles, switches, icons and dividers.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.notifications = true, this.biometrics = false});

  final bool notifications;
  final bool biometrics;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: <Widget>[
          const SectionHeader('Account'),
          const SettingsTile(icon: Icons.person_outline, title: 'Profile', subtitle: 'Name, email, phone'),
          const Divider(height: 1),
          const SettingsTile(icon: Icons.account_balance_outlined, title: 'Linked bank accounts', trailingText: '2'),
          const SectionHeader('Preferences'),
          SettingsTile(icon: Icons.notifications_none, title: 'Notifications', value: notifications),
          const Divider(height: 1),
          SettingsTile(icon: Icons.fingerprint, title: 'Unlock with biometrics', value: biometrics),
          const Divider(height: 1),
          const SettingsTile(icon: Icons.language, title: 'Language', trailingText: 'English'),
          const SectionHeader('About'),
          const SettingsTile(icon: Icons.description_outlined, title: 'Terms of service'),
          const Divider(height: 1),
          const SettingsTile(icon: Icons.info_outline, title: 'Version', trailingText: '1.0.0'),
        ],
      ),
    );
  }
}
