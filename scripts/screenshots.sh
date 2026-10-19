#!/bin/zsh
# README 용 macOS 앱 스크린샷을 docs/screenshots/ 에 다시 찍는다.
# 설치된 앱(/Applications/Leobog Control.app)을 `-automation YES` 로 다시 띄운 뒤 화면마다 자기 창을 캡처하게 하고,
# 끝나면 평소대로 다시 실행한다. 앱이 자기 창만 캡처하므로 화면 기록 권한은 필요 없다.
#   zsh scripts/screenshots.sh            # 전체 화면
#   zsh scripts/screenshots.sh "키 매핑"   # 한 화면만
# 크래시 탭은 로컬 경로·크래시 로그가 그대로 찍히므로 README 에 넣지 않고 여기서도 찍지 않는다.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="/Applications/Leobog Control.app"
OUT="$ROOT/docs/screenshots"
SIZE="${SIZE:-1240x880}"
[[ -d "$APP" ]] || { echo "설치된 앱이 없습니다: $APP (scripts/build-app.sh 로 먼저 설치)" >&2; exit 1; }
SDK_DIR=/Library/Developer/CommandLineTools/SDKs
# build-app.sh 와 같은 규칙: 이 Mac 의 swiftc(6.3) 와 맞는 26.5 SDK 를 우선, 없으면 가장 최신 번호
if [[ -z "${SDKROOT:-}" ]]; then
  if [[ -d "$SDK_DIR/MacOSX26.5.sdk" ]]; then SDKROOT="$SDK_DIR/MacOSX26.5.sdk"
  else SDKROOT="$(ls -d $SDK_DIR/MacOSX*.sdk | grep -v 'MacOSX.sdk' | sort -V | tail -1)"; fi
fi
TOOL="$ROOT/build/screenshot-post"
mkdir -p "$ROOT/build" "$OUT"
swiftc -sdk "$SDKROOT" -target arm64-apple-macosx14.0 -O -o "$TOOL" "$ROOT/scripts/screenshot-post.swift"

typeset -A FILES
FILES=("장치" device "키 테스터" tester "키 매핑" remap "단축키 · Fn 레이어" shortcuts "펑션키" fnkeys "조명 (RGB)" lighting "진단 · 벤더 채널" diagnostics)
if [[ $# -gt 0 ]]; then SECTIONS=("$@"); else SECTIONS=("${(@k)FILES}"); fi

restart() {  # 인자: 앱에 넘길 추가 인자 (zsh 는 $1 을 단어로 나누지 않으므로 "$@" 로 따로따로 넘긴다)
  if pgrep -x LeobogControl >/dev/null; then pkill -x LeobogControl || true; for _ in $(seq 1 20); do pgrep -x LeobogControl >/dev/null || break; sleep 0.25; done; fi
  if [[ $# -gt 0 ]]; then open "$APP" --args "$@"; else open "$APP"; fi
  # 메모리 압박 등으로 첫 창이 늦게 뜰 수 있으니 프로세스가 보일 때까지 기다린 뒤 한 번 더 여유를 둔다
  for _ in $(seq 1 60); do pgrep -x LeobogControl >/dev/null && break; sleep 0.25; done
  sleep 4
}
restart -automation YES
for s in "장치" "키 테스터" "키 매핑" "단축키 · Fn 레이어" "펑션키" "조명 (RGB)" "진단 · 벤더 채널"; do
  (( ${SECTIONS[(Ie)$s]} )) || continue
  "$TOOL" "$s" "$OUT/macos-${FILES[$s]}.png" "$SIZE"
done
restart
echo "완료: $OUT"
