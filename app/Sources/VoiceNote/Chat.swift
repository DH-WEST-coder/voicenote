import Foundation

// MARK: - 설정

enum ChatEngine: String, CaseIterable, Identifiable {
    case agy, codex, lmstudio
    var id: String { rawValue }
    var label: String {
        switch self {
        case .agy: return "Antigravity (Gemini)"
        case .codex: return "Codex (GPT)"
        case .lmstudio: return "LM Studio (로컬)"
        }
    }
}

final class ChatSettings: ObservableObject {
    static let shared = ChatSettings()
    private let d = UserDefaults.standard
    @Published var engine: ChatEngine { didSet { d.set(engine.rawValue, forKey: "chatEngine") } }
    @Published var agyPath: String { didSet { d.set(agyPath, forKey: "agyPath") } }
    @Published var codexPath: String { didSet { d.set(codexPath, forKey: "codexPath") } }
    @Published var agyModel: String { didSet { d.set(agyModel, forKey: "agyModel") } }
    @Published var codexModel: String { didSet { d.set(codexModel, forKey: "codexModel") } }
    @Published var lmURL: String { didSet { d.set(lmURL, forKey: "lmURL") } }
    @Published var lmModel: String { didSet { d.set(lmModel, forKey: "lmModel") } }
    @Published var transcriptCap: Int { didSet { d.set(transcriptCap, forKey: "transcriptCap") } }
    @Published var materialCap: Int { didSet { d.set(materialCap, forKey: "materialCap") } }
    @Published var recentMinutes: Int { didSet { d.set(recentMinutes, forKey: "recentMinutes") } }
    /// vault 경로는 VaultConfig(config.json) 하나만 쓴다.
    var vaultPath: String { VaultConfig.shared.vault }
    /// 엔진에 위키 vault를 읽기 전용으로 붙여 스스로 더 찾게 한다.
    @Published var attachVault: Bool { didSet { d.set(attachVault, forKey: "attachVault") } }

    init() {
        engine = ChatEngine(rawValue: d.string(forKey: "chatEngine") ?? "") ?? .agy
        agyPath = d.string(forKey: "agyPath") ?? "/Users/DH_WEST/.local/bin/agy"
        codexPath = d.string(forKey: "codexPath") ?? "/Users/DH_WEST/.local/bin/codex"
        agyModel = d.string(forKey: "agyModel") ?? "gemini-3.8-flash-medium"
        codexModel = d.string(forKey: "codexModel") ?? ""
        lmURL = d.string(forKey: "lmURL") ?? "http://localhost:1234/v1"
        lmModel = d.string(forKey: "lmModel") ?? ""
        transcriptCap = d.object(forKey: "transcriptCap") as? Int ?? 60000
        materialCap = d.object(forKey: "materialCap") as? Int ?? 120000
        recentMinutes = d.object(forKey: "recentMinutes") as? Int ?? 10
        attachVault = d.object(forKey: "attachVault") as? Bool ?? true
    }
}

// MARK: - 프롬프트 설정 파일

struct QuickPrompt: Codable, Identifiable { var label: String; var prompt: String; var id: String { label } }

struct ChatPrompts: Codable {
    var system: String
    var organize: String
    var quick: [QuickPrompt]

    static let defaults = ChatPrompts(
        system: """
        너는 대학 수업을 듣는 학생의 학습 도우미다. 한국어로 답한다.
        - 근거가 있으면 대본 시각 [mm:ss]과 강의자료 페이지(p.12)를 붙인다.
        - 대본은 자동 받아쓰기라 오인식(전문 용어, 고유명사)이 있을 수 있다. 의심되면 문맥으로 바로잡아 해석하되 그렇다고 밝힌다.
        - 강의자료에 없는 내용은 일반 지식임을 밝힌다.
        - 답은 간결하게, 필요하면 제목·목록·수식을 쓴다.
        """,
        organize: """
        지금까지의 수업을 구조화된 노트로 정리해 줘. 형식:
        ## 수업 개요 (한두 문장)
        ## 핵심 개념·정의·수식 (각 항목에 대본 시각 [mm:ss]와 강의자료 p.N 출처)
        ## 교수님이 강조한 것 (시험·과제·주의 언급 포함, [mm:ss])
        ## 열린 질문 / 더 확인할 것
        관련 강의자료는 자동으로 붙여 준 것과, 필요하면 위키에서 더 찾은 것을 함께 써서 대본의 내용을 자료와 연결해 줘.
        """,
        quick: [
            QuickPrompt(label: "방금 내용 설명", prompt: "현재 시각 기준 최근 3분 동안의 대본 내용을 쉬운 말로 설명해 줘. 관련 강의자료가 있으면 연결하고 [mm:ss]를 표시해 줘."),
            QuickPrompt(label: "지금까지 노트 초안", prompt: "지금까지의 대본과 내 노트를 바탕으로 노트 초안을 써 줘. 핵심 개념, 수식, 강조점을 [mm:ss]와 함께 정리해 줘."),
            QuickPrompt(label: "모르는 용어 찾기", prompt: "대본에서 학생이 낯설어할 만한 전문 용어를 골라 한 줄씩 설명해 줘. 강의자료에 정의가 있으면 p.N을 붙여 줘."),
        ])

