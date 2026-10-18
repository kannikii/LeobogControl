import Foundation

/// macOS 크래시 리포트(.ips) 한 건을 읽기 쉽게 정리한 것
public struct CrashReport: Identifiable, Sendable {
    public enum Kind: Sendable {
        case badAccess        // EXC_BAD_ACCESS: 잘못된 메모리 접근 (힙 손상 / 해제된 포인터) — 소프트웨어 버그
        case abort            // SIGABRT / EXC_CRASH: 런타임이 스스로 중단
        case trap             // EXC_BREAKPOINT: Swift 런타임 트랩 (강제 언래핑, 배열 범위 초과 등)
        case memoryLimit      // EXC_RESOURCE MEMORY / jetsam: 메모리 부족·초과로 시스템이 종료
        case jetsam           // JetsamEvent 리포트에 이 앱이 올라옴
        case watchdog         // 응답 없음으로 시스템이 종료
        case other
    }

    public let id: String             // 파일 경로
    public let url: URL
    public let date: Date
    public let kind: Kind
    public let exceptionType: String
    public let signal: String
    public let subtype: String
    public let terminationNamespace: String
    public let terminationIndicator: String
    public let terminationBy: String
    public let faultingThreadName: String
    public let topFrames: [String]
    public let mallocSummary: String  // vmSummary 에서 MALLOC 줄들
    public let processLaunch: String
    public let osVersion: String
    public let appVersion: String
    public let pid: Int
    public let jetsamReason: String   // jetsam 일 때 reason ('per-process-limit' 등)
    public let note: String           // 기타 참고

    /// 사람이 읽는 판정 (한국어)
    public var verdict: String {
        switch kind {
        case .badAccess:
            return "소프트웨어 버그 — 잘못된 메모리 접근(힙 손상 또는 해제된 메모리 사용). 메모리 부족(하드웨어) 때문이 아닙니다."
        case .abort:
            return "소프트웨어 버그 — 런타임이 스스로 중단(abort). 메모리 부족 때문이 아닙니다."
        case .trap:
            return "소프트웨어 버그 — Swift 런타임 트랩(강제 언래핑·범위 초과 등). 메모리 부족 때문이 아닙니다."
        case .memoryLimit:
            return "메모리 부족·초과 — 시스템(jetsam)이 메모리 때문에 종료했습니다."
        case .jetsam:
            return "메모리 부족 — macOS 가 메모리 압박으로 이 앱을 종료했습니다(JetsamEvent)."
        case .watchdog:
            return "응답 없음 — 메인 스레드가 오래 멈춰 시스템이 종료했습니다."
        case .other:
            return "분류되지 않은 종료. 아래 예외·종료 정보를 확인하세요."
        }
    }

    public var isMemoryRelated: Bool { kind == .memoryLimit || kind == .jetsam }
}

/// 세션 시작 시 직전 실행의 끝을 판정한 결과
public struct LastRunStatus: Sendable {
    public enum Outcome: Sendable { case cleanOrFirst, crashed, killed }
    public let outcome: Outcome
    public let previousPid: Int32
    public let previousLaunch: Date?
    public let report: CrashReport?

    public var message: String {
        switch outcome {
        case .cleanOrFirst: return "직전 실행은 정상 종료되었습니다."
        case .crashed:
            if let r = report { return "직전 실행이 크래시로 끝났습니다 (\(DateFormatter.shortKR.string(from: r.date))). " + r.verdict }
            return "직전 실행이 크래시로 끝났습니다."
        case .killed:
            return "직전 실행이 정상 종료 표식 없이 끝났습니다 (재빌드·pkill·강제 종료 등). 그 시각의 크래시 리포트는 없습니다."
        }
    }
}

public extension DateFormatter {
    static let shortKR: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 HH:mm:ss"
        return f
    }()
}

public enum CrashReportReader {
    public static let processName = "LeobogControl"
    public static var directories: [URL] {
        [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports"),
         URL(fileURLWithPath: "/Library/Logs/DiagnosticReports")]
    }

