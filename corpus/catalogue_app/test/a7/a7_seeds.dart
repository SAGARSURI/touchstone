// The A7 sample, shared by the tool's runs and the device's
// (doc/phase3/a7_expectations.md).

import 'package:flutter/material.dart';

const int a7FirstSeed = int.fromEnvironment('A7_START');
const int a7SeedCount = int.fromEnvironment('A7_COUNT', defaultValue: 300);

/// No overscroll indicator: its render objects differ by renderer, and the
/// same seed must pick the same mutation in the widget tests and on the
/// device.
final ScrollBehavior a7ScrollBehavior = const MaterialScrollBehavior().copyWith(overscroll: false);
