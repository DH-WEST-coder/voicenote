import AppKit
import SwiftUI

/// 노트 파일: ~/Documents/VoiceNote/notes/<노트 id>.md
enum NoteFile {
    static func url(_ id: UUID) -> URL { Paths.notes.appendingPathComponent("\(id.uuidString).md") }
    static func load(_ id: UUID) -> String { (try? String(contentsOf: url(id), encoding: .utf8)) ?? "" }
    static func save(_ id: UUID, _ text: String) {
        let u = url(id)
        if text.isEmpty && !FileManager.default.fileExists(atPath: u.path) { return }
        try? FileManager.default.createDirectory(at: Paths.notes, withIntermediateDirectories: true)
        try? text.write(to: u, atomically: true, encoding: .utf8)
    }
}

/// 지금 화면에 있는 노트 편집기를 가리킨다(채팅의 "노트에 넣기", 자동 저장 flush용).
@MainActor
final class NoteController: ObservableObject {
    static let shared = NoteController()
    weak var textView: TimestampTextView?
    var sessionID: UUID?
    var dirty = false
    private var work: DispatchWorkItem?
    @Published var savedAt: Date?

    func changed() {
        dirty = true
        work?.cancel()
        let w = DispatchWorkItem { MainActor.assumeIsolated { NoteController.shared.flush() } }
        work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: w)
    }

    func flush() {
        work?.cancel()
        guard dirty, let id = sessionID, let tv = textView else { return }
        NoteFile.save(id, tv.string)
        dirty = false; savedAt = Date()
    }

    func noteText(sessionID id: UUID) -> String {
        if sessionID == id, let tv = textView { return tv.string }
        return NoteFile.load(id)
    }

    /// 노트에서 고른 부분(없으면 커서가 있는 줄)으로 AI에게 묻는다.
    func askAI(_ mode: String) {
        guard let tv = textView, let id = sessionID, let sess = Store.shared.session(id) else { return }
        let ns = tv.string as NSString
        var r = tv.selectedRange()
        if r.length == 0 { r = ns.lineRange(for: NSRange(location: min(r.location, ns.length), length: 0)) }
        let sel = ns.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sel.isEmpty else { return }
        flush()
        LayoutState.shared.showChat = true
        let short = sel.count > 60 ? String(sel.prefix(60)) + "…" : sel
        let session = ChatHub.shared.session(for: id)
        if mode == "expand" {
            session.ask(NotePrompts.expand(sel), session: sess, display: "노트 보충: \(short)")
        } else {
            session.ask(NotePrompts.explain(sel), session: sess, display: "노트 설명: \(short)")
        }
    }

    /// 커서 위치에 붙인다. 줄 중간이면 줄을 바꾸고, 첫 줄에 현재 시각을 붙인다.
    func insertAtCursor(_ text: String) {
        guard let tv = textView else { return }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        let ns = tv.string as NSString
        let loc = tv.selectedRange().location
        var s = ""
        if loc > 0 && loc <= ns.length && ns.character(at: loc - 1) != 10 { s = "\n" }
        if let t = tv.clock?() { s += "[\(formatTime(t))] " }
        s += body + "\n"
        tv.suppressStamp = true
        tv.insertText(s, replacementRange: tv.selectedRange())
        tv.suppressStamp = false
        tv.window?.makeFirstResponder(tv)
    }
}

