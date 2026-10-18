# Leobog Control

LEOBOG Hi8SE 키보드를 **블루투스로 연결한 macOS** 에서 설정하는 앱 + 커맨드라인 도구입니다.
공식 드라이버(LEOBOG ONE)가 Windows 전용이라, Mac 쪽에서 할 수 있는 일을 한곳에 모았습니다.

| 항목 | 값 |
|---|---|
| 앱 | `/Applications/Leobog Control.app` (Spotlight 에서 "Leobog Control") |
| CLI | `/Applications/Leobog Control.app/Contents/MacOS/leobog-cli` |
| 대상 장치 | LEOBOG Hi8SE 5.0 · VID `0x3554` / PID `0xFA07` · Bluetooth Low Energy |
| 요구 사항 | macOS 14 이상, Apple Silicon |

사용 환경 전제: 블루투스는 MacBook, 2.4G 동글은 Windows 노트북에 꽂아 두고, 키보드의 물리 스위치로 모드를 바꿔 가며 씁니다. 이 앱은 **블루투스 쪽(Mac)** 만 다룹니다.

---

## 1. 첫 실행

1. `Leobog Control` 을 실행하면 **입력 모니터링** 권한을 요청합니다.
   입력 모니터링 대화상자에는 **허용** 버튼이 없습니다. **시스템 설정 열기** 를 누르고 입력 모니터링 목록에서 `Leobog Control` 스위치를 켜면, 앱으로 돌아오거나 몇 초 안에 자동으로 장치를 다시 엽니다. 대화상자를 놓쳤으면 시스템 설정 → 개인정보 보호 및 보안 → 입력 모니터링 → `Leobog Control` 을 켠 뒤, 앱의 "장치" 탭에서 **권한 다시 확인** 을 누릅니다.
   "장치" 탭에 **거부됨** 으로 보이면 macOS 가 이전 결정(거부, 또는 앱을 다시 빌드해서 무효가 된 허용)을 기억하고 있어 대화상자를 다시 띄우지 않는 것입니다. 이때 버튼은 **권한 기록 지우고 다시 요청** 으로 표시되며, 누르면 기록을 지우고(`tccutil reset ListenEvent com.leobog.control`) 바로 다시 묻습니다.
2. 권한이 없어도 되는 기능: 장치 정보 · 배터리, **키 매핑**, 펑션키 설정, Fn 단축키 표, 키 테스터(앱 창이 맨 앞에 있을 때만).
3. 권한이 필요한 기능: 키 테스터의 HID 수준 감지(다른 앱이 앞에 있어도 감지), 진단 탭의 벤더 채널, 조명 탭의 "키보드에 적용".

---

## 2. 탭별 기능

### 장치
연결 상태, 배터리 잔량(블루투스 시스템 정보에서 읽음, 2분마다 갱신), HID 장치 정보(VID/PID, 리포트 크기, usage 쌍), 권한 상태.

### 키 테스터
키보드 그림 위에서 지금 눌린 키가 켜지고, 최근 입력(usage 코드 포함)이 목록으로 쌓입니다. 노브 돌리기/누르기도 소비자(consumer) usage 로 잡힙니다.
매핑을 적용한 키는 주황색 테두리와 `→대상` 라벨로 표시됩니다.

오른쪽 위 **키보드 모드** 선택기(Mac 모드 / Windows 모드)는 키보드 펌웨어 모드(키보드에서 **Fn + M** 으로 전환)에 맞춰 하단열 그림을 바꿉니다. 하단열은 모드에 따라 다른 코드를 보냅니다.

| 물리 위치 | Mac 모드 | Windows 모드 |
|---|---|---|
| Ctrl | ⌃ (0xE0) | Ctrl (0xE0) |
| Win 자리 | ⌥ (0xE2) | Win (0xE3) |
| Alt 자리 | ⌘ (0xE3) | Alt (0xE2) |
| 스페이스 바로 오른쪽 | 오른쪽 ⌘ (0xE7) — 매핑 가능 | **Fn** (펌웨어 전용) |
| 스페이스 오른쪽 두 번째 | **Fn** (펌웨어 전용) | 오른쪽 Ctrl (0xE4) |