    static func load() -> ChatPrompts {
        if let d = try? Data(contentsOf: Paths.promptsFile), let p = try? JSONDecoder().decode(ChatPrompts.self, from: d) { return p }
        ensureFile()
        return defaults
    }

    static func ensureFile() {
        guard !FileManager.default.fileExists(atPath: Paths.promptsFile.path) else { return }
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        if let d = try? enc.encode(defaults) { try? d.write(to: Paths.promptsFile) }
    }
}

/// 노트를 기준으로 묻는 고정 프롬프트
enum NotePrompts {
    static let fill = """
    내 노트를 기준으로 정리해 줘. 노트의 항목 순서([m:ss])를 그대로 따르면서, 각 항목에 대해 대본과 강의자료에서 빠진 설명·수식·예시를 찾아 보충해 줘.
    - 새로 넣은 내용에는 근거 [mm:ss]와 p.N을 붙인다.
    - 노트가 대본·자료와 어긋나면 "확인 필요"로 짚는다.
    - 마지막에 "노트에 빠진 것"으로, 수업에서 중요하게 다뤘는데 노트에 없는 내용을 모아 준다.
    """

    static func explain(_ sel: String) -> String {
        "내 노트의 다음 부분을 대본(같은 시각 전후)과 강의자료를 근거로 쉽게 설명해 줘. 근거 [mm:ss]·p.N을 붙여 줘.\n\n> " +
            sel.replacingOccurrences(of: "\n", with: "\n> ")
    }

    static func expand(_ sel: String) -> String {
        "내 노트의 다음 부분을 대본과 강의자료에서 찾아 보충해 줘. 노트에 바로 붙일 수 있게 짧은 목록으로, 근거 [mm:ss]·p.N과 함께.\n\n> " +
            sel.replacingOccurrences(of: "\n", with: "\n> ")
    }
}

// MARK: - 강의자료 색인 / 자동 선택

struct MaterialFile: Identifiable, Hashable {
    let name: String; let path: String; let size: Int
    var id: String { name }
}

final class MaterialIndex: @unchecked Sendable {
    static let shared = MaterialIndex()
    struct Entry { let file: MaterialFile; let terms: [String: Int]; let total: Int }
    private let lock = NSLock()
    private var entries: [Entry] = []
    private var df: [String: Int] = [:]
    private var builtVault: String?
    private var building = false
    private var waiters: [() -> Void] = []

    static func sourcesDir(_ vault: String) -> URL { URL(fileURLWithPath: vault).appendingPathComponent(".agents/cache/sources") }

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

