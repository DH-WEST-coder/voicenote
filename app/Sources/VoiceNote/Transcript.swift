import Foundation

struct Segment: Identifiable {
    let id: Int
    let time: Double
    let timeLabel: String
    var speaker: String
    var text: String
}

struct Transcript {
    var meta: [String: String] = [:]
    var segments: [Segment] = []
    var speakers: [String] {
        var seen: [String] = []
        for s in segments where !seen.contains(s.speaker) { seen.append(s.speaker) }
        return seen
    }
}

enum TranscriptIO {
    // [m:ss] 화자1: text   또는 [h:mm:ss] ...
    static let lineRegex = try! NSRegularExpression(pattern: #"^\[((?:\d+:)?\d+:\d{2})\] (.+?): (.*)$"#)

    static func seconds(_ label: String) -> Double {
        label.split(separator: ":").compactMap { Double($0) }.reduce(0) { $0 * 60 + $1 }
    }

    static func match(_ line: String) -> (time: String, speaker: String, text: String)? {
        let ns = line as NSString
        guard let m = lineRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (ns.substring(with: m.range(at: 1)), ns.substring(with: m.range(at: 2)), ns.substring(with: m.range(at: 3)))
    }

    static func parse(_ text: String) -> Transcript {
        var t = Transcript()
        var lines = text.components(separatedBy: "\n")
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            lines.removeFirst()
            while let l = lines.first {
                lines.removeFirst()
                if l.trimmingCharacters(in: .whitespaces) == "---" { break }
                if let r = l.range(of: ":") {
                    t.meta[String(l[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)] =
                        String(l[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        for l in lines {
            if let m = match(l) {
                t.segments.append(Segment(id: t.segments.count, time: seconds(m.time), timeLabel: m.time, speaker: m.speaker, text: m.text))
            }
        }
        return t
    }

    static func load(path: String) -> Transcript? {
        guard let s = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return parse(s)
    }

    /// 화자 이름을 .md 파일에서 일괄 변경한다.
    static func renameSpeaker(path: String, from: String, to: String) throws {
        let s = try String(contentsOfFile: path, encoding: .utf8)
        let out = s.components(separatedBy: "\n").map { line -> String in
            if let m = match(line), m.speaker == from { return "[\(m.time)] \(to): \(m.text)" }
            return line
        }.joined(separator: "\n")
        try out.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
