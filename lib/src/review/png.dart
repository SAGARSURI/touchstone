// PNG for review crops (spec: Developer experience, Review): 8-bit RGBA,
// non-interlaced, which is what Flutter's encoder writes. Pure Dart, so the
// review command needs no image package.

import 'dart:io';
import 'dart:typed_data';

/// An RGBA image, four bytes per pixel, rows top to bottom.
class Rgba {
  Rgba(this.width, this.height, this.pixels) : assert(pixels.length == width * height * 4);

  Rgba.blank(this.width, this.height) : pixels = Uint8List(width * height * 4);

  final int width;
  final int height;
  final Uint8List pixels;
}

const List<int> _signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];

/// [image] as PNG bytes.
Uint8List encodePng(Rgba image) {
  final int stride = image.width * 4;
  final raw = Uint8List((stride + 1) * image.height);
  for (var y = 0; y < image.height; y++) {
    raw[y * (stride + 1)] = 0;
    raw.setRange(y * (stride + 1) + 1, (y + 1) * (stride + 1), image.pixels, y * stride);
  }
  final header = ByteData(13)
    ..setUint32(0, image.width)
    ..setUint32(4, image.height)
    ..setUint8(8, 8)
    ..setUint8(9, 6);
  final out = BytesBuilder(copy: false)..add(_signature);
  _chunk(out, 'IHDR', header.buffer.asUint8List());
  _chunk(out, 'IDAT', Uint8List.fromList(ZLibCodec(level: 6).encode(raw)));
  _chunk(out, 'IEND', Uint8List(0));
  return out.takeBytes();
}

/// [bytes] (an 8-bit RGBA, non-interlaced PNG) as pixels.
Rgba decodePng(Uint8List bytes) {
  for (var i = 0; i < _signature.length; i++) {
    if (bytes[i] != _signature[i]) {
      throw const FormatException('not a PNG');
    }
  }
  final view = ByteData.sublistView(bytes);
  var at = _signature.length;
  int? width;
  int? height;
  final data = BytesBuilder(copy: false);
  while (at < bytes.length) {
    final int length = view.getUint32(at);
    final String type = String.fromCharCodes(bytes, at + 4, at + 8);
    final Uint8List body = Uint8List.sublistView(bytes, at + 8, at + 8 + length);
    if (type == 'IHDR') {
      width = ByteData.sublistView(body).getUint32(0);
      height = ByteData.sublistView(body).getUint32(4);
      if (body[8] != 8 || body[9] != 6 || body[12] != 0) {
        throw const FormatException('only 8-bit RGBA, non-interlaced PNGs are read');
      }
    } else if (type == 'IDAT') {
      data.add(body);
    } else if (type == 'IEND') {
      break;
    }
    at += 12 + length;
  }
  if (width == null || height == null) {
    throw const FormatException('PNG without a header');
  }
  final raw = Uint8List.fromList(ZLibCodec().decode(data.takeBytes()));
  final int stride = width * 4;
  final out = Uint8List(stride * height);
  for (var y = 0; y < height; y++) {
    final int filter = raw[y * (stride + 1)];
    final int from = y * (stride + 1) + 1;
    for (var x = 0; x < stride; x++) {
      final int a = x >= 4 ? out[y * stride + x - 4] : 0;
      final int b = y > 0 ? out[(y - 1) * stride + x] : 0;
      final int c = x >= 4 && y > 0 ? out[(y - 1) * stride + x - 4] : 0;
      final int v = raw[from + x];
      out[y * stride + x] =
          switch (filter) {
            0 => v,
            1 => v + a,
            2 => v + b,
            3 => v + ((a + b) >> 1),
            4 => v + _paeth(a, b, c),
            _ => throw FormatException('unknown PNG filter $filter'),
          } &
          0xFF;
    }
  }
  return Rgba(width, height, out);
}

int _paeth(int a, int b, int c) {
  final int p = a + b - c;
  final int pa = (p - a).abs();
  final int pb = (p - b).abs();
  final int pc = (p - c).abs();
  return pa <= pb && pa <= pc ? a : (pb <= pc ? b : c);
}

void _chunk(BytesBuilder out, String type, Uint8List body) {
  final typed = Uint8List.fromList(type.codeUnits);
  out
    ..add((ByteData(4)..setUint32(0, body.length)).buffer.asUint8List())
    ..add(typed)
    ..add(body)
    ..add((ByteData(4)..setUint32(0, _crc(typed, body))).buffer.asUint8List());
}

final List<int> _crcTable = List<int>.generate(256, (int n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc(Uint8List a, Uint8List b) {
  var c = 0xFFFFFFFF;
  for (final Uint8List part in <Uint8List>[a, b]) {
    for (final int byte in part) {
      c = _crcTable[(c ^ byte) & 0xFF] ^ (c >> 8);
    }
  }
  return c ^ 0xFFFFFFFF;
}