    /// 백그라운드에서 색인(파일명×5, 제목×3, 본문 앞 40000자). 끝나면 completion(main).
    func ensureBuilt(vault: String, completion: @escaping () -> Void) {
        lock.lock()
        if builtVault == vault { lock.unlock(); DispatchQueue.main.async(execute: completion); return }
        waiters.append(completion)
        if building { lock.unlock(); return }
        building = true; lock.unlock()
        DispatchQueue.global(qos: .utility).async { [self] in
            let dir = Self.sourcesDir(vault)
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
                .filter { $0.hasSuffix(".processed.md") }.sorted()
            var es: [Entry] = []; var dfm: [String: Int] = [:]
            for n in names {
                let url = dir.appendingPathComponent(n)
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                let text = String((try? String(contentsOf: url, encoding: .utf8))?.prefix(40000) ?? "")
                var t = Self.terms(text)
                for (k, v) in Self.terms(n) { t[k, default: 0] += v * 5 }
                let heads = text.split(separator: "\n").filter { $0.hasPrefix("#") }.joined(separator: " ")
                for (k, v) in Self.terms(heads) { t[k, default: 0] += v * 3 }
                for k in t.keys { dfm[k, default: 0] += 1 }
                es.append(Entry(file: MaterialFile(name: n, path: url.path, size: size), terms: t, total: t.values.reduce(0, +)))
            }
            lock.lock(); entries = es; df = dfm; builtVault = vault; building = false
            let ws = waiters; waiters = []; lock.unlock()
            DispatchQueue.main.async { ws.forEach { $0() } }
        }
    }

    func allFiles() -> [MaterialFile] { lock.lock(); defer { lock.unlock() }; return entries.map { $0.file } }

    /// 대본과 키워드가 가장 겹치는 자료 top N. 과목 prefix 파일은 가산점.
    func pick(text: String, prefixes: [String], top: Int = 3) -> [MaterialFile] {
        lock.lock(); let es = entries; let dfm = df; lock.unlock()
        guard !es.isEmpty, !text.isEmpty else { return [] }
        let n = Double(es.count)
        let q = Self.terms(String(text.prefix(100_000)))
        func idf(_ k: String) -> Double? {
            guard let d = dfm[k], Double(d) / n <= 0.2 else { return nil }   // 너무 흔한 항은 무시
            let latin = k.unicodeScalars.first.map { $0.isASCII } ?? false
            return (log(n / Double(d)) + 0.1) * (latin ? 2 : 1)
        }
        var weights: [(String, Double)] = q.compactMap { k, tf in idf(k).map { (k, (1 + log(Double(tf))) * $0) } }
        weights.sort { $0.1 > $1.1 }
        weights = Array(weights.prefix(300))
        var scored: [(MaterialFile, Double)] = []
        for e in es {
            // 코사인 유사도(tf-idf). 파일 쪽 노름은 그 파일의 모든 항 기준.
            var dot = 0.0, norm = 0.0
            for (k, c) in e.terms { if let w = idf(k) { let x = (1 + log(Double(c))) * w; norm += x * x } }
            for (k, w) in weights { if let c = e.terms[k], let w2 = idf(k) { dot += w * (1 + log(Double(c))) * w2 } }
            var s = norm > 0 ? dot / sqrt(norm) : 0
            if prefixes.contains(where: { e.file.name.hasPrefix($0 + "_") }) { s *= 2 }
            if s > 0 { scored.append((e.file, s)) }
        }
        scored.sort { $0.1 > $1.1 }
        guard let best = scored.first?.1 else { return [] }
        return scored.prefix(top).filter { $0.1 >= best * 0.3 }.map { $0.0 }
    }
}

enum Materials {
    /// 과목 → 캐시 prefix 목록 (vault의 course-prefixes.md 표 사용)
    static func prefixes(course: String?, vault: String) -> [String] {
        guard let course, !course.isEmpty else { return [] }
        var out = [course.replacingOccurrences(of: " ", with: "")]
        let table = URL(fileURLWithPath: vault).appendingPathComponent(".agents/skills/source-processor/course-prefixes.md")
        guard let text = try? String(contentsOf: table, encoding: .utf8) else { return out }
        var exact: [String] = []; var fuzzy: [String] = []
        for line in text.split(separator: "\n") where line.hasPrefix("|") {
            let cells = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count >= 3 else { continue }
            let hub = cells[1], cell = cells[2]
            if hub == "Hub" || hub.hasPrefix("---") { continue }
            var ps: [String] = []
            var rest = Substring(cell)
            while let a = rest.firstIndex(of: "`"), let b = rest[rest.index(after: a)...].firstIndex(of: "`") {
                ps.append(String(rest[rest.index(after: a)..<b])); rest = rest[rest.index(after: b)...]
            }
            if hub == course { exact += ps } else if hub.contains(course) || course.contains(hub) { fuzzy += ps }
        }
        out += exact.isEmpty ? fuzzy : exact
        return Array(Set(out))
    }
}

// MARK: - 대화 기록

