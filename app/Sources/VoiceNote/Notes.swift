import AppKit
import SwiftUI

/// 노트 파일: ~/Documents/VoiceNote/notes/<job id>.md
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
    var jobID: UUID?
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
        guard dirty, let id = jobID, let tv = textView else { return }
        NoteFile.save(id, tv.string)
        dirty = false; savedAt = Date()
    }

    func noteText(jobID id: UUID) -> String {
        if jobID == id, let tv = textView { return tv.string }
        return NoteFile.load(id)
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
    let jobID: UUID
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
        tv.textContainerInset = NSSize(width: 8, height: 8)
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
        nc.textView = tv; nc.jobID = jobID; nc.dirty = false
        tv.string = NoteFile.load(jobID)
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
    let job: Job

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("내 노트", systemImage: "square.and.pencil").font(.subheadline.bold())
                Spacer()
                if let t = nc.savedAt { Text("저장됨 " + t.formatted(date: .omitted, time: .standard)).font(.caption2).foregroundStyle(.tertiary) }
                Text(hint).font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            Divider()
            NoteEditor(jobID: job.id,
                       clock: { [store, job] in MainActor.assumeIsolated { store.notePosition(for: job) } },
                       onSeek: { [store, job] sec in MainActor.assumeIsolated { store.seek(job: job, to: sec) } })
                .id(job.id)
        }
    }

    private var hint: String {
        if job.status == .recording { return "새 줄을 쓰면 녹음 시각이 붙습니다" }
        if player.loadedPath == job.audioPath { return "새 줄을 쓰면 재생 위치가 붙습니다 · 시각을 누르면 이동" }
        return "재생을 시작하면 새 줄에 시각이 붙습니다"
    }
}
