import Foundation

/// Translation-only view of a subtitle file. Playback continues to use its existing loaders.
enum SubtitleDocumentFormat: String {
    case srt, vtt, ass, ssa
}

enum SubtitleSkipReason: Equatable {
    case empty, drawing, karaoke, sign, effect, openingOrEnding, nonDialogue
}

struct SubtitleTranslationUnit {
    let id: String
    let start: TimeInterval
    let end: TimeInterval
    let originalText: String
    /// Text without formatting commands. Use translationTemplate when asking for a translation.
    let plainText: String
    /// Contains opaque markers for protected formatting and ASS line breaks.
    let translationTemplate: String
    let format: SubtitleDocumentFormat
    let skipReason: SubtitleSkipReason?
    let duplicateOf: String?

    var isEligible: Bool { skipReason == nil }
}

enum SubtitleDocumentError: LocalizedError {
    case invalidFormat
    case unknownUnit
    case skippedUnit
    case damagedPlaceholders

    var errorDescription: String? {
        switch self {
        case .invalidFormat: return "The subtitle document does not match its format."
        case .unknownUnit: return "The subtitle cue was not found."
        case .skippedUnit: return "This subtitle event is not eligible for translation."
        case .damagedPlaceholders: return "The translation changed protected subtitle formatting."
        }
    }
}

struct SubtitleDocument {
    let format: SubtitleDocumentFormat
    let units: [SubtitleTranslationUnit]

    /// Duplicate ASS layers appear once here, while all source events remain in `units`.
    var translatableUnits: [SubtitleTranslationUnit] {
        units.filter { $0.isEligible && $0.duplicateOf == nil }
    }

    private let source: String
    private let records: [Record]
    private var replacements: [String: String] = [:]

    private struct Record {
        let unit: SubtitleTranslationUnit
        let textRange: NSRange
        let protected: [ProtectedPart]
    }

    private struct ProtectedPart {
        let marker: String
        let original: String
    }

    private struct Line {
        let body: NSRange
        let full: NSRange
    }

    static func parse(_ source: String, format: SubtitleDocumentFormat) throws -> SubtitleDocument {
        let lines = lineRanges(source)
        var records: [Record] = []
        switch format {
        case .srt, .vtt:
            if format == .vtt {
                guard source.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("WEBVTT") else {
                    throw SubtitleDocumentError.invalidFormat
                }
            }
            parseTimedBlocks(source, lines: lines, format: format, into: &records)
        case .ass, .ssa:
            guard source.range(of: "[Events]", options: .caseInsensitive) != nil else {
                throw SubtitleDocumentError.invalidFormat
            }
            parseASS(source, lines: lines, format: format, into: &records)
        }
        return SubtitleDocument(format: format, units: records.map(\.unit), source: source, records: records)
    }

    /// The input should already have been decoded by SubtitleFileHandling.prepare.
    static func parse(_ utf8: Data, format: SubtitleDocumentFormat) throws -> SubtitleDocument {
        guard let source = String(data: utf8, encoding: .utf8) else { throw SubtitleDocumentError.invalidFormat }
        return try parse(source, format: format)
    }

    mutating func applyTranslation(id: String, text: String) throws {
        guard let record = records.first(where: { $0.unit.id == id }) else { throw SubtitleDocumentError.unknownUnit }
        guard record.unit.isEligible else { throw SubtitleDocumentError.skippedUnit }
        // A duplicate belongs to the same group as its representative.
        let representative = record.unit.duplicateOf ?? id
        guard let primary = records.first(where: { $0.unit.id == representative }) else {
            throw SubtitleDocumentError.unknownUnit
        }
        guard Self.restored(text, parts: primary.protected) != nil else {
            throw SubtitleDocumentError.damagedPlaceholders
        }
        replacements[representative] = text
    }

    func serialize() throws -> String {
        guard !replacements.isEmpty else { return source }
        let result = NSMutableString(string: source)
        for record in records.reversed() {
            let representative = record.unit.duplicateOf ?? record.unit.id
            guard let translated = replacements[representative] else { continue }
            let protected = records.first(where: { $0.unit.id == representative })?.protected ?? record.protected
            guard let restored = Self.restored(translated, parts: protected) else {
                throw SubtitleDocumentError.damagedPlaceholders
            }
            result.replaceCharacters(in: record.textRange, with: restored)
        }
        return result as String
    }

    private static func lineRanges(_ source: String) -> [Line] {
        let ns = source as NSString
        var result: [Line] = []
        var offset = 0
        while offset < ns.length {
            var end = offset
            while end < ns.length && ns.character(at: end) != 10 && ns.character(at: end) != 13 { end += 1 }
            var after = end
            if after < ns.length {
                if ns.character(at: after) == 13 && after + 1 < ns.length && ns.character(at: after + 1) == 10 {
                    after += 2
                } else { after += 1 }
            }
            result.append(Line(body: NSRange(location: offset, length: end - offset),
                               full: NSRange(location: offset, length: after - offset)))
            offset = after
        }
        return result
    }

