import Foundation

/// Compx(CX) 계열 키보드가 쓰는 벤더 채널(usage page 0xFF02, Report ID 0x13, 20바이트) 패킷.
///
/// 와이어 레이아웃 (오픈소스 두 곳의 분석이 일치):
/// ```
/// [0]  0x13  Report ID
/// [1]  명령 (cmd)
/// [2]  전체 페이지 수 (0x7F & packageNum)
/// [3]  페이지 번호   (0x7F & packageIndex)
/// [4]  (0x0F & dataLen) | (board << 4)   — 키맵 페이지는 항상 0x0E(14)
/// [5...18] 14바이트 페이로드
/// [19] 체크섬
/// ```
/// 체크섬은 두 가지 변형이 보고되었다. 수신 패킷으로 어느 쪽인지 자동 판별한다.
/// - `.sumAll`  : sum(bytes[0...18]) & 0xFF   (aula-f75 에서 키맵 쓰기까지 검증)
/// - `.rkStyle` : (19 + sum(bytes[1...17])) & 0xFF (openrgb-rk-r87pro, 마지막 페이로드 바이트 제외)
public struct CompxPacket: Equatable, Sendable, CustomStringConvertible {
    public static let length = 20
    public static let reportID: UInt8 = 0x13
    public static let payloadLength = 14

    public var bytes: [UInt8]

    public init(bytes: [UInt8]) {
        var b = bytes
        if b.first != Self.reportID { b.insert(Self.reportID, at: 0) }
        if b.count < Self.length { b += [UInt8](repeating: 0, count: Self.length - b.count) }
        if b.count > Self.length { b = Array(b.prefix(Self.length)) }
        self.bytes = b
    }

    public init(cmd: UInt8, pageCount: UInt8 = 1, pageIndex: UInt8 = 0, dataLength: UInt8 = 0, board: UInt8 = 0,
                payload: [UInt8] = [], checksum: ChecksumStyle = .sumAll) {
        var b = [UInt8](repeating: 0, count: Self.length)
        b[0] = Self.reportID
        b[1] = cmd
        b[2] = pageCount & 0x7F
        b[3] = pageIndex & 0x7F
        b[4] = (dataLength & 0x0F) | ((board & 0x0F) << 4)
        for (i, v) in payload.prefix(Self.payloadLength).enumerated() { b[5 + i] = v }
        self.bytes = b
        self.bytes[19] = checksum.compute(self.bytes)
    }

    /// AULA 식 단순 명령: [0x13, cmd, payload...] 형태 (바이트 2 부터 바로 페이로드)
    public init(simpleCmd cmd: UInt8, body: [UInt8] = [], checksum: ChecksumStyle = .sumAll) {
        var b = [UInt8](repeating: 0, count: Self.length)
        b[0] = Self.reportID
        b[1] = cmd
        for (i, v) in body.prefix(17).enumerated() { b[2 + i] = v }
        self.bytes = b
        self.bytes[19] = checksum.compute(self.bytes)
    }

    public var cmd: UInt8 { bytes[1] }
    public var pageCount: UInt8 { bytes[2] & 0x7F }
    public var pageIndex: UInt8 { bytes[3] & 0x7F }
    public var dataLength: UInt8 { bytes[4] & 0x0F }
    public var board: UInt8 { bytes[4] >> 4 }
    public var payload: [UInt8] { Array(bytes[5..<19]) }
    public var checksumByte: UInt8 { bytes[19] }
    /// 응답 패킷의 바이트 2 bit7 이 1이면 아직 처리 중(재전송 요청), 0이면 ACK
    public var isAck: Bool { (bytes[2] >> 7) == 0 }

    public func checksumValid(_ style: ChecksumStyle) -> Bool { style.compute(bytes) == bytes[19] }
    /// 어느 체크섬 변형과 맞는지 (둘 다/하나/없음)
    public var matchingChecksumStyles: [ChecksumStyle] { ChecksumStyle.allCases.filter { checksumValid($0) } }

    public mutating func seal(_ style: ChecksumStyle) { bytes[19] = style.compute(bytes) }

    public var hex: String { bytes.map { String(format: "%02X", $0) }.joined(separator: " ") }
    public var description: String { hex }
}

public enum ChecksumStyle: String, CaseIterable, Sendable {
    case sumAll
    case rkStyle

    public func compute(_ b: [UInt8]) -> UInt8 {
        switch self {
        case .sumAll:
            return UInt8(b[0..<19].reduce(0) { ($0 + Int($1)) & 0xFF })
        case .rkStyle:
            return UInt8((19 + b[1..<18].reduce(0) { $0 + Int($1) }) & 0xFF)
        }
    }

    public var label: String {
        switch self {
        case .sumAll: return "sum(0…18) 방식 (aula-f75)"
        case .rkStyle: return "19+sum(1…17) 방식 (rk-r87pro)"
        }
    }
}

