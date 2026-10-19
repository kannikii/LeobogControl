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
SIZE="${SIZE:-1120x740}"
[[ -d "$APP" ]] || { echo "설치된 앱이 없습니다: $APP (scripts/build-app.sh 로 먼저 설치)" >&2; exit 1; }
SDK_DIR=/Library/Developer/CommandLineTools/SDKs
[[ -n "${SDKROOT:-}" ]] || SDKROOT="$(ls -d $SDK_DIR/MacOSX*.sdk | grep -v 'MacOSX.sdk' | sort -V | tail -1)"
TOOL="$ROOT/build/screenshot-post"
mkdir -p "$ROOT/build" "$OUT"
swiftc -sdk "$SDKROOT" -target arm64-apple-macosx14.0 -O -o "$TOOL" "$ROOT/scripts/screenshot-post.swift"

typeset -A FILES
FILES=("장치" device "키 테스터" tester "키 매핑" remap "단축키 · Fn 레이어" shortcuts "펑션키" fnkeys "조명 (RGB)" lighting "진단 · 벤더 채널" diagnostics)
if [[ $# -gt 0 ]]; then SECTIONS=("$@"); else SECTIONS=("${(@k)FILES}"); fi

restart() {  # $1: 추가 인자
  if pgrep -x LeobogControl >/dev/null; then pkill -x LeobogControl || true; for _ in $(seq 1 20); do pgrep -x LeobogControl >/dev/null || break; sleep 0.25; done; fi
  open "$APP" --args $1
  sleep 2
}
restart "-automation YES"
for s in "장치" "키 테스터" "키 매핑" "단축키 · Fn 레이어" "펑션키" "조명 (RGB)" "진단 · 벤더 채널"; do
  (( ${SECTIONS[(Ie)$s]} )) || continue
  "$TOOL" "$s" "$OUT/macos-${FILES[$s]}.png" "$SIZE"
done
restart ""
echo "완료: $OUT"
