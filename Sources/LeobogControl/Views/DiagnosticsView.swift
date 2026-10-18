import SwiftUI
import LeobogCore

struct DiagnosticsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var hid: HIDDeviceManager
    @EnvironmentObject var compx: CompxClient
    @State private var summary = ""
    @State private var keymapText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Card(title: "벤더 채널 (usage page 0xFF02 · Report ID 0x13 · 20바이트)", subtitle: "읽기 전용 명령만 보내는 안전한 검사입니다. 쓰기 명령은 응답이 확인된 뒤에만 허용됩니다.") {
                HStack {
                    Button("연결 확인 (프로브)") { Task { let r = await compx.probe(); summary = r.summary } }
                        .buttonStyle(.borderedProminent).disabled(compx.busy || !hid.isOpen)
                    Button("키맵 레이어 1 읽기 (0x41)") { Task { await readKeymap(1) } }.disabled(compx.busy || !hid.isOpen)
                    Button("조명 설정 읽기 (0x49)") { Task { await readPages(CompxCommand.getLedEffect.rawValue) } }.disabled(compx.busy || !hid.isOpen)
                    Button("프로필 읽기 (0x44)") { Task { await readPages(CompxCommand.getProfile.rawValue) } }.disabled(compx.busy || !hid.isOpen)
                    Button("로그 지우기") { compx.clearLog() }
                    Spacer()
                    if compx.busy { ProgressView().controlSize(.small) }
                }
                HStack(spacing: 16) {
                    Label(hid.isOpen ? "장치 열림" : "장치 닫힘 (권한)", systemImage: hid.isOpen ? "checkmark.circle" : "xmark.circle")
                    Label("하트비트 \(compx.heartbeatCount)회", systemImage: "waveform.path.ecg")
                    Label("벤더 리포트 \(hid.vendorReportCount)개", systemImage: "arrow.down.circle")
                    Label(compx.protocolVerified ? "프로토콜 확인됨" : "프로토콜 미확인", systemImage: compx.protocolVerified ? "checkmark.seal" : "questionmark.circle")
                    if let f = compx.firmware { Label("펌웨어 \(f)", systemImage: "cpu") }
                    if let cs = compx.detectedChecksum { Label(cs.label, systemImage: "number") }
                }.font(.caption)
                if !summary.isEmpty { Text(summary).font(.callout) }
            }

            HStack(alignment: .top, spacing: 12) {
                Card(title: "패킷 로그") {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 1) {
                                ForEach(compx.log) { e in
                                    Text(e.line).font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(e.direction == .tx ? Color.blue : (e.direction == .rx ? Color.green : Color.secondary))
                                        .textSelection(.enabled).id(e.id)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .onChange(of: compx.log.count) { _, _ in if let l = compx.log.last { proxy.scrollTo(l.id) } }
                    }
                    .frame(minHeight: 220)
                }
                Card(title: "읽은 데이터 해석") {
                    ScrollView {
                        Text(keymapText.isEmpty ? "키맵/조명 읽기 결과가 여기에 표시됩니다." : keymapText)
                            .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(minHeight: 220)
                }.frame(width: 360)
            }

            Card(title: "참고") {
                Text("""
                • 명령 체계: 0x05 장치정보, 0x41/0x42/0x43 키맵 레이어 읽기, 0x44 프로필, 0x49 조명 읽기, 0x09 조명 효과 쓰기, 0x02 키별 색상 쓰기, 0x81 키맵 페이지 쓰기, 0xFD 플래시 저장.
                • 출처: aula-f75 (JavaProgswing), openrgb-rk-r87pro (myxk1792) 의 Compx 프로토콜 분석 + 공식 LEOBOG ONE 드라이버 설정 파일. 두 분석의 패킷 틀은 같고 체크섬 계산만 달라 자동 판별합니다.
                • 블루투스 모드에서 응답이 없으면 설정 채널이 닫힌 것입니다. 이 경우 조명은 Fn 단축키로, 키 매핑은 macOS hidutil 로 처리하는 것이 이 앱의 기본 동작입니다.
                """).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    private func readKeymap(_ layer: Int) async {
        do {
            let pages = try await compx.readKeymap(layer: layer)
            var s = "레이어 \(layer): \(pages.count) 페이지\n"
            for p in pages {
                let names = p.usages.map { u -> String in
                    u == 0 ? "·" : HIDUsage(page: UInt32(u >> 8 == 0 ? 0x07 : 0x07), usage: UInt32(u & 0xFF)).shortName + String(format: "(%04X)", u)
                }
                s += String(format: "p%02d: ", p.pageIndex) + names.joined(separator: " ") + "\n"
            }
            keymapText = s
        } catch { keymapText = "읽기 실패: \(error)" }
    }

    private func readPages(_ cmd: UInt8) async {
        do {
            let pages = try await compx.readPages(cmd)
            var s = "\(CompxCommand.name(of: cmd)): \(pages.count) 페이지\n"
            for p in pages { s += String(format: "p%02d/%02d len=%d: ", p.pageIndex, p.pageCount, p.dataLength) + p.payload.map { String(format: "%02X", $0) }.joined(separator: " ") + "\n" }
            keymapText = s
        } catch { keymapText = "읽기 실패: \(error)" }
    }
}
