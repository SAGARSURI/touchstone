import 'package:flutter/material.dart';

import '../tokens.dart';
import 'app_button.dart';

class StatusView extends StatelessWidget {
  const StatusView({super.key, required this.icon, required this.title, required this.message, this.action});

  final IconData icon;
  final String title;
  final String message;
  final String? action;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = AppTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 48, color: t.textSecondary),
            const SizedBox(height: Space.m),
            Text(
              title,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: t.textPrimary),
            ),
            const SizedBox(height: Space.s),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: t.textSecondary),
            ),
            if (action != null) ...<Widget>[
              const SizedBox(height: Space.l),
              AppButton(label: action!, variant: ButtonVariant.secondary),
            ],
          ],
        ),
      ),
    );
  }
}

/// A loading placeholder with a moving highlight. It animates forever, so a
/// test captures it at an explicitly pumped time.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = AppTokens.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (Rect bounds) => LinearGradient(
          begin: Alignment(-1 + 2 * _controller.value, 0),
          end: Alignment(1 + 2 * _controller.value, 0),
          colors: <Color>[t.surfaceMuted, t.surface, t.surfaceMuted],
        ).createShader(bounds),
        child: child,
      ),
      child: widget.child,
    );
  }
}

class SkeletonRow extends StatelessWidget {
  const SkeletonRow({super.key});

  @override
  Widget build(BuildContext context) {
    final AppTokens t = AppTokens.of(context);
    Widget bar(double w) => Container(
      width: w,
      height: 12,
      decoration: BoxDecoration(color: t.surfaceMuted, borderRadius: BorderRadius.circular(6)),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
      child: Row(
        children: <Widget>[
          CircleAvatar(radius: 18, backgroundColor: t.surfaceMuted),
          const SizedBox(width: Space.m),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              bar(120),
              const SizedBox(height: Space.s),
              bar(80),
            ],
          ),
        ],
      ),
    );
  }
}