/// 새 줄에 첫 글자를 칠 때 `[m:ss] `를 자동으로 붙이고, 시각을 누르면 그 위치로 이동하는 텍스트 뷰.
final class TimestampTextView: NSTextView {
    override func menu(for event: NSEvent) -> NSMenu? {
        let m = super.menu(for: event) ?? NSMenu()
        let a = NSMenuItem(title: "AI에게 이 부분 설명 요청", action: #selector(askExplain), keyEquivalent: "")
        let b = NSMenuItem(title: "AI로 이 부분 보충하기", action: #selector(askExpand), keyEquivalent: "")
        a.target = self; b.target = self
        m.insertItem(a, at: 0); m.insertItem(b, at: 1); m.insertItem(.separator(), at: 2)
        return m
    }
    @objc private func askExplain() { MainActor.assumeIsolated { NoteController.shared.askAI("explain") } }
    @objc private func askExpand() { MainActor.assumeIsolated { NoteController.shared.askAI("expand") } }

    var clock: (() -> Double?)?
    var onSeek: ((Double) -> Void)?
    var suppressStamp = false
    static let stampRegex = try! NSRegularExpression(pattern: #"^\[((?:\d+:)?\d+:\d{2})\]"#, options: .anchorsMatchLines)

    private func lineIsEmptyAtCaret() -> Bool {
        let sel = selectedRange()
        guard sel.length == 0 else { return false }
        let ns = string as NSString
        let lr = ns.lineRange(for: NSRange(location: min(sel.location, ns.length), length: 0))
        return ns.substring(with: lr).trimmingCharacters(in: .newlines).isEmpty
    }

    private func stampIfNeeded(_ s: Any) {
        guard !suppressStamp, !hasMarkedText(), let t = clock?(), lineIsEmptyAtCaret() else { return }
        let str = (s as? String) ?? (s as? NSAttributedString)?.string ?? ""
        guard let f = str.first, !f.isNewline else { return }
        suppressStamp = true
        super.insertText("[\(formatTime(t))] ", replacementRange: NSRange(location: NSNotFound, length: 0))
        suppressStamp = false
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        stampIfNeeded(string)
        super.insertText(string, replacementRange: replacementRange)
    }

    // 한글 조합(마킹 텍스트)의 첫 자모에서도 시각을 붙인다.
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        stampIfNeeded(string)
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
    }

    /// 지점(p)에 있는 줄 머리 시각 표식의 초. 없으면 nil.
    func stampSeconds(at p: NSPoint) -> Double? {
        guard let lm = layoutManager, let tc = textContainer, !string.isEmpty else { return nil }
        let tp = NSPoint(x: p.x - textContainerOrigin.x, y: p.y - textContainerOrigin.y)
        var frac: CGFloat = 0
        let ci = lm.characterIndex(for: tp, in: tc, fractionOfDistanceBetweenInsertionPoints: &frac)
        let ns = string as NSString
        guard ci < ns.length else { return nil }
        let gr = lm.glyphRange(forCharacterRange: NSRange(location: ci, length: 1), actualCharacterRange: nil)
        guard lm.boundingRect(forGlyphRange: gr, in: tc).contains(tp) else { return nil }
        let line = ns.lineRange(for: NSRange(location: ci, length: 0))
        guard let m = Self.stampRegex.firstMatch(in: string, range: line), NSLocationInRange(ci, m.range) else { return nil }
        return TranscriptIO.seconds(ns.substring(with: m.range(at: 1)))
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if event.clickCount == 1, let sec = stampSeconds(at: p) { onSeek?(sec) }
        super.mouseDown(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
    }

    func restyle() {
        guard let ts = textStorage, !hasMarkedText() else { return }
        let full = NSRange(location: 0, length: ts.length)
        ts.beginEditing()
        ts.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)
        Self.stampRegex.enumerateMatches(in: string, range: full) { m, _, _ in
            guard let r = m?.range else { return }
            ts.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: r)
            ts.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r)
        }
        ts.endEditing()
        typingAttributes = [.font: font ?? NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.labelColor]
    }
}

struct NoteEditor: NSViewRepresentable {
    let sessionID: UUID
    let clock: () -> Double?
    let onSeek: (Double) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let storage = NSTextStorage()
        let lm = NSLayoutManager(); storage.addLayoutManager(lm)
        let tc = NSTextContainer(size: NSSize(width: 100, height: CGFloat.greatestFiniteMagnitude))
        tc.widthTracksTextView = true
        lm.addTextContainer(tc)
        let tv = TimestampTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 100), textContainer: tc)
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true; tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.isRichText = false; tv.allowsUndo = true
        tv.font = NSFont.systemFont(ofSize: 14)
        tv.textContainerInset = NSSize(width: 12, height: 10)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.delegate = context.coordinator
        let scroll = NSScrollView()
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        tv.drawsBackground = false

        context.coordinator.tv = tv
        let nc = NoteController.shared
        nc.flush()
        nc.textView = tv; nc.sessionID = sessionID; nc.dirty = false
        tv.string = NoteFile.load(sessionID)
        tv.restyle()
        tv.clock = clock; tv.onSeek = onSeek
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? TimestampTextView else { return }
        tv.clock = clock; tv.onSeek = onSeek
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        MainActor.assumeIsolated {
            NoteController.shared.flush()
            if NoteController.shared.textView === coordinator.tv { NoteController.shared.textView = nil }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        weak var tv: TimestampTextView?
        func textDidChange(_ notification: Notification) {
            tv?.restyle()
            MainActor.assumeIsolated { NoteController.shared.changed() }
        }
    }
}

struct NoteView: View {
    @EnvironmentObject var store: Store
    @ObservedObject var player = AudioPlayer.shared
    @ObservedObject var nc = NoteController.shared
    let session: Session

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label("내 노트", systemImage: "square.and.pencil").font(.headline)
                Text(hint).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if let t = nc.savedAt {
                    Label("저장됨 " + t.formatted(date: .omitted, time: .shortened), systemImage: "checkmark.circle")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 6)
            NoteEditor(sessionID: session.id,
                       clock: { [store, session] in MainActor.assumeIsolated { store.notePosition(for: session) } },
                       onSeek: { [store, session] sec in MainActor.assumeIsolated { store.seek(session: session, to: sec) } })
                .id(session.id)
                .background(Theme.paneBackground, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
                .padding(.horizontal, 14).padding(.bottom, 14)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var hint: String {
        let rs = store.recordings(of: session)
        if rs.contains(where: { $0.status == .recording }) { return "새 줄을 쓰면 녹음 시각이 붙습니다" }
        if rs.contains(where: { $0.audioPath == player.loadedPath }) { return "새 줄을 쓰면 재생 위치가 붙습니다 · 시각을 누르면 이동" }
        return "녹음하거나 재생하면 새 줄에 누적 시각이 붙습니다"
    }
}
