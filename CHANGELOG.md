# 변경 이력

형식은 [Keep a Changelog](https://keepachangelog.com/ko/1.1.0/) 를 따르고, 버전은 [유의적 버전](https://semver.org/lang/ko/) 을 따릅니다.
릴리스 절차는 README 의 "배포(릴리스)" 절을 참고하세요.

## [Unreleased]

### 추가
- README 에 macOS 앱 실제 스크린샷(탭별 7장) 추가. `scripts/screenshots.sh` 로 다시 찍을 수 있고, 앱은 `-automation` 인자로 실행했을 때만 캡처 알림(`com.leobog.control.automation`)을 받는다.

## [1.0.0] - 2026-10-19

### 추가
- **macOS 앱 (SwiftUI)**: 장치, 키 테스터, 키 매핑(hidutil, 장치별), 단축키·Fn 레이어 참고표, 펑션키, 조명, 진단, 크래시 모니터 탭
- **macOS CLI `leobog-cli`**: `info` `battery` `listen` `probe` `keymap` `watch` `fn` `led` 하위 명령, 재연결 시 매핑을 다시 적용하는 LaunchAgent
- **Windows 앱 (.NET 7 WinForms)**: 장치, 키 테스터(Raw Input), 키 매핑(레지스트리 Scancode Map), 단축키·Fn 레이어, 조명, 진단 탭
- 두 플랫폼이 같은 `remaps.json` 형식과 같은 Compx 벤더 프로토콜 구현(체크섬 자동 판별, 프로브 후에만 쓰기 허용)을 공유
- `scripts/release.sh` 로 버전 올리기·로컬 패키징·태그, GitHub Actions 로 태그 푸시 시 자동 릴리스