키보드 자체 Fn 키는 호스트로 전송되지 않으므로 혼자 누르면 그림에 켜지지 않는 것이 정상입니다(조합 중에 가끔 오른쪽 Ctrl 로 보이기도 함). Fn 조합(Fn+F8 등)은 미디어 usage 로 도착하며 그때 Fn 키와 해당 키가 함께 켜집니다.
"배열표에 없는 입력" 카드가 모드 불일치를 알려 줍니다. Mac 모드에서 오른쪽 Ctrl(0xE4) 이 다른 키 없이 혼자 눌린 횟수가 쌓이거나(펌웨어 Fn 은 조합 중에만 0xE4 를 섞어 보냄), Windows 모드에서 오른쪽 ⌘(0xE7) 이 목록에 쌓이면 선택한 모드와 키보드 펌웨어 모드가 다른 것입니다. Fn 레이어 출력(Fn+F8 재생, Fn+U 등)은 "Fn + 해당 키" 로 그림에 표시되며 이 카드에 쌓이지 않습니다.

### 키 매핑
키보드 그림에서 키를 누르고 → 오른쪽 목록에서 대상 키를 고른 뒤 → **시스템에 적용**.

- 원리: macOS 내장 `hidutil` 의 장치 한정 `UserKeyMapping` 을 **VID/PID 로 이 키보드에만** 적용합니다. MacBook 내장 키보드나 다른 키보드에는 영향이 없습니다.
- 저장 위치: `~/Library/Application Support/LeobogControl/remaps.json`
- 블루투스가 끊겼다 다시 붙으면 hidutil 매핑이 사라집니다. **"재연결 시 자동 재적용"** 을 켜면 LaunchAgent(`com.leobog.control.remap`)가 `leobog-cli watch` 를 띄워 두고 키보드가 다시 연결될 때마다 저장된 매핑(`~/Library/Application Support/LeobogControl/remaps.json`)을 다시 적용합니다. **"시스템에 적용"** 이 이 파일을 저장하고, **"시스템 매핑 해제"** 와 **"목록 비우기"** 는 저장 파일도 비웁니다 — 그래야 다음 재연결 때 방금 지운 매핑이 되살아나지 않습니다 ("시스템 매핑 해제" 는 화면의 목록은 남겨 두므로 "시스템에 적용" 으로 다시 켤 수 있습니다). LaunchAgent 는 `leobog-cli` 실행 파일이 있을 때만 유지되도록(`KeepAlive` → `PathState`) 등록되어, 앱을 지워도 launchd 가 없는 프로그램을 계속 재시작하려 들지 않습니다.
- 프리셋

| 프리셋 | 내용 |
|---|---|
| `swap-cmd-opt` | Win ↔ Alt 교체 (Mac 모드에서는 펌웨어가 이미 바꿔 주므로 Windows 모드로 쓸 때만) |
| `caps-ctrl` | Caps Lock → Control |
| `caps-esc` | Caps Lock → Esc |
| `f-media` | F7–F12 → 이전곡 / 재생·일시정지 / 다음곡 / 음소거 / 볼륨 |
| `f-bright` | F1/F2 → 화면 밝기 |
| `rcmd-fn` | **Mac 모드**: 스페이스 바로 오른쪽 키(오른쪽 ⌘) → macOS Fn(🌐) 키 |
| `rctrl-fn` | **Windows 모드**: 스페이스 오른쪽 두 번째 키(오른쪽 Ctrl) → macOS Fn(🌐) 키 |
| `del-fwd` | 오른쪽 위 Del → Backspace |

### 단축키 · Fn 레이어
키보드 펌웨어에 들어 있는 Fn 조합을 분류별로 보여 줍니다(출처: 공식 드라이버 `Hi8SE KB.ini` 의 FN1 레이어 + Leobog 설명서). 입력 모니터링 권한이 있으면 실제로 Mac 에 도착한 usage 와 대조해 ✓ 를 찍어 줍니다. "추정" 배지가 붙은 항목은 드라이버 기능 코드만 있고 의미를 확정하지 못한 것입니다.

