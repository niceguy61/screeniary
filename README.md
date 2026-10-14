# Screeniary

Your screen, turned into a diary. A local-first Windows app that captures what you did and writes it up for you.

## What it does
- Captures your screen(s) on an interval (only when something changes)
- Auto-captions each capture with a local vision model
- Generates a daily diary (on demand or on schedule)
- Per-day timelapse GIF export, diary digest view, dark theme
- Multi-monitor aware: pick which screens to record
- LLM backends: Ollama (local) / OpenAI / OpenRouter / Claude / Bedrock

## Privacy
Everything stays on your machine: SQLite + PNGs under `%APPDATA%/com.vtt/vtt_app`. Cloud providers are only called when you configure an API key.

## Quick start (Windows)
1. Install [Ollama](https://ollama.com/download) and pull models: `ollama pull qwen2.5vl:3b` + `ollama pull qwen3:8b` (or run `packaging/setup-models.ps1`)
2. `flutter build windows --release` (Flutter 3.47+, VS Build Tools)
3. Run `build/windows/x64/runner/Release/vtt_app.exe`

Or grab `VTT-Portable-*.zip` from the repo root history (renamed to Screeniary builds going forward).

## Tech
Flutter (Windows) · SQLite (`sqflite_common_ffi`) · GDI screen capture via Dart FFI · Ollama + OpenAI-compatible/Anthropic/Bedrock APIs · `CHANGELOG.md` tracks releases.

## Status
MVP in active development. See `PHASE_*_LOG.md` for the build journal.
