import 'package:flutter/material.dart';

import '../tokens.dart';

enum ButtonVariant { primary, secondary }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.variant = ButtonVariant.primary,
    this.enabled = true,
    this.loading = false,
    this.onPressed,
  });

  final String label;
  final ButtonVariant variant;
  final bool enabled;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = AppTokens.of(context);
    final bool primary = variant == ButtonVariant.primary;
    final VoidCallback? action = enabled && !loading ? (onPressed ?? () {}) : null;
    final Widget content = loading
        ? const SizedBox(width: 18, height: 18, child: _Spinner())
        : Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600));
    final ButtonStyle style = primary
        ? FilledButton.styleFrom(backgroundColor: t.brandAccent, minimumSize: const Size.fromHeight(48))
        : OutlinedButton.styleFrom(foregroundColor: t.brandAccent, minimumSize: const Size.fromHeight(48));
    return Semantics(
      label: loading ? '$label, loading' : null,
      child: primary
          ? FilledButton(onPressed: action, style: style, child: content)
          : OutlinedButton(onPressed: action, style: style, child: content),
    );
  }
}

/// A static progress mark: a loading button must still settle, so it does
/// not animate.
class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const CircularProgressIndicator(value: 0.7, strokeWidth: 2.5);
}
