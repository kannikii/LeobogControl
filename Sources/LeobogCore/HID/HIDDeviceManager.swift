import Foundation
import IOKit.hid
import Combine

/// 키보드에서 올라온 HID 입력 값 (키 테스터용)
public struct HIDKeyEvent: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let usage: HIDUsage
    public let value: Int          // 1 = 눌림, 0 = 뗌 (consumer 는 1/0, 일부는 값)
    public var isDown: Bool { value != 0 }
    public init(timestamp: Date, usage: HIDUsage, value: Int) { self.timestamp = timestamp; self.usage = usage; self.value = value }
}

/// 벤더 채널(Report ID 0x13) 원시 패킷
public struct VendorReport: Sendable {
    public let timestamp: Date
    public let bytes: [UInt8]       // Report ID 포함 20바이트로 정규화
}

/// 리포트 ID 별 수신 통계
public struct InputReportStat: Sendable, Equatable {
    public var count: Int = 0
    public var maxLength: Int = 0      // IOKit 이 알려준 가장 긴 리포트 길이
    public var overrunCount: Int = 0   // 버퍼보다 길어서 잘라낸 횟수 (0 이어야 정상)
    public init() {}
}

public enum InputMonitoringStatus: String, Sendable {
    case granted = "허용됨"
    case denied = "거부됨"
    case unknown = "요청 전"

    init(_ access: IOHIDAccessType) {
        switch access {
        case kIOHIDAccessTypeGranted: self = .granted
        case kIOHIDAccessTypeDenied: self = .denied
        default: self = .unknown
        }
    }
}

public enum DeviceOpenState: Equatable, Sendable {
    case notFound
    case foundNotOpen(reason: String)
    case open
}

/// Leobog Hi8SE (VID 0x3554 / PID 0xFA07, BLE) 를 IOHIDManager 로 다루는 관리자.
/// - 장치 탐지(연결/해제)는 입력 모니터링 권한 없이도 동작한다.
/// - 입력 리포트 수신 / 출력 리포트 전송은 '입력 모니터링' 권한이 있어야 한다.
public final class HIDDeviceManager: ObservableObject {
    public static let vendorID: Int = 0x3554
    public static let productID: Int = 0xFA07
    public static let vendorReportID: UInt8 = 0x13
    public static let vendorReportLength = 20

    @Published public private(set) var devices: [IOHIDDevice] = []
    @Published public private(set) var state: DeviceOpenState = .notFound
    @Published public private(set) var permission: InputMonitoringStatus = .unknown
    @Published public private(set) var productName: String = ""
    @Published public private(set) var transport: String = ""
    @Published public private(set) var lastKeyEvents: [HIDKeyEvent] = []
    @Published public private(set) var vendorReportCount: Int = 0
    @Published public private(set) var lastError: String?

    public let keyEvents = PassthroughSubject<HIDKeyEvent, Never>()
    public let vendorReports = PassthroughSubject<VendorReport, Never>()
    public let deviceArrived = PassthroughSubject<IOHIDDevice, Never>()
    public let deviceRemoved = PassthroughSubject<IOHIDDevice, Never>()

    /// 리포트 ID 별 수신 통계 (크래시 모니터 / 진단 화면용)
    @Published public private(set) var reportStats: [UInt32: InputReportStat] = [:]

