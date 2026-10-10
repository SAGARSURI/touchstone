import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../tokens.dart';

/// Stands in for a native map view. There is no platform side, so the
/// surface shows nothing on its own: the app draws its pins over it.
class MapPlaceholderController extends PlatformViewController {
  MapPlaceholderController(this.viewId);

  @override
  final int viewId;

  @override
  Future<void> clearFocus() async {}

  @override
  Future<void> dispatchPointerEvent(PointerEvent event) async {}

  @override
  Future<void> dispose() async {}
}

/// A branch shown as a pin on the map.
class Branch {
  const Branch(this.name, this.at);

  final String name;

  /// Position on the map, as fractions of its width and height.
  final Offset at;
}

const List<Branch> branches = <Branch>[
  Branch('Harbor St', Offset(0.22, 0.30)),
  Branch('Market Sq', Offset(0.58, 0.44)),
  Branch('North Gate', Offset(0.74, 0.18)),
  Branch('Riverside', Offset(0.36, 0.66)),
];

/// Level 5: a map placeholder (a platform view) under a blurred header, with
/// pins over the map and a card below it. Exercises platform views, backdrop
/// filters and the coverage report.
class MapScreen extends StatelessWidget {
  MapScreen({super.key, PlatformViewController? controller, this.selected = 1})
    : controller = controller ?? MapPlaceholderController(1);

  final PlatformViewController controller;

  /// The branch shown in the card.
  final int selected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints c) => Stack(
                children: <Widget>[
                  Positioned.fill(child: MapSurface(controller: controller)),
                  for (int i = 0; i < branches.length; i++)
                    Positioned(
                      left: branches[i].at.dx * c.maxWidth - 14,
                      top: branches[i].at.dy * c.maxHeight - 28,
                      child: MapPin(selected: i == selected),
                    ),
                ],
              ),
            ),
          ),
          const Positioned(left: 0, right: 0, top: 0, child: BlurredHeader(title: 'Branches near you')),
          Positioned(
            left: Space.m,
            right: Space.m,
            bottom: Space.l,
            child: BranchCard(branch: branches[selected]),
          ),
        ],
      ),
    );
  }
}

class MapSurface extends StatelessWidget {
  const MapSurface({super.key, required this.controller});

  final PlatformViewController controller;

  @override
  Widget build(BuildContext context) => PlatformViewSurface(
    controller: controller,
    gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
    hitTestBehavior: PlatformViewHitTestBehavior.opaque,
  );
}

class MapPin extends StatelessWidget {
  const MapPin({super.key, required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = AppTokens.of(context);
    return Icon(Icons.location_on, size: 28, color: selected ? t.brandAccent : t.textSecondary);
  }
}

class BlurredHeader extends StatelessWidget {
  const BlurredHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = AppTokens.of(context);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          height: 104,
          color: t.surface.withValues(alpha: 0.72),
          padding: const EdgeInsets.fromLTRB(Space.m, 56, Space.m, Space.s),
          alignment: Alignment.bottomLeft,
          child: Text(
            title,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: t.textPrimary),
          ),
        ),
      ),
    );
  }
}

class BranchCard extends StatelessWidget {
  const BranchCard({super.key, required this.branch});

  final Branch branch;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = AppTokens.of(context);
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      color: t.surface,
      child: ListTile(
        leading: Icon(Icons.account_balance, color: t.brandAccent),
        title: Text(branch.name),
        subtitle: const Text('Open until 18:00'),
        trailing: const Icon(Icons.directions),
      ),
    );
  }
}
