# 변경 이력

형식은 [Keep a Changelog](https://keepachangelog.com/ko/1.1.0/) 를 따르고, 버전은 [유의적 버전](https://semver.org/lang/ko/) 을 따릅니다.
릴리스 절차는 README 의 "배포(릴리스)" 절을 참고하세요.

## [Unreleased]

## [1.2.0] - 2026-11-23

### 추가
- **창을 닫아도 백그라운드에서 계속 실행** (macOS · Windows). 새 **설정** 탭의 "창을 닫을 때" 에서 **백그라운드 실행**(기본값)과 **그냥 끄기** 중 고른다.
  - macOS: 창을 닫으면 Dock 아이콘이 사라지고 **메뉴 막대에 앱 로고(키 격자 + 띠)를 단색 템플릿으로 그린 작은 아이콘**이 남는다(라이트/다크 메뉴 막대 색을 따른다). 아이콘 메뉴: Leobog Control 열기 / 연결 상태 / 배터리 / 키 매핑… / 설정… / 종료(⌘Q). 창을 다시 열면 Dock 아이콘이 돌아온다. '그냥 끄기' 에서는 메뉴 막대 아이콘이 없고 마지막 창을 닫으면 앱이 끝난다.
  - Windows: 창을 닫으면 **작업 표시줄 오른쪽 아래 알림 영역(트레이)** 아이콘으로 계속 실행한다. 아이콘을 누르면 창이 다시 열리고, 오른쪽 클릭 메뉴는 Leobog Control 열기 / 연결 상태 / 설정… / 종료. 처음 숨길 때 한 번 풍선 알림으로 알려 준다. X 버튼·Alt+F4 만 숨기고, Windows 종료·작업 관리자 종료는 그대로 끝낸다.
- **처음 실행 때 "컴퓨터를 켤 때마다 자동으로 실행할까요?"** 를 한 번 묻는다. 설정 탭에서 언제든 켜고 끌 수 있다.
  - macOS: `SMAppService` 로 등록해 시스템 설정 → 일반 → 로그인 항목의 '로그인 시 열기' 목록에 들어간다. 로그인 때 실행되면(또는 `--background` 인자) 창 없이 메뉴 막대 아이콘으로만 시작한다.
  - Windows: 현재 사용자 Run 키(`HKCU\Software\Microsoft\Windows\CurrentVersion\Run`, 값 `LeobogControl`)에 `--background` 인자로 등록한다. 관리자 권한이 필요 없고 작업 관리자 → 시작 앱 목록에 보인다. 앱을 다른 폴더로 옮겼으면 설정 탭에서 다시 켜면 현재 위치로 고친다.
- Windows: **한 번만 실행** — 이미 떠 있으면(트레이에 숨어 있어도) 다시 실행할 때 기존 창을 앞으로 가져온다. 설정은 `%APPDATA%\LeobogControl\settings.json` 에 저장한다.

## [1.1.0] - 2026-10-19

### 추가
- 장치 탭 배터리 카드에 **키보드에서 직접 읽기**: 앱이 CoreBluetooth 로 BLE GATT Battery Service(0x180F / 0x2A19) 를 1분마다 읽고, 펌웨어가 지원하면 notify 도 구독한다. macOS 가 보여 주는 값(system_profiler)은 bluetoothd 가 연결 시점에 한 번 읽은 뒤 키보드가 알려 줄 때만 바뀌어, Hi8SE 처럼 notify 를 보내지 않는 펌웨어에선 며칠째 100% 에 머문다. 처음 한 번 macOS 블루투스 권한 대화상자가 뜨며(`NSBluetoothAlwaysUsageDescription`), 허용된 뒤로는 앱이 시작할 때 자동으로 읽는다. 키보드에 쓰는 동작은 없다. 사이드바 하단 배터리 표시도 직접 읽은 값을 우선한다.
- README 에 macOS 앱 실제 스크린샷(탭별 7장) 추가. `scripts/screenshots.sh` 로 다시 찍을 수 있고, 앱은 `-automation` 인자로 실행했을 때만 캡처 알림(`com.leobog.control.automation`)을 받는다.
- 키 매핑 대상 목록에 **macOS 기능 키** 두 그룹 추가. 첫 그룹은 Magic Keyboard(Touch ID) 상단열 F1–F12 순 — 밝기− / 밝기+ / Mission Control / Spotlight / 받아쓰기 / **방해금지** / 이전 곡 / 재생·일시정지 / 다음 곡 / 음소거 / 볼륨− / 볼륨+. 둘째 그룹은 그 밖의 Mac 기능 — Launchpad / 데스크탑 보기 / 화면 잠금(🔒) / 키보드 조명 밝기·토글 / 입력 소스 전환. 방해금지는 HID Usage Tables 1.3 의 Generic Desktop 0x9B, 밝기·Mission Control·Spotlight·Launchpad 는 Apple 벤더 페이지(0xFF01), 키보드 조명은 Apple 탑케이스 페이지(0xFF) usage 로 보낸다. Apple 벤더·탑케이스·Generic Desktop usage 의 한국어 이름 표기도 함께 확장. 방해금지 매핑은 Hi8SE 실기에서 hidutil 로 적용해 집중 모드가 켜지는 것까지 확인했다.

### 변경
- macOS 앱 기본 창 크기를 1240×880 으로 키우고 최소 1040×720 으로 제한. 키 테스터 탭이 기본 창에서 아래가 잘리지 않고 다 보인다 (이전에 저장된 창 크기는 무시되고 새 기본값으로 뜬다).
- 키 테스터: 상태 문구와 "키보드 모드" 선택기·"기록 지우기" 버튼이 서로 겹치거나 세로로 찌그러지지 않게 헤더를 정리하고, 오른쪽 카드 묶음은 스크롤 영역(340px)에 둔다.
- 키보드 다이어그램: 매핑된 키의 라벨을 원래 키 + 대상 키 두 줄로 나누고 좁은 키에서는 화살표를 빼서 글자가 읽히게 한다.
- 단축키·Fn 레이어 탭의 모드 선택기도 라벨을 바깥으로 빼서 세그먼트 안에서 줄바꿈되지 않는다.
- 스크린샷 7장을 새 창 크기로 다시 찍음.

### 수정
- `-automation` 캡처 훅이 창이 뒤에 있을 때 알림을 못 받던 문제: Combine 구독 대신 `DistributedNotificationCenter` 의 `.deliverImmediately` 옵저버로 등록.
- `scripts/screenshots.sh`: 이 Mac 의 swiftc 와 맞지 않는 최신 SDK 를 집던 문제(build-app.sh 와 같은 규칙으로), `-automation YES` 가 한 단어로 전달돼 훅이 켜지지 않던 문제, 앱이 늦게 뜨면 시간 초과되던 문제 수정.

## [1.0.0] - 2026-10-19

### 추가
- **macOS 앱 (SwiftUI)**: 장치, 키 테스터, 키 매핑(hidutil, 장치별), 단축키·Fn 레이어 참고표, 펑션키, 조명, 진단, 크래시 모니터 탭
- **macOS CLI `leobog-cli`**: `info` `battery` `listen` `probe` `keymap` `watch` `fn` `led` 하위 명령, 재연결 시 매핑을 다시 적용하는 LaunchAgent
- **Windows 앱 (.NET 7 WinForms)**: 장치, 키 테스터(Raw Input), 키 매핑(레지스트리 Scancode Map), 단축키·Fn 레이어, 조명, 진단 탭
- 두 플랫폼이 같은 `remaps.json` 형식과 같은 Compx 벤더 프로토콜 구현(체크섬 자동 판별, 프로브 후에만 쓰기 허용)을 공유
- `scripts/release.sh` 로 버전 올리기·로컬 패키징·태그, GitHub Actions 로 태그 푸시 시 자동 릴리스
