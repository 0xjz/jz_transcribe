#!/usr/bin/env bash
#
# install.sh — 강의 전사 환경 원클릭 설치 (whisper.cpp 기반)
#
#   클론 후:  ./install.sh            # large-v3-turbo (속도)
#             ./install.sh large-v3   # 정확도 조금 더
#
# 하는 일:
#   1. 사전 점검 (root 금지, Apple Silicon/brew 경로 확인)
#   2. brew install ffmpeg whisper-cpp
#   3. whisper 실행파일 이름 자동 탐지 (whisper-cli / whisper-cpp)
#   4. 모델 다운로드 (~/whisper-models, 이미 있으면 skip)
#   5. 설정 파일 생성 (~/.config/transcribe.env)
#   6. transcribe.sh → ~/bin/
#   7. "*.workflow" → ~/Library/Services/  (Finder 빠른 동작)
#   8. 설치 검증 출력
#
# 멱등: 여러 번 돌려도 안전 (이미 된 단계는 건너뜀).
#
set -euo pipefail

MODEL_NAME="${1:-large-v3-turbo}"
MODEL_DIR="$HOME/whisper-models"
CONFIG="$HOME/.config/transcribe.env"
BIN_DIR="$HOME/bin"
SERVICES_DIR="$HOME/Library/Services"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

say()  { printf '\n\033[1m▶ %s\033[0m\n' "$1"; }
ok()   { printf '   \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '   \033[33m⚠\033[0m %s\n' "$1"; }
die()  { printf '\n\033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

# ── 1. 사전 점검 ─────────────────────────────────────────────
say "사전 점검"
[ "$(id -u)" -ne 0 ] || die "sudo/root 로 실행하지 마세요. 일반 사용자로 다시 실행하세요."

if [ "$(uname -m)" = "arm64" ]; then
  ok "Apple Silicon"
else
  warn "Intel Mac 감지 — 동작은 하지만 Metal 가속 이점은 적습니다."
fi

if ! command -v brew >/dev/null 2>&1; then
  die "Homebrew가 없습니다. 먼저 설치하세요:
   /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"
   그 뒤 'eval \"\$(/opt/homebrew/bin/brew shellenv)\"' 를 ~/.zprofile 에 추가하고 터미널 재시작."
fi
BREW_PREFIX="$(brew --prefix)"
if [ "$(uname -m)" = "arm64" ] && [ "$BREW_PREFIX" != "/opt/homebrew" ]; then
  warn "현재 brew가 $BREW_PREFIX (인텔용)입니다. arm64 네이티브(/opt/homebrew)가 아니면 느릴 수 있어요."
fi
ok "Homebrew: $BREW_PREFIX"

# ── 2. 패키지 설치 (brew 가 멱등 처리) ───────────────────────
say "패키지 설치 (ffmpeg, whisper-cpp)"
brew install ffmpeg whisper-cpp
ok "설치 완료"

# ── 3. whisper 바이너리 탐지 ─────────────────────────────────
say "whisper 실행파일 탐지"
WHISPER_BIN=""
for cand in whisper-cli whisper-cpp; do
  if command -v "$cand" >/dev/null 2>&1; then WHISPER_BIN="$(command -v "$cand")"; break; fi
done
[ -n "$WHISPER_BIN" ] || WHISPER_BIN="$(find "$BREW_PREFIX/bin" -maxdepth 1 -iname 'whisper-c*' 2>/dev/null | head -n1)"
[ -n "$WHISPER_BIN" ] || die "whisper 바이너리를 못 찾음. 'brew list whisper-cpp | grep bin/' 로 확인."
ok "$WHISPER_BIN"

# ── 4. 모델 다운로드 (이어받기) ──────────────────────────────
say "모델 준비 ($MODEL_NAME)"
mkdir -p "$MODEL_DIR"
MODEL_PATH="$MODEL_DIR/ggml-${MODEL_NAME}.bin"
if [ -s "$MODEL_PATH" ]; then
  ok "이미 있음: $MODEL_PATH"
else
  URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-${MODEL_NAME}.bin"
  echo "   다운로드: $URL"
  curl -L --fail --progress-bar -o "$MODEL_PATH" "$URL" \
    || { rm -f "$MODEL_PATH"; die "모델 다운로드 실패. 모델명 확인 (base/small/medium/large-v3/large-v3-turbo)."; }
  ok "다운로드 완료"
fi

# ── 5. 설정 파일 ─────────────────────────────────────────────
say "설정 파일 기록 ($CONFIG)"
mkdir -p "$(dirname "$CONFIG")" 2>/dev/null || true
if ! cat > "$CONFIG" <<EOF 2>/dev/null
# transcribe.sh 설정. install.sh 가 생성.
WHISPER_BIN="$WHISPER_BIN"
MODEL_DIR="$MODEL_DIR"
EOF
then
  die "$CONFIG 쓰기 실패 — ~/.config 소유권 문제일 수 있습니다:
   sudo chown -R \"\$(whoami)\" ~/.config  실행 후 다시 시도하세요."
fi
ok "기록됨"

# ── 6. transcribe.sh → ~/bin ─────────────────────────────────
say "transcribe.sh 설치 ($BIN_DIR)"
[ -f "$SCRIPT_DIR/transcribe.sh" ] || die "레포에 transcribe.sh 가 없습니다 (install.sh 와 같은 폴더에 있어야 함)."
mkdir -p "$BIN_DIR"
cp "$SCRIPT_DIR/transcribe.sh" "$BIN_DIR/transcribe.sh"
chmod +x "$BIN_DIR/transcribe.sh"
ok "$BIN_DIR/transcribe.sh"

# ── 7. 빠른 동작(.workflow) → ~/Library/Services ─────────────
say "Finder 빠른 동작 설치"
WORKFLOW_SRC="$(find "$SCRIPT_DIR" -maxdepth 1 -name '*.workflow' -print -quit 2>/dev/null || true)"
if [ -n "$WORKFLOW_SRC" ]; then
  find "$WORKFLOW_SRC" -name '.DS_Store' -delete 2>/dev/null || true
  mkdir -p "$SERVICES_DIR"
  DEST="$SERVICES_DIR/$(basename "$WORKFLOW_SRC")"
  rm -rf "$DEST"
  cp -R "$WORKFLOW_SRC" "$DEST"
  /System/Library/CoreServices/pbs -flush 2>/dev/null || true
  ok "$(basename "$WORKFLOW_SRC") → Services"
else
  warn "레포에서 *.workflow 를 못 찾음 — 빠른 동작은 건너뜀 (터미널 사용은 정상 동작)."
fi

# ── 8. 검증 ──────────────────────────────────────────────────
say "설치 검증"
ARCH="$(file "$WHISPER_BIN" 2>/dev/null | grep -o 'arm64\|x86_64' | head -n1 || echo '?')"
ok "whisper 아키텍처: $ARCH"
ok "모델: $MODEL_PATH"
ok "설정: $CONFIG"
[ -n "$WORKFLOW_SRC" ] && ok "빠른 동작: $DEST"

cat <<EOF

════════════════════════════════════════
 설치 완료 🎉
════════════════════════════════════════
 사용법:
   • 터미널  :  transcribe.sh 강의.mp4
   • Finder  :  mp4 우클릭 → 빠른 동작 → $( [ -n "${WORKFLOW_SRC:-}" ] && basename "$WORKFLOW_SRC" .workflow || echo "(미설치)" )

 ※ 빠른 동작 첫 실행 시 macOS가 "자동화 권한"을 물으면
    '허용'을 눌러주세요 (터미널을 띄우기 위한 정상 절차).
════════════════════════════════════════
EOF
