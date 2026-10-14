# Phase 0 - 환경체크 로그 (2026-10-14)

## 확인됨
- GPU: NVIDIA GeForce RTX 3060, 12288 MiB — OK
- Ollama: 설치됨
  - `qwen3:8b` (5.2GB) 있음 → 일기 요약용으로 바로 사용 가능
  - `gemma4:26b`, `muse-glimmer:30b-q4_K_M` 있음 → 12GB VRAM에 동시 적재 불가, VTT용으로는 제외
  - `qwen2.5vl:3b` 없음 → 캡션용으로 필요, `ollama pull qwen2.5vl:3b` (~2GB) 필요
- Flutter: 없음 (`Get-Command flutter` 실패)
  - winget에 `Google.Flutter` ID 없음. 수동 zip 설치 or Puro(FVM) 필요

## 남은 작업
1. Flutter SDK 설치 (~1.5GB, 10~20분) + `flutter doctor` + VS C++ 빌드도구 확인
2. `ollama pull qwen2.5vl:3b`
3.完了 후 Phase 1 scaffold: `flutter create vtt_app --platforms=windows`

## 결정 필요
- Flutter 자동 설치 진행 여부 (디스크/시간 소요 큼)
