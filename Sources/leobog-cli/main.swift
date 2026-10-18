import Foundation
import LeobogCore

// leobog-cli — Leobog Hi8SE 제어 명령줄 도구 (앱과 같은 LeobogCore 사용)

let args = Array(CommandLine.arguments.dropFirst())

func usage() -> Never {
    print("""
    사용법: leobog-cli <명령> [옵션]

      info                     HID 장치 정보 + 권한 상태
      battery                  블루투스 배터리 잔량
      listen [초]              키 입력 / 벤더 리포트 실시간 출력 (입력 모니터링 권한 필요)
      probe                    벤더 채널 읽기 전용 프로브 (0x05 장치정보)
      keymap list              저장된 매핑 + 시스템에 적용된 매핑
      keymap set SRC DST       매핑 추가 (예: keymap set 0x700000039 0x7000000E0  또는  caps lctrl)
      keymap remove SRC        매핑 제거
      keymap clear             저장 목록 비우고 시스템 매핑 해제
      keymap apply             저장된 매핑을 시스템에 적용
      keymap preset NAME       프리셋 적용 후 시스템에 적용 (presets 로 목록)
      keymap presets           프리셋 목록
      watch                    키보드가 연결될 때마다 저장된 매핑 재적용 (LaunchAgent 용)
      fn get | fn set on|off   macOS 표준 기능 키 설정 읽기/쓰기
      led list                 조명 효과 목록
      led read                 조명 설정 읽기 (0x49, 권한 필요)
      led effect N [--brightness 0-4] [--speed 0-4] [--random] [--color RRGGBB]
    """)
    exit(2)
}

func parseUsage(_ s: String) -> HIDUsage? {
    let lower = s.lowercased()
    let alias: [String: HIDUsage] = [
        "caps": .keyboard(0x39), "capslock": .keyboard(0x39), "esc": .keyboard(0x29), "tab": .keyboard(0x2B), "space": .keyboard(0x2C),
        "lctrl": .keyboard(0xE0), "lshift": .keyboard(0xE1), "lalt": .keyboard(0xE2), "lopt": .keyboard(0xE2), "lcmd": .keyboard(0xE3), "lwin": .keyboard(0xE3),
        "rctrl": .keyboard(0xE4), "rshift": .keyboard(0xE5), "ralt": .keyboard(0xE6), "ropt": .keyboard(0xE6), "rcmd": .keyboard(0xE7), "rwin": .keyboard(0xE7),
        "fn": .appleFn, "globe": .appleFn, "none": .disabled, "off": .disabled, "del": .keyboard(0x4C), "backspace": .keyboard(0x2A),
        "bs": .keyboard(0x2A), "enter": .keyboard(0x28), "return": .keyboard(0x28),
        "play": .consumer(0xCD), "next": .consumer(0xB5), "prev": .consumer(0xB6), "mute": .consumer(0xE2), "volup": .consumer(0xE9), "voldown": .consumer(0xEA),
    ]
    if let a = alias[lower] { return a }
    if lower.hasPrefix("f"), let n = Int(lower.dropFirst()), (1...24).contains(n) {
        return .keyboard(n <= 12 ? UInt32(0x3A + n - 1) : UInt32(0x68 + n - 13))
    }
    if lower.count == 1, let c = lower.first, let d = c.wholeNumberValue, c.isASCII { return .keyboard(d == 0 ? 0x27 : UInt32(0x1E + d - 1)) }
    if lower.hasPrefix("0x"), let v = UInt64(lower.dropFirst(2), radix: 16) { return HIDUsage(hidutilValue: v) }
    if let v = UInt64(lower) { return HIDUsage(hidutilValue: v) }
    if lower.count == 1, let c = lower.first, c.isLetter, let a = c.asciiValue { return .keyboard(UInt32(a - 97 + 4)) }
    return nil
}

func printRemaps(_ list: [KeyRemap]) {
    if list.isEmpty { print("  (없음)"); return }
    for r in list { print("  \(r.src.name) [\(r.src.hexString)]  →  \(r.dst.name) [\(r.dst.hexString)]") }
}

func runLoop(seconds: Double) {
    let until = Date().addingTimeInterval(seconds)
    while Date() < until { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05)) }
}

guard let cmd = args.first else { usage() }

