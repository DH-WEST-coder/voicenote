import Foundation
import IOKit.ps

/// `ioreg -rn AppleSmartBattery` 한 번의 표본.
struct BatterySample {
    var amperageMA: Int64      // InstantAmperage (mA, 방전이면 음수)
    var voltageMV: Int64       // Voltage (mV)
    var externalConnected: Bool
    var percent: Double?       // 가능하면 mAh 기준 소수 %, 아니면 CurrentCapacity

    /// 배터리로 소비 중일 때만 의미 있는 전력(W). 충전 중/AC/0이면 nil.
    var dischargeWatts: Double? {
        guard !externalConnected, amperageMA < 0, voltageMV > 0 else { return nil }
        return Double(-amperageMA) * Double(voltageMV) / 1_000_000
    }

    private static func int(_ text: String, _ key: String) -> Int64? {
        guard let r = text.range(of: "\"\(key)\" = ") else { return nil }
        let rest = text[r.upperBound...]
        let tok = rest.prefix { $0 == "-" || $0.isNumber }
        guard !tok.isEmpty else { return nil }
        // 방전 중 InstantAmperage는 부호 없는 64비트로 찍힌다(예: 18446744073709550000) → 비트 그대로 부호 있는 값으로 읽는다.
        if let v = Int64(tok) { return v }
        if let u = UInt64(tok) { return Int64(bitPattern: u) }
        return nil
    }

    static func parse(_ text: String) -> BatterySample? {
        guard let amp = int(text, "InstantAmperage") ?? int(text, "Amperage"),
              let volt = int(text, "Voltage") else { return nil }
        let ext = text.range(of: "\"ExternalConnected\" = Yes") != nil
        var pct: Double?
        if let raw = int(text, "AppleRawCurrentCapacity"), let mx = int(text, "AppleRawMaxCapacity"), mx > 0 {
            pct = Double(raw) / Double(mx) * 100
        } else if let cur = int(text, "CurrentCapacity") {
            pct = Double(cur)
        }
        return BatterySample(amperageMA: amp, voltageMV: volt, externalConnected: ext, percent: pct)
    }

    /// ioreg를 실행해 표본을 읽는다(관리자 권한 불필요). 배터리가 없으면 nil.
    static func read() -> BatterySample? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        p.arguments = ["-rn", "AppleSmartBattery"]
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return parse(String(decoding: data, as: UTF8.self))
    }
}

/// 전원 상태(IOKit power source)와 배터리 소비 전력 기록.
@MainActor
final class PowerMonitor: ObservableObject {
    static let shared = PowerMonitor()

    @Published var onAC = true
    @Published var percent: Int?
    @Published var lastWatts: Double?
    /// 전원 상태가 바뀌면 호출(큐 재개용)
    var onChange: (() -> Void)?
    /// (job id, 합계 W, 표본 수, 사용 %p)
    var onSample: ((UUID, Double, Int, Double) -> Void)?

    private struct Track {
        var sumW: Double; var n: Int; var usedBase: Double
        var startPct: Double?; var lastPct: Double?
        var used: Double { usedBase + ((startPct ?? 0) - (lastPct ?? startPct ?? 0)) }
    }
    private var tracks: [UUID: Track] = [:]
    private var timer: Timer?
    private var started = false
    static let interval: TimeInterval = 30

    static func isOnAC() -> Bool? {
        guard let snap = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let t = IOPSGetProvidingPowerSourceType(snap)?.takeUnretainedValue() else { return nil }
        return (t as String) == "AC Power"
    }

