#!/bin/zsh
# Leobog Control 배포 도구
#
# 사용:
#   scripts/release.sh build [mac|windows|all]   # dist/ 에 배포용 zip 생성 (기본 all)
#   scripts/release.sh bump X.Y.Z                # VERSION, Info.plist, csproj, CHANGELOG 의 버전을 한 번에 올림
#   scripts/release.sh tag                       # vX.Y.Z 태그를 만들고 푸시 → GitHub Actions 가 릴리스 생성
#   scripts/release.sh clean                     # dist/, build/, windows bin/obj 삭제
#
# 산출물 (dist/):
#   LeobogControl-macOS-X.Y.Z.zip     Leobog Control.app (ad-hoc 서명, 첫 실행 시 우클릭 → 열기)
#   LeobogControl-Windows-X.Y.Z.zip   LeobogControl.exe (self-contained 단일 파일, .NET 설치 불필요)
#   SHA256SUMS.txt
#
# Windows 산출물은 이 Mac 에서도 만들 수 있지만(교차 퍼블리시) exe 아이콘·버전 리소스는
# Windows 에서 빌드할 때만 들어간다. 정식 배포본은 GitHub Actions(windows-latest) 가 만든 것을 쓴다.
set -euo pipefail
SCRIPT="$0"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="$(tr -d '[:space:]' < VERSION)"
DIST="$ROOT/dist"
WIN_PROJ="$ROOT/windows/LeobogControl.Windows/LeobogControl.Windows.csproj"
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1

usage() { sed -n '2,20p' "$SCRIPT"; exit 1; }

build_mac() {
  echo "== macOS $VERSION"
  zsh scripts/build-app.sh --no-install
  mkdir -p "$DIST"
  local out="$DIST/LeobogControl-macOS-$VERSION.zip"
  rm -f "$out"
  # ditto 가 서명·확장 속성·심볼릭 링크를 보존한다 (zip 보다 .app 에 안전)
  ditto -c -k --sequesterRsrc --keepParent "build/Leobog Control.app" "$out"
  echo "생성: $out"
}

build_windows() {
  echo "== Windows $VERSION"
  command -v dotnet >/dev/null || { echo "dotnet SDK 가 없습니다 (https://dotnet.microsoft.com/download)" >&2; exit 1; }
  local pub="$ROOT/build/windows"
  rm -rf "$pub"
  dotnet publish "$WIN_PROJ" -c Release -r win-x64 --self-contained true \
    -p:PublishSingleFile=true -p:EnableCompressionInSingleFile=true -p:DebugType=none -p:Version="$VERSION" \
    -o "$pub"
  mkdir -p "$DIST"
  local out="$DIST/LeobogControl-Windows-$VERSION.zip"
  rm -f "$out"
  (cd "$pub" && zip -q -9 "$out" LeobogControl.exe)
  echo "생성: $out"
}

checksums() {
  (cd "$DIST" && shasum -a 256 *.zip > SHA256SUMS.txt && cat SHA256SUMS.txt)
}

bump() {
  local new="${1:-}"
  [[ "$new" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "버전 형식: X.Y.Z" >&2; exit 1; }
  local today; today="$(date +%Y-%m-%d)"
  printf '%s\n' "$new" > VERSION
  # Info.plist: 짧은 버전은 X.Y.Z, 빌드 번호는 단조 증가 (기존 값 + 1)
  local build; build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $new" Resources/Info.plist
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((build + 1))" Resources/Info.plist
  sed -i '' -E "s#<Version>[0-9.]+</Version>#<Version>$new</Version>#" "$WIN_PROJ"
  # CHANGELOG: Unreleased 아래 내용을 새 버전 절로 옮긴다
  python3 - "$new" "$today" <<'PY'
import re, sys, pathlib
new, today = sys.argv[1], sys.argv[2]
p = pathlib.Path("CHANGELOG.md"); s = p.read_text(encoding="utf-8")
if f"## [{new}]" in s: sys.exit(0)
s = s.replace("## [Unreleased]\n", f"## [Unreleased]\n\n## [{new}] - {today}\n", 1)
p.write_text(s, encoding="utf-8")
PY
  echo "버전 $new 으로 갱신: VERSION, Resources/Info.plist (build $((build + 1))), csproj, CHANGELOG.md"
  echo "확인 후 커밋하세요:  git commit -am \"v$new\""
}

tag() {
  git diff --quiet && git diff --cached --quiet || { echo "커밋되지 않은 변경이 있습니다. 먼저 커밋하세요." >&2; exit 1; }
  local t="v$VERSION"
  git rev-parse -q --verify "refs/tags/$t" >/dev/null && { echo "태그 $t 가 이미 있습니다." >&2; exit 1; }
  git tag -a "$t" -m "Leobog Control $VERSION"
  git push origin "$t"
  echo "태그 $t 푸시 완료 → GitHub Actions 의 release 워크플로가 릴리스를 만듭니다."
}

case "${1:-}" in
  build)
    case "${2:-all}" in
      mac) build_mac ;;
      windows) build_windows ;;
      all) build_mac; build_windows ;;
      *) usage ;;
    esac
    checksums ;;
  bump) bump "${2:-}" ;;
  tag) tag ;;
  clean) rm -rf "$DIST" "$ROOT/build" windows/LeobogControl.Windows/bin windows/LeobogControl.Windows/obj; echo "정리 완료" ;;
  *) usage ;;
esac
