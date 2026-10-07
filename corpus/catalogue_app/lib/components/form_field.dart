import 'package:flutter/material.dart';

import '../tokens.dart';

class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    this.controller,
    this.focusNode,
    this.error,
    this.obscure = false,
    this.enabled = true,
    this.autofocus = false,
  });

  final String label;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? error;
  final bool obscure;
  final bool enabled;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.m),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        autofocus: autofocus,
        obscureText: obscure,
        // A blinking cursor never settles; tests capture with it hidden.
        showCursor: false,
        decoration: InputDecoration(
          labelText: label,
          errorText: error,
          filled: true,
          fillColor: t.surfaceMuted,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
