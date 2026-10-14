#Requires -Version 5.1
# VTT 필요 모델 설치 스크립트. 압축 푼 폴더에서 우클릭 -> "PowerShell로 실행".
$ErrorActionPreference = 'Stop'

if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) {
  Write-Host 'Ollama가 없습니다. https://ollama.com/download 에서 설치 후 다시 실행하세요.'
  exit 1
}

foreach ($m in @('qwen2.5vl:3b', 'qwen3:8b')) {
  Write-Host "== ollama pull $m (수 분 소요)"
  ollama pull $m
}

Write-Host ''
ollama list
Write-Host '완료. vtt_app.exe를 실행하세요.'
