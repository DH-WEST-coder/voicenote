import Foundation

/// 채팅 맥락에 넣을 위키 페이지(읽기 전용)
struct WikiHit {
    let rel: String      // vault 기준 상대경로 "wiki/…"
    let path: String
    let text: String
    var name: String { ((rel as NSString).lastPathComponent as NSString).deletingPathExtension }
}

/// `<vault>/wiki/**/*.md` 본문 색인. 읽기만 하고 위키는 고치지 않는다.
/// 백그라운드에서 한 번 만들고, 파일 수정 시각이 바뀐 것만 다시 읽는다.
final class WikiIndex: @unchecked Sendable {
    static let shared = WikiIndex()

    struct Entry {
        let rel: String; let path: String; let mtime: Date
        let courses: [String]; let type: String
        let terms: [String: Int]
    }
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var df: [String: Int] = [:]
    private var builtVault: String?
    private var lastScan = Date.distantPast

    /// 한글은 2글자 조각(조사 흡수), 영문은 3글자 이상 단어.
    static func terms(_ s: String) -> [String: Int] {
        var out: [String: Int] = [:]
        var latin = ""; var hangul: [Character] = []
        func flush() {
            if latin.count >= 3 { out[latin, default: 0] += 1 }
            if hangul.count >= 2 { for i in 0..<(hangul.count - 1) { out[String(hangul[i...(i + 1)]), default: 0] += 1 } }
            latin = ""; hangul = []
        }
        for ch in s {
            if let u = ch.unicodeScalars.first, ch.unicodeScalars.count == 1, (0xAC00...0xD7A3).contains(u.value) {
                if !latin.isEmpty { flush() }
                hangul.append(ch)
            } else if ch.isASCII, ch.isLetter {
                if !hangul.isEmpty { flush() }
                latin.append(Character(ch.lowercased()))
            } else { flush() }
        }
        flush()
        return out
    }

    /// frontmatter의 courses(인라인 [a, b] 또는 `- a` 목록)와 type
    static func frontmatter(_ text: String) -> (courses: [String], type: String, body: String) {
        guard text.hasPrefix("---"), let r = text.range(of: "\n---", range: text.index(text.startIndex, offsetBy: 3)..<text.endIndex) else {
            return ([], "", text)
        }
        let head = String(text[text.index(text.startIndex, offsetBy: 3)..<r.lowerBound])
        let body = String(text[r.upperBound...])
        var courses: [String] = []; var type = ""; var inCourses = false
        func clean(_ x: String) -> String {
            x.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'[]")).trimmingCharacters(in: CharacterSet(charactersIn: "[[]]"))
        }
        for raw in head.components(separatedBy: "\n") {
            let l = raw.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("courses:") {
                inCourses = true
                let v = String(l.dropFirst("courses:".count)).trimmingCharacters(in: .whitespaces)
                if v.hasPrefix("[") { courses += v.split(separator: ",").map { clean(String($0)) }.filter { !$0.isEmpty }; inCourses = false }
                else if !v.isEmpty { courses.append(clean(v)); inCourses = false }
            } else if inCourses, l.hasPrefix("-") {
                let v = clean(String(l.dropFirst()))
                if !v.isEmpty { courses.append(v) }
            } else {
                inCourses = false
                if l.hasPrefix("type:") { type = clean(String(l.dropFirst(5))) }
            }
        }
        return (courses, type, body)
    }

    private static func norm(_ s: String) -> String { s.precomposedStringWithCanonicalMapping.lowercased() }