switch cmd {
case "info":
    let hid = HIDDeviceManager(listenOnly: true)
    hid.start()
    runLoop(seconds: 0.3)
    print("입력 모니터링 권한: \(hid.permission.rawValue)")
    if let i = hid.deviceInfo() {
        print("제품: \(i.product)  제조사: \(i.manufacturer)")
        print(String(format: "VID/PID: 0x%04X/0x%04X  전송: %@  버전: 0x%04X", i.vendorID, i.productID, i.transport, i.version))
        print("리포트 크기: 입력 \(i.maxInput) 출력 \(i.maxOutput) 기능 \(i.maxFeature)")
        print("Usage 쌍: " + i.usagePairs.map { String(format: "%X:%X", $0.page, $0.usage) }.joined(separator: ", "))
        print(String(format: "RegistryID: 0x%llx", i.registryID))
    } else {
        print("키보드(VID 0x3554 / PID 0xFA07)를 찾지 못했습니다.")
        exit(1)
    }

case "battery":
    if let s = BatteryService.query() {
        print("\(s.name): \(s.batteryPercent.map { "\($0)%" } ?? "배터리 정보 없음")  연결: \(s.connected ? "예" : "아니요")  주소: \(s.address)")
    } else { print("블루투스 목록에서 Leobog 키보드를 찾지 못했습니다."); exit(1) }

case "listen", "probe":
    let hid = HIDDeviceManager()
    hid.start()
    runLoop(seconds: 0.3)
    guard hid.isOpen else {
        print("장치를 열 수 없습니다: \(hid.lastError ?? "권한 없음"). 터미널 앱에 입력 모니터링 권한을 주거나 GUI 앱을 사용하세요.")
        exit(1)
    }
    let client = MainActor.assumeIsolated { CompxClient(hid: hid) }
    if cmd == "listen" {
        let secs = Double(args.count > 1 ? args[1] : "10") ?? 10
        print("\(Int(secs))초 동안 입력을 기다립니다…")
        let c1 = hid.keyEvents.sink { ev in print("키  \(ev.usage.hexString) \(ev.usage.name) \(ev.isDown ? "눌림" : "뗌")") }
        let c2 = hid.vendorReports.sink { r in print("벤더 " + r.bytes.map { String(format: "%02X", $0) }.joined(separator: " ")) }
        runLoop(seconds: secs)
        _ = c1; _ = c2
    } else {
        let sem = DispatchSemaphore(value: 0)
        Task { @MainActor in
            let r = await client.probe()
            for l in client.log { print(l.line) }
            print(r.summary)
            sem.signal()
        }
        while sem.wait(timeout: .now()) != .success { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05)) }
    }

case "keymap":
    let svc = HidutilRemapService()
    let sub = args.count > 1 ? args[1] : "list"
    switch sub {
    case "list":
        print("저장된 매핑 (\(HidutilRemapService.storeURL.path)):"); printRemaps(svc.remaps)
        print("시스템에 적용된 매핑:"); printRemaps(HidutilRemapService.readSystemMappings())
    case "set":
        guard args.count >= 4, let s = parseUsage(args[2]), let d = parseUsage(args[3]) else { print("SRC/DST 를 해석할 수 없습니다"); exit(2) }
        svc.set(KeyRemap(src: s, dst: d)); try svc.save(); print("추가: \(s.name) → \(d.name) (apply 로 적용)")
    case "remove":
        guard args.count >= 3, let s = parseUsage(args[2]) else { usage() }
        svc.remove(src: s); try svc.save(); print("제거됨")
    case "clear":
        svc.removeAll(); try svc.save(); _ = svc.clearSystem(); print(svc.lastMessage)
    case "apply":
        switch svc.applyToSystem() { case .success(let m): print(m); case .failure(let e): print("실패: \(e.localizedDescription)"); exit(1) }
    case "presets":
        for p in HidutilRemapService.presets { print("  \(p.id)\t\(p.title) — \(p.detail)") }
    case "preset":
        guard args.count >= 3, let p = HidutilRemapService.presets.first(where: { $0.id == args[2] }) else { print("프리셋 이름을 확인하세요 (presets)"); exit(2) }
        svc.apply(preset: p); try svc.save()
        switch svc.applyToSystem() { case .success(let m): print(m); case .failure(let e): print("실패: \(e.localizedDescription)"); exit(1) }
    default: usage()
    }

