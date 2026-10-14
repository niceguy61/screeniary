# Phase 1 - 완료 로그 (2026-10-14)

## 한 일
- `flutter create vtt_app --platforms=windows` 스캐폴드
- `lib/main.dart`를 타임라인 목업 UI로 교체 (mock 4건 + 상태바 + Phase 2/3 버튼 disabled)
- `flutter build windows --release` 성공

## 빌드물 (직접 실행 가능)
- `D:\idea_bank\vtt_app\build\windows\x64\runner\Release\vtt_app.exe`
- 실행법: 해당 폴더에서 `vtt_app.exe` 더블클릭 (같은 폴더의 dll들과 함께 있어야 함)
- 확인 포인트: 창 타이틀 "VTT - 오늘 타임라인", mock 4건 리스트, 상태바에 3060/Ollama 문구

## 환경 확정
- Flutter 3.47.7 stable (`D:\flutter`), PATH 등록됨 (setx)
- VS Build Tools 2019로 윈도우 빌드 통과
- Ollama: `qwen2.5vl:3b`(3.2GB) + `qwen3:8b`(5.2GB) 준비됨
- Android toolchain 경고는 무시 (윈도우 전용)

## 다음 (Phase 2)
- `screen_capturer` + 10초 간격 캡처 + pHash 중복제거 + SQLite(`drift`) 저장
- 타임라인에 실제 캡처 썸네일 표시
