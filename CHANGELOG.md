# 변경 이력

형식은 [Keep a Changelog](https://keepachangelog.com/ko/1.1.0/) 를 따르고, 버전은 [유의적 버전](https://semver.org/lang/ko/) 을 따릅니다.
릴리스 절차는 README 의 "배포(릴리스)" 절을 참고하세요.

## [Unreleased]

### 추가
- 장치 탭 배터리 카드에 **키보드에서 직접 읽기**: 앱이 CoreBluetooth 로 BLE GATT Battery Service(0x180F / 0x2A19) 를 1분마다 읽고, 펌웨어가 지원하면 notify 도 구독한다. macOS 가 보여 주는 값(system_profiler)은 bluetoothd 가 연결 시점에 한 번 읽은 뒤 키보드가 알려 줄 때만 바뀌어, Hi8SE 처럼 notify 를 보내지 않는 펌웨어에선 며칠째 100% 에 머문다. 처음 한 번 macOS 블루투스 권한 대화상자가 뜨며(`NSBluetoothAlwaysUsageDescription`), 허용된 뒤로는 앱이 시작할 때 자동으로 읽는다. 키보드에 쓰는 동작은 없다. 사이드바 하단 배터리 표시도 직접 읽은 값을 우선한다.
- README 에 macOS 앱 실제 스크린샷(탭별 7장) 추가. `scripts/screenshots.sh` 로 다시 찍을 수 있고, 앱은 `-automation` 인자로 실행했을 때만 캡처 알림(`com.leobog.control.automation`)을 받는다.

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
