import 'package:flutter/material.dart';

import '../tokens.dart';

class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.trailingText,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// When set, the tile ends in a switch.
  final bool? value;
  final String? trailingText;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = AppTokens.of(context);
    return ListTile(
      leading: SettingsIcon(icon: icon),
      title: Text(title, style: TextStyle(color: t.textPrimary)),
      subtitle: subtitle == null ? null : Text(subtitle!, style: TextStyle(color: t.textSecondary)),
      trailing: TileTrailing(value: value, text: trailingText),
    );
  }
}

class TileTrailing extends StatelessWidget {
  const TileTrailing({super.key, this.value, this.text});

  final bool? value;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = AppTokens.of(context);
    return value != null
        ? Switch(value: value!, onChanged: (_) {})
        : text != null
        ? Text(text!, style: TextStyle(color: t.textSecondary))
        : Icon(Icons.chevron_right, color: t.textSecondary);
  }
}

class SettingsIcon extends StatelessWidget {
  const SettingsIcon({super.key, required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = AppTokens.of(context);
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(color: t.surfaceMuted, borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, size: 20, color: t.brandAccent),
    );
  }
}