    static func iopsPercent() -> Int? {
        guard let snap = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snap)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(snap, ps)?.takeUnretainedValue() as? [String: Any],
                  let cur = d["Current Capacity"] as? Int, let mx = d["Max Capacity"] as? Int, mx > 0 else { continue }
            return Int((Double(cur) / Double(mx) * 100).rounded())
        }
        return nil
    }

    func start() {
        guard !started else { return }
        started = true
        // Store.init 안에서 불린다. 첫 값은 로그 없이 맞춘다(refresh가 Store.shared를 부르면 재귀 초기화로 크래시).
        onAC = Self.isOnAC() ?? true
        refresh()
        let src = IOPSNotificationCreateRunLoopSource({ _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { PowerMonitor.shared.refresh() } }
        }, nil).takeRetainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { _ in
            MainActor.assumeIsolated {
                let m = PowerMonitor.shared
                m.refresh()
                if !m.tracks.isEmpty { m.sampleNow() }
            }
        }
    }

    func refresh() {
        let ac = Self.isOnAC() ?? true
        percent = Self.iopsPercent()
        if ac != onAC {
            onAC = ac
            Store.shared.log("power source -> \(ac ? "AC" : "battery") pct=\(percent.map(String.init) ?? "-")")
            onChange?()
        }
    }

    /// 녹음/처리 시작 시 호출. 이미 쌓인 값(prior)에서 이어서 센다.
    func begin(_ id: UUID, priorSumW: Double?, priorN: Int?, priorUsed: Double?) {
        guard tracks[id] == nil else { return }
        tracks[id] = Track(sumW: priorSumW ?? 0, n: priorN ?? 0, usedBase: priorUsed ?? 0, startPct: nil, lastPct: nil)
        sampleNow()
    }

    func end(_ id: UUID) {
        guard tracks[id] != nil else { return }
        sampleNow() // 마지막 표본
        tracks[id] = nil
    }

    /// ioreg를 백그라운드에서 읽어 기록한다. AC이거나 값이 0이면 W는 기록하지 않는다.
    func sampleNow() {
        let ids = Array(tracks.keys)
        DispatchQueue.global(qos: .utility).async {
            let s = BatterySample.read()
            DispatchQueue.main.async { MainActor.assumeIsolated { PowerMonitor.shared.apply(s, ids: ids) } }
        }
    }

    private func apply(_ s: BatterySample?, ids: [UUID]) {
        guard let s else { Store.shared.log("power: no battery (ioreg AppleSmartBattery empty)"); lastWatts = nil; return }
        guard let w = s.dischargeWatts else {
            lastWatts = nil
            Store.shared.log(String(format: "power: on AC / not discharging amp=%dmA volt=%dmV pct=%@ (W not recorded)",
                                    s.amperageMA, s.voltageMV, s.percent.map { String(format: "%.1f", $0) } ?? "-"))
            return
        }
        lastWatts = w
        Store.shared.log(String(format: "power: %.2fW amp=%dmA volt=%dmV pct=%@ tracked=%d",
                                w, s.amperageMA, s.voltageMV, s.percent.map { String(format: "%.1f", $0) } ?? "-", ids.count))
        for id in ids {
            guard var t = tracks[id] else { continue }
            t.sumW += w; t.n += 1
            if let p = s.percent { if t.startPct == nil { t.startPct = p }; t.lastPct = p }
            tracks[id] = t
            onSample?(id, t.sumW, t.n, t.used)
        }
    }

    /// 자체 점검: 방전/AC/0 합성 입력을 파싱한다(--power-selftest).
    static func selfTest() -> String {
        let dis = "\"ExternalConnected\" = No\n\"InstantAmperage\" = 18446744073709549000\n\"Voltage\" = 12100\n\"AppleRawCurrentCapacity\" = 3000\n\"AppleRawMaxCapacity\" = 6000\n\"CurrentCapacity\" = 50"
        let ac = "\"ExternalConnected\" = Yes\n\"InstantAmperage\" = 1500\n\"Voltage\" = 12900\n\"CurrentCapacity\" = 80"
        let zero = "\"ExternalConnected\" = Yes\n\"InstantAmperage\" = 0\n\"Voltage\" = 0"
        func d(_ t: String) -> String {
            guard let s = BatterySample.parse(t) else { return "parse=nil" }
            return "amp=\(s.amperageMA) volt=\(s.voltageMV) W=\(s.dischargeWatts.map { String(format: "%.2f", $0) } ?? "nil") pct=\(s.percent.map { String(format: "%.1f", $0) } ?? "nil")"
        }
        return "discharge: \(d(dis))\nac: \(d(ac))\nzero: \(d(zero))\nempty: \(BatterySample.parse("").map { _ in "?" } ?? "nil")"
    }
}
