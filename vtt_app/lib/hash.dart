import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 8x8 average-hash. Returns 64-char '0'/'1' string, or '' on decode failure.
String averageHash(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  if (image == null) return '';
  final small = img.copyResize(
    image,
    width: 8,
    height: 8,
    interpolation: img.Interpolation.average,
  );
  final gray = img.grayscale(small);
  final pixels = <int>[];
  var sum = 0;
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 8; x++) {
      final lum = gray.getPixel(x, y).r.toInt();
      pixels.add(lum);
      sum += lum;
    }
  }
  final avg = sum / pixels.length;
  final sb = StringBuffer();
  for (final v in pixels) {
    sb.write(v >= avg ? '1' : '0');
  }
  return sb.toString();
}

/// Hamming distance between two hash strings. 999 if lengths differ.
int hamming(String a, String b) {
  if (a.length != b.length) return 999;
  var d = 0;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) d++;
  }
  return d;
}
