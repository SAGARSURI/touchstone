// Toolchain fingerprint (spec: Snapshot fields, toolchain; Self-checks).
//
// A baseline and a run whose fingerprints differ are routed to migration, not
// compared. The renderer is part of it: under Impeller the widget tree itself
// differs in widget tests (Phase 0 decision 1).

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

/// The library version, kept equal to pubspec.yaml by a test.
const String touchstoneVersion = '0.0.1-dev.0';

/// Fonts loaded for snapshot tests. With none, tests render with the
/// FlutterTest font that ships with the test environment.
abstract final class SnapshotFonts {
  static final Map<String, String> _loaded = <String, String>{};

  /// Loads [bytes] as [family] and records its hash in the fingerprint.
  static Future<void> load(String family, List<Uint8List> bytes) async {
    final loader = FontLoader(family);
    for (final b in bytes) {
      loader.addFont(Future<ByteData>.value(ByteData.sublistView(b)));
    }
    await loader.load();
    final digest = sha256.convert(<int>[for (final b in bytes) ...sha256.convert(b).bytes]);
    _loaded[family] = digest.toString();
  }

  /// True when no font was loaded through [load].
  static bool get usingTestFont => _loaded.isEmpty;

  static String get fingerprint {
    if (_loaded.isEmpty) {
      return 'FlutterTest';
    }
    final List<String> entries = (_loaded.entries.map((e) => '${e.key}:${e.value}').toList()..sort());
    return 'FlutterTest+${sha256.convert(utf8.encode(entries.join(','))).toString().substring(0, 16)}';
  }
}

/// The renderer `flutter test` used: Skia unless `--enable-impeller` was
/// passed. Shader image filters are supported only by Impeller.
String get rendererName => ui.ImageFilter.isShaderFilterSupported ? 'impeller' : 'skia';

Map<String, String> toolchainFingerprint() => <String, String>{
  'flutter': FlutterVersion.version ?? '?',
  'framework': FlutterVersion.frameworkRevision ?? '?',
  'engine': FlutterVersion.engineRevision ?? '?',
  'dart': FlutterVersion.dartVersion ?? '?',
  'renderer': rendererName,
  'library': touchstoneVersion,
  'fonts': SnapshotFonts.fingerprint,
};