case "watch":
    // LaunchAgent 용: 장치가 나타날 때마다 저장된 매핑을 다시 적용. 권한 불필요.
    let svc = HidutilRemapService()
    let hid = HIDDeviceManager(listenOnly: true)
    func reapply(_ why: String) {
        svc.load()
        guard !svc.remaps.isEmpty else { print("[\(Date())] \(why): 저장된 매핑 없음"); return }
        switch svc.applyToSystem() {
        case .success(let m): print("[\(Date())] \(why): \(m)")
        case .failure(let e): print("[\(Date())] \(why): 실패 \(e.localizedDescription)")
        }
        fflush(stdout)
    }
    // 시작 직후의 장치 열거와 '장치 연결' 이벤트가 겹쳐 같은 매핑을 두 번 적용하지 않도록, 예약된 적용은 하나만 둔다
    // (새 요청이 오면 이전 예약을 취소하고 1.5 초 뒤로 다시 잡는다).
    var pending: DispatchWorkItem?
    func scheduleReapply(_ why: String) {
        pending?.cancel()
        let item = DispatchWorkItem { pending = nil; reapply(why) }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: item)
    }
    let c = hid.deviceArrived.sink { _ in scheduleReapply("장치 연결") }
    hid.start()
    runLoop(seconds: 0.5)
    if !hid.devices.isEmpty { scheduleReapply("시작") } else { print("[\(Date())] 키보드 대기 중"); fflush(stdout) }
    _ = c
    RunLoop.main.run()

case "fn":
    let f = FnKeyService()
    if args.count > 1, args[1] == "set", args.count > 2 {
        f.set(standardFunctionKeys: args[2] == "on" || args[2] == "true" || args[2] == "1"); print(f.lastMessage)
    } else {
        print("com.apple.keyboard.fnState = \(f.standardFunctionKeys.map { $0 ? "켜짐 (표준 기능 키)" : "꺼짐 (특수 기능)" } ?? "설정 안 됨 (기본 꺼짐)")")
    }

case "led":
    let sub = args.count > 1 ? args[1] : "list"
    if sub == "list" {
        for e in LedEffects.all {
            var opts: [String] = []
            if e.supportsBrightness { opts.append("밝기") }; if e.supportsSpeed { opts.append("속도") }
            if e.supportsRandomColor { opts.append("랜덤색") }; if e.supportsCustomColor { opts.append("사용자색") }
            print(String(format: "  %2d  hw=%2d  %@  [%@]", e.id, Int(e.hardwareID), e.name, opts.joined(separator: ",")))
        }
        break
    }
    let hid = HIDDeviceManager(); hid.start(); runLoop(seconds: 0.3)
    guard hid.isOpen else { print("장치를 열 수 없습니다 (입력 모니터링 권한 필요)"); exit(1) }
    let client = MainActor.assumeIsolated { CompxClient(hid: hid) }
    let sem = DispatchSemaphore(value: 0)
    Task { @MainActor in
        defer { sem.signal() }
        let probe = await client.probe(listen: 0.8)
        guard probe.ok else { print(probe.summary); return }
        if sub == "read" {
            do { for p in try await client.readLighting() { print(p.hex) } } catch { print("읽기 실패: \(error)") }
        } else if sub == "effect", args.count > 2, let n = Int(args[2]), let e = LedEffects.all.first(where: { $0.id == n }) {
            var s = CompxClient.LedEffectSetting(effect: e.hardwareID)
            var i = 3
            // 값이 필요한 옵션이 마지막 인자로 오면 다음 인자를 읽을 수 없다 → 범위를 확인하고 안내 후 종료 (인덱스 초과 크래시 방지)
            func value(for flag: String) -> String {
                guard i + 1 < args.count else { print("옵션 값 없음: \(flag) (예: \(flag) 4)"); exit(2) }
                i += 1
                return args[i]
            }
            while i < args.count {
                switch args[i] {
                case "--brightness": s.brightness = UInt8(value(for: "--brightness")) ?? 4
                case "--speed": s.speed = UInt8(value(for: "--speed")) ?? 2
                case "--random": s.random = 1
                case "--color": if let v = UInt32(value(for: "--color"), radix: 16) { s.r = UInt8(v >> 16); s.g = UInt8((v >> 8) & 0xFF); s.b = UInt8(v & 0xFF) }
                default: break
                }
                i += 1
            }
            do { let r = try await client.setLedEffect(s); print("응답: \(r.hex)") } catch { print("실패: \(error)") }
        } else { print("led 하위 명령을 확인하세요") }
    }
    while sem.wait(timeout: .now()) != .success { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05)) }

default:
    usage()
}