struct ChatMessage: Codable, Identifiable, Equatable {
    var id = UUID()
    var role: String          // user / assistant
    var text: String
    var date = Date()
    var engine: String?
    var ttft: Double?
    var total: Double?
    var isError = false
}

struct ChatFile: Codable {
    var messages: [ChatMessage] = []
    var materials: [String] = []
    var manualMaterials = false
}

// MARK: - 맥락 조립

enum ChatContext {
    struct Line { let time: Double; let text: String }

    static func transcriptLines(job: Job) -> [Line] {
        guard job.status == .done, let p = job.transcriptPath, let s = try? String(contentsOfFile: p, encoding: .utf8) else { return [] }
        // 2단계(실시간)에서는 여기서 라이브 대본을 돌려주면 된다.
        return s.components(separatedBy: "\n").compactMap { l in
            TranscriptIO.match(l).map { Line(time: TranscriptIO.seconds($0.time), text: l) }
        }
    }

    /// 전체 글자 수 상한. 최근 N분은 전부 두고, 앞부분은 남는 예산만큼 그대로, 나머지는 중략.
    static func trim(_ lines: [Line], now: Double?, cap: Int, recentMin: Int) -> String {
        let total = lines.reduce(0) { $0 + $1.text.count + 1 }
        if total <= cap { return lines.map(\.text).joined(separator: "\n") }
        let n = now ?? lines.last?.time ?? 0
        var keep = [Bool](repeating: false, count: lines.count)
        var budget = cap
        // 최근 구간(뒤에서부터, 상한의 60%까지)
        let recentIdx = lines.indices.filter { lines[$0].time >= n - Double(recentMin) * 60 && lines[$0].time <= n }
        var recentBudget = Int(Double(cap) * 0.6)
        for i in recentIdx.reversed() {
            let c = lines[i].text.count + 1
            if c > recentBudget { break }
            keep[i] = true; recentBudget -= c; budget -= c
        }
        for i in lines.indices where !keep[i] {
            let c = lines[i].text.count + 1
            if c > budget { break }
            keep[i] = true; budget -= c
        }
        var out: [String] = []; var gap = false
        for i in lines.indices {
            if keep[i] { if gap { out.append("[… 중략 …]"); gap = false }; out.append(lines[i].text) } else { gap = true }
        }
        if gap { out.append("[… 이후 중략 …]") }
        return out.joined(separator: "\n")
    }

    static func readMaterials(_ files: [MaterialFile], cap: Int) -> String {
        var out = ""; var left = cap
        for f in files where left > 200 {
            guard var s = try? String(contentsOfFile: f.path, encoding: .utf8) else { continue }
            // 앞쪽 front matter 제거
            if s.hasPrefix("---"), let r = s.range(of: "\n---\n") { s = String(s[r.upperBound...]) }
            let per = max(2000, left / max(1, files.count))
            let part = s.count > per ? String(s.prefix(per)) + "\n[… 자료 일부 생략 …]" : s
            out += "\n<강의자료 파일=\"\(f.name)\">\n\(part)\n</강의자료>\n"
            left -= part.count
        }
        return out
    }

