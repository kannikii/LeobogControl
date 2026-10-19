#!/bin/zsh
# Leobog Control 빌드 + .app 번들 + /Applications 설치
# 사용: scripts/build-app.sh [--no-install] [--debug] [--asan]
#   --asan : Address Sanitizer 빌드 (힙 손상 추적용, 느림). 실행 시 ASAN_OPTIONS=log_path=… 로 리포트 파일 지정 가능.
#
# 이 맥의 Command Line Tools 는 swift-package(SwiftPM) 바이너리가 깨져 있어(dyld 심볼 오류)
# swiftc 로 직접 컴파일한다. SwiftPM 이 정상인 환경에서는 `swift build -c release` 도 그대로 된다.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SDK_DIR=/Library/Developer/CommandLineTools/SDKs
if [[ -z "${SDKROOT:-}" ]]; then
  if [[ -d "$SDK_DIR/MacOSX26.5.sdk" ]]; then export SDKROOT="$SDK_DIR/MacOSX26.5.sdk"
  else export SDKROOT="$(ls -d $SDK_DIR/MacOSX*.sdk | grep -v 'MacOSX.sdk' | sort -V | tail -1)"; fi
fi
echo "SDKROOT=$SDKROOT"

OPT="-O"
INSTALL=1
ASAN=0
for a in "$@"; do
  case "$a" in
    --no-install) INSTALL=0 ;;
    --debug) OPT="-Onone -g" ;;
    --asan) OPT="-Onone -g -sanitize=address"; ASAN=1 ;;
  esac
done

OBJ="$ROOT/build/obj"
rm -rf "$OBJ"; mkdir -p "$OBJ"
COMMON=(-sdk "$SDKROOT" -target arm64-apple-macosx14.0 -swift-version 5 $=OPT)

echo "[1/3] LeobogCore 모듈"
swiftc "${COMMON[@]}" -parse-as-library -module-name LeobogCore \
  -emit-library -static -emit-module -emit-module-path "$OBJ/LeobogCore.swiftmodule" \
  -o "$OBJ/libLeobogCore.a" \
  Sources/LeobogCore/HID/*.swift Sources/LeobogCore/Protocol/*.swift Sources/LeobogCore/Services/*.swift Sources/LeobogCore/Data/*.swift Sources/LeobogCore/Diagnostics/*.swift

echo "[2/3] LeobogControl 앱"
swiftc "${COMMON[@]}" -parse-as-library -module-name LeobogControl \
  -I "$OBJ" -L "$OBJ" -lLeobogCore -framework IOKit -framework AppKit -framework SwiftUI -framework Combine -framework CoreBluetooth \
  -o "$OBJ/LeobogControl" \
  Sources/LeobogControl/*.swift Sources/LeobogControl/Views/*.swift

echo "[3/3] leobog-cli"
swiftc "${COMMON[@]}" -module-name leobog_cli \
  -I "$OBJ" -L "$OBJ" -lLeobogCore -framework IOKit -framework Combine \
  -o "$OBJ/leobog-cli" \
  Sources/leobog-cli/main.swift

APP_NAME="Leobog Control"
APP="$ROOT/build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$OBJ/LeobogControl" "$APP/Contents/MacOS/LeobogControl"
cp "$OBJ/leobog-cli" "$APP/Contents/MacOS/leobog-cli"
if [[ $ASAN -eq 1 ]]; then
  # 샌드박스/설치 위치와 무관하게 런타임을 찾도록 ASan dylib 을 번들에 넣고 rpath 를 맞춘다
  RT=$(dirname "$(dirname "$(xcrun --find swiftc)")")/lib/swift/clang/lib/darwin/libclang_rt.asan_osx_dynamic.dylib
  mkdir -p "$APP/Contents/Frameworks"; cp "$RT" "$APP/Contents/Frameworks/"
  install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/LeobogControl" 2>/dev/null || true
  echo "ASan 빌드: 런타임 동봉"
fi
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
echo -n "APPL????" > "$APP/Contents/PkgInfo"

# 아이콘
ICONSET="$ROOT/build/AppIcon.iconset"
rm -rf "$ICONSET"
swiftc -sdk "$SDKROOT" -target arm64-apple-macosx14.0 -framework AppKit -o "$OBJ/make-icon" "$ROOT/scripts/make-icon.swift"
"$OBJ/make-icon" "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# 서명. 기본은 임시(ad-hoc) 서명.
# ad-hoc 의 기본 designated requirement 는 cdhash 라 다시 빌드할 때마다 바뀌고, 그러면 macOS 가 기억해 둔
# '입력 모니터링' 허용 기록이 무효가 되어 앱에서는 '거부됨'으로 보이고 권한 대화상자도 다시 뜨지 않는다.
# → requirement 를 번들 ID 기준(identifier "com.leobog.control")으로 고정해 빌드 사이에도 기록이 유지되게 한다.
#   그래도 '거부됨'이면 앱의 '권한 기록 지우고 다시 요청' 버튼(tccutil reset ListenEvent com.leobog.control)으로 푼다.
#   주의: identifier 만으로 고정하면 같은 번들 ID 로 ad-hoc 서명한 다른 바이너리도 이 허용을 물려받는다.
#   개인 개발 머신에서 재빌드 편의를 택한 절충이며, 인증서 서명(CODESIGN_IDENTITY)은 requirement 에 인증서가 들어가 더 엄격하다.
# 키체인에 코드 서명 인증서가 있으면 CODESIGN_IDENTITY="인증서 이름" 으로 그걸 쓴다 (그때는 기본 requirement 사용).
IDENTITY="${CODESIGN_IDENTITY:--}"
if [[ "$IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - --identifier com.leobog.control \
    -r '=designated => identifier "com.leobog.control"' "$APP"
else
  codesign --force --deep --sign "$IDENTITY" --identifier com.leobog.control "$APP"
fi
codesign --verify --verbose=1 "$APP" 2>&1 | tail -1
codesign -d -r- "$APP" 2>&1 | grep designated || true
echo "번들 생성: $APP"

if [[ $INSTALL -eq 1 ]]; then
  DEST="/Applications/$APP_NAME.app"
  if pgrep -x LeobogControl >/dev/null; then pkill -x LeobogControl || true; sleep 0.5; fi
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  echo "설치 완료: $DEST"
  AGENT="gui/$(id -u)/com.leobog.control.remap"
  AGENT_PLIST="$HOME/Library/LaunchAgents/com.leobog.control.remap.plist"
  if [[ -f "$AGENT_PLIST" ]]; then
    # bootout 은 비동기라 바로 bootstrap 하면 "37: Operation already in progress" 로 실패한다 → 사라질 때까지 기다린 뒤 올린다
    launchctl bootout "$AGENT" 2>/dev/null || true
    for _ in $(seq 1 30); do launchctl print "$AGENT" >/dev/null 2>&1 || break; sleep 0.1; done
    ok=0
    for _ in $(seq 1 6); do
      if launchctl bootstrap "gui/$(id -u)" "$AGENT_PLIST"; then ok=1; break; fi
      sleep 0.25
    done
    if [[ $ok -eq 1 ]]; then echo "LaunchAgent 재시작: $AGENT"; else echo "경고: LaunchAgent 를 올리지 못했습니다 — 앱의 '키 매핑 → 다시 설치' 를 누르세요" >&2; fi
  fi
fi
