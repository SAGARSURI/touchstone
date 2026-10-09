// The digest of rasterized pixels (A10).
//
// SHA-256 in Dart hashed about 90 MB of pixels per second in a widget test,
// and the catalogue's opaque nodes rasterize about 85 MB per run, so the
// pixel digest was most of the cost of a capture. Nothing here needs a
// cryptographic hash: a baseline is compared with the same code's output,
// and no one chooses pixels to collide. This digest reads the pixels as
// 32-bit words in two 64-bit lanes:
//
// - lane 1 is FNV-1a over words; each step is a bijection of the state for a
//   given word, so a change to any single word always changes the result;
// - lane 2 multiplies by a different odd constant and xor-shifts, so a
//   change that cancels in lane 1 is independent in lane 2.
//
// The length goes in last, and each lane is finished with MurmurHash3's
// 64-bit mixer. The result is 128 bits as 32 hex digits. It needs 64-bit
// integer arithmetic, which widget tests have (they run on the Dart VM).

import 'dart:typed_data';

const int _fnvOffset = 0xcbf29ce484222325;
const int _fnvPrime = 0x100000001b3;
const int _golden = 0x9e3779b97f4a7c15;

/// A 128-bit digest of [bytes], as 32 lowercase hex digits.
String pixelDigest(Uint8List bytes) {
  final int words = bytes.lengthInBytes ~/ 4;
  final Uint32List view = bytes.offsetInBytes % 4 == 0
      ? bytes.buffer.asUint32List(bytes.offsetInBytes, words)
      : Uint8List.fromList(bytes.sublist(0, words * 4)).buffer.asUint32List();
  var h1 = _fnvOffset;
  var h2 = _golden;
  for (var i = 0; i < words; i++) {
    final int w = view[i];
    h1 = (h1 ^ w) * _fnvPrime;
    h2 = (h2 ^ w) * _golden;
    h2 ^= h2 >>> 31;
  }
  var tail = 0;
  for (var i = words * 4; i < bytes.lengthInBytes; i++) {
    tail = (tail << 8) | bytes[i];
  }
  final int length = bytes.lengthInBytes;
  h1 = (((h1 ^ tail) * _fnvPrime) ^ length) * _fnvPrime;
  h2 = (((h2 ^ tail) * _golden) ^ length) * _golden;
  return '${_hex(_mix(h1))}${_hex(_mix(h2))}';
}

int _mix(int x) {
  x ^= x >>> 33;
  x *= 0xff51afd7ed558ccd;
  x ^= x >>> 33;
  x *= 0xc4ceb9fe1a85ec53;
  x ^= x >>> 33;
  return x;
}

String _hex(int x) =>
    '${((x >>> 32) & 0xffffffff).toRadixString(16).padLeft(8, '0')}${(x & 0xffffffff).toRadixString(16).padLeft(8, '0')}';