    static func build(job: Job, question: String, now: Double?, notes: String, materials: [MaterialFile],
                      history: [ChatMessage], prompts: ChatPrompts, settings: ChatSettings, scratch: String) -> String {
        var p = prompts.system + "\n\n"
        p += """
        [안전 규칙] 이 대화에서는 파일을 만들거나 고치거나 지우지 말고, 쓰기·삭제 명령을 실행하지 말 것. 읽기만 한다.
        필요한 자료는 아래에 이미 넣어 두었다.
        """
        if settings.attachVault {
            p += "\n위키 vault(\(settings.vaultPath))가 읽기 전용으로 붙어 있다. 더 필요하면 그 안의 wiki/ 와 .agents/cache/ 에서 검색·열람(grep, 읽기)해 관련 자료를 스스로 찾아도 된다. 절대 수정하지 말 것."
            p += "\n셸 명령 실행(run_command)은 이 환경에서 막혀 있으니 시도하지 말 것. 파일 열람 도구(view_file)로 아래 목록의 절대 경로를 직접 열어라. 목록에 없는 곳은 wiki/index.md 부터 따라가면 된다."
            let names = MaterialIndex.shared.allFiles().map(\.name)
            if !names.isEmpty {
                p += "\n\n<열람 가능한 강의자료 캐시 목록 (폴더: \(MaterialIndex.sourcesDir(settings.vaultPath).path))>\n" + names.joined(separator: "\n") + "\n</목록>"
            }
        }
        p += "\n\n"
        let course = Profiles.course(for: job.profile)
        p += "<수업 정보>\n제목: \(job.title)\n과목 프로필: \(job.profile.isEmpty ? "자동(없음)" : job.profile)"
        if let course { p += "\n과목: \(course)" }
        if let now { p += "\n현재 시각: [\(formatTime(now))] (재생/녹음 위치)" }
        p += "\n</수업 정보>\n\n"
        let lines = transcriptLines(job: job)
        let tr = lines.isEmpty ? "(아직 대본이 없다)" : trim(lines, now: now, cap: settings.transcriptCap, recentMin: settings.recentMinutes)
        p += "<강의 대본>\n\(tr)\n</강의 대본>\n"
        p += materials.isEmpty ? "\n(자동/선택된 강의자료 없음)\n" : readMaterials(materials, cap: settings.materialCap)
        let atts = job.attachments ?? []
        if !atts.isEmpty {
            let per = max(4000, settings.materialCap / atts.count)
            for a in atts {
                if let t = MaterialImporter.text(of: a, cap: per) {
                    p += "\n<수업 자료 파일=\"\(a.name)\" (이 수업에 직접 넣은 슬라이드·PDF, 페이지는 [p.N])>\n\(t)\n</수업 자료>\n"
                } else {
                    p += "\n(수업 자료 \(a.name): 본문을 읽을 수 없음)\n"
                }
            }
        }
        p += """

        <내 노트 (학생이 수업 중 직접 쓴 것. [m:ss]는 녹음 시각. 학생의 이해·관심이 드러나므로 답할 때 기준으로 삼고, 노트와 대본·자료가 어긋나면 짚어 줄 것)>
        \(notes.isEmpty ? "(비어 있음)" : notes)
        </내 노트>

        """
        let hist = history.suffix(8).filter { !$0.isError && !$0.text.isEmpty }
        if !hist.isEmpty {
            p += "\n<이전 대화>\n" + hist.map { ($0.role == "user" ? "사용자: " : "도우미: ") + $0.text }.joined(separator: "\n\n") + "\n</이전 대화>\n"
        }
        p += "\n<질문>\n\(question)\n</질문>\n위 질문에 바로 답하라. 요청한 분량과 형식을 지켜라.\n"
        return p
    }
}

// MARK: - 엔진 실행

final class ChatRunner: @unchecked Sendable {
    private var process: Process?
    private var task: Task<Void, Never>?
    private var cancelled = false

    struct Parsed { var delta: String?; var error: String?; var finalText: String? }

    func cancel() { cancelled = true; process?.terminate(); task?.cancel() }

    /// onDelta/onFinish는 메인 스레드에서 호출된다. onFinish(error)
    func run(engine: ChatEngine, settings s: ChatSettings, prompt: String,
             onDelta: @escaping (String) -> Void, onFinish: @escaping (String?) -> Void) {
        try? FileManager.default.createDirectory(at: Paths.chatScratch, withIntermediateDirectories: true)
        let scratch = Paths.chatScratch.path
        switch engine {
        case .agy:
            // plan 모드는 답변을 "계획서"로 바꿔 버려 쓰지 않는다. 헤드리스에서는 허용 규칙 없는 쓰기/명령이 자동 거부된다.
            var a = ["--output-format", "stream-json", "--sandbox"]
            if !s.agyModel.isEmpty { a += ["--model", s.agyModel] }
            if s.attachVault { a += ["--add-dir", s.vaultPath] }
            a += ["-p", prompt]
            spawn(exe: s.agyPath, args: a, stdin: nil, cwd: scratch, parse: Self.parseAgy, onDelta: onDelta, onFinish: onFinish)
        case .codex:
            var a = ["exec", "--json", "-s", "read-only", "--skip-git-repo-check", "--ephemeral",
                     "-c", "model_reasoning_effort=\"low\"", "-C", scratch]
            if !s.codexModel.isEmpty { a += ["-m", s.codexModel] }
            a.append("-")
            spawn(exe: s.codexPath, args: a, stdin: prompt, cwd: scratch, parse: Self.parseCodex, onDelta: onDelta, onFinish: onFinish)
        case .lmstudio:
            runLM(settings: s, prompt: prompt, onDelta: onDelta, onFinish: onFinish)
        }
    }

