import Foundation
import Combine

/// 벤더 채널 위에서 요청/응답을 다루는 클라이언트.
/// 모든 호출은 메인 스레드(IOHIDManager 가 메인 런루프에 스케줄됨)에서 async 로 동작한다.
@MainActor
public final class CompxClient: ObservableObject {
    public let hid: HIDDeviceManager

    @Published public private(set) var log: [VendorLogEntry] = []
    @Published public private(set) var detectedChecksum: ChecksumStyle? = nil
    @Published public private(set) var heartbeatCount = 0
    @Published public private(set) var lastHeartbeat: CompxPacket?
    @Published public private(set) var firmware: String?
    @Published public private(set) var protocolVerified = false   // 읽기 명령에 응답이 왔는지
    @Published public private(set) var busy = false

    private var cancellables = Set<AnyCancellable>()
    private var collectors: [UUID: (CompxPacket) -> Void] = [:]
    private let logLimit = 400
    /// 쓰기 시 사용할 체크섬 (자동 판별 전엔 sumAll)
    public var checksumStyle: ChecksumStyle { detectedChecksum ?? .sumAll }

    public init(hid: HIDDeviceManager) {
        self.hid = hid
        hid.vendorReports
            .receive(on: RunLoop.main)
            .sink { [weak self] r in self?.handle(r) }
            .store(in: &cancellables)
    }

    private func handle(_ r: VendorReport) {
        let p = CompxPacket(bytes: r.bytes)
        let styles = p.matchingChecksumStyles
        if detectedChecksum == nil, styles.count == 1 { detectedChecksum = styles[0] }
        if p.cmd == CompxCommand.activelyReport.rawValue {
            heartbeatCount += 1
            lastHeartbeat = p
            if p.payload.count >= 3, firmware == nil {
                // AULA: 13 0A 01 00 major minor ... → bytes[4], bytes[5]
                firmware = "\(p.bytes[4]).\(p.bytes[5]) (하트비트 기준)"
            }
        }
        append(.rx, p, note: "")
        for (_, c) in collectors { c(p) }
    }

    private func append(_ d: VendorLogEntry.Direction, _ p: CompxPacket?, note: String) {
        log.append(VendorLogEntry(time: Date(), direction: d, packet: p, note: note))
        if log.count > logLimit { log.removeFirst(log.count - logLimit) }
    }

    public func note(_ s: String) { append(.note, nil, note: s) }
    public func clearLog() { log.removeAll() }

    // MARK: 저수준 송수신

