import Foundation
import Darwin

/// 앱 로그(브레드크럼). `~/Library/Logs/LeobogControl/app.log` 에 한 줄씩 바로 기록한다.
/// 버퍼링 없이 O_APPEND 로 열어 쓰고 닫으므로, 앱이 죽어도 직전 줄까지 남는다 → 크래시 직전에 무엇을 하고 있었는지 알 수 있다.
public final class AppLog: @unchecked Sendable {
    public static let shared = AppLog()
    public static let directory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/LeobogControl", isDirectory: true)
    public static let fileURL = directory.appendingPathComponent("app.log")
    private static let maxBytes = 2_000_000
    private let lock = NSLock()
    private let formatter: DateFormatter
    private let processTag: String

    private init() {
        formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        processTag = ProcessInfo.processInfo.processName
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
    }

    /// 한 줄 기록. 어느 스레드에서 불러도 된다.
    public func log(_ category: String, _ message: String) {
        let line = "\(formatter.string(from: Date())) [\(processTag):\(getpid())] [\(category)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        lock.lock(); defer { lock.unlock() }
        rotateIfNeeded()
        let fd = open(Self.fileURL.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { return }
        data.withUnsafeBytes { buf in _ = write(fd, buf.baseAddress, buf.count) }
        close(fd)
    }

    /// 2MB 를 넘으면 app.log.1 로 밀어낸다 (이전 .1 은 버림).
    private func rotateIfNeeded() {
        let fm = FileManager.default
        guard let size = (try? fm.attributesOfItem(atPath: Self.fileURL.path)[.size]) as? Int, size > Self.maxBytes else { return }
        let old = Self.directory.appendingPathComponent("app.log.1")
        try? fm.removeItem(at: old)
        try? fm.moveItem(at: Self.fileURL, to: old)
    }

    /// 마지막 `max` 줄 (오래된 것부터).
    public func recentLines(_ max: Int = 200) -> [String] {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: Self.fileURL),
              let text = String(data: data.suffix(400_000), encoding: .utf8) else { return [] }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        return Array(lines.suffix(max))
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: Self.fileURL)
    }
}

/// 실행 표식. 시작할 때 `running.json` 을 쓰고 정상 종료 때 지운다.
/// 다음 실행에서 파일이 남아 있고 그 pid 가 살아 있지 않으면 → 직전 실행이 정상 종료되지 않았다(크래시 또는 강제 종료).
public enum RunMarker {
    public static let url = AppLog.directory.appendingPathComponent("running.json")

    public struct Previous: Sendable {
        public let pid: Int32
        public let launchedAt: Date
        public let version: String
    }

    private struct Record: Codable { var pid: Int32; var launchedAt: Double; var version: String }

    /// 앱 시작 시. 직전 실행이 정상 종료 표식을 남기지 않았으면 그 정보를 돌려준다 (다른 인스턴스가 살아 있으면 nil).
    @discardableResult
    public static func beginSession(version: String) -> Previous? {
        var previous: Previous? = nil
        if let data = try? Data(contentsOf: url), let r = try? JSONDecoder().decode(Record.self, from: data) {
            let alive = r.pid > 0 && (kill(r.pid, 0) == 0 || errno == EPERM)
            if !alive && r.pid != getpid() {
                previous = Previous(pid: r.pid, launchedAt: Date(timeIntervalSince1970: r.launchedAt), version: r.version)
            }
        }
        let rec = Record(pid: getpid(), launchedAt: Date().timeIntervalSince1970, version: version)
        try? FileManager.default.createDirectory(at: AppLog.directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(rec) { try? data.write(to: url, options: .atomic) }
        return previous
    }

    /// 정상 종료 시.
    public static func endSession() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// 이 프로세스와 시스템의 메모리 상태 (task_info / host_statistics64 / sysctl).
public struct MemoryStats: Sendable {
    public var residentBytes: UInt64 = 0        // 실제 상주 메모리
    public var footprintBytes: UInt64 = 0       // phys_footprint (활성 모니터의 '메모리' 와 같은 기준)
    public var virtualBytes: UInt64 = 0
    public var systemTotalBytes: UInt64 = 0
    public var systemFreeBytes: UInt64 = 0      // free + inactive 페이지 (바로 쓸 수 있는 양)
    public var systemAvailablePercent: Int? = nil   // kern.memorystatus_level
    public var pressureLevel: Int? = nil            // kern.memorystatus_vm_pressure_level: 1 정상, 2 경고, 4 위험

    public var pressureLabel: String {
        switch pressureLevel {
        case 1: return "정상"
        case 2: return "경고 (시스템 메모리 부족 — 다른 앱이 많이 쓰는 중)"
        case 4: return "위험 (macOS 가 프로세스를 종료할 수 있음)"
        case nil: return "알 수 없음"
        default: return "레벨 \(pressureLevel!)"
        }
    }

    public static func current() -> MemoryStats {
        var s = MemoryStats()
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { p in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        if kr == KERN_SUCCESS {
            s.residentBytes = UInt64(info.resident_size)
            s.footprintBytes = UInt64(info.phys_footprint)
            s.virtualBytes = UInt64(info.virtual_size)
        }
        s.systemTotalBytes = ProcessInfo.processInfo.physicalMemory
        var vm = vm_statistics64_data_t()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr2 = withUnsafeMutablePointer(to: &vm) { p in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount) }
        }
        if kr2 == KERN_SUCCESS {
            s.systemFreeBytes = (UInt64(vm.free_count) + UInt64(vm.inactive_count)) * UInt64(vm_kernel_page_size)
        }
        s.systemAvailablePercent = sysctlInt("kern.memorystatus_level")
        s.pressureLevel = sysctlInt("kern.memorystatus_vm_pressure_level")
        return s
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }

    public static func format(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb >= 1024 { return String(format: "%.2f GB", mb / 1024) }
        return String(format: "%.1f MB", mb)
    }
}

/// macOS 메모리 압박 알림(DispatchSource) — 경고/위험이 오면 로그에 남긴다. 나중에 '왜 죽었나' 를 볼 때 메모리 부족 여부의 근거가 된다.
public final class MemoryPressureWatcher {
    private var source: DispatchSourceMemoryPressure?

    public init(onEvent: @escaping (String) -> Void) {
        let src = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        src.setEventHandler { [weak src] in
            guard let src else { return }
            let ev = src.data
            let label: String
            if ev.contains(.critical) { label = "위험(critical)" }
            else if ev.contains(.warning) { label = "경고(warning)" }
            else { label = "정상(normal)" }
            onEvent(label)
        }
        src.resume()
        source = src
    }

    deinit { source?.cancel() }
}
