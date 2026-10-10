# whisper-transcribe

macOS에서 **강의 영상(mp4 등)을 로컬에서 텍스트로 받아쓰는** 도구입니다.
[whisper.cpp](https://github.com/ggml-org/whisper.cpp)를 Apple Silicon의 Metal GPU로 돌려
`.txt` / `.srt` 자막을 뽑아줍니다. **완전 오프라인** — 오디오가 외부로 나가지 않습니다.

## 특징

- **Finder 우클릭 한 번**으로 전사 (빠른 동작 등록)
- **여러 파일 배치 처리** — 터미널 1개에서 하나씩 순차 처리 (자원 포화 없음)
- **진행률 표시** + `[N/전체]` 카운터, 완료 시 알림
- **이어하기** — 중단 후 다시 돌리면 이미 만든 `.txt`는 건너뜀
- 한국어 기본 (`--lang en` 등으로 변경 가능)

## 요구 사항

- macOS (Apple Silicon 권장 — Metal 가속)
- [Homebrew](https://brew.sh)

Homebrew가 없으면 먼저 설치:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
source ~/.zprofile
```

## 설치

```bash
git clone <레포주소>
cd whisper-transcribe
./install.sh
```

이 한 번으로 모두 처리합니다:

1. `ffmpeg`, `whisper-cpp` 설치
2. 모델 다운로드 (`~/whisper-models/`)
3. 설정 파일 생성 (`~/.config/transcribe.env`)
4. `transcribe.sh` → `~/bin/`
5. 빠른 동작 → `~/Library/Services/`

> 정확도를 조금 더 원하면 모델을 바꿔서 설치:
> ```bash
> ./install.sh large-v3
> ```
> (기본값은 속도가 빠른 `large-v3-turbo`)

멱등하게 작성돼 있어 **여러 번 실행해도 안전**합니다.

## 사용법

### Finder 우클릭 (주 사용법)

영상 파일을 선택하고 **우클릭 → 빠른 동작 → 강의 전사**.
터미널 창이 뜨면서 진행률이 보이고, 영상과 같은 폴더에 `.txt` / `.srt`가 생깁니다.

> 첫 실행 시 macOS가 **자동화 권한**을 물으면 "허용"을 누르세요.
> (터미널을 띄우기 위한 정상 절차입니다.)

### 터미널

```bash
transcribe.sh 강의.mp4               # 기본 언어(ko)
transcribe.sh *.mp4                   # 여러 개 순차 처리
transcribe.sh --lang en 강의.mp4     # 영어
transcribe.sh --model large-v3 *.mp4 # 모델 지정
```

## 설정

기본 언어·모델을 바꾸려면 `~/.config/transcribe.env`에 추가:

```bash
TRANSCRIBE_LANG=en
TRANSCRIBE_MODEL=large-v3
```

## 구성

| 파일 | 역할 |
|------|------|
| `install.sh` | 설치 전체 오케스트레이션 (멱등) |
| `transcribe.sh` | 전사 스크립트 (배치·진행률·이어하기) |
| `강의 전사.workflow/` | Finder 빠른 동작 번들 |

## 동작 방식

```
Finder 우클릭 → 빠른 동작
      │  (선택한 파일 전체를 인자로 전달)
      ▼
transcribe.sh "$@"
      │  터미널 밖이면 → 터미널 1개 띄워 자신을 재실행
      ▼
터미널에서 파일 하나씩 순차 처리
      │  ffmpeg(16kHz 추출) → whisper.cpp(전사, Metal)
      ▼
  영상 옆에 .txt / .srt 생성
```

## 문제 해결

| 증상 | 조치 |
|------|------|
| `whisper 실행파일 없음` | `brew list whisper-cpp \| grep bin/` 로 경로 확인 |
| `~/.config` 쓰기 실패 | `sudo chown -R "$(whoami)" ~/.config` 후 재실행 |
| arm64인데 brew가 `/usr/local` | arm64 네이티브 brew(`/opt/homebrew`)를 PATH 앞에 두기 |
| 빠른 동작이 메뉴에 안 보임 | 로그아웃/로그인 또는 `/System/Library/CoreServices/pbs -flush` |
| 속도가 답답함 | `transcribe.sh`의 whisper 호출에 `-bo 1 -bs 1` 추가 (greedy, 더 빠름) |

## 라이선스

개인용 유틸리티. whisper.cpp / ffmpeg 각각의 라이선스를 따릅니다.
