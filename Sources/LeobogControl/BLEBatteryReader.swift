import Foundation
import Combine
import CoreBluetooth

/// 키보드의 BLE GATT Battery Service(0x180F / 0x2A19) 를 앱이 직접 읽는다.
///
/// macOS 가 시스템 설정·system_profiler 에 보여 주는 배터리 값은 bluetoothd 가 같은 특성을 연결 시점에 한 번 읽고
/// 그 뒤로는 키보드가 notify 로 알려 줄 때만 갱신하는 값이다. 펌웨어가 notify 를 보내지 않으면 며칠이고 그대로
/// (예: 100%) 머문다. 여기서는 이미 시스템이 연결해 둔 peripheral 에 CoreBluetooth 로 붙어 주기적으로 read 를 보내고,
/// 특성이 notify 를 지원하면 구독도 한다. 쓰기는 하지 않는다.
///
/// CoreBluetooth 는 처음 쓰는 순간 macOS 블루투스 권한 대화상자를 띄우므로, `CBCentralManager.authorization` 이
/// 이미 허용일 때만 자동으로 시작하고 그 외에는 사용자가 버튼으로 시작한다.
final class BLEBatteryReader: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle                 // 아직 시작 안 함
        case unauthorized(String) // 권한 거부/제한
        case poweredOff
        case searching            // 연결된 peripheral 중 Battery Service 가진 것을 찾는 중
        case notFound             // 시스템에 연결된 BLE 장치 중 배터리 서비스를 가진 Leobog 가 없음
        case connecting(String)
        case ready(String)        // 특성 찾음, 읽는 중
        case disconnected(String)

        var label: String {
            switch self {
            case .idle: return "시작 안 함"
            case .unauthorized(let r): return "블루투스 권한 없음 (\(r))"
            case .poweredOff: return "블루투스 꺼짐"
            case .searching: return "키보드 찾는 중…"
            case .notFound: return "배터리 서비스를 가진 연결된 키보드가 없음"
            case .connecting(let n): return "\(n) 에 연결 중…"
            case .ready(let n): return "\(n) 에서 직접 읽는 중"
            case .disconnected(let n): return "\(n) 연결 끊김 — 키보드를 깨우면 다시 붙습니다"
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var percent: Int?
    @Published private(set) var lastRead: Date?
    @Published private(set) var supportsNotify = false
    @Published private(set) var readCount = 0
    @Published private(set) var history: [(Date, Int)] = []   // 값이 바뀐 시점만 기록 (최근 20개)

    static let batteryService = CBUUID(string: "180F")
    static let batteryLevel = CBUUID(string: "2A19")

    /// 시스템 권한이 이미 허용돼 있는지 (대화상자 없이 확인 가능)
    static var isAuthorized: Bool { CBCentralManager.authorization == .allowedAlways }
    static var authorizationLabel: String {
        switch CBCentralManager.authorization {
        case .allowedAlways: return "허용됨"
        case .denied: return "거부됨"
        case .restricted: return "제한됨"
        case .notDetermined: return "아직 묻지 않음"
        @unknown default: return "알 수 없음"
        }
    }

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?
    private var pollTimer: Timer?
    private var searchTimer: Timer?
    private let pollInterval: TimeInterval
    private let log: (String) -> Void

    init(pollInterval: TimeInterval = 60, log: @escaping (String) -> Void = { _ in }) {
        self.pollInterval = pollInterval
        self.log = log
        super.init()
    }

    var isRunning: Bool { central != nil }

    /// CBCentralManager 를 만든다 — 권한 기록이 없으면 이 순간 시스템 대화상자가 뜬다.
    func start() {
        guard central == nil else { readNow(); return }
        phase = .searching
        central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
        log("BLE 배터리 리더 시작 · 권한 \(Self.authorizationLabel)")
    }

    func stop() {
        pollTimer?.invalidate(); pollTimer = nil
        searchTimer?.invalidate(); searchTimer = nil
        if let p = peripheral, let c = central { c.cancelPeripheralConnection(p) }
        peripheral = nil; characteristic = nil; central = nil
        phase = .idle
    }

    /// 지금 바로 한 번 읽는다 (특성이 준비돼 있을 때). 아니면 다시 찾는다.
    func readNow() {
        if let p = peripheral, let ch = characteristic, p.state == .connected {
            p.readValue(for: ch)
        } else {
            search()
        }
    }

    // MARK: - 내부

    private func search() {
        guard let c = central, c.state == .poweredOn else { return }
        // 시스템(bluetoothd)이 이미 연결해 둔 peripheral 만 쓴다 — 스캔도, 새 연결도 하지 않는다.
        let found = c.retrieveConnectedPeripherals(withServices: [Self.batteryService])
        let named = found.filter { ($0.name ?? "").uppercased().contains("LEOBOG") || ($0.name ?? "").uppercased().contains("HI8") }
        guard let target = named.first ?? (found.count == 1 ? found.first : nil) else {
            if peripheral == nil { phase = .notFound }
            log("BLE 배터리: Battery Service 가진 연결 장치 \(found.count)개, Leobog 없음 \(found.map { $0.name ?? "?" })")
            scheduleSearch()
            return
        }
        if let p = peripheral, p.identifier == target.identifier, p.state == .connected { readNow(); return }
        peripheral = target
        target.delegate = self
        let name = target.name ?? "키보드"
        phase = .connecting(name)
        log("BLE 배터리: \(name) (\(target.identifier.uuidString)) 에 GATT 연결 시도")
        c.connect(target, options: nil)
    }

    private func scheduleSearch(after: TimeInterval = 30) {
        searchTimer?.invalidate()
        searchTimer = Timer.scheduledTimer(withTimeInterval: after, repeats: false) { [weak self] _ in self?.search() }
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in self?.readNow() }
    }

    private func record(_ value: Int) {
        let now = Date()
        readCount += 1
        lastRead = now
        if percent != value {
            log("BLE 배터리: \(percent.map { "\($0)%" } ?? "—") → \(value)%")
            percent = value
            history.append((now, value))
            if history.count > 20 { history.removeFirst(history.count - 20) }
        }
    }
}

