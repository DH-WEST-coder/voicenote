import Foundation

/// 채팅에서 고른 엔진(모델 포함)으로 한 번 묻고 답 텍스트를 받는 일들: 용어 힌트 뽑기, 노트 제목 짓기.
@MainActor
final class AITasks: ObservableObject {
    static let shared = AITasks()
    /// 실행 중인 일: "terms-<노트 id>", "title-<노트 id>"
    @Published var running: Set<String> = []

    private var runners: [String: ChatRunner] = [:]
    private static let readOnly = "[안전 규칙] 파일을 만들거나 고치거나 지우지 말고, 쓰기·삭제 명령을 실행하지 말 것. 읽기만 한다. 요청한 형식으로만 답하라.\n\n"

    /// completion(답 텍스트, 오류) — 메인 스레드에서 한 번 호출된다.
    func oneShot(key: String, prompt: String, images: [String] = [], completion: @escaping (String?, String?) -> Void) {
        let settings = ChatSettings.shared
        let engine = settings.engine
        var text = ""
        let r = ChatRunner()
        runners[key] = r
        running.insert(key)
        r.run(engine: engine, settings: settings, prompt: Self.readOnly + prompt,
              images: engine == .lmstudio ? [] : images,
              onDelta: { d in if engine == .codex && !text.isEmpty { text += "\n" }; text += d },
              onFinish: { [weak self] err in
            MainActor.assumeIsolated {
                self?.runners[key] = nil
                self?.running.remove(key)
                if let err { completion(nil, err) } else { completion(text.trimmingCharacters(in: .whitespacesAndNewlines), nil) }
            }
        })
    }

    // MARK: - 용어 힌트

