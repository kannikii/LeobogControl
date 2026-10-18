#!/bin/zsh
# Leobog Control 크래시 · 메모리 모니터 (터미널용)
#   scripts/crash-monitor.sh          → 상태 요약 + 최근 리포트 판정 + 앱 로그 tail -f
#   scripts/crash-monitor.sh --once   → 요약만 출력
set -u
setopt null_glob   # 리포트 디렉터리에 파일이 없어도 "no matches found" 로 멈추지 않게
LOG="$HOME/Library/Logs/LeobogControl/app.log"
DIRS=("$HOME/Library/Logs/DiagnosticReports" "/Library/Logs/DiagnosticReports")

summary() {
  echo "== 프로세스 =="
  if pgrep -fl "Leobog Control.app/Contents/MacOS/LeobogControl" >/dev/null; then
    local pid; pid=$(pgrep -f "Leobog Control.app/Contents/MacOS/LeobogControl" | head -1)
    echo "실행 중 (pid $pid) · footprint $(ps -o rss= -p "$pid" | awk '{printf "%.1f MB", $1/1024}')"
  else
    echo "실행 중 아님"
  fi
  echo "시스템 메모리 압박: $(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null) (1 정상, 2 경고, 4 위험) · 사용 가능 $(sysctl -n kern.memorystatus_level 2>/dev/null)%"
  echo
  echo "== 크래시 리포트 (최근 5건) =="
  local found=0
  for d in "${DIRS[@]}"; do
    for f in "$d"/LeobogControl-*.ips(Nom[1,5]); do   # zsh 글롭: 없으면 비움(N), 최근 수정순(om) 5개
      found=1
      python3 -I - "$f" <<'PY'
import json, sys
p = sys.argv[1]
with open(p, encoding="utf-8") as fh:
    head = json.loads(fh.readline()); body = json.load(fh)
exc = body.get("exception", {}); term = body.get("termination", {})
t = exc.get("type", ""); sig = exc.get("signal", ""); ns = term.get("namespace", "")
if ns == "JETSAM" or (t == "EXC_RESOURCE" and "MEMORY" in exc.get("subtype", "").upper()):
    verdict = "메모리 부족/초과 (jetsam)"
elif t == "EXC_BAD_ACCESS": verdict = "소프트웨어 버그: 잘못된 메모리 접근 (메모리 부족 아님)"
elif t == "EXC_BREAKPOINT": verdict = "소프트웨어 버그: Swift 런타임 트랩"
elif t == "EXC_CRASH" or sig == "SIGABRT": verdict = "소프트웨어 버그: abort"
else: verdict = "기타"
malloc = [l for l in body.get("vmSummary", "").split("\n") if "MALLOC" in l and "=" not in l]
print(f"{head.get('timestamp','?')}  {t} {sig}  {term.get('indicator','')}  → {verdict}")
ft = body.get("faultingThread", 0); imgs = body.get("usedImages", [])
for fr in body.get("threads", [{}])[ft].get("frames", [])[:4]:
    img = imgs[fr.get("imageIndex", 0)].get("name", "?") if fr.get("imageIndex", 0) < len(imgs) else "?"
    print(f"    {img}  {fr.get('symbol','?')} + {fr.get('symbolLocation',0)}")
if malloc: print("    " + malloc[0].strip())
PY
    done
  done
  for d in "${DIRS[@]}"; do
    for f in "$d"/JetsamEvent-*.ips(Nom[1,20]); do
      if grep -q '"name":"LeobogControl"' "$f" 2>/dev/null; then found=1; echo "JETSAM(메모리 부족) 리포트에 이 앱이 있음: $f"; fi
    done
  done
  [[ $found -eq 0 ]] && echo "없음"
  echo
}

summary
if [[ "${1:-}" == "--once" ]]; then exit 0; fi
echo "== 앱 로그 ($LOG) — Ctrl+C 로 종료 =="
touch "$LOG"
tail -n 30 -f "$LOG"
