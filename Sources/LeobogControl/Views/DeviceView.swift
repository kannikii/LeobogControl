import SwiftUI
import LeobogCore

struct DeviceView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var hid: HIDDeviceManager
    @EnvironmentObject var battery: BatteryService
    @EnvironmentObject var ble: BLEBatteryReader
    @EnvironmentObject var remap: HidutilRemapService
    @EnvironmentObject var compx: CompxClient


    /// 앱이 BLE GATT Battery Service 에서 직접 읽는 값. 시스템 값은 키보드가 notify 를 안 보내면 연결 시점 값(흔히 100%)에 머문다.
    @ViewBuilder private var directBatterySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("키보드에서 직접 읽기 (BLE Battery Service 0x2A19)").font(.subheadline.bold())
            InfoRow(label: "배터리 (직접)", value: ble.percent.map { "\($0)%" } ?? "—")
            InfoRow(label: "상태", value: ble.phase.label)
            if let t = ble.lastRead {
                InfoRow(label: "마지막 읽기", value: "\(t.formatted(date: .omitted, time: .standard)) · \(ble.readCount)회 · 1분마다" + (ble.supportsNotify ? " + notify 구독" : " (펌웨어가 notify 미지원)"))
            }
            if ble.history.count > 1 {
                InfoRow(label: "값 변화", value: ble.history.suffix(6).map { "\($0.1)% (\($0.0.formatted(date: .omitted, time: .shortened)))" }.joined(separator: " → "))
            }
            HStack {
                if ble.isRunning {
                    Button("지금 읽기") { ble.readNow() }
                    Button("중지") { ble.stop() }
                } else {
                    Button("직접 읽기 시작") { ble.start() }.buttonStyle(.borderedProminent)
                        .help("처음 한 번 macOS 블루투스 권한 대화상자가 뜹니다. 허용하면 다음 실행부터 자동으로 시작합니다.")
                }
                Text("블루투스 권한: \(BLEBatteryReader.authorizationLabel)").font(.caption).foregroundStyle(.secondary)
            }
            Text("macOS 는 연결할 때 배터리 특성을 한 번 읽고 그 뒤로는 키보드가 알려 줄 때만 갱신합니다. 값이 며칠째 그대로면 펌웨어가 변화를 알리지 않는 것이고, 여기서 직접 읽은 값이 실제 잔량입니다. 직접 읽은 값도 그대로면 펌웨어가 보고하는 값 자체가 거친 것입니다 (키보드에서 Fn + Space 를 길게 눌러 LED 표시와 비교해 보세요).")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

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

                Card(title: "배터리 · 블루투스", subtitle: "macOS 가 보여 주는 값(system_profiler, 2분마다 갱신)과 앱이 키보드에서 직접 읽은 값") {
                    if let s = battery.status {
                        InfoRow(label: "장치 이름", value: s.name)
                        InfoRow(label: "배터리 (시스템)", value: s.batteryPercent.map { "\($0)%" } ?? "정보 없음")
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
                    Divider()
                    directBatterySection
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