    public func send(_ p: CompxPacket, note: String = "") throws {
        AppLog.shared.log("compx", "송신 \(note.isEmpty ? "" : note + " ")" + p.bytes.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " "))
        append(.tx, p, note: note)
        if case .failure(let e) = hid.sendVendorReport(p.bytes) {
            append(.note, nil, note: "전송 실패: \(e.description)")
            throw e
        }
    }

    /// 지정 시간 동안 조건에 맞는 패킷을 모은다. `quiet` 초 동안 조용하면 조기 종료.
    public func collect(for total: TimeInterval, quiet: TimeInterval? = nil,
                        where filter: @escaping (CompxPacket) -> Bool) async -> [CompxPacket] {
        var got: [CompxPacket] = []
        let id = UUID()
        var last = Date()
        collectors[id] = { p in
            if filter(p) { got.append(p); last = Date() }
        }
        defer { collectors[id] = nil }
        let start = Date()
        while Date().timeIntervalSince(start) < total {
            try? await Task.sleep(nanoseconds: 20_000_000)
            if let q = quiet, !got.isEmpty, Date().timeIntervalSince(last) > q { break }
        }
        return got
    }

    /// 단순 요청 → 같은 cmd 의 첫 응답 (재시도 포함)
    public func request(_ cmd: UInt8, body: [UInt8] = [], retries: Int = 3, timeout: TimeInterval = 0.5) async throws -> CompxPacket {
        var lastErr: Error = HIDError.timeout
        for attempt in 0..<max(1, retries) {
            let pkt = CompxPacket(simpleCmd: cmd, body: body, checksum: checksumStyle)
            do { try send(pkt, note: attempt > 0 ? "재시도 \(attempt)" : "") } catch { lastErr = error; continue }
            let got = await collect(for: timeout) { $0.cmd == cmd }
            if let first = got.first { return first }
        }
        throw lastErr
    }

    /// 페이지 스트림 읽기 (키맵/조명): cmd 를 보내고 같은 cmd 응답을 모아 페이지 순 정렬
    public func readPages(_ cmd: UInt8, timeout: TimeInterval = 2.5) async throws -> [CompxPacket] {
        try send(CompxPacket(simpleCmd: cmd, checksum: checksumStyle))
        var pages = await collect(for: timeout, quiet: 0.35) { $0.cmd == cmd }
        pages.sort { $0.pageIndex < $1.pageIndex }
        if pages.isEmpty { throw HIDError.timeout }
        return pages
    }

    // MARK: 고수준 동작

    public struct ProbeResult: Sendable {
        public var opened = false
        public var heartbeatSeen = false
        public var infoReply: CompxPacket?
        public var checksum: ChecksumStyle?
        public var summary: String = ""
        public var ok: Bool { infoReply != nil || heartbeatSeen }
    }

    /// 안전한 프로브: 수동 청취 → 읽기 전용 정보 명령만 전송. 쓰기 명령은 절대 보내지 않는다.
    public func probe(listen: TimeInterval = 1.5) async -> ProbeResult {
        var r = ProbeResult()
        busy = true
        defer { busy = false }
        guard hid.isOpen else {
            r.summary = "장치가 열려 있지 않습니다. 입력 모니터링 권한을 허용한 뒤 다시 시도하세요."
            return r
        }
        r.opened = true
        note("프로브 시작: \(Int(listen * 1000))ms 동안 수동 청취 (키를 몇 번 눌러 보세요)")
        let before = heartbeatCount
        _ = await collect(for: listen) { _ in true }
        r.heartbeatSeen = heartbeatCount > before
        note("하트비트 \(r.heartbeatSeen ? "수신됨" : "없음")")
        do {
            let info = try await request(CompxCommand.getDeviceInfo.rawValue, retries: 3, timeout: 0.6)
            r.infoReply = info
            protocolVerified = true
            // RK: model id [9], fw [12..13] ; AULA: fw major [4] minor [5]
            let fwA = "\(info.bytes[4]).\(info.bytes[5])"
            let fwR = String(format: "%02X%02X", info.bytes[13], info.bytes[14])
            firmware = "v\(fwA) (AULA 해석) / \(fwR) (RK 해석)"
            note("장치 정보 응답 수신 — 펌웨어 \(firmware ?? "")")
        } catch {
            note("장치 정보(0x05) 응답 없음: \(error)")
        }
        r.checksum = detectedChecksum
        if let cs = detectedChecksum { note("체크섬 방식 판별: \(cs.label)") }
        r.summary = r.ok
            ? "벤더 채널 통신 확인됨" + (r.infoReply == nil ? " (하트비트만 수신, 명령 응답은 없음)" : "")
            : "키보드가 벤더 채널 명령에 응답하지 않았습니다. 블루투스 모드에서는 설정 채널이 닫혀 있을 수 있습니다 (이 키보드의 모드 전환은 Fn + M; 공식 드라이버 문서는 Fn + W 로 Windows 모드 전환 후 사용하라고 안내)."
        return r
    }

    /// 키맵 레이어 읽기 (1,2,3)
    public func readKeymap(layer: Int) async throws -> [KeymapPage] {
        let cmd: UInt8 = [1: 0x41, 2: 0x42, 3: 0x43][layer] ?? 0x41
        busy = true
        defer { busy = false }
        let pages = try await readPages(cmd)
        return pages.compactMap { KeymapPage(packet: $0) }
    }

    /// 키맵 페이지 쓰기 + 커밋 (AULA 검증 흐름). 반드시 읽기가 성공한 뒤에만 호출.
    public func writeKeymap(pages: [KeymapPage]) async throws {
        guard protocolVerified else { throw HIDError.badResponse("프로토콜이 확인되지 않아 쓰기를 거부합니다") }
        busy = true
        defer { busy = false }
        for page in pages {
            let pkt = page.writePacket(checksum: checksumStyle)
            var acked = false
            for attempt in 0..<3 {
                try send(pkt, note: attempt > 0 ? "재시도" : "")
                let echo = await collect(for: 0.5) { $0.cmd == pkt.cmd && $0.pageIndex == pkt.pageIndex }
                if echo.contains(where: { $0.isAck }) { acked = true; break }
            }
            if !acked { throw HIDError.badResponse("페이지 \(page.pageIndex) 에 대한 ACK 없음") }
        }
        try await commit()
    }

    public func commit() async throws {
        let r = try await request(CompxCommand.commit.rawValue, retries: 2, timeout: 0.8)
        guard r.bytes[2] == 0x01 || r.isAck else { throw HIDError.badResponse("커밋 응답 이상: \(r.hex)") }
        note("플래시 저장(커밋) 완료")
    }

    // MARK: 조명

    public struct LedEffectSetting: Sendable, Equatable {
        public var effect: UInt8          // 공식 드라이버 LedOpt 의 하드웨어 효과 번호
        public var speed: UInt8           // 0...4
        public var brightness: UInt8      // 0...4
        public var direction: UInt8       // 0/1
        public var random: UInt8          // 0 = 지정 색, 1 = 무지개/랜덤
        public var r: UInt8, g: UInt8, b: UInt8
        public init(effect: UInt8, speed: UInt8 = 2, brightness: UInt8 = 4, direction: UInt8 = 0, random: UInt8 = 0, r: UInt8 = 255, g: UInt8 = 255, b: UInt8 = 255) {
            self.effect = effect; self.speed = speed; self.brightness = brightness; self.direction = direction; self.random = random; self.r = r; self.g = g; self.b = b
        }
        /// 추정 페이로드 순서: 공식 드라이버 KB.ini 의 LedOpt 필드 순서(효과, 속도, 밝기, 방향, 랜덤, 색) 를 따른다.
        public var payload: [UInt8] { [effect, speed, brightness, direction, random, r, g, b] }
    }

    /// 현재 조명 설정 읽기 (원시 페이지 반환; 해석은 진단 화면에서)
    public func readLighting() async throws -> [CompxPacket] {
        busy = true
        defer { busy = false }
        return try await readPages(CompxCommand.getLedEffect.rawValue)
    }

    public func readProfile() async throws -> [CompxPacket] {
        busy = true
        defer { busy = false }
        return try await readPages(CompxCommand.getProfile.rawValue)
    }

    /// 조명 효과 설정 (실험적: 페이로드 순서는 추정). ACK(에코) 가 오면 커밋.
    public func setLedEffect(_ s: LedEffectSetting, commitToFlash: Bool = true) async throws -> CompxPacket {
        guard protocolVerified else { throw HIDError.badResponse("프로토콜이 확인되지 않아 쓰기를 거부합니다 (먼저 '연결 확인' 실행)") }
        busy = true
        defer { busy = false }
        let pkt = CompxPacket(cmd: CompxCommand.setLedEffect.rawValue, pageCount: 1, pageIndex: 0,
                              dataLength: UInt8(s.payload.count), payload: s.payload, checksum: checksumStyle)
        var reply: CompxPacket?
        for attempt in 0..<3 {
            try send(pkt, note: attempt > 0 ? "재시도" : "SetLedEffect \(s.payload.map { String(format: "%02X", $0) }.joined(separator: " "))")
            let got = await collect(for: 0.6) { $0.cmd == pkt.cmd }
            if let a = got.first(where: { $0.isAck }) { reply = a; break }
        }
        guard let r = reply else { throw HIDError.badResponse("SetLedEffect 에 대한 응답 없음") }
        if commitToFlash { try? await commit() }
        return r
    }

    /// 키별 색상 직접 지정 (RK 분석: planar R[n] G[n] B[n] 를 14바이트 청크로, 청크마다 ACK)
    public func setLedColors(_ colors: [(UInt8, UInt8, UInt8)], slots: Int = 126) async throws {
        guard protocolVerified else { throw HIDError.badResponse("프로토콜이 확인되지 않아 쓰기를 거부합니다") }
        busy = true
        defer { busy = false }
        var buf = [UInt8](repeating: 0, count: slots * 3)
        for (i, c) in colors.prefix(slots).enumerated() {
            buf[i] = c.0; buf[slots + i] = c.1; buf[slots * 2 + i] = c.2
        }
        let chunk = CompxPacket.payloadLength
        let count = (buf.count + chunk - 1) / chunk
        for idx in 0..<count {
            let off = idx * chunk
            let len = min(chunk, buf.count - off)
            let pkt = CompxPacket(cmd: CompxCommand.setLedColors.rawValue, pageCount: UInt8(count), pageIndex: UInt8(idx),
                                  dataLength: UInt8(len), payload: Array(buf[off..<off + len]), checksum: checksumStyle)
            var acked = false
            for _ in 0..<5 {
                try send(pkt)
                let got = await collect(for: 0.4) { $0.cmd == pkt.cmd }
                if got.contains(where: { $0.isAck }) { acked = true; break }
            }
            if !acked { throw HIDError.badResponse("색상 청크 \(idx)/\(count) ACK 없음") }
        }
    }
}