    static func parseAgy(_ line: String) -> Parsed {
        guard let d = line.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let ev = o["event"] as? String else { return Parsed() }
        if ev == "step_update", let su = o["step_update"] as? [String: Any],
           su["step_type"] as? String == "agent_response", let t = su["text_delta"] as? String, !t.isEmpty {
            return Parsed(delta: t)
        }
        if ev == "result", let r = o["result"] as? [String: Any] {
            let status = r["status"] as? String ?? ""
            if status != "SUCCESS" { return Parsed(error: (r["error"] as? String) ?? "agy 오류: \(status)") }
            return Parsed(finalText: r["response"] as? String)
        }
        return Parsed()
    }

    static func parseCodex(_ line: String) -> Parsed {
        guard let d = line.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let ty = o["type"] as? String else { return Parsed() }
        if ty == "item.completed", let it = o["item"] as? [String: Any], it["type"] as? String == "agent_message",
           let t = it["text"] as? String { return Parsed(delta: t) }
        if ty == "turn.failed" || ty == "error" {
            let m = ((o["error"] as? [String: Any])?["message"] as? String) ?? (o["message"] as? String) ?? "codex 오류"
            return Parsed(error: m)
        }
        return Parsed()
    }

    private func spawn(exe: String, args: [String], stdin: String?, cwd: String,
                       parse: @escaping (String) -> Parsed,
                       onDelta: @escaping (String) -> Void, onFinish: @escaping (String?) -> Void) {
        guard FileManager.default.isExecutableFile(atPath: exe) else {
            DispatchQueue.main.async { onFinish("실행 파일을 찾을 수 없습니다: \(exe)") }; return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.currentDirectoryURL = URL(fileURLWithPath: cwd)
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/Users/DH_WEST/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "")
        p.environment = env
        let out = Pipe(), err = Pipe(), inp = Pipe()
        p.standardOutput = out; p.standardError = err
        p.standardInput = stdin == nil ? FileHandle.nullDevice : inp
        do { try p.run() } catch {
            DispatchQueue.main.async { onFinish("실행 실패: \(error.localizedDescription)") }; return
        }
        process = p
        if let stdin {
            DispatchQueue.global().async {
                inp.fileHandleForWriting.write(Data(stdin.utf8))
                try? inp.fileHandleForWriting.close()
            }
        }
        var errBuf = Data()
        let errLock = NSLock()
        let errThread = Thread {
            while true {
                let d = err.fileHandleForReading.availableData
                if d.isEmpty { break }
                errLock.lock(); errBuf.append(d); errLock.unlock()
            }
        }
        errThread.start()
        Thread.detachNewThread { [self] in
            var buf = Data(); var gotDelta = false; var parsedError: String?; var finalText: String?
            let h = out.fileHandleForReading
            func handle(_ line: String) {
                let r = parse(line)
                if let e = r.error { parsedError = e }
                if let f = r.finalText { finalText = f }
                if let dl = r.delta {
                    gotDelta = true
                    DispatchQueue.main.async { onDelta(dl) }
                }
            }
            while true {
                let d = h.availableData
                if d.isEmpty { break }
                buf.append(d)
                while let nl = buf.firstIndex(of: 10) {
                    handle(String(decoding: buf[buf.startIndex..<nl], as: UTF8.self))
                    buf.removeSubrange(buf.startIndex...nl)
                }
            }
            if !buf.isEmpty { handle(String(decoding: buf, as: UTF8.self)) }
            p.waitUntilExit()
            Thread.sleep(forTimeInterval: 0.05)
            errLock.lock(); let errText = String(decoding: errBuf, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines); errLock.unlock()
            if !gotDelta, let f = finalText, !f.isEmpty { DispatchQueue.main.async { onDelta(f) }; gotDelta = true }
            var error: String?
            if cancelled { error = "중지됨" }
            else if let e = parsedError { error = e }
            else if !gotDelta { error = errText.isEmpty ? "엔진이 응답을 내지 않았습니다 (종료 코드 \(p.terminationStatus))" : String(errText.suffix(600)) }
            else if p.terminationStatus != 0 { error = "엔진 종료 코드 \(p.terminationStatus)" }
            DispatchQueue.main.async { onFinish(error) }
        }
    }