| 조합 | 동작 |
|---|---|
| Fn + F1 / F2 | 화면 밝기 − / + |
| Fn + F7 / F8 / F9 | 이전 곡 / 재생·일시정지 / 다음 곡 |
| Fn + F10 / F11 / F12 | 음소거 / 볼륨 − / 볼륨 + |
| Fn + Tab | 조명 효과 전환 |
| Fn + ↑ / ↓ | 조명 밝기 + / − |
| Fn + ← / → | 조명 속도 − / + (추정) |
| Fn + \ | 조명 색상 전환 (추정) |
| Fn + M | Mac ↔ Windows 모드 전환 (실측; Fn 은 Mac 모드에서 스페이스 오른쪽 두 번째, Windows 모드에서 스페이스 바로 오른쪽) |
| Fn + W / Fn + Q | Windows / Mac 모드 전환 (드라이버 코드만 있음, 이 키보드에서는 미확인) |
| Fn + 1 / 2 / 3 | 블루투스 장치 1 / 2 / 3 (3초 길게: 페어링) |
| Fn + U / I / O | Print Screen / Scroll Lock / Pause |
| Fn + Del / End | Insert / Home |
| Fn + Win 자리 키 | Win 키 잠금/해제 (Mac 모드에서는 그 자리가 ⌥ — 동작 미확인) |
| Fn + Space 길게 | 배터리 잔량 표시 (설명서) |
| Fn + ` 3초 길게 | 공장 초기화 (설명서) |
| 노브 돌리기 / 누르기 | 볼륨 / 음소거 |

### 펑션키
- **F1–F12 를 표준 기능 키로 사용** 토글: macOS 의 `com.apple.keyboard.fnState` 를 바꿉니다(시스템 설정 → 키보드 의 같은 항목과 동일). 켜면 F 열이 항상 F1–F12 로 들어가고, 미디어 동작은 키보드 Fn 조합으로만 나갑니다.
- F 열 매핑 프리셋(`f-media`, `f-bright`)을 여기서도 바로 적용/해제할 수 있습니다.
- 표에 F 열 각 키의 기본 usage 와 Fn 조합 동작이 함께 나옵니다.
- **macOS Fn(🌐) 키 만들기**: 키보드 자체 Fn 키는 펌웨어 전용이라 바꿀 수 없으므로, Mac 모드에서는 스페이스 바로 오른쪽 키(오른쪽 ⌘)를 macOS Fn/🌐 로 매핑하는 버튼(`rcmd-fn` 프리셋)을 제공합니다. 받아쓰기·이모지·fn+화살표 등이 그 키로 동작하고, 키보드 Fn 조합은 그대로 유지됩니다.

### 조명 (RGB)
20가지 효과(공식 드라이버 KB.ini 의 LedOpt 목록, 한국어 이름), 밝기/속도 0–4, 랜덤 색, 사용자 색, 프리셋 색을 고르고 **키보드에 적용** 을 누르면 벤더 채널(report 0x13, Compx 계열 프로토콜)로 전송합니다.

> **현재 상태 (2026-10-19 실측)**: 블루투스 모드에서는 키보드가 벤더 채널 조회(0x05 장치 정보)에 **응답하지 않았습니다** (3회 재시도 모두 시간 초과, 하트비트 없음). 따라서 **블루투스 연결 상태에서는 소프트웨어로 RGB 를 바꿀 수 없습니다.** 앱은 안전장치로, 진단 탭의 "연결 확인" 에서 응답이 확인되기 전에는 조명 쓰기 명령을 보내지 않습니다.
>
> 지금 쓸 수 있는 방법
> 1. 키보드 자체 단축키: Fn + Tab(효과), Fn + ↑/↓(밝기), Fn + ←/→(속도), Fn + \(색).
> 2. Windows 노트북(2.4G 동글) 쪽에서 공식 LEOBOG ONE 드라이버로 조명을 설정하면 키보드 내부에 저장되므로, 블루투스 모드로 바꿔도 보통 그대로 유지됩니다.
> 3. 나중에 키보드를 USB 케이블이나 동글로 Mac 에 직접 연결하면 진단 탭 → "연결 확인" 으로 벤더 채널이 열리는지 다시 확인할 수 있습니다. 응답하면 조명 탭이 그대로 동작합니다.

### 진단 · 벤더 채널
읽기 전용 명령(연결 확인 0x05, 키맵 레이어 읽기 0x41, 조명 읽기 0x49, 프로필 0x44)과 패킷 로그, 체크섬 방식 자동 감지 결과를 보여 줍니다. 프로토콜 분석이나 문제 보고용입니다.

### 크래시 · 메모리 모니터
앱이 갑자기 종료됐을 때 **왜** 죽었는지 바로 볼 수 있는 화면입니다.
- `~/Library/Logs/DiagnosticReports/LeobogControl-*.ips` 를 읽어 종료 종류(EXC_BAD_ACCESS 같은 메모리 접근 오류 / SIGABRT / **jetsam = 메모리 부족으로 시스템이 종료**)와 죽은 스레드의 호출 스택을 요약합니다. 메모리 부족(jetsam, `MemoryPressure` 리포트)이면 그렇게 표시되고, 그 외는 소프트웨어 버그로 분류합니다.
- 실행 중 메모리 사용량(footprint)과 시스템 메모리 압박 단계를 2초마다 보여 주고, `~/Library/Logs/LeobogControl/app.log` 에 남는 동작 기록(화면 전환, 장치 연결/해제, 권한 변화, 종료)을 함께 보여 줍니다. 비정상 종료 뒤 다시 실행하면 "지난 실행이 비정상 종료됨" 배너가 뜹니다.
- 터미널에서는 `zsh scripts/crash-monitor.sh` 로 같은 내용을 요약할 수 있습니다.

---

## 3. CLI

```bash
alias leobog='"/Applications/Leobog Control.app/Contents/MacOS/leobog-cli"'
```

| 명령 | 설명 |
|---|---|
| `leobog info` | HID 장치 정보 + 권한 상태 |
| `leobog battery` | 블루투스 배터리 잔량 |
| `leobog listen [초]` | 키 입력 / 벤더 리포트 실시간 출력 (입력 모니터링 권한 필요) |
| `leobog probe` | 벤더 채널 읽기 전용 프로브 |
| `leobog keymap list` | 저장된 매핑 + 시스템에 적용된 매핑 |
| `leobog keymap set caps lctrl` | 매핑 추가 (별칭 또는 `0x7000000xx` usage) |
| `leobog keymap remove caps` | 매핑 제거 |
| `leobog keymap apply` / `clear` | 저장된 매핑 적용 / 전부 해제 |
| `leobog keymap preset caps-esc` | 프리셋 적용 (`keymap presets` 로 목록) |
| `leobog watch` | 재연결 시 재적용 (LaunchAgent 가 사용) |
| `leobog fn get` / `fn set on\|off` | 표준 기능 키 설정 |
| `leobog led list` / `led read` / `led effect N [--brightness 0-4] [--speed 0-4] [--random] [--color RRGGBB]` | 조명 (벤더 채널 응답이 있을 때만) |

키 별칭: `caps esc tab space enter del bs lctrl lshift lalt lcmd rctrl … fn globe none f1–f24 play next prev mute volup voldown a–z 0–9`, 또는 `0x700000039` 형식.

---

## 4. 빌드 (소스에서 다시 만들기)

```bash
zsh scripts/build-app.sh            # 빌드 + 번들 + 아이콘 + 서명 + /Applications 설치
zsh scripts/build-app.sh --no-install
zsh scripts/build-app.sh --debug    # -Onone -g
zsh scripts/build-app.sh --asan     # Address Sanitizer 빌드 (힙 손상 추적용, 느림) — 확인이 끝나면 꼭 일반 빌드로 다시 설치
```

- Command Line Tools 의 `swiftc` 만으로 빌드합니다. 이 머신의 SwiftPM(`swift build`)은 `swift-package` 가 dyld 심볼 오류로 죽기 때문에 스크립트가 swiftc 를 직접 호출합니다(Package.swift 는 SwiftPM 이 정상인 환경용으로 남겨 두었습니다).
- SDK 는 `MacOSX26.5.sdk` 를 자동 선택합니다. 다른 SDK 를 쓰려면 `SDKROOT=... zsh scripts/build-app.sh`.
- 서명은 ad-hoc 입니다. ad-hoc 서명의 기본 designated requirement 는 `cdhash` 라 다시 빌드할 때마다 바뀌고, 그러면 macOS 가 기억한 입력 모니터링 허용이 무효가 되어 앱에 "거부됨"으로 보이면서 대화상자도 다시 뜨지 않습니다. 그래서 스크립트는 requirement 를 번들 ID(`identifier "com.leobog.control"`)로 고정합니다. 번들 ID 만으로 고정하면 같은 ID 로 ad-hoc 서명한 다른 바이너리도 이 허용을 물려받을 수 있는데, 개인 개발 머신에서 재빌드 편의를 택한 절충입니다. 그래도 "거부됨"이면 장치 탭의 **권한 기록 지우고 다시 요청** 버튼이 기록을 지우고 다시 묻습니다. 키체인에 코드 서명 인증서(키체인 접근 → 인증서 지원 → 인증서 생성, 유형 "코드 서명")가 있으면 `CODESIGN_IDENTITY="인증서 이름" zsh scripts/build-app.sh` 로 그 인증서로 서명해 빌드 사이에도 권한이 유지되면서 requirement 에 인증서가 포함되어 더 엄격합니다.

구조

```
Sources/LeobogCore      HID 접근(IOHIDManager), 키보드 레이아웃, Compx 벤더 프로토콜, hidutil/펑션키/배터리 서비스, Fn 레이어·조명 데이터
Sources/LeobogControl  SwiftUI 앱 (장치 / 키 테스터 / 키 매핑 / 단축키 / 펑션키 / 조명 / 진단 / 크래시 · 메모리 모니터)
Sources/LeobogCore/Diagnostics  동작 기록(app.log), 메모리 통계, .ips 크래시 리포트 파서
Sources/leobog-cli     커맨드라인 도구 (LaunchAgent 의 watch 포함)
scripts/build-app.sh   빌드·번들·설치 스크립트,  scripts/make-icon.swift  아이콘 생성
```

---

## 5. 제거

```bash
launchctl bootout gui/$(id -u)/com.leobog.control.remap 2>/dev/null; rm -f ~/Library/LaunchAgents/com.leobog.control.remap.plist
hidutil property --matching '{"VendorID":0x3554,"ProductID":0xFA07}' --set '{"UserKeyMapping":[]}'
rm -rf "/Applications/Leobog Control.app" ~/Library/Application\ Support/LeobogControl
```

---

## 6. 문제 해결

- **키 테스터에 아무것도 안 뜸**: 입력 모니터링 권한을 확인하세요. 권한이 없으면 앱 창이 맨 앞에 있을 때만(NSEvent 방식) 감지됩니다.
- **"거부됨" 이 안 풀림 / 권한 대화상자가 안 뜸**: macOS 는 결정 기록이 있으면 다시 묻지 않습니다. 장치 탭의 **권한 기록 지우고 다시 요청** 을 누르세요 (터미널에서는 `tccutil reset ListenEvent com.leobog.control` 후 앱 재실행). 시스템 설정의 입력 모니터링 목록에 `Leobog Control` 이 켜져 있는데도 "거부됨"이면 그 항목은 이전 빌드의 것이므로 같은 방법으로 지우고 다시 허용하면 됩니다.
- **매핑이 어느 순간 풀림**: 블루투스 재연결 때문입니다. 키 매핑 탭의 "재연결 시 자동 재적용" 을 켜세요. `leobog keymap list` 로 "시스템에 적용된 매핑" 을 확인할 수 있습니다.
- **"매핑 N개를 보냈지만 시스템에서 확인되지 않음"**: `hidutil --set` 은 키보드가 연결되어 있지 않아도(절전·블루투스 끊김) 성공으로 끝납니다. 앱은 적용 직후 다시 읽어 실제로 걸렸는지 확인하고, 안 걸렸으면 이 메시지를 보여 줍니다. 키보드가 다시 연결되면 LaunchAgent 가 자동으로 적용합니다.
- **자동 재적용이 "설치됨 (중지됨)" 으로 보이거나 다시 설치해도 안 돎**: `launchctl bootout` 은 비동기라(종료 신호만 보내고 돌아옴) 곧바로 `bootstrap` 하면 "Operation already in progress"(37) 로 실패하고, 예전 버전은 그 오류를 삼켜 plist 만 남고 에이전트는 안 도는 상태가 됐습니다. 지금은 서비스가 사라질 때까지 기다린 뒤 올리고(최대 3 초 + 재시도), 끝내 실패하면 plist 를 지우고 오류를 보여 줍니다. `scripts/build-app.sh` 의 재설치도 같은 방식입니다. 확인: `launchctl print gui/$(id -u)/com.leobog.control.remap | grep state`.
- **⌥ 와 ⌘ 가 그림과 반대 / 스페이스 오른쪽 키가 안 켜짐**: 키 테스터의 키보드 모드 선택기가 키보드 펌웨어 모드(Fn + M)와 맞는지 확인하세요. Mac 모드에서 스페이스 바로 오른쪽은 오른쪽 ⌘, 그 옆 Fn 키는 키보드 자체(펌웨어) Fn 이라 혼자 눌러도 맥에 아무 입력이 오지 않습니다. Fn+F8 같은 조합을 누르면 Fn 과 그 키가 함께 켜지고, 키 테스터의 "키보드 자체 Fn 키" 카드에 감지 횟수가 올라갑니다. Fn+M(모드 전환)은 맥에 아무것도 보내지 않습니다.
- **키 테스터에서 방향키를 누르면 다른 화면으로 넘어감**: 키 테스터 화면이 앞에 있을 때는 방향키·Tab·Space 도 테스터가 받습니다 (⌘ 조합은 제외). 다른 화면으로 가려면 사이드바를 클릭하세요. 이전 버전에서 이때 앱이 종료되던 문제(장치 재연결 중 입력 리포트 버퍼가 해제되던 메모리 버그)는 고쳐졌습니다.
- **앱이 갑자기 종료됨 (튕김)**: 먼저 **크래시 · 메모리 모니터** 탭을 보세요. 종료 종류가 jetsam/메모리 압박이면 시스템 메모리 부족이고, EXC_BAD_ACCESS 이면 소프트웨어 버그입니다. 2026-10-19 에 고친 두 가지 원인:
  1. 장치 재연결 중 입력 리포트 버퍼가 해제된 채 IOKit 이 거기에 썼음 (버퍼는 콜백을 끊기 전엔 해제하지 않고, 크기는 장치의 maxInputReportSize 에 맞춤).
  2. **키 매핑 화면에서 다른 탭으로 옮기거나 키를 누를 때 튕김**: 화면을 그리는 도중(`RemapView.body`) LaunchAgent 상태를 `launchctl` 로 동기 조회했는데, `Process.waitUntilExit()` 가 메인 런루프를 다시 돌려 SwiftUI 레이아웃이 중첩 실행되고 메모리가 깨졌습니다 (리포트 10건 모두 `HVStack.updateCache → swift_release` 스택, 메모리 사용량 53–106 MB, 즉 메모리 부족이 아님). 이제 외부 명령은 런루프를 돌리지 않고 기다리며, LaunchAgent 상태는 백그라운드에서 조회해 반영합니다.
  규칙: SwiftUI 의 body / onChange 안에서는 프로세스 실행·런루프를 돌리는 호출(`waitUntilExit`, `runModal`, `RunLoop.run`)을 절대 하지 않습니다.
  수정 뒤 소스 전체를 읽기 전용 리뷰(26개 에이전트, 22건 지적 중 9건 확인)해 함께 고친 것: LaunchAgent 설치의 bootout→bootstrap 경쟁(위 항목), `KeepAlive` 를 `PathState` 로, 매핑 해제·목록 비우기의 저장 파일 미반영, `watch` 가 시작 직후 같은 매핑을 두 번 적용하던 것(예약 하나로 합침), 키보드 없이 "적용됨" 이라고 하던 것(적용 후 읽어서 확인), 제거 버튼 직후 늦게 도착한 상태 조회가 "설치됨" 으로 되돌리던 것(세대 번호), CLI `led effect --color` 처럼 값 없는 옵션에서 인덱스 초과, jetsam 리포트의 `rpages × pageSize` 오버플로.
- **F1–F12 가 밝기/미디어로 동작하지 않음**: 펑션키 탭의 토글이 켜져 있으면 F 열은 순수 F 키입니다. 끄거나 `f-media` / `f-bright` 프리셋을 쓰세요. 키보드 자체 Fn 조합(Fn+F7 등)은 토글과 무관하게 항상 동작합니다.
- **조명이 안 바뀜**: 블루투스에서는 벤더 채널이 닫혀 있습니다(위 "조명" 절 참고). Fn 단축키나 Windows 쪽 공식 드라이버를 쓰세요.

---

## 7. 참고 자료

- 공식 LEOBOG ONE 드라이버의 `Hi8SE KB.ini` — 키 좌표·LED 인덱스·FN1 레이어 코드·조명 효과 목록
- Leobog 키보드 공통 설명서 — Fn 조합(블루투스 장치 선택, 배터리 표시, 공장 초기화)
- aula-f75 (https://github.com/JavaProgswing/aula-f75) — Compx/AULA 계열 벤더 프로토콜(report 0x13, 명령 0x05/0x41/0x49/0x09/0x02/0x81/0xFD)
- openrgb-rk-r87pro (https://github.com/myxk1792/openrgb-rk-r87pro) — RK 변형 체크섬·조명 패킷 구조
- OpenRGB Sinowealth 계열 컨트롤러 — 색상 페이지 레이아웃 참고
