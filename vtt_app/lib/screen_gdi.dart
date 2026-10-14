import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:image/image.dart' as img;
import 'package:win32/win32.dart';

/// Full virtual-screen (all monitors) capture via GDI.
///
/// Pure Dart FFI - no native plugin/ATL build needed.
/// Writes a PNG to [outPath]. Returns [outPath] on success, null on
/// failure. Never throws.
Future<String?> captureScreenPng(String outPath) async {
  final x = GetSystemMetrics(SM_XVIRTUALSCREEN);
  final y = GetSystemMetrics(SM_YVIRTUALSCREEN);
  final w = GetSystemMetrics(SM_CXVIRTUALSCREEN);
  final h = GetSystemMetrics(SM_CYVIRTUALSCREEN);
  if (w <= 0 || h <= 0) return null;
  return captureRegionPng(outPath, x: x, y: y, w: w, h: h);
}

/// Captures an arbitrary virtual-screen rectangle (e.g. a monitor subset).
/// Coordinates use the same space as EnumDisplayMonitors (may be negative).
Future<String?> captureRegionPng(
  String outPath, {
  required int x,
  required int y,
  required int w,
  required int h,
}) async {
  if (w <= 0 || h <= 0) return null;
  try {
    final hdcScreen = GetDC(0);
    if (hdcScreen == 0) return null;
    try {
      final hdcMem = CreateCompatibleDC(hdcScreen);
      if (hdcMem == 0) return null;
      try {
        final hbmp = CreateCompatibleBitmap(hdcScreen, w, h);
        if (hbmp == 0) return null;
        try {
          final hOld = SelectObject(hdcMem, hbmp);
          final blitted =
              BitBlt(hdcMem, 0, 0, w, h, hdcScreen, x, y, SRCCOPY);
          SelectObject(hdcMem, hOld);
          if (blitted == 0) return null;

          final bmi = calloc<BITMAPINFO>();
          try {
            bmi.ref.bmiHeader.biSize = sizeOf<BITMAPINFOHEADER>();
            bmi.ref.bmiHeader.biWidth = w;
            bmi.ref.bmiHeader.biHeight = -h; // top-down DIB, no flip needed
            bmi.ref.bmiHeader.biPlanes = 1;
            bmi.ref.bmiHeader.biBitCount = 32;
            bmi.ref.bmiHeader.biCompression = BI_RGB;

            final size = w * h * 4;
            final pixels = calloc<Uint8>(size);
            try {
              final lines = GetDIBits(
                hdcMem,
                hbmp,
                0,
                h,
                pixels.cast(),
                bmi,
                DIB_RGB_COLORS,
              );
              if (lines == 0) return null;
              // Copy out before freeing native memory.
              final copy = Uint8List(size);
              copy.setRange(0, size, pixels.asTypedList(size));
              final image = img.Image.fromBytes(
                width: w,
                height: h,
                bytes: copy.buffer,
                order: img.ChannelOrder.bgra,
              );
              await File(outPath).writeAsBytes(img.encodePng(image));
              return outPath;
            } finally {
              calloc.free(pixels);
            }
          } finally {
            calloc.free(bmi);
          }
        } finally {
          DeleteObject(hbmp);
        }
      } finally {
        DeleteDC(hdcMem);
      }
    } finally {
      ReleaseDC(0, hdcScreen);
    }
  } catch (_) {
    return null;
  }
}