    /// 바뀐 파일만 다시 읽는다(20초 안에 다시 부르면 건너뜀). 호출 스레드에서 동기로 돈다 — 백그라운드에서 부를 것.
    func refresh(vault: String) {
        lock.lock()
        if builtVault == vault, Date().timeIntervalSince(lastScan) < 20 { lock.unlock(); return }
        lock.unlock()
        let fm = FileManager.default
        let wikiDir = URL(fileURLWithPath: vault).appendingPathComponent("wiki")
        var found: [String: (URL, Date)] = [:]
        if let en = fm.enumerator(at: wikiDir, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                                  options: [.skipsHiddenFiles]) {
            for case let u as URL in en {
                let v = try? u.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
                if v?.isDirectory == true {
                    if u.lastPathComponent == "graphify-out" { en.skipDescendants() }
                    continue
                }
                guard u.pathExtension.lowercased() == "md" else { continue }
                let n = u.lastPathComponent
                if n == "log.md" || n == "index.md" { continue }
                found[u.path] = (u, v?.contentModificationDate ?? .distantPast)
            }
        }
        lock.lock()
        var cur = builtVault == vault ? entries : [:]
        lock.unlock()
        for k in cur.keys where found[k] == nil { cur.removeValue(forKey: k) }
        for (p, (u, m)) in found {
            if let e = cur[p], e.mtime == m { continue }
            guard let text = try? String(contentsOf: u, encoding: .utf8) else { continue }
            let fmt = Self.frontmatter(text)
            let rel = p.hasPrefix(vault + "/") ? String(p.dropFirst(vault.count + 1)) : p
            var t = Self.terms(String(fmt.body.prefix(60000)))
            for (k, v) in Self.terms(u.deletingPathExtension().lastPathComponent) { t[k, default: 0] += v * 5 }
            let heads = fmt.body.components(separatedBy: "\n").filter { $0.hasPrefix("#") }.joined(separator: " ")
            for (k, v) in Self.terms(heads) { t[k, default: 0] += v * 3 }
            cur[p] = Entry(rel: rel, path: p, mtime: m, courses: fmt.courses, type: fmt.type, terms: t)
        }
        var dfm: [String: Int] = [:]
        for e in cur.values { for k in e.terms.keys { dfm[k, default: 0] += 1 } }
        lock.lock(); entries = cur; df = dfm; builtVault = vault; lastScan = Date(); lock.unlock()
    }

    var count: Int { lock.lock(); defer { lock.unlock() }; return entries.count }

    /// 질의와 가장 겹치는 페이지 top개. 노트 과목이 courses에 있거나 파일명에 과목이 있으면 ×1.5. 합계 cap자, 페이지당 pageCap자.
    func select(vault: String, query: String, course: String?, top: Int, cap: Int, pageCap: Int) -> [WikiHit] {
        refresh(vault: vault)
        lock.lock(); let es = Array(entries.values); let dfm = df; lock.unlock()
        guard !es.isEmpty, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let n = Double(es.count)
        let q = Self.terms(String(query.prefix(100_000)))
        func idf(_ k: String) -> Double? {
            guard let d = dfm[k], n < 20 || Double(d) / n <= 0.3 else { return nil }   // 너무 흔한 항은 무시
            let latin = k.unicodeScalars.first.map { $0.isASCII } ?? false
            return (log(n / Double(d)) + 0.1) * (latin ? 2 : 1)
        }
        var weights: [(String, Double)] = q.compactMap { k, tf in idf(k).map { (k, (1 + log(Double(tf))) * $0) } }
        weights.sort { $0.1 > $1.1 }
        weights = Array(weights.prefix(300))
        let c = course.map(Self.norm)
        var scored: [(Entry, Double)] = []
        for e in es {
            var dot = 0.0, norm = 0.0
            for (k, cnt) in e.terms { if let w = idf(k) { let x = (1 + log(Double(cnt))) * w; norm += x * x } }
            for (k, w) in weights { if let cnt = e.terms[k], let w2 = idf(k) { dot += w * (1 + log(Double(cnt))) * w2 } }
            var s = norm > 0 ? dot / sqrt(norm) : 0
            if let c, e.courses.contains(where: { Self.norm($0) == c }) || Self.norm((e.rel as NSString).lastPathComponent).contains(c) { s *= 1.5 }
            if s > 0 { scored.append((e, s)) }
        }
        scored.sort { $0.1 > $1.1 }
        if ProcessInfo.processInfo.environment["VNOTE_WIKI_DEBUG"] != nil { for (e, sc) in scored { FileHandle.standardError.write(Data("wiki score \(e.rel) \(sc)\n".utf8)) } }
        guard let best = scored.first?.1 else { return [] }
        var out: [WikiHit] = []; var left = cap
        for (e, s) in scored.prefix(top) where s >= best * 0.15 && left > 500 {
            guard let text = try? String(contentsOfFile: e.path, encoding: .utf8) else { continue }
            let body = Self.frontmatter(text).body.trimmingCharacters(in: .whitespacesAndNewlines)
            let per = min(pageCap, left)
            let part = body.count > per ? String(body.prefix(per)) + "\n[… 이하 생략 …]" : body
            out.append(WikiHit(rel: e.rel, path: e.path, text: part))
            left -= part.count
        }
        return out
    }
}
