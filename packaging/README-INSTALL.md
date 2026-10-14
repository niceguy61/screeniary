# VTT 설치법 (포터블)

## 요구사항
- Windows 10/11 64비트
- [Ollama](https://ollama.com/download) 설치됨 (로컬 모델 사용 시)
- NVIDIA GPU 권장 (없으면 CPU로 느리게 동작)

## 설치
1. 이 압축을 원하는 폴더에 풀기
2. `setup-models.ps1` 우클릭 → "PowerShell로 실행" (모델 약 8GB 다운로드, 1회만)
3. `vtt_app.exe` 실행

SmartScreen 경고가 뜨면 "추가 정보 → 실행" (서명 없는 로컬 빌드라 정상).

## 사용
- 하단 빨간 원 버튼으로 녹화 시작/정지, 좌우 버튼으로 수동 캡처·일기 생성
- 행 클릭 → 원본 미리보기, 스와이프/길게누르기 → 삭제
- 상단 타임랩스 버튼 → 하루 GIF 만들기
- 버전별 변경사항은 `CHANGELOG.md` 참고
- 설정 맨 아래 피드백 보내기로 의견 전달

## 데이터/삭제
- 데이터: `%APPDATA%\com.vtt\vtt_app\` (timeline.db + shots)
- 삭제: 압축 푼 폴더 + 위 데이터 폴더를 지우면 됨. 레지스트리 건드린 것 없음