    /// 이 앱의 크래시 리포트 + 이 앱이 언급된 jetsam 리포트. 최신순.
    public static func loadAll(limit: Int = 50) -> [CrashReport] {
        var out: [CrashReport] = []
        let fm = FileManager.default
        for dir in directories {
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in names where name.hasSuffix(".ips") {
                let url = dir.appendingPathComponent(name)
                if name.hasPrefix(processName + "-") {
                    if let r = parseCrash(url) { out.append(r) }
                } else if name.hasPrefix("JetsamEvent-") {
                    if let r = parseJetsam(url) { out.append(r) }
                }
            }
        }
        out.sort { $0.date > $1.date }
        return Array(out.prefix(limit))
    }

    /// 직전 실행 판정: 표식(RunMarker)이 남아 있으면, 그 실행 시작 이후의 크래시 리포트가 있는지 본다.
    public static func lastRunStatus(previous: RunMarker.Previous?) -> LastRunStatus {
        guard let prev = previous else {
            return LastRunStatus(outcome: .cleanOrFirst, previousPid: 0, previousLaunch: nil, report: nil)
        }
        let reports = loadAll(limit: 20)
        let match = reports.first { r in
            r.date >= prev.launchedAt.addingTimeInterval(-2) && (r.pid == Int(prev.pid) || r.pid == 0)
        } ?? reports.first { $0.date >= prev.launchedAt.addingTimeInterval(-2) }
        if let m = match {
            return LastRunStatus(outcome: .crashed, previousPid: prev.pid, previousLaunch: prev.launchedAt, report: m)
        }
        return LastRunStatus(outcome: .killed, previousPid: prev.pid, previousLaunch: prev.launchedAt, report: nil)
    }

    // MARK: 파싱

    private static func splitIPS(_ url: URL) -> ([String: Any], [String: Any])? {
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { return nil }
        guard let nl = text.firstIndex(of: "\n") else { return nil }
        let headerText = String(text[..<nl])
        let bodyText = String(text[text.index(after: nl)...])
        let header = (try? JSONSerialization.jsonObject(with: Data(headerText.utf8))) as? [String: Any] ?? [:]
        let body = (try? JSONSerialization.jsonObject(with: Data(bodyText.utf8))) as? [String: Any] ?? [:]
        return (header, body)
    }

