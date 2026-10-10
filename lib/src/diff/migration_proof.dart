// The pixel proof for a toolchain migration (spec: A12; Diff engine, toolchain
// check).
//
// A baseline holds hashes, not pixels, so the old pixels come from rendering
// again on the old toolchain. Migration runs in two steps. On the old
// toolchain, a snapshot that matches its baseline writes a pending proof: the
// toolchain, the baseline's root hash and a digest of the whole test view. On
// the new toolchain, the baseline is rewritten, and a proof beside it records
// both sides. Review passes a migrated snapshot only when its proof names both
// baselines exactly and the pixels are identical.

import 'dart:convert';

import 'changes.dart';

const String _magic = 'touchstone-migration';
const int migrationProofVersion = 1;

/// A rasterized test view: its size in physical pixels and its pixel digest.
class ViewPixels {
  const ViewPixels(this.width, this.height, this.digest);

  final int width;
  final int height;
  final String digest;

  bool sameAs(ViewPixels other) => width == other.width && height == other.height && digest == other.digest;

  @override
  String toString() => '${width}x$height $digest';

  static ViewPixels parse(String text) {
    final RegExpMatch? m = RegExp(r'^(\d+)x(\d+) ([0-9a-f]+)$').firstMatch(text);
    if (m == null) {
      throw FormatException('Expected "<width>x<height> <digest>", found: $text');
    }
    return ViewPixels(int.parse(m[1]!), int.parse(m[2]!), m[3]!);
  }
}

/// One side of a migration: the toolchain, the baseline's root hash on it, and
/// the view's pixels when they were rendered.
class MigrationSide {
  const MigrationSide(this.toolchain, this.rootHash, this.pixels);

  final Map<String, String> toolchain;
  final String rootHash;
  final ViewPixels? pixels;
}

/// What migration records for one snapshot. [before] alone is the pending
/// proof written on the old toolchain; with [after] it is the proof committed
/// beside the rewritten baseline.
class MigrationProof {
  const MigrationProof(this.snapshotId, this.before, [this.after]);

  final String snapshotId;
  final MigrationSide before;
  final MigrationSide? after;

  /// Both sides were rendered, at the same size, with the same digest.
  bool get pixelsIdentical {
    final ViewPixels? a = before.pixels;
    final ViewPixels? b = after?.pixels;
    return a != null && b != null && a.sameAs(b);
  }

  /// Whether this proof is about [report]'s two baselines: the same toolchains
  /// and root hashes.
  bool covers(ChangeReport report) =>
      report.kind == ReportKind.migration &&
      after != null &&
      report.snapshotId == snapshotId &&
      _same(report.beforeToolchain!, before.toolchain) &&
      _same(report.afterToolchain!, after!.toolchain) &&
      report.beforeRoot == before.rootHash &&
      report.afterRoot == after!.rootHash;

  String toText() {
    final out = StringBuffer()
      ..writeln('$_magic $migrationProofVersion')
      ..writeln('id\t${jsonEncode(snapshotId)}');
    void side(String name, MigrationSide s) {
      out
        ..writeln('$name.toolchain\t${_pairs(s.toolchain)}')
        ..writeln('$name.root\t${s.rootHash}')
        ..writeln('$name.pixels\t${s.pixels ?? 'none'}');
    }

    side('before', before);
    if (after != null) {
      side('after', after!);
      out.writeln('pixels\t${pixelsIdentical ? 'identical' : 'differ'}');
    }
    return out.toString();
  }

  static MigrationProof parse(String text) {
    final List<String> lines = const LineSplitter().convert(text);
    if (lines.isEmpty || lines.first != '$_magic $migrationProofVersion') {
      throw FormatException('Not a touchstone migration proof, version $migrationProofVersion');
    }
    final fields = <String, String>{
      for (final String line in lines.skip(1))
        if (line.contains('\t')) line.substring(0, line.indexOf('\t')): line.substring(line.indexOf('\t') + 1),
    };
    String field(String name) => fields[name] ?? (throw FormatException('Migration proof without $name'));
    MigrationSide side(String name) {
      final String pixels = field('$name.pixels');
      return MigrationSide(
        _parsePairs(field('$name.toolchain')),
        field('$name.root'),
        pixels == 'none' ? null : ViewPixels.parse(pixels),
      );
    }

    final proof = MigrationProof(
      jsonDecode(field('id')) as String,
      side('before'),
      fields.containsKey('after.root') ? side('after') : null,
    );
    if (proof.after != null && field('pixels') != (proof.pixelsIdentical ? 'identical' : 'differ')) {
      throw const FormatException('Migration proof whose pixels line does not match its digests');
    }
    return proof;
  }
}

String _pairs(Map<String, String> m) => m.entries.map((e) => '${e.key}=${jsonEncode(e.value)}').join('\t');

Map<String, String> _parsePairs(String s) => <String, String>{
  for (final String p in s.isEmpty ? const <String>[] : s.split('\t'))
    p.substring(0, p.indexOf('=')): jsonDecode(p.substring(p.indexOf('=') + 1)) as String,
};

bool _same(Map<String, String> a, Map<String, String> b) =>
    a.length == b.length && a.entries.every((MapEntry<String, String> e) => b[e.key] == e.value);
