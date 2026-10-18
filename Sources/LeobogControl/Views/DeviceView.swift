import SwiftUI
import LeobogCore

struct DeviceView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var hid: HIDDeviceManager
    @EnvironmentObject var battery: BatteryService
    @EnvironmentObject var remap: HidutilRemapService
    @EnvironmentObject var compx: CompxClient

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Card(title: "연결 상태") {
                    HStack(spacing: 14) {
                        Image(systemName: "keyboard.fill").font(.system(size: 42)).foregroundStyle(hid.devices.isEmpty ? .secondary : Color.accentColor)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(hid.devices.isEmpty ? "LEOBOG Hi8SE 를 찾지 못했습니다" : hid.productName).font(.title3.bold())
                            switch hid.state {
                            case .notFound: Text("블루투스로 연결된 키보드가 없습니다. 키보드의 물리 스위치가 BT 쪽인지, 시스템 설정 › 블루투스에서 연결됐는지 확인하세요.").foregroundStyle(.secondary)
                            case .foundNotOpen(let reason): Text(reason).foregroundStyle(.orange)
                            case .open: Text("연결됨 · 입력 리포트 수신 중 (\(hid.transport))").foregroundStyle(.green)
                            }
                        }
                        Spacer()
                        Button("다시 연결") { hid.reconnect() }
                    }
                    if hid.permission != .granted {
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            Label("입력 모니터링 권한: \(hid.permission.rawValue)", systemImage: "exclamationmark.shield").foregroundStyle(.orange)
                            Text("키 테스터(실시간 키 확인)와 조명 제어(벤더 채널)는 macOS 의 '입력 모니터링' 권한이 필요합니다. 키 매핑과 배터리 확인은 권한 없이 동작합니다.")
                                .font(.callout).foregroundStyle(.secondary)
                            HStack {
                                Button(hid.permission == .denied ? "권한 기록 지우고 다시 요청" : "권한 요청") { model.requestPermission() }
                                    .buttonStyle(.borderedProminent)
                                    .help(hid.permission == .denied
                                          ? "macOS 가 기억한 거부(또는 무효가 된 허용) 기록을 지우고 시스템 대화상자를 다시 띄웁니다 (tccutil reset ListenEvent)"
                                          : "시스템 '입력 모니터링' 대화상자를 띄웁니다 (허용은 대화상자가 아니라 시스템 설정의 스위치로 합니다)")
                                Button("시스템 설정 열기") { model.openInputMonitoringSettings() }
                                Button("권한 다시 확인") { model.reopenIfPermitted() }
                            }
                            if let m = model.permissionMessage {
                                Text(m).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Label("입력 모니터링 권한: 허용됨", systemImage: "checkmark.shield").foregroundStyle(.green).font(.callout)
                    }
                }

                Card(title: "배터리 · 블루투스", subtitle: "system_profiler 기준, 2분마다 갱신") {
                    if let s = battery.status {
                        InfoRow(label: "장치 이름", value: s.name)
                        InfoRow(label: "배터리", value: s.batteryPercent.map { "\($0)%" } ?? "정보 없음")
                        InfoRow(label: "연결", value: s.connected ? "연결됨" : "연결 안 됨")
                        InfoRow(label: "주소", value: s.address)
                        if !s.firmware.isEmpty { InfoRow(label: "펌웨어", value: s.firmware) }
                        if let r = s.rssi { InfoRow(label: "신호(RSSI)", value: "\(r) dBm") }
                    } else {
                        Text(battery.refreshing ? "조회 중…" : "블루투스 목록에서 Leobog 키보드를 찾지 못했습니다.").foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("새로 고침") { battery.refresh() }.disabled(battery.refreshing)
                        if let t = battery.lastUpdated { Text("마지막 갱신 \(t.formatted(date: .omitted, time: .standard))").font(.caption).foregroundStyle(.secondary) }
                    }
                }

                Card(title: "HID 장치 정보") {
                    if let i = hid.deviceInfo() {
                        InfoRow(label: "제품", value: i.product)
                        InfoRow(label: "제조사", value: i.manufacturer.isEmpty ? "(없음)" : i.manufacturer)
                        InfoRow(label: "VID / PID", value: String(format: "0x%04X / 0x%04X", i.vendorID, i.productID))
                        InfoRow(label: "전송", value: i.transport)
                        InfoRow(label: "버전", value: String(format: "0x%04X", i.version))
                        InfoRow(label: "리포트 크기", value: "입력 \(i.maxInput) / 출력 \(i.maxOutput) / 기능 \(i.maxFeature) 바이트")
                        InfoRow(label: "Usage 쌍", value: i.usagePairs.map { String(format: "%X:%X", $0.page, $0.usage) }.joined(separator: ", "))
                        InfoRow(label: "RegistryID", value: String(format: "0x%llx", i.registryID))
                    } else {
                        Text("장치가 연결되면 표시됩니다.").foregroundStyle(.secondary)
                    }
                }

                Card(title: "현재 사용 방식", subtitle: "참고: 2.4G 동글은 Windows 노트북에, 블루투스는 이 맥북에 연결 · 물리 스위치로 모드 전환") {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("키 매핑: macOS hidutil (장치별, 권한 불필요, 즉시 적용) — 시스템 매핑 \(remap.activeFromSystem.count)개 적용 중", systemImage: "arrow.triangle.swap")
                        Label("재연결 자동 재적용: \(remap.launchAgentInstalled ? "설치됨" : "미설치") (키 매핑 화면에서 설정)", systemImage: "arrow.clockwise")
                        Label("조명(RGB): 블루투스 벤더 채널 — \(compx.protocolVerified ? "통신 확인됨" : "미확인 (진단 화면에서 '연결 확인')")", systemImage: "lightbulb.led")
                        Label("펌웨어 키맵·Fn 레이어는 키보드 안에 저장되어 Windows 노트북에서도 그대로 유지됩니다.", systemImage: "info.circle")
                    }.font(.callout)
                }
            }
            .padding(16)
        }
    }
}