    // OpenAI 호환 /chat/completions 스트리밍 (LM Studio)
    private func runLM(settings s: ChatSettings, prompt: String,
                       onDelta: @escaping (String) -> Void, onFinish: @escaping (String?) -> Void) {
        task = Task { [self] in
            let base = s.lmURL.hasSuffix("/") ? String(s.lmURL.dropLast()) : s.lmURL
            func finish(_ e: String?) async { await MainActor.run { onFinish(e) } }
            do {
                var model = s.lmModel
                if model.isEmpty {
                    var r = URLRequest(url: URL(string: base + "/models")!); r.timeoutInterval = 5
                    let (d, _) = try await URLSession.shared.data(for: r)
                    if let o = try JSONSerialization.jsonObject(with: d) as? [String: Any],
                       let arr = o["data"] as? [[String: Any]], let id = arr.first?["id"] as? String { model = id }
                }
                var req = URLRequest(url: URL(string: base + "/chat/completions")!)
                req.httpMethod = "POST"; req.timeoutInterval = 600
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let body: [String: Any] = ["model": model, "stream": true, "temperature": 0.3,
                    "messages": [["role": "system", "content": "파일을 만들거나 고치지 않는다. 한국어로 답한다."],
                                 ["role": "user", "content": prompt]]]
                req.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                if let h = resp as? HTTPURLResponse, h.statusCode != 200 { await finish("LM Studio HTTP \(h.statusCode)"); return }
                var got = false
                for try await line in bytes.lines {
                    if cancelled { await finish("중지됨"); return }
                    guard line.hasPrefix("data:") else { continue }
                    let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    if payload == "[DONE]" { break }
                    if let d = payload.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                       let ch = (o["choices"] as? [[String: Any]])?.first,
                       let t = (ch["delta"] as? [String: Any])?["content"] as? String, !t.isEmpty {
                        got = true
                        await MainActor.run { onDelta(t) }
                    }
                }
                await finish(got ? nil : "LM Studio가 빈 응답을 보냈습니다")
            } catch {
                await finish(cancelled ? "중지됨" : "LM Studio 연결 실패(\(s.lmURL)): \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - 세션

@MainActor
final class ChatSession: ObservableObject {
    let jobID: UUID
    @Published var messages: [ChatMessage] = []
    @Published var materials: [String] = []          // 선택된 자료 파일명
    @Published var manualMaterials = false           // true면 자동 선택을 다시 덮어쓰지 않는다
    @Published var busy = false
    @Published var waitingFirstToken = false
    @Published var picking = false
    private var runner: ChatRunner?
    private var t0 = Date()
    private var ttft: Double?
    private var autoJobStamp = ""

    init(jobID: UUID) {
        self.jobID = jobID
        let url = Paths.chats.appendingPathComponent("\(jobID.uuidString).json")
        if let d = try? Data(contentsOf: url) {
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            if let f = try? dec.decode(ChatFile.self, from: d) {
                messages = f.messages; materials = f.materials; manualMaterials = f.manualMaterials
            }
        }
    }

    func save() {
        try? FileManager.default.createDirectory(at: Paths.chats, withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let f = ChatFile(messages: messages, materials: materials, manualMaterials: manualMaterials)
        if let d = try? enc.encode(f) { try? d.write(to: Paths.chats.appendingPathComponent("\(jobID.uuidString).json"), options: .atomic) }
    }

    func clear() { guard !busy else { return }; messages = []; save() }

    var materialFiles: [MaterialFile] {
        let all = Dictionary(MaterialIndex.shared.allFiles().map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        return materials.compactMap { all[$0] }
    }

    /// 자동 모드: 대본·과목으로 관련 자료를 고른다(수동으로 만진 뒤에는 건드리지 않음).
    func refreshAutoMaterials(job: Job, force: Bool = false) {
        if force { manualMaterials = false }
        guard !manualMaterials else { return }
        let stamp = "\(job.status.rawValue)-\(job.transcriptPath ?? "")"
        guard force || stamp != autoJobStamp else { return }
        autoJobStamp = stamp
        let vault = ChatSettings.shared.vaultPath
        let prefixes = Materials.prefixes(course: Profiles.course(for: job.profile), vault: vault)
        let text = ChatContext.transcriptLines(job: job).map(\.text).joined(separator: "\n")
            + "\n" + NoteController.shared.noteText(jobID: job.id)
        MaterialIndex.shared.ensureBuilt(vault: vault) { [weak self] in
            guard let self, !self.manualMaterials else { return }
            // 대본·노트가 없으면 과목 파일을 고르지 않는다(질문 때 다시 고른다).
            let picked = MaterialIndex.shared.pick(text: text, prefixes: prefixes).map(\.name)
            self.materials = picked; self.save()
        }
    }

    func removeMaterial(_ name: String) { materials.removeAll { $0 == name }; manualMaterials = true; save() }
    func toggleMaterial(_ name: String) {
        if let i = materials.firstIndex(of: name) { materials.remove(at: i) } else { materials.append(name) }
        manualMaterials = true; save()
    }

    func stop() { runner?.cancel() }

    func ask(_ question: String, job: Job, organize: Bool = false, display: String? = nil) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !busy else { return }
        let settings = ChatSettings.shared
        let engine = settings.engine
        messages.append(ChatMessage(role: "user", text: organize ? "수업 정리" : (display ?? q)))
        messages.append(ChatMessage(role: "assistant", text: "", engine: engine.rawValue))
        busy = true; waitingFirstToken = true; ttft = nil
        let history = Array(messages.dropLast(2))
        let store = Store.shared
        let now = store.notePosition(for: job)
        NoteController.shared.flush()
        let notes = NoteController.shared.noteText(jobID: job.id)
        let prompts = ChatPrompts.load()
        // 자동 모드에서 대본이 늦게 생겼다면 지금 한 번 더 고른다.
        if !manualMaterials {
            let vault = settings.vaultPath
            let picked = MaterialIndex.shared.pick(
                text: ChatContext.transcriptLines(job: job).map(\.text).joined(separator: "\n") + "\n" + notes,
                prefixes: Materials.prefixes(course: Profiles.course(for: job.profile), vault: vault)).map(\.name)
            if !picked.isEmpty { materials = picked }
        }
        let files = materialFiles
        let promptText = organize ? prompts.organize : q
        store.log("chat ask engine=\(engine.rawValue) job=\(job.id) q=\(q.prefix(60)) materials=\(materials)")
        t0 = Date()
        let r = ChatRunner(); runner = r
        let prompt = ChatContext.build(job: job, question: promptText, now: now, notes: notes, materials: files,
                                       history: history, prompts: prompts, settings: settings, scratch: Paths.chatScratch.path)
        r.run(engine: engine, settings: settings, prompt: prompt, onDelta: { [weak self] d in
            guard let self, let i = self.messages.indices.last else { return }
            if self.ttft == nil { self.ttft = Date().timeIntervalSince(self.t0); self.waitingFirstToken = false }
            if !self.messages[i].text.isEmpty && engine == .codex { self.messages[i].text += "\n\n" }
            self.messages[i].text += d
        }, onFinish: { [weak self] err in
            guard let self, let i = self.messages.indices.last else { return }
            let total = Date().timeIntervalSince(self.t0)
            self.messages[i].ttft = self.ttft; self.messages[i].total = total
            if let err {
                if err == "중지됨" && !self.messages[i].text.isEmpty { self.messages[i].text += "\n\n(중지됨)" }
                else { self.messages[i].text = err; self.messages[i].isError = true }
            }
            self.busy = false; self.waitingFirstToken = false; self.runner = nil
            self.save()
            Store.shared.log(String(format: "chat done engine=%@ ttft=%@ total=%.2fs chars=%d err=%@", engine.rawValue,
                                    self.ttft.map { String(format: "%.2fs", $0) } ?? "-", total, self.messages[i].text.count, err ?? "-"))
        })
    }
}

@MainActor
final class ChatHub {
    static let shared = ChatHub()
    private var sessions: [UUID: ChatSession] = [:]
    func session(for id: UUID) -> ChatSession {
        if let s = sessions[id] { return s }
        let s = ChatSession(jobID: id); sessions[id] = s; return s
    }
}