/// 알려진 명령 코드 (두 오픈소스 분석 + 공식 드라이버 문자열 종합)
public enum CompxCommand: UInt8, CaseIterable, Sendable {
    case setKeyMatrix = 0x01
    case setLedColors = 0x02
    case setMacros = 0x03
    case setProfile = 0x04
    case getDeviceInfo = 0x05      // RK: GetPassword (모델/펌웨어), AULA: device info
    case setFactory = 0x06
    case getDongleStatus = 0x07
    case setLedEffect = 0x09
    case activelyReport = 0x0A     // 키보드가 자발적으로 보내는 하트비트
    case getKeyMatrix = 0x41       // 레이어 1 키맵 (36 페이지)
    case getKeyMatrixLayer2 = 0x42 // RK: GetLedColors / AULA: 레이어 2 키맵
    case getKeyMatrixLayer3 = 0x43 // RK: GetMacros / AULA: 레이어 3
    case getProfile = 0x44         // RK: GetProfile / AULA: 조명 설정 (10 페이지)
    case getLedEffect = 0x49       // RK: GetLedEffect / AULA: 키별 RGB (35 페이지)
    case writeKeyMatrixPage = 0x81 // AULA: 키맵 페이지 쓰기(에코로 ACK)
    case writeLedPage = 0x89       // 추정: 키별 RGB 페이지 쓰기
    case abort = 0xFC
    case commit = 0xFD             // RAM → 플래시 저장, 응답 01
    case beginSession = 0xFE

    public var name: String {
        switch self {
        case .setKeyMatrix: return "SetKeyMatrix"
        case .setLedColors: return "SetLedColors"
        case .setMacros: return "SetMacros"
        case .setProfile: return "SetProfile"
        case .getDeviceInfo: return "GetDeviceInfo / GetPassword"
        case .setFactory: return "SetFactory(공장 초기화)"
        case .getDongleStatus: return "GetDongleStatus"
        case .setLedEffect: return "SetLedEffect"
        case .activelyReport: return "ActivelyReport(하트비트)"
        case .getKeyMatrix: return "GetKeyMatrix(레이어1)"
        case .getKeyMatrixLayer2: return "GetKeyMatrix 레이어2 / GetLedColors"
        case .getKeyMatrixLayer3: return "GetKeyMatrix 레이어3 / GetMacros"
        case .getProfile: return "GetProfile / 조명 설정 읽기"
        case .getLedEffect: return "GetLedEffect / 키별 RGB 읽기"
        case .writeKeyMatrixPage: return "WriteKeyMatrixPage"
        case .writeLedPage: return "WriteLedPage(추정)"
        case .abort: return "Abort(0xFC)"
        case .commit: return "Commit(플래시 저장)"
        case .beginSession: return "BeginSession(0xFE)"
        }
    }

    public static func name(of cmd: UInt8) -> String {
        CompxCommand(rawValue: cmd)?.name ?? String(format: "알 수 없음 0x%02X", cmd)
    }
}

/// 벤더 채널 로그 한 줄 (진단 화면/CLI 출력용)
public struct VendorLogEntry: Identifiable, Sendable {
    public enum Direction: String, Sendable { case tx = "→", rx = "←", note = "·" }
    public let id = UUID()
    public let time: Date
    public let direction: Direction
    public let packet: CompxPacket?
    public let note: String

    public var line: String {
        let t = Self.fmt.string(from: time)
        if let p = packet {
            let cs = p.matchingChecksumStyles.map { $0 == .sumAll ? "A" : "R" }.joined()
            return "\(t) \(direction.rawValue) \(p.hex)  [\(CompxCommand.name(of: p.cmd))\(cs.isEmpty ? " 체크섬불일치" : " cs:\(cs)")]\(note.isEmpty ? "" : "  " + note)"
        }
        return "\(t) \(direction.rawValue) \(note)"
    }

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}

/// 키맵 페이지 해석 (AULA 분석 기준: 페이지당 7키 × 2바이트 빅엔디언 HID usage)
public struct KeymapPage: Sendable {
    public let layerCmd: UInt8
    public let pageCount: Int
    public let pageIndex: Int
    public var usages: [UInt16]   // 7개

    public init?(packet: CompxPacket) {
        guard packet.dataLength == 14 || packet.pageCount > 0 else { return nil }
        layerCmd = packet.cmd
        pageCount = Int(packet.pageCount)
        pageIndex = Int(packet.pageIndex)
        let p = packet.payload
        usages = (0..<7).map { UInt16(p[$0 * 2]) << 8 | UInt16(p[$0 * 2 + 1]) }
    }

    /// 쓰기용 패킷 (0x81) 으로 변환
    public func writePacket(checksum: ChecksumStyle) -> CompxPacket {
        var payload: [UInt8] = []
        for u in usages { payload += [UInt8(u >> 8), UInt8(u & 0xFF)] }
        return CompxPacket(cmd: CompxCommand.writeKeyMatrixPage.rawValue, pageCount: UInt8(pageCount), pageIndex: UInt8(pageIndex),
                           dataLength: 14, payload: payload, checksum: checksum)
    }
}