    private static func parseTimedBlocks(_ source: String, lines: [Line], format: SubtitleDocumentFormat,
                                         into records: inout [Record]) {
        let ns = source as NSString
        var position = 0
        while position < lines.count {
            while position < lines.count && ns.substring(with: lines[position].body)
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { position += 1 }
            guard position < lines.count else { break }
            let beginning = position
            while position < lines.count && !ns.substring(with: lines[position].body)
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { position += 1 }
            let block = Array(lines[beginning..<position])
            guard !block.isEmpty else { continue }
            if format == .vtt {
                let first = ns.substring(with: block[0].body).trimmingCharacters(in: .whitespaces)
                if first == "WEBVTT" || first.hasPrefix("WEBVTT ") || first == "NOTE" || first.hasPrefix("NOTE ") ||
                    first == "STYLE" || first == "REGION" { continue }
            }
            // A cue may have a numeric index or a VTT identifier, but no arbitrary preamble.
            let timeIndex: Int
            if parseTimeLine(ns.substring(with: block[0].body)) != nil { timeIndex = 0 }
            else if block.count > 1 && parseTimeLine(ns.substring(with: block[1].body)) != nil { timeIndex = 1 }
            else { continue } // Retain malformed blocks verbatim.
            guard timeIndex + 1 < block.count,
                  let times = parseTimeLine(ns.substring(with: block[timeIndex].body)) else { continue }
            let firstText = block[timeIndex + 1].body.location
            let lastText = block.last!.body.location + block.last!.body.length
            let textRange = NSRange(location: firstText, length: lastText - firstText)
            let raw = ns.substring(with: textRange)
            let id = "\(format.rawValue):\(records.count)"
            let protected = protect(raw, format: format, id: id, source: source)
            let reason: SubtitleSkipReason? = protected.plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .empty : nil
            let unit = SubtitleTranslationUnit(id: id, start: times.0, end: times.1,
                originalText: raw, plainText: protected.plain,
                translationTemplate: protected.template, format: format,
                skipReason: reason, duplicateOf: nil)
            records.append(Record(unit: unit, textRange: textRange, protected: protected.parts))
        }
    }

    private static func parseTimeLine(_ line: String) -> (TimeInterval, TimeInterval)? {
        let pieces = line.components(separatedBy: "-->")
        guard pieces.count == 2,
              let start = timestamp(pieces[0].trimmingCharacters(in: .whitespaces)),
              let endToken = pieces[1].split(whereSeparator: \.isWhitespace).first,
              let end = timestamp(String(endToken)), end >= start else { return nil }
        return (start, end)
    }

    private static func timestamp(_ value: String) -> TimeInterval? {
        let pieces = value.replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard pieces.count == 2 || pieces.count == 3,
              let seconds = Double(pieces.last!), seconds >= 0, seconds < 60,
              let minutes = Int(pieces[pieces.count - 2]), minutes >= 0, minutes < 60 else { return nil }
        let hours: Int
        if pieces.count == 3 {
            guard let parsed = Int(pieces[0]), parsed >= 0 else { return nil }
            hours = parsed
        } else { hours = 0 }
        return Double(hours * 3600 + minutes * 60) + seconds
    }