    /// IOKit 에 등록한 입력 리포트 버퍼. 크기는 장치마다 다르다 (아래 `reportBufferSize(for:)`).
    private struct ReportBuffer {
        let ptr: UnsafeMutablePointer<UInt8>
        let count: Int
    }
    private var manager: IOHIDManager?
    private var opened = false
    private var reportBuffers: [IOHIDDevice: ReportBuffer] = [:]
    /// 콜백을 끊은 뒤에도 IOKit 이 큐에 남은 리포트를 버퍼에 쓸 수 있어 끝까지 free 하지 않는 버퍼들 (재연결 횟수만큼만 쌓임)
    private var retiredBuffers: [ReportBuffer] = []
    /// 버퍼 최소 크기와 여유분. 이 키보드는 한 PID 아래 인터페이스가 둘이고(키보드 0x01/6: 최대 입력 21바이트, 벤더 0xFF00/3: 최대 입력 108바이트),
    /// 예전처럼 64바이트 고정 버퍼를 쓰면 108바이트 리포트가 힙을 44바이트 덮어써 SwiftUI 쪽에서 EXC_BAD_ACCESS 로 죽는다.
    public static let minReportBufferSize = 64
    public static let reportBufferMargin = 64
    private let keyEventLimit = 200
    /// 장치 탐지만 할지(권한 불필요) 입력까지 열지 결정
    private let listenOnly: Bool

    public init(listenOnly: Bool = false) {
        self.listenOnly = listenOnly
        refreshPermission()
    }

    deinit { stop() }

    // MARK: 권한

    public func refreshPermission() {
        let now = InputMonitoringStatus(IOHIDCheckAccess(kIOHIDRequestTypeListenEvent))
        if now != permission { permission = now }   // 1초 폴링마다 objectWillChange 를 쏘지 않도록 바뀔 때만
    }

    /// 시스템 '입력 모니터링' 권한 요청 대화상자를 띄운다 (앱 이름으로 요청됨).
    /// 주의: macOS 는 이 앱에 대한 결정 기록(허용/거부)이 이미 있으면 대화상자를 다시 띄우지 않고 그 기록대로 답한다.
    /// 임시(ad-hoc) 서명 앱은 다시 빌드하면 서명 해시가 바뀌어 기존 '허용' 기록이 무효가 되는데, 그때도 '거부됨'으로 보이면서
    /// 대화상자는 뜨지 않는다. 그 경우 `resetPermissionRecord(bundleID:)` 로 기록을 지운 뒤 다시 부른다.
    @discardableResult
    public func requestPermission() -> Bool {
        let ok = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        refreshPermission()
        return ok
    }

    /// 이 앱의 '입력 모니터링' 결정 기록을 지운다 (`tccutil reset ListenEvent <번들 ID>`). 지운 뒤 `requestPermission()` 을 부르면
    /// 시스템 대화상자가 다시 뜬다. 사용자 권한으로 동작하며 관리자 암호는 필요 없다.
    @discardableResult
    public func resetPermissionRecord(bundleID: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        p.arguments = ["reset", "ListenEvent", bundleID]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        // waitUntilExit() 는 런루프를 재진입시키므로 쓰지 않는다 (HidutilRemapService.run 참고)
        let exited = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in exited.signal() }
        do { try p.run() } catch {
            lastError = "tccutil 실행 실패: \(error.localizedDescription)"
            return false
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        exited.wait()
        let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        refreshPermission()
        guard p.terminationStatus == 0 else {
            lastError = "tccutil reset 실패 (\(p.terminationStatus)): \(out)"
            return false
        }
        return true
    }

    // MARK: 시작/중지

