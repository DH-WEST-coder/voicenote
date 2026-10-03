import AppKit
import SwiftUI

/// 화면 전체에서 같이 쓰는 색·부품
enum Theme {
    static let record = Color(red: 0.93, green: 0.27, blue: 0.27)
    static let speakerPalette: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .brown, .indigo]
    static func speakerColor(_ i: Int) -> Color { speakerPalette[i % speakerPalette.count] }
    static let paneBackground = Color(nsColor: .textBackgroundColor)
    static let subtleFill = Color.primary.opacity(0.05)
}

/// 빨간 캡슐 녹음 버튼. 녹음 중이면 경과 시간과 정지 아이콘을 보여 준다.
struct RecordButton: View {
    @EnvironmentObject var store: Store
    var large = false

    var body: some View {
        Button { store.toggleRecording() } label: {
            HStack(spacing: 6) {
                Image(systemName: store.isRecording ? "stop.fill" : "circle.fill")
                    .font(.system(size: large ? 13 : 9, weight: .bold))
                Text(store.isRecording ? formatTime(store.elapsed) : "녹음")
                    .monospacedDigit()
            }
            .font(large ? .title3.weight(.semibold) : .callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, large ? 22 : 12)
            .padding(.vertical, large ? 10 : 4)
            .background(Theme.record.opacity(store.isRecording ? 1 : 0.92), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(store.isRecording ? "녹음 정지 (⌥⌘R)" : "녹음 시작 (⌥⌘R)")
    }
}

/// 상태를 색 동그라미 아이콘 하나로
struct StatusIcon: View {
    let status: JobStatus
    var body: some View {
        Group {
            switch status {
            case .recording: Image(systemName: "record.circle.fill").foregroundStyle(Theme.record)
            case .queued: Image(systemName: "clock.fill").foregroundStyle(.secondary)
            case .processing: ProgressView().controlSize(.small)
            case .done: Image(systemName: "waveform.circle.fill").foregroundStyle(Color.accentColor)
            case .failed: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            }
        }
        .font(.title2)
        .frame(width: 26, height: 26)
    }
}

/// 작은 회색 칩 (프로필, 길이 등)
struct Chip: View {
    let text: String
    var systemImage: String?
    var tint: Color = .secondary
    var body: some View {
        HStack(spacing: 3) {
            if let s = systemImage { Image(systemName: s) }
            Text(text).lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(tint)
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

@MainActor func pickAudioFiles(into store: Store) {
    let p = NSOpenPanel()
    p.allowsMultipleSelection = true
    p.canChooseDirectories = false
    p.allowedContentTypes = [.audio, .movie]
    NSApp.activate(ignoringOtherApps: true)
    if p.runModal() == .OK { store.importFiles(p.urls) }
}

/// 채팅 답변용 간단한 Markdown 블록 렌더러(제목, 목록, 인용, 코드 블록, 구분선 + 인라인 서식)
struct MarkdownText: View {
    let text: String

    private enum Block: Hashable {
        case heading(Int, String), bullet(Int, String), numbered(String, String), quote(String), code(String), rule, para(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in view(b) }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder private func view(_ b: Block) -> some View {
        switch b {
        case .heading(let level, let s):
            inline(s).font(level <= 1 ? .title3.bold() : level == 2 ? .headline : .subheadline.bold())
                .padding(.top, 4)
        case .bullet(let indent, let s):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•").foregroundStyle(.secondary)
                inline(s)
            }
            .padding(.leading, CGFloat(indent) * 14)
        case .numbered(let n, let s):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(n).foregroundStyle(.secondary).monospacedDigit()
                inline(s)
            }
        case .quote(let s):
            inline(s).foregroundStyle(.secondary)
                .padding(.leading, 10)
                .overlay(alignment: .leading) { Rectangle().fill(.tertiary).frame(width: 3) }
        case .code(let s):
            Text(s).font(.system(.callout, design: .monospaced))
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: 6))
        case .rule:
            Divider().padding(.vertical, 2)
        case .para(let s):
            inline(s).lineSpacing(2)
        }
    }

    private func inline(_ s: String) -> Text {
        let a = (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
        return Text(a)
    }

    private var blocks: [Block] {
        var out: [Block] = []
        var para: [String] = []
        var code: [String]? = nil
        func flush() { if !para.isEmpty { out.append(.para(para.joined(separator: "\n"))); para = [] } }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let c = code { out.append(.code(c.joined(separator: "\n"))); code = nil } else { flush(); code = [] }
                continue
            }
            if code != nil { code!.append(raw); continue }
            if line.isEmpty { flush(); continue }
            let hashes = line.prefix { $0 == "#" }.count
            if (1...6).contains(hashes), line.dropFirst(hashes).first == " " {
                flush(); out.append(.heading(hashes, String(line.dropFirst(hashes + 1)))); continue
            }
            if line == "---" || line == "***" { flush(); out.append(.rule); continue }
            if let f = line.first, "-*+".contains(f), line.dropFirst().first == " " {
                flush()
                let indent = (raw.prefix { $0 == " " }.count) / 2
                out.append(.bullet(indent, String(line.dropFirst(2)))); continue
            }
            let digits = line.prefix { $0.isNumber }
            if !digits.isEmpty, line.count > digits.count + 1 {
                let rest = line.dropFirst(digits.count)
                if let d = rest.first, ".)".contains(d), rest.dropFirst().first == " " {
                    flush(); out.append(.numbered(digits + String(d), String(rest.dropFirst(2)))); continue
                }
            }
            if line.hasPrefix(">") {
                flush(); out.append(.quote(String(line.dropFirst()).trimmingCharacters(in: .whitespaces))); continue
            }
            para.append(line)
        }
        if let c = code { out.append(.code(c.joined(separator: "\n"))) }
        flush()
        return out
    }
}