    private static func parseASS(_ source: String, lines: [Line], format: SubtitleDocumentFormat,
                                 into records: inout [Record]) {
        let ns = source as NSString
        var section = ""
        var fields: [String] = []
        var duplicateIDs: [String: String] = [:]
        for line in lines {
            let body = ns.substring(with: line.body)
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                section = trimmed.lowercased()
                fields = []
                continue
            }
            guard section == "[events]" else { continue }
            if trimmed.lowercased().hasPrefix("format:") {
                fields = String(trimmed.dropFirst(7)).split(separator: ",", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                continue
            }
            guard trimmed.lowercased().hasPrefix("dialogue:"),
                  let colon = body.firstIndex(of: ":") else { continue }
            let prefixLength = (String(body[...colon]) as NSString).length
            let value = String(body[body.index(after: colon)...])
            let columns = splitASSFields(value, fields: fields)
            guard let columns,
                  let textIndex = fields.firstIndex(of: "text"),
                  let startIndex = fields.firstIndex(of: "start"),
                  let endIndex = fields.firstIndex(of: "end"),
                  let start = assTimestamp(columns[startIndex].value.trimmingCharacters(in: .whitespaces)),
                  let end = assTimestamp(columns[endIndex].value.trimmingCharacters(in: .whitespaces)), end >= start else { continue }
            let textColumn = columns[textIndex]
            let textRange = NSRange(location: line.body.location + prefixLength + textColumn.range.location,
                                    length: textColumn.range.length)
            let raw = ns.substring(with: textRange)
            let id = "\(format.rawValue):\(records.count)"
            let protected = protect(raw, format: format, id: id, source: source)
            let style = fields.firstIndex(of: "style").map { columns[$0].value.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
            let effect = fields.firstIndex(of: "effect").map { columns[$0].value.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
            let reason = assSkipReason(raw: raw, plain: protected.plain, style: style, effect: effect)
            let key = "\(start)|\(end)|\(raw)"
            let duplicate = reason == nil ? duplicateIDs[key] : nil
            if reason == nil && duplicate == nil { duplicateIDs[key] = id }
            let unit = SubtitleTranslationUnit(id: id, start: start, end: end,
                originalText: raw, plainText: protected.plain,
                translationTemplate: protected.template, format: format,
                skipReason: reason, duplicateOf: duplicate)
            records.append(Record(unit: unit, textRange: textRange, protected: protected.parts))
        }
    }

    private struct ASSColumn {
        let value: String
        let range: NSRange
    }

    /// Fixed fields are read from both ends; the Text field consumes remaining commas.
    private static func splitASSFields(_ value: String, fields: [String]) -> [ASSColumn]? {
        guard fields.count >= 3, let textIndex = fields.firstIndex(of: "text") else { return nil }
        let ns = value as NSString
        var ranges = [NSRange](repeating: NSRange(location: 0, length: 0), count: fields.count)
        var left = 0
        for index in 0..<textIndex {
            let comma = ns.range(of: ",", options: [], range: NSRange(location: left, length: ns.length - left))
            guard comma.location != NSNotFound else { return nil }
            ranges[index] = NSRange(location: left, length: comma.location - left)
            left = comma.location + 1
        }
        var right = ns.length
        if textIndex + 1 < fields.count {
            for index in stride(from: fields.count - 1, through: textIndex + 1, by: -1) {
                let comma = ns.range(of: ",", options: .backwards, range: NSRange(location: left, length: right - left))
                guard comma.location != NSNotFound else { return nil }
                ranges[index] = NSRange(location: comma.location + 1, length: right - comma.location - 1)
                right = comma.location
            }
        }
        guard right >= left else { return nil }
        ranges[textIndex] = NSRange(location: left, length: right - left)
        return ranges.map { ASSColumn(value: ns.substring(with: $0), range: $0) }
    }

    private static func assTimestamp(_ value: String) -> TimeInterval? {
        timestamp(value)
    }

    private static func assSkipReason(raw: String, plain: String, style: String, effect: String) -> SubtitleSkipReason? {
        if raw.range(of: #"\\p[1-9]"#, options: .regularExpression) != nil { return .drawing }
        if raw.range(of: #"\\(?:[kK](?:f|o)?)\d"#, options: .regularExpression) != nil { return .karaoke }
        if style.range(of: #"(?:^|[ _-])(sign|typeset)(?:$|[ _-])"#, options: .regularExpression) != nil ||
            raw.contains("\\pos(") || raw.contains("\\move(") { return .sign }
        if !effect.isEmpty { return .effect }
        if style.range(of: #"(?:^|[ _-])(op|ed|opening|ending)(?:$|[ _-])"#, options: .regularExpression) != nil {
            return .openingOrEnding
        }
        if plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .empty }
        return nil
    }

    private static func protect(_ raw: String, format: SubtitleDocumentFormat, id: String, source: String)
        -> (plain: String, template: String, parts: [ProtectedPart]) {
        let pattern: String
        switch format {
        case .ass, .ssa: pattern = #"\{\\[^}]*\}|\\[Nnh]"#
        case .srt, .vtt: pattern = #"<[^>\r\n]+>"#
        }
        let regex = try! NSRegularExpression(pattern: pattern)
        let ns = raw as NSString
        let matches = regex.matches(in: raw, range: NSRange(location: 0, length: ns.length))
        var salt = 0
        var prefix: String
        repeat {
            prefix = "\u{E000}B1_\(id)_\(salt)_"
            salt += 1
        } while source.contains(prefix)
        var template = ""
        var plain = ""
        var parts: [ProtectedPart] = []
        var cursor = 0
        for (index, match) in matches.enumerated() {
            let before = ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            template += before
            plain += before
            let original = ns.substring(with: match.range)
            let marker = "\(prefix)\(index)\u{E001}"
            template += marker
            if original == "\\N" || original == "\\n" { plain += "\n" }
            else if original == "\\h" { plain += " " }
            parts.append(ProtectedPart(marker: marker, original: original))
            cursor = match.range.location + match.range.length
        }
        let tail = ns.substring(from: cursor)
        return (plain + tail, template + tail, parts)
    }

    private static func restored(_ translated: String, parts: [ProtectedPart]) -> String? {
        var previous = 0
        let ns = translated as NSString
        for part in parts {
            let range = ns.range(of: part.marker)
            guard range.location != NSNotFound, range.location >= previous,
                  ns.range(of: part.marker, options: [], range: NSRange(location: range.location + range.length,
                      length: ns.length - range.location - range.length)).location == NSNotFound else { return nil }
            previous = range.location + range.length
        }
        var result = translated
        for part in parts { result = result.replacingOccurrences(of: part.marker, with: part.original) }
        return result
    }
}