extension BLEBatteryReader: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            search()
        case .poweredOff:
            phase = .poweredOff
        case .unauthorized:
            phase = .unauthorized(Self.authorizationLabel)
            log("BLE 배터리: 블루투스 권한 \(Self.authorizationLabel) — 시스템 설정 › 개인정보 보호 및 보안 › Bluetooth 에서 Leobog Control 을 켜 주세요")
        case .unsupported:
            phase = .unauthorized("이 Mac 은 BLE 미지원")
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        phase = .connecting(peripheral.name ?? "키보드")
        peripheral.discoverServices([Self.batteryService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log("BLE 배터리: 연결 실패 \(error?.localizedDescription ?? "")")
        phase = .disconnected(peripheral.name ?? "키보드")
        scheduleSearch()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        // 키보드가 절전으로 들어가면 BLE 링크 자체가 끊긴다. 시스템이 다시 붙이면 우리도 다시 찾는다.
        characteristic = nil
        pollTimer?.invalidate(); pollTimer = nil
        phase = .disconnected(peripheral.name ?? "키보드")
        log("BLE 배터리: 연결 끊김 \(error?.localizedDescription ?? "")")
        scheduleSearch(after: 15)
    }
}

extension BLEBatteryReader: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let svc = peripheral.services?.first(where: { $0.uuid == Self.batteryService }) else {
            log("BLE 배터리: Battery Service 없음 \(error?.localizedDescription ?? "")")
            phase = .notFound
            return
        }
        peripheral.discoverCharacteristics([Self.batteryLevel], for: svc)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let ch = service.characteristics?.first(where: { $0.uuid == Self.batteryLevel }) else {
            log("BLE 배터리: Battery Level 특성 없음 \(error?.localizedDescription ?? "")")
            phase = .notFound
            return
        }
        characteristic = ch
        supportsNotify = ch.properties.contains(.notify)
        phase = .ready(peripheral.name ?? "키보드")
        log("BLE 배터리: 특성 찾음 · properties \(ch.properties.rawValue) (read \(ch.properties.contains(.read)) notify \(supportsNotify))")
        peripheral.readValue(for: ch)
        if supportsNotify { peripheral.setNotifyValue(true, for: ch) }
        startPolling()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let e = error { log("BLE 배터리: 읽기 오류 \(e.localizedDescription)"); return }
        guard let b = characteristic.value?.first else { return }
        record(Int(b))
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let e = error { log("BLE 배터리: notify 구독 실패 \(e.localizedDescription)"); supportsNotify = false }
        else { log("BLE 배터리: notify 구독 \(characteristic.isNotifying ? "됨" : "해제")") }
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        characteristic = nil
        peripheral.discoverServices([Self.batteryService])
    }
}
