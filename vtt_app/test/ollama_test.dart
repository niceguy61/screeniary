import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:vtt_app/ollama.dart';

void main() {
  final ollama = Ollama();

  test('ollama up with required models', () async {
    expect(await ollama.alive(), isTrue);
    final models = await ollama.models();
    expect(models.any((m) => m.startsWith('qwen3:8b')), isTrue);
    expect(models.any((m) => m.startsWith('qwen2.5vl:3b')), isTrue);
  });

  test('qwen2.5vl:3b captions a test image', () async {
    final dir = await Directory.systemTemp.createTemp('vtt_cap_');
    try {
      final image = img.Image(width: 320, height: 120);
      img.fill(image, color: img.ColorRgb8(30, 30, 30));
      img.drawString(
        image,
        'hello vtt',
        font: img.arial14,
        x: 20,
        y: 40,
        color: img.ColorRgb8(255, 255, 255),
      );
      final path = '${dir.path}${Platform.pathSeparator}cap.png';
      await File(path).writeAsBytes(img.encodePng(image));
      final text = await ollama.caption(path);
      expect(text.isNotEmpty, isTrue);
    } finally {
      await dir.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 6)));

  test('qwen3:8b answers tiny prompt', () async {
    final text = await ollama.generate(
      model: 'qwen3:8b',
      prompt: 'Reply with exactly this word: ok',
      timeout: const Duration(seconds: 300),
    );
    expect(text.toLowerCase().contains('ok'), isTrue);
  }, timeout: const Timeout(Duration(minutes: 6)));
}