    private static let tsFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SS Z"
        return f
    }()

    private static func parseDate(_ s: String?, fallback url: URL) -> Date {
        if let s, let d = tsFormatter.date(from: s) { return d }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.modificationDate] as? Date) ?? Date.distantPast
    }

    static func parseCrash(_ url: URL) -> CrashReport? {
        guard let (header, body) = splitIPS(url) else { return nil }
        let date = parseDate(header["timestamp"] as? String, fallback: url)
        let exc = body["exception"] as? [String: Any] ?? [:]
        let term = body["termination"] as? [String: Any] ?? [:]
        let excType = exc["type"] as? String ?? ""
        let signal = exc["signal"] as? String ?? ""
        let subtype = exc["subtype"] as? String ?? ""
        let ns = term["namespace"] as? String ?? ""
        let indicator = term["indicator"] as? String ?? ""
        let by = term["byProc"] as? String ?? ""
        let pid = body["pid"] as? Int ?? 0
        let faulting = body["faultingThread"] as? Int ?? 0
        var threadName = ""
        var frames: [String] = []
        let images = body["usedImages"] as? [[String: Any]] ?? []
        if let threads = body["threads"] as? [[String: Any]], faulting < threads.count {
            let t = threads[faulting]
            threadName = (t["name"] as? String) ?? (t["queue"] as? String) ?? "thread \(faulting)"
            for f in (t["frames"] as? [[String: Any]] ?? []).prefix(12) {
                let idx = f["imageIndex"] as? Int ?? -1
                let img = (idx >= 0 && idx < images.count) ? (images[idx]["name"] as? String ?? "?") : "?"
                let sym = f["symbol"] as? String
                let loc = f["symbolLocation"] as? Int
                let off = f["imageOffset"] as? Int ?? 0
                if let sym { frames.append("\(img)  \(sym) + \(loc ?? 0)") }
                else { frames.append(String(format: "%@  +0x%llx", img, off)) }
            }
        }
        var malloc = ""
        if let vm = body["vmSummary"] as? String {
            let lines = vm.split(separator: "\n").map(String.init)
            malloc = lines.filter { $0.contains("MALLOC") || $0.hasPrefix("TOTAL") || $0.contains("=======") }.joined(separator: "\n")
        }
        let kind: CrashReport.Kind
        let lowerNs = ns.uppercased()
        if lowerNs == "JETSAM" || excType == "EXC_RESOURCE" && subtype.uppercased().contains("MEMORY") {
            kind = .memoryLimit
        } else if excType == "EXC_BAD_ACCESS" { kind = .badAccess }
        else if excType == "EXC_BREAKPOINT" { kind = .trap }
        else if excType == "EXC_CRASH" || signal == "SIGABRT" { kind = .abort }
        else if lowerNs == "WATCHDOG" || indicator.lowercased().contains("watchdog") { kind = .watchdog }
        else { kind = .other }
        let meta = body["bundleInfo"] as? [String: Any] ?? [:]
        return CrashReport(
            id: url.path, url: url, date: date, kind: kind,
            exceptionType: excType, signal: signal, subtype: subtype,
            terminationNamespace: ns, terminationIndicator: indicator, terminationBy: by,
            faultingThreadName: threadName, topFrames: frames, mallocSummary: malloc,
            processLaunch: body["procLaunch"] as? String ?? "",
            osVersion: header["os_version"] as? String ?? (body["osVersion"] as? [String: Any])?["train"] as? String ?? "",
            appVersion: meta["CFBundleShortVersionString"] as? String ?? "",
            pid: pid, jetsamReason: "", note: "")
    }

    static func parseJetsam(_ url: URL) -> CrashReport? {
        guard let (header, body) = splitIPS(url) else { return nil }
        let procs = body["processes"] as? [[String: Any]] ?? []
        guard let me = procs.first(where: { ($0["name"] as? String) == processName }) else { return nil }
        let date = parseDate(header["timestamp"] as? String ?? body["date"] as? String, fallback: url)
        let reason = me["reason"] as? String ?? ""
        let states = (me["states"] as? [String])?.joined(separator: ",") ?? ""
        let pages = me["rpages"] as? Int ?? 0
        let pageSize = (body["memoryStatus"] as? [String: Any])?["pageSize"] as? Int ?? 16384
        let largest = body["largestProcess"] as? String ?? ""
        // 외부 파일 값이라 음수/거대값이 올 수 있다 — 곱셈 오버플로로 트랩되지 않게 확인하며 계산
        let product = UInt64(max(0, pages)).multipliedReportingOverflow(by: UInt64(max(0, pageSize)))
        let resident = product.overflow ? UInt64.max : product.partialValue
        let note = "jetsam 당시 이 앱 상주 메모리 \(MemoryStats.format(resident)) · 상태 \(states) · 가장 큰 프로세스: \(largest)"
        let isKilled = !reason.isEmpty
        return CrashReport(
            id: url.path, url: url, date: date, kind: isKilled ? .jetsam : .other,
            exceptionType: "JETSAM", signal: "", subtype: reason,
            terminationNamespace: "JETSAM", terminationIndicator: reason, terminationBy: "kernel",
            faultingThreadName: "", topFrames: [], mallocSummary: "",
            processLaunch: "", osVersion: header["os_version"] as? String ?? "", appVersion: "",
            pid: me["pid"] as? Int ?? 0, jetsamReason: reason, note: note)
    }
}
