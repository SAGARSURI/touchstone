import 'package:flutter/material.dart';

import '../components/app_button.dart';
import '../components/section_header.dart';
import '../tokens.dart';

/// Level 1: primary, secondary, disabled and loading buttons.
class ButtonSetScreen extends StatelessWidget {
  const ButtonSetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Buttons')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: Space.m),
        children: const <Widget>[
          SectionHeader('Primary'),
          AppButton(key: ValueKey<String>('primary'), label: 'Continue'),
          SectionHeader('Secondary'),
          AppButton(key: ValueKey<String>('secondary'), label: 'Cancel', variant: ButtonVariant.secondary),
          SectionHeader('Disabled'),
          AppButton(key: ValueKey<String>('disabled'), label: 'Continue', enabled: true),
          SectionHeader('Loading'),
          AppButton(key: ValueKey<String>('loading'), label: 'Continue', loading: true),
        ],
      ),
    );
  }
}
