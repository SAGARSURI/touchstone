// The digest of rasterized pixels: fast enough for every opaque node on every
// pull request (A10), and changed by any change to any byte.

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:touchstone/src/recorder/pixel_digest.dart';

void main() {
  test('equal pixels give the same 128-bit digest', () {
    final a = Uint8List.fromList(List<int>.generate(4096, (int i) => i * 7 % 256));
    final b = Uint8List.fromList(a);
    expect(pixelDigest(a), pixelDigest(b));
    expect(pixelDigest(a), matches(RegExp(r'^[0-9a-f]{32}$')));
  });

  test('a change to any one byte changes the digest', () {
    final random = Random(1);
    final base = Uint8List.fromList(List<int>.generate(1024, (_) => random.nextInt(256)));
    final String digest = pixelDigest(base);
    for (var i = 0; i < base.length; i++) {
      final changed = Uint8List.fromList(base)..[i] ^= 1 + random.nextInt(255);
      expect(pixelDigest(changed), isNot(digest), reason: 'byte $i');
    }
  });

  test('length and swapped words change the digest', () {
    final a = Uint8List.fromList(<int>[1, 0, 0, 0, 2, 0, 0, 0]);
    final b = Uint8List.fromList(<int>[2, 0, 0, 0, 1, 0, 0, 0]);
    expect(pixelDigest(a), isNot(pixelDigest(b)));
    expect(pixelDigest(Uint8List(8)), isNot(pixelDigest(Uint8List(12))));
    expect(pixelDigest(Uint8List(0)), isNot(pixelDigest(Uint8List(4))));
  });
}
