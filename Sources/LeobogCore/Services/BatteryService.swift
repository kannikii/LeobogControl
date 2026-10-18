import Foundation
import Combine

/// 블루투스 배터리/연결 정보. IORegistry 에 BatteryPercent 가 없어서 `system_profiler SPBluetoothDataType -json` 을 쓴다.
public struct BluetoothDeviceStatus: Sendable, Equatable {
    public var name = ""
    public var connected = false
    public var batteryPercent: Int? = nil
    public var address = ""
    public var firmware = ""
    public var minorType = ""
    public var rssi: Int? = nil
    public var vendorID = ""
    public var productID = ""
    public var raw: [String: String] = [:]
}

public final class BatteryService: ObservableObject {
    @Published public private(set) var status: BluetoothDeviceStatus?
    @Published public private(set) var lastUpdated: Date?
    @Published public private(set) var refreshing = false

    private var timer: Timer?

    public init() {}

    public func startAutoRefresh(interval: TimeInterval = 120) {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.refresh() }
    }

    public func stopAutoRefresh() { timer?.invalidate(); timer = nil }

    public func refresh() {
        guard !refreshing else { return }
        refreshing = true
        DispatchQueue.global(qos: .utility).async {
            let s = Self.query()
            DispatchQueue.main.async {
                self.status = s
                self.lastUpdated = Date()
                self.refreshing = false
            }
        }
    }

    /// 동기 조회 (CLI 용)
    public static func query() -> BluetoothDeviceStatus? {
        guard case .success(let out) = HidutilRemapService.run(["SPBluetoothDataType", "-json"], tool: "/usr/sbin/system_profiler"),
              let data = out.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["SPBluetoothDataType"] as? [[String: Any]] else { return nil }
        for top in list {
            for (key, connected) in [("device_connected", true), ("device_not_connected", false)] {
                guard let entries = top[key] as? [[String: Any]] else { continue }
                for entry in entries {
                    for (name, infoAny) in entry {
                        guard let info = infoAny as? [String: Any] else { continue }
                        let vid = (info["device_vendorID"] as? String ?? "").lowercased()
                        let up = name.uppercased()
                        guard up.contains("LEOBOG") || up.contains("HI8") || vid.contains("3554") else { continue }
                        var s = BluetoothDeviceStatus()
                        s.name = name
                        s.connected = connected
                        s.address = info["device_address"] as? String ?? ""
                        s.firmware = info["device_firmwareVersion"] as? String ?? ""
                        s.minorType = info["device_minorType"] as? String ?? ""
                        s.vendorID = info["device_vendorID"] as? String ?? ""
                        s.productID = info["device_productID"] as? String ?? ""
                        if let r = info["device_rssi"] as? String, let v = Int(r.replacingOccurrences(of: " dBm", with: "")) { s.rssi = v }
                        if let b = info["device_batteryLevelMain"] as? String {
                            s.batteryPercent = Int(b.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
                        }
                        for (k, v) in info { s.raw[k] = "\(v)" }
                        return s
                    }
                }
            }
        }
        return nil
    }
}