    /// 노트에 연결된 자료(PDF 본문 + 글자 적은 페이지 이미지)에서 교수가 말로 할 전공 용어를 뽑아 session.terms에 넣는다.
    func extractTerms(session id: UUID) {
        let key = "terms-\(id.uuidString)"
        let store = Store.shared
        guard !running.contains(key), let s = store.session(id) else { return }
        let atts = s.attachments
        guard !atts.isEmpty else {
            store.updateSession(id) { $0.termsNote = "연결된 강의자료가 없습니다. 자료를 넣으면 용어를 뽑을 수 있어요." }
            return
        }
        let lang = Profiles.entry(s.profile).language
        let wantImages = ChatSettings.shared.sendPageImages
        store.updateSession(id) { $0.termsNote = "용어 뽑는 중…" }
        DispatchQueue.global(qos: .userInitiated).async {
            let per = max(2000, 40_000 / atts.count)
            var body = ""
            for a in atts {
                if let t = MaterialImporter.text(of: a, cap: per) {
                    body += "\n<자료 파일=\"\(a.name)\">\n\(t)\n</자료>\n"
                }
            }
            var images: [String] = []
            if wantImages { for a in atts where images.count < 8 { images += MaterialImporter.pageImages(a, minChars: 80, max: 8 - images.count) } }
            let imgCount = images.count
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if body.isEmpty && images.isEmpty {
                        Store.shared.updateSession(id) { $0.termsNote = "자료에서 글자를 읽지 못했습니다." }
                        return
                    }
                    let langRule: String
                    switch lang {
                    case "Korean": langRule = "한국어 용어만(영어 약어·기호를 한국어로 읽는 방식으로) 적는다."
                    case "English": langRule = "영어 용어만 적는다."
                    default: langRule = "한국어와 영어 둘 다 적는다. 같은 개념의 한국어 표기와 영어 표기를 모두 넣어도 된다."
                    }
                    let prompt = """
                    아래는 대학 수업에 쓰는 강의자료다. 이 수업의 녹음을 자동 받아쓰기(ASR)할 때 오인식을 줄이려고 용어 힌트 목록을 만든다.
                    교수가 말로 할 만한 전공 용어, 고유명사, 기호·약어 읽는 법(예: "듀티비", "freewheeling diode", "PLECS") 위주로 뽑아라.
                    - 일반적인 단어(예: "그래서", "문제", "그림")는 제외한다.
                    - \(langRule)
                    - 최대 60개.
                    - 출력은 JSON 문자열 배열 하나만. 설명·코드블록 표시 없이 [ "...", "..." ] 형태로.
                    \(imgCount > 0 ? "\n글자가 적은 페이지 \(imgCount)장은 이미지로 첨부했다. 이미지 속 용어도 포함하라." : "")
                    \(body)
                    """
                    AITasks.shared.oneShot(key: key, prompt: prompt, images: images) { text, err in
                        let st = Store.shared
                        guard let text else { st.updateSession(id) { $0.termsNote = "용어 뽑기 실패: \(err ?? "알 수 없는 오류")" }; return }
                        let terms = Self.parseTerms(text)
                        if terms.isEmpty {
                            st.updateSession(id) { $0.termsNote = "AI 답에서 용어 목록을 읽지 못했습니다. 다시 뽑아 보세요." }
                        } else {
                            st.updateSession(id) { $0.terms = terms; $0.termsNote = "강의자료에서 \(terms.count)개를 뽑았습니다." }
                            st.log("terms extracted n=\(terms.count) session=\(id)")
                        }
                    }
                }
            }
        }
    }

    /// 첫 `[`~마지막 `]`를 문자열 배열로 읽는다. 공백 정리·중복 제거·60개.
    nonisolated static func parseTerms(_ text: String) -> [String] {
        guard let a = text.firstIndex(of: "["), let b = text.lastIndex(of: "]"), a < b,
              let d = String(text[a...b]).data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: d) as? [Any] else { return [] }
        var seen = Set<String>(); var out: [String] = []
        for x in arr {
            guard let s0 = x as? String else { continue }
            let s = s0.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
            if s.isEmpty || s.count > 60 || !seen.insert(s.lowercased()).inserted { continue }
            out.append(s)
            if out.count >= 60 { break }
        }
        return out
    }

    // MARK: - 제목

    /// 접두는 앱이 정하고(과목 + 주차, 없으면 날짜), AI에게는 주제만 묻는다. titleIsAuto일 때만.
    func makeTitle(session id: UUID) {
        let key = "title-\(id.uuidString)"
        let store = Store.shared
        guard !running.contains(key), let s = store.session(id), s.titleIsAuto else { return }
        let atts = s.attachments
        let course = Courses.course(forProfile: s.profile)
        let week = VaultConfig.shared.week(of: s.createdAt)
        let f = DateFormatter(); f.dateFormat = "M월 d일"
        var prefix = ""
        if let course { prefix = course + (week.map { " \($0)주차" } ?? " " + f.string(from: s.createdAt)) + " · " }
        else { prefix = f.string(from: s.createdAt) + " · " }
        let transcript = store.combinedTranscript(of: s).lines.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
        let notes = NoteFile.load(id)
        DispatchQueue.global(qos: .userInitiated).async {
            var mat = ""
            for a in atts {
                mat += "파일: \(a.name)\n"
                if let t = MaterialImporter.text(of: a, cap: 2000, maxPages: 2) { mat += t + "\n" }
            }
            let tr = String(transcript.prefix(3000)), nt = String(notes.prefix(1000))
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if mat.isEmpty && tr.isEmpty && nt.isEmpty { return }
                    let prompt = """
                    대학 수업 노트의 제목에 붙일 '주제'를 지어라. 아래 자료·대본·학생 노트를 보고 이 수업이 다룬 핵심 주제 하나를 고른다.
                    - 20자 이내, 한 줄, 명사구. 따옴표·마침표·접두(과목명·주차)는 붙이지 않는다.
                    - 출력은 주제 문구만.

                    <강의자료>\n\(mat)</강의자료>
                    <대본 앞부분>\n\(tr)\n</대본 앞부분>
                    <학생 노트>\n\(nt)\n</학생 노트>
                    """
                    AITasks.shared.oneShot(key: key, prompt: prompt) { text, err in
                        let st = Store.shared
                        guard let text, !text.isEmpty else { st.log("title failed \(err ?? "-")"); return }
                        var topic = text.components(separatedBy: "\n").first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
                        topic = topic.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'“”‘’`.。*#"))
                        if topic.count > 30 { topic = String(topic.prefix(30)) }
                        guard !topic.isEmpty else { return }
                        // 그 사이 사용자가 제목을 고쳤다면 건드리지 않는다.
                        guard let cur = st.session(id), cur.titleIsAuto else { return }
                        st.updateSession(id) { $0.title = prefix + topic }
                        st.log("title made: \(prefix + topic)")
                    }
                }
            }
        }
    }
}