    public func start() {
        if manager != nil { stop() }
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [kIOHIDVendorIDKey: Self.vendorID, kIOHIDProductIDKey: Self.productID]
        IOHIDManagerSetDeviceMatching(m, matching as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(m, { ctx, _, _, device in
            guard let ctx else { return }
            Unmanaged<HIDDeviceManager>.fromOpaque(ctx).takeUnretainedValue().handleArrival(device)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(m, { ctx, _, _, device in
            guard let ctx else { return }
            Unmanaged<HIDDeviceManager>.fromOpaque(ctx).takeUnretainedValue().handleRemoval(device)
        }, ctx)
        if !listenOnly {
            IOHIDManagerRegisterInputValueCallback(m, { ctx, _, _, value in
                guard let ctx else { return }
                Unmanaged<HIDDeviceManager>.fromOpaque(ctx).takeUnretainedValue().handleValue(value)
            }, ctx)
        }
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        manager = m
        refreshPermission()
        if listenOnly {
            opened = false
            // 열지 않아도 매칭 콜백은 동작한다. 단, 이미 연결된 장치는 Open 없이도 CopyDevices 로 확인 가능.
            syncDevices(openResult: nil)
        } else {
            let r = IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
            opened = (r == IOErr.success)
            if !opened { lastError = Self.describe(r) }
            syncDevices(openResult: r)
        }
    }

    public func stop() {
        guard let m = manager else { return }
        // 리포트 콜백부터 끊는다. 등록된 채로 버퍼를 free 하면 키 입력이 해제된 메모리에 써져 힙이 깨지고
        // 엉뚱한 곳(SwiftUI 레이아웃 등)에서 앱이 죽는다.
        for d in Array(reportBuffers.keys) { detachReportCallback(d) }
        IOHIDManagerRegisterDeviceMatchingCallback(m, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(m, nil, nil)
        if !listenOnly { IOHIDManagerRegisterInputValueCallback(m, nil, nil) }
        IOHIDManagerUnscheduleFromRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        if opened { IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone)) }
        manager = nil
        opened = false
        devices = []
        state = .notFound
    }

    /// 권한을 받은 뒤 다시 열기. 이미 열려 있으면 아무것도 하지 않는다 (열린 상태에서 stop/start 를 반복할 이유가 없다).
    public func reopen() {
        if opened { return }
        start()
    }

    /// 사용자가 명시적으로 '다시 연결' 을 눌렀을 때: 열려 있어도 닫고 다시 연다.
    public func reconnect() {
        stop()
        start()
    }

    private func syncDevices(openResult: IOReturn?) {
        guard let m = manager else { return }
        let set = (IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice>) ?? []
        devices = Self.sorted(Array(set))
        for d in devices { attachReportCallback(d) }
        updateState(openResult: openResult)
    }

    /// 같은 VID/PID 아래 인터페이스가 여럿일 때 벤더 채널(0x13, 20바이트 출력)을 보낼 수 있는 쪽을 앞에 둔다:
    /// 출력 리포트 최대 크기가 20 이상인 것 → Generic Desktop/Keyboard(0x01/6) 인 것 → 나머지.
    /// `devices.first` 가 Set 순서에 따라 출력 1바이트짜리 0xFF00 인터페이스가 될 수 있어서 IOHIDDeviceSetReport 가 조용히 실패하던 것을 막는다.
    private static func sorted(_ list: [IOHIDDevice]) -> [IOHIDDevice] {
        func rank(_ d: IOHIDDevice) -> Int {
            let maxOut = IOHIDDeviceGetProperty(d, kIOHIDMaxOutputReportSizeKey as CFString) as? Int ?? 0
            let page = IOHIDDeviceGetProperty(d, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
            let usage = IOHIDDeviceGetProperty(d, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
            if maxOut >= vendorReportLength { return 0 }
            if page == 0x01 && usage == 0x06 { return 1 }
            return 2
        }
        return list.enumerated().sorted { a, b in
            let ra = rank(a.element), rb = rank(b.element)
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map { $0.element }
    }

    /// 벤더 채널 송수신·속성 표시에 쓰는 대표 인터페이스
    public var primaryDevice: IOHIDDevice? { devices.first }

    /// 장치의 최대 입력 리포트 크기(kIOHIDMaxInputReportSize) + Report ID 1바이트 + 여유분. 최소 64.
    public static func reportBufferSize(for device: IOHIDDevice) -> Int {
        let maxIn = IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? 0
        return max(minReportBufferSize, maxIn + 1 + reportBufferMargin)
    }

    private static func describeInterface(_ d: IOHIDDevice) -> String {
        let page = IOHIDDeviceGetProperty(d, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        let usage = IOHIDDeviceGetProperty(d, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
        let maxIn = IOHIDDeviceGetProperty(d, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? 0
        let maxOut = IOHIDDeviceGetProperty(d, kIOHIDMaxOutputReportSizeKey as CFString) as? Int ?? 0
        let transport = IOHIDDeviceGetProperty(d, kIOHIDTransportKey as CFString) as? String ?? "?"
        return String(format: "usage 0x%02X/%d transport %@ maxIn %d maxOut %d", page, usage, transport, maxIn, maxOut)
    }

    private func updateState(openResult: IOReturn?) {
        guard let d = primaryDevice else {
            state = .notFound
            productName = ""
            transport = ""
            return
        }
        productName = (IOHIDDeviceGetProperty(d, kIOHIDProductKey as CFString) as? String) ?? "LEOBOG Hi8SE"
        transport = (IOHIDDeviceGetProperty(d, kIOHIDTransportKey as CFString) as? String) ?? ""
        if listenOnly {
            state = .foundNotOpen(reason: "탐지 전용 모드")
        } else if opened {
            state = .open
        } else {
            let reason: String
            if let r = openResult, r == IOErr.notPermitted {
                reason = "입력 모니터링 권한이 필요합니다 (시스템 설정 › 개인정보 보호 및 보안 › 입력 모니터링)"
            } else if let r = openResult {
                reason = "열기 실패: \(Self.describe(r))"
            } else {
                reason = "열리지 않음"
            }
            state = .foundNotOpen(reason: reason)
        }
    }

    private func handleArrival(_ device: IOHIDDevice) {
        if !devices.contains(device) { devices = Self.sorted(devices + [device]) }
        AppLog.shared.log("hid", "장치 연결: " + Self.describeInterface(device))
        attachReportCallback(device)
        updateState(openResult: opened ? IOErr.success : IOErr.notPermitted)
        deviceArrived.send(device)
    }

    private func handleRemoval(_ device: IOHIDDevice) {
        devices.removeAll { $0 == device }
        AppLog.shared.log("hid", "장치 해제: " + Self.describeInterface(device))
        detachReportCallback(device)
        updateState(openResult: opened ? IOErr.success : IOErr.notPermitted)
        deviceRemoved.send(device)
    }

    private func attachReportCallback(_ device: IOHIDDevice) {
        guard !listenOnly, opened, reportBuffers[device] == nil else { return }
        let size = Self.reportBufferSize(for: device)
        let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        ptr.initialize(repeating: 0, count: size)
        let buf = ReportBuffer(ptr: ptr, count: size)
        reportBuffers[device] = buf
        AppLog.shared.log("hid", "리포트 콜백 등록: 버퍼 \(size)B — " + Self.describeInterface(device))
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, ptr, size, { ctx, _, sender, _, reportID, report, len in
            guard let ctx else { return }
            let me = Unmanaged<HIDDeviceManager>.fromOpaque(ctx).takeUnretainedValue()
            // IOKit 은 등록한 버퍼 크기 안에서만 쓰지만, 혹시 모를 경우를 위해 우리가 아는 버퍼 길이로 한 번 더 자른다.
            var limit = len
            var overrun = false
            if let sender {
                let dev = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
                if let b = me.reportBuffers[dev] {
                    if len > b.count { overrun = true; limit = b.count }
                }
            }
            let bytes = Array(UnsafeBufferPointer(start: report, count: max(0, limit)))
            me.handleReport(id: reportID, bytes: bytes, rawLength: len, overrun: overrun)
        }, ctx)
    }

    /// 리포트 콜백을 끊고 버퍼를 은퇴시킨다. 콜백을 nil 로 바꾼 뒤에도 IOKit 이 잠시 버퍼를 참조할 수 있으므로 free 하지 않는다.
    private func detachReportCallback(_ device: IOHIDDevice) {
        guard let buf = reportBuffers.removeValue(forKey: device) else { return }
        IOHIDDeviceRegisterInputReportCallback(device, buf.ptr, buf.count, nil, nil)
        retiredBuffers.append(buf)
        AppLog.shared.log("hid", "리포트 콜백 해제: 버퍼 \(buf.count)B 은퇴 (누적 \(retiredBuffers.count)개)")
    }

    private func handleReport(id: UInt32, bytes: [UInt8], rawLength: Int, overrun: Bool) {
        var st = reportStats[id] ?? InputReportStat()
        st.count += 1
        st.maxLength = max(st.maxLength, rawLength)
        if overrun {
            st.overrunCount += 1
            if st.overrunCount == 1 {
                AppLog.shared.log("hid", String(format: "경고: 리포트 0x%02X 길이 %d 가 버퍼보다 큼 — 잘라서 처리", id, rawLength))
            }
        }
        reportStats[id] = st
        guard id == UInt32(Self.vendorReportID) else { return }
        // macOS 는 번호가 있는 리포트의 경우 첫 바이트에 Report ID 를 포함해 전달한다. 둘 다 처리.
        var pkt = bytes
        if pkt.first != Self.vendorReportID { pkt.insert(Self.vendorReportID, at: 0) }
        if pkt.count < Self.vendorReportLength { pkt += [UInt8](repeating: 0, count: Self.vendorReportLength - pkt.count) }
        if pkt.count > Self.vendorReportLength { pkt = Array(pkt.prefix(Self.vendorReportLength)) }
        vendorReportCount += 1
        vendorReports.send(VendorReport(timestamp: Date(), bytes: pkt))
    }

    private func handleValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let page = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        // 키보드(0x07), 소비자(0x0C), Apple 벤더(0xFF/0xFF01) 만 보고, 롤오버/패딩 제외
        guard page == 0x07 || page == 0x0C || page == 0xFF || page == 0xFF01 else { return }
        if page == 0x07 && (usage < 0x04 || usage > 0xFFFF) { return }
        let v = IOHIDValueGetIntegerValue(value)
        let ev = HIDKeyEvent(timestamp: Date(), usage: HIDUsage(page: page, usage: usage), value: v)
        lastKeyEvents.append(ev)
        if lastKeyEvents.count > keyEventLimit { lastKeyEvents.removeFirst(lastKeyEvents.count - keyEventLimit) }
        keyEvents.send(ev)
    }

    public func clearKeyEvents() { lastKeyEvents.removeAll() }

    // MARK: 벤더 채널 송신

    /// 20바이트(Report ID 포함) 패킷을 출력 리포트로 보낸다.
    @discardableResult
    public func sendVendorReport(_ packet: [UInt8]) -> Result<Void, HIDError> {
        guard let d = primaryDevice else { return .failure(.noDevice) }
        guard opened else { return .failure(.notOpen) }
        var pkt = packet
        if pkt.first != Self.vendorReportID { pkt.insert(Self.vendorReportID, at: 0) }
        if pkt.count < Self.vendorReportLength { pkt += [UInt8](repeating: 0, count: Self.vendorReportLength - pkt.count) }
        let r = pkt.withUnsafeBufferPointer { buf -> IOReturn in
            IOHIDDeviceSetReport(d, kIOHIDReportTypeOutput, CFIndex(Self.vendorReportID), buf.baseAddress!, pkt.count)
        }
        if r == IOErr.success { return .success(()) }
        return .failure(.ioReturn(r, Self.describe(r)))
    }

    /// IOHIDManagerOpen 에 성공한 상태인가 (장치가 아직 열거되지 않았어도 true 일 수 있다)
    public var isManagerOpen: Bool { opened }
    public var isOpen: Bool { opened && !devices.isEmpty }

    public static func describe(_ r: IOReturn) -> String {
        switch r {
        case IOErr.success: return "성공"
        case IOErr.notPermitted: return "권한 없음 (IOErr.notPermitted, 입력 모니터링 필요)"
        case IOErr.notOpen: return "장치가 열려 있지 않음 (IOErr.notOpen)"
        case IOErr.exclusiveAccess: return "다른 프로세스가 독점 사용 중 (IOErr.exclusiveAccess)"
        case IOErr.unsupported: return "지원되지 않음 (IOErr.unsupported)"
        case IOErr.timeout: return "시간 초과 (IOErr.timeout)"
        case IOErr.noDevice: return "장치 없음 (IOErr.noDevice)"
        default: return String(format: "IOReturn 0x%08x", r)
        }
    }

    // MARK: 장치 속성

    public struct DeviceInfo: Sendable {
        public var product: String = ""
        public var manufacturer: String = ""
        public var transport: String = ""
        public var vendorID: Int = 0
        public var productID: Int = 0
        public var version: Int = 0
        public var serial: String = ""
        public var maxInput: Int = 0
        public var maxOutput: Int = 0
        public var maxFeature: Int = 0
        public var usagePairs: [(page: Int, usage: Int)] = []
        public var registryID: UInt64 = 0
    }

    public func deviceInfo() -> DeviceInfo? {
        guard let d = primaryDevice else { return nil }
        func p(_ k: String) -> Any? { IOHIDDeviceGetProperty(d, k as CFString) }
        var i = DeviceInfo()
        i.product = p(kIOHIDProductKey) as? String ?? ""
        i.manufacturer = p(kIOHIDManufacturerKey) as? String ?? ""
        i.transport = p(kIOHIDTransportKey) as? String ?? ""
        i.vendorID = p(kIOHIDVendorIDKey) as? Int ?? 0
        i.productID = p(kIOHIDProductIDKey) as? Int ?? 0
        i.version = p(kIOHIDVersionNumberKey) as? Int ?? 0
        i.serial = p(kIOHIDSerialNumberKey) as? String ?? ""
        i.maxInput = p(kIOHIDMaxInputReportSizeKey) as? Int ?? 0
        i.maxOutput = p(kIOHIDMaxOutputReportSizeKey) as? Int ?? 0
        i.maxFeature = p(kIOHIDMaxFeatureReportSizeKey) as? Int ?? 0
        if let pairs = p(kIOHIDDeviceUsagePairsKey) as? [[String: Int]] {
            i.usagePairs = pairs.compactMap { d in
                guard let pg = d[kIOHIDDeviceUsagePageKey], let u = d[kIOHIDDeviceUsageKey] else { return nil }
                return (pg, u)
            }
        }
        var rid: UInt64 = 0
        let service = IOHIDDeviceGetService(d)
        if service != 0 { IORegistryEntryGetRegistryEntryID(service, &rid) }
        i.registryID = rid
        return i
    }
}

public enum HIDError: Error, CustomStringConvertible {
    case noDevice
    case notOpen
    case ioReturn(IOReturn, String)
    case timeout
    case badResponse(String)

    public var description: String {
        switch self {
        case .noDevice: return "키보드를 찾을 수 없습니다"
        case .notOpen: return "장치가 열려 있지 않습니다 (입력 모니터링 권한 확인)"
        case .ioReturn(_, let s): return s
        case .timeout: return "응답 시간 초과"
        case .badResponse(let s): return "잘못된 응답: \(s)"
        }
    }
}

/// IOKit 오류 코드 (복합 매크로라 Swift 로 import 되지 않아 직접 정의)
public enum IOErr {
    public static let success: IOReturn = 0
    public static let noDevice: IOReturn = IOReturn(bitPattern: 0xE00002C0)
    public static let exclusiveAccess: IOReturn = IOReturn(bitPattern: 0xE00002C5)
    public static let unsupported: IOReturn = IOReturn(bitPattern: 0xE00002C7)
    public static let notOpen: IOReturn = IOReturn(bitPattern: 0xE00002CD)
    public static let timeout: IOReturn = IOReturn(bitPattern: 0xE00002D6)
    public static let notPermitted: IOReturn = IOReturn(bitPattern: 0xE00002E2)
}
