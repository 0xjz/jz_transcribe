#!/usr/bin/env bash
#
# transcribe.sh — mp4/영상/오디오 → 텍스트 (whisper.cpp 래퍼, 배치 지원)
#
# 특징:
#   - 파일 여러 개를 줘도 터미널 1개에서 "순차" 처리 (자원 포화 없음)
#   - 터미널 밖(Finder 우클릭)에서 실행하면 터미널을 1개만 띄워서 그 안에서 처리
#   - 각 파일 진행률(-pp) + [N/전체] 카운터 표시
#   - 이미 .txt 가 있으면 건너뜀 (중단 후 재실행 = 이어하기)
#   - 완료 시 macOS 알림
#
# 사용법:
#   transcribe.sh 강의.mp4                    # 기본 언어(ko)
#   transcribe.sh *.mp4                        # 여러 개 순차 처리
#   transcribe.sh --lang en 강의.mp4          # 영어
#   transcribe.sh --model large-v3 *.mp4      # 모델 지정
#
# 설정(~/.config/transcribe.env)으로 기본값 변경 가능:
#   TRANSCRIBE_LANG=en   TRANSCRIBE_MODEL=large-v3
#
set -euo pipefail

# ── 설정 로드 ────────────────────────────────────────────────
[ -f "$HOME/.config/transcribe.env" ] && source "$HOME/.config/transcribe.env"
WHISPER_BIN="${WHISPER_BIN:-/opt/homebrew/bin/whisper-cli}"
MODEL_DIR="${MODEL_DIR:-$HOME/whisper-models}"

# ── 이 스크립트의 절대 경로 (터미널 재실행용) ────────────────
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

# ── 터미널 밖이면 터미널 1개 띄워서 자신을 다시 실행 ─────────
#    (인자 전체를 한 번에 넘김 → 그 터미널 안에서 순차 처리)
if [ ! -t 1 ]; then
  LAUNCH_DIR="$(mktemp -d)"
  LAUNCHER="$LAUNCH_DIR/transcribe.command"
  {
    echo '#!/bin/bash'
    printf '%s\n' "$(printf '%q ' "$SCRIPT_PATH" "$@")"
    printf 'status=$?\n'
    printf 'rm -rf %q\n' "$LAUNCH_DIR"
    printf 'exit $status\n'
  } > "$LAUNCHER"
  chmod +x "$LAUNCHER"
  open -a Terminal "$LAUNCHER"
  exit 0
fi

# ── 여기부터는 항상 터미널 안 ────────────────────────────────
WLANG="${TRANSCRIBE_LANG:-ko}"
MODEL_NAME="${TRANSCRIBE_MODEL:-large-v3-turbo}"
FILES=()

while [ $# -gt 0 ]; do
  case "$1" in
    -l|--lang)  WLANG="$2";      shift 2;;
    -m|--model) MODEL_NAME="$2"; shift 2;;
    -h|--help)
      echo "사용법: transcribe.sh [--lang ko] [--model large-v3-turbo] <파일...>"; exit 0;;
    *) FILES+=("$1"); shift;;
  esac
done

[ "${#FILES[@]}" -gt 0 ] || { echo "❌ 입력 파일이 없습니다."; echo "사용법: transcribe.sh <파일...>"; exit 1; }

MODEL="$MODEL_DIR/ggml-${MODEL_NAME}.bin"

notify() { osascript -e "display notification \"$1\" with title \"Whisper 전사\"" 2>/dev/null || true; }

# ── 사전 점검 ────────────────────────────────────────────────
command -v ffmpeg >/dev/null || { echo "❌ ffmpeg 없음: brew install ffmpeg"; exit 1; }
[ -x "$WHISPER_BIN" ] || command -v "$WHISPER_BIN" >/dev/null 2>&1 \
  || { echo "❌ whisper 실행파일 없음: $WHISPER_BIN"; exit 1; }
[ -f "$MODEL" ] || { echo "❌ 모델 없음: $MODEL"; echo "   setup-whisper.sh 를 먼저 실행하세요."; exit 1; }

# ── 공용 임시 폴더 (파일마다 재사용) ─────────────────────────
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
WAV="$TMP_DIR/audio.wav"
THREADS="$(sysctl -n hw.logicalcpu)"

# ── 파일 1개 처리 ────────────────────────────────────────────
process_one() {
  local input="$1" base="${1%.*}"
  [ -f "$input" ] || { echo "  ⚠ 파일 없음, 건너뜀"; return 1; }
  if [ -s "$base.txt" ]; then
    echo "  ⏭ 이미 있음, 건너뜀: $(basename "$base").txt"; return 0
  fi
  echo "  · 오디오 추출…"
  ffmpeg -y -loglevel error -i "$input" -ar 16000 -ac 1 -c:a pcm_s16le "$WAV"
  echo "  · 전사…"
  "$WHISPER_BIN" -m "$MODEL" -f "$WAV" -l "$WLANG" -fa -pp \
    -t "$THREADS" -otxt -osrt -of "$base"
  return 0
}

# ── 배치 루프 (순차) ─────────────────────────────────────────
TOTAL="${#FILES[@]}"
OK=0; FAIL=0; SKIP=0
echo "════════════════════════════════════════"
echo "  전사 시작: 총 ${TOTAL}개   모델=${MODEL_NAME}  언어=${WLANG}"
echo "════════════════════════════════════════"
notify "시작: 총 ${TOTAL}개 파일"

i=0
for f in "${FILES[@]}"; do
  i=$((i + 1))
  echo
  echo "──────── [$i/$TOTAL] $(basename "$f") ────────"
  if [ -s "${f%.*}.txt" ]; then
    SKIP=$((SKIP + 1)); echo "  ⏭ 이미 있음, 건너뜀"; continue
  fi
  if process_one "$f"; then
    OK=$((OK + 1)); echo "  ✅ 완료: $(basename "${f%.*}").txt"
  else
    FAIL=$((FAIL + 1)); echo "  ❌ 실패: $(basename "$f")"
  fi
done

echo
echo "════════════════════════════════════════"
echo "  전체 완료  ✅ $OK  ⏭ $SKIP  ❌ $FAIL  (총 $TOTAL)"
echo "════════════════════════════════════════"
notify "전체 완료: 성공 $OK / 건너뜀 $SKIP / 실패 $FAIL"
