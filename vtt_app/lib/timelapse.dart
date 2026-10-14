import 'dart:io';

import 'package:image/image.dart' as img;

/// Evenly sample at most [maxFrames] paths, preserving order and endpoints.
List<String> samplePaths(List<String> paths, int maxFrames) {
  if (paths.length <= maxFrames) return List<String>.from(paths);
  final out = <String>[];
  final step = paths.length / maxFrames;
  for (var i = 0; i < maxFrames; i++) {
    out.add(paths[(i * step).floor()]);
  }
  return out;
}

/// Builds an animated GIF from screenshot files. Runs in an isolate via
/// `compute`. Args: {paths, outPath, width, maxFrames, frameMs}.
/// Returns {ok, frames, bytes, path} or {ok:false, reason, frames}.
Future<Map<String, dynamic>> buildTimelapse(
    Map<String, dynamic> args) async {
  final paths = (args['paths'] as List).cast<String>();
  final outPath = args['outPath'] as String;
  // Very large width = keep native resolution.
  final width = args['width'] as int? ?? 480;
  final maxFrames = args['maxFrames'] as int? ?? 200;
  final frameMs = args['frameMs'] as int? ?? 400;
  final sampling = args['sampling'] as int? ?? 10;

  img.Image? anim;
  for (final p in samplePaths(paths, maxFrames)) {
    try {
      final bytes = await File(p).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) continue;
      final small = decoded.width > width
          ? img.copyResize(decoded, width: width)
          : decoded;
      small.frameDuration = frameMs;
      if (anim == null) {
        anim = small;
      } else {
        anim.addFrame(small);
      }
    } catch (_) {
      // Missing/pruned files are skipped.
    }
  }
  final frames = anim?.numFrames ?? 0;
  if (anim == null || frames < 2) {
    return {'ok': false, 'reason': 'frames', 'frames': frames};
  }
  final gif = img.encodeGif(anim, samplingFactor: sampling);
  await File(outPath).writeAsBytes(gif);
  return {'ok': true, 'frames': frames, 'bytes': gif.length, 'path': outPath};
}
