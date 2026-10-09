import Foundation
import ZIPFoundation
#if canImport(zlib)
import zlib
#endif

enum SubtitleFileError: LocalizedError {
    case empty
    case tooLarge
    case unsupportedFormat
    case unreadableArchive
    case noMatchingSubtitle
    case invalidEncoding
    case missingTimedCues

    var errorDescription: String? {
        switch self {
        case .empty: return "The subtitle file is empty."
        case .tooLarge: return "The subtitle file exceeds the 12 MB safety limit."
        case .unsupportedFormat: return "Unsupported subtitle format."
        case .unreadableArchive: return "The subtitle archive could not be read."
        case .noMatchingSubtitle: return "The archive contains no suitable subtitle for this episode."
        case .invalidEncoding: return "The subtitle encoding could not be read as UTF-8, UTF-16, or Turkish Windows-1254."
        case .missingTimedCues: return "The file does not contain timed subtitle cues."
        }
    }

}

struct PreparedSubtitleFile: Sendable {
    let data: Data
    let fileName: String
    let format: String
}

enum SubtitleFileHandling {
    static let maximumBytes = 12 * 1_024 * 1_024
    private static let formats: Set<String> = ["srt", "vtt", "ass", "ssa"]

    /// For online subtitle sources, the response body is authoritative; URL and addon formats are hints.
    static func prepareDetected(_ data: Data, hintedFileName: String? = nil,
                                hintedFormat: String? = nil, query: SubtitleQuery? = nil) throws -> PreparedSubtitleFile {
        guard !data.isEmpty else { throw SubtitleFileError.empty }
        guard data.count <= maximumBytes else { throw SubtitleFileError.tooLarge }
        if data.starts(with: [0x50, 0x4b, 0x03, 0x04]) {
            return try validateTimedDocument(prepare(data, fileName: "subtitle.zip", query: query))
        }
        if data.starts(with: [0x1f, 0x8b]) {
            return try prepare(data, fileName: "subtitle.gz", query: query)
        }
        guard let decoded = decodeText(data) else { throw SubtitleFileError.invalidEncoding }
        var text = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("\u{feff}") { text.removeFirst() }
        let detected: String?
        if text.hasPrefix("WEBVTT") {
            detected = "vtt"
        } else if text.range(of: #"(?im)^\s*\[Events\]\s*$"#, options: .regularExpression) != nil,
                  text.range(of: #"(?im)^\s*Dialogue\s*:"#, options: .regularExpression) != nil {
            detected = text.range(of: #"(?im)^\s*\[V4 Styles\]\s*$"#, options: .regularExpression) != nil
                ? "ssa" : "ass"
        } else if text.contains("-->") {
            detected = "srt"
        } else {
            detected = nil
        }
        let hinted = [hintedFormat, hintedFileName.map { ($0 as NSString).pathExtension }]
            .compactMap { $0?.lowercased() }.first(where: { formats.contains($0) })
        guard let format = detected ?? hinted, formats.contains(format) else {
            throw SubtitleFileError.unsupportedFormat
        }
        let prepared = try prepare(data, fileName: "subtitle.\(format)", query: query)
        return try validateTimedDocument(prepared)
    }

    private static func validateTimedDocument(_ prepared: PreparedSubtitleFile) throws -> PreparedSubtitleFile {
        guard let documentFormat = SubtitleDocumentFormat(rawValue: prepared.format),
              let document = try? SubtitleDocument.parse(prepared.data, format: documentFormat),
              !document.units.isEmpty else { throw SubtitleFileError.missingTimedCues }
        return prepared
    }

    static func prepare(_ data: Data, fileName: String, query: SubtitleQuery? = nil) throws -> PreparedSubtitleFile {
        guard !data.isEmpty else { throw SubtitleFileError.empty }
        guard data.count <= maximumBytes else { throw SubtitleFileError.tooLarge }
        if data.starts(with: [0x50, 0x4b, 0x03, 0x04]) {
            return try prepareZIP(data, query: query)
        }
        if data.starts(with: [0x1f, 0x8b]) {
            guard let inflated = inflateGZIP(data) else { throw SubtitleFileError.unreadableArchive }
            let name = (fileName as NSString).deletingPathExtension
            return try prepareDetected(inflated, hintedFileName: name, query: query)
        }
        let format = (fileName as NSString).pathExtension.lowercased()
        guard formats.contains(format) else { throw SubtitleFileError.unsupportedFormat }
        guard var text = decodeText(data) else { throw SubtitleFileError.invalidEncoding }
        if text.hasPrefix("\u{feff}") { text.removeFirst() }
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if format == "srt" || format == "vtt" {
            text = text.split(separator: "\n", omittingEmptySubsequences: false)
                .map { line -> String in
                    var value = String(line)
                    while value.last == " " || value.last == "\t" { value.removeLast() }
                    return value
                }
                .joined(separator: "\n")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SubtitleFileError.empty }
        let hasCues = ["ass", "ssa"].contains(format)
            ? trimmed.localizedCaseInsensitiveContains("[Script Info]")
                && trimmed.localizedCaseInsensitiveContains("Dialogue:")
            : trimmed.contains("-->")
        guard hasCues else { throw SubtitleFileError.missingTimedCues }
        return PreparedSubtitleFile(data: Data(text.utf8), fileName: fileName, format: format)
    }

    private static func decodeText(_ data: Data) -> String? {
        if data.starts(with: [0xff, 0xfe]) { return String(data: data, encoding: .utf16LittleEndian) }
        if data.starts(with: [0xfe, 0xff]) { return String(data: data, encoding: .utf16BigEndian) }
        if data.starts(with: [0xef, 0xbb, 0xbf]) { return String(data: data, encoding: .utf8) }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1254)
    }

    private static func prepareZIP(_ data: Data, query: SubtitleQuery?) throws -> PreparedSubtitleFile {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("subtitle-\(UUID().uuidString).zip")
        try data.write(to: temporaryURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        let archive: Archive
        do { archive = try Archive(url: temporaryURL, accessMode: .read) }
        catch { throw SubtitleFileError.unreadableArchive }
        let entries = archive.filter { entry in
            entry.type == .file
                && formats.contains((entry.path as NSString).pathExtension.lowercased())
                && entry.uncompressedSize <= UInt64(maximumBytes)
        }
        guard !entries.isEmpty else { throw SubtitleFileError.noMatchingSubtitle }
        let ranked = entries.map { (entry: $0, score: archiveScore($0.path, query: query)) }
            .sorted { $0.score > $1.score }
        guard let best = ranked.first, best.score > -400,
              ranked.count == 1 || best.score > ranked[1].score else {
            throw SubtitleFileError.noMatchingSubtitle
        }
        let selected = best.entry
        var extracted = Data()
        do {
            _ = try archive.extract(selected, bufferSize: 64 * 1_024, skipCRC32: false, progress: nil) { chunk in
                guard chunk.count <= maximumBytes - extracted.count else { throw SubtitleFileError.tooLarge }
                extracted.append(chunk)
            }
        } catch let error as SubtitleFileError { throw error }
        catch { throw SubtitleFileError.unreadableArchive }
        return try prepare(extracted, fileName: (selected.path as NSString).lastPathComponent, query: query)
    }

    private static func archiveScore(_ name: String, query: SubtitleQuery?) -> Int {
        guard let query else { return 0 }
        let normalizedName = name.lowercased()
        let language: String
        if normalizedName.range(of: #"(?:^|[^a-z])(?:tr|tur|turkish)(?:[^a-z]|$)"#, options: .regularExpression) != nil {
            language = "tur"
        } else if normalizedName.range(of: #"(?:^|[^a-z])(?:en|eng|english)(?:[^a-z]|$)"#, options: .regularExpression) != nil {
            language = "eng"
        } else {
            language = "und"
        }
        let candidate = SubtitleCandidate(
            id: name, providerID: "archive", language: language, releaseName: name,
            format: (name as NSString).pathExtension.lowercased(), downloads: nil,
            rating: nil, isHearingImpaired: false, isMachineTranslated: false,
            score: 0, matchReasons: []
        )
        return SubtitleRanking.score(candidate, for: query).score
    }

    private static func inflateGZIP(_ data: Data) -> Data? {
#if canImport(zlib)
        var stream = z_stream()
        guard inflateInit2_(&stream, 15 + 16, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            return nil
        }
        defer { inflateEnd(&stream) }
        var output = Data()
        return data.withUnsafeBytes { input in
            guard let inputPointer = input.bindMemory(to: Bytef.self).baseAddress else { return nil }
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: inputPointer)
            stream.avail_in = uInt(data.count)
            var status: Int32 = Z_OK
            repeat {
                var chunk = [UInt8](repeating: 0, count: 64 * 1_024)
                chunk.withUnsafeMutableBufferPointer { buffer in
                    stream.next_out = buffer.baseAddress
                    stream.avail_out = uInt(buffer.count)
                    status = inflate(&stream, Z_NO_FLUSH)
                    if status == Z_OK || status == Z_STREAM_END {
                        let count = buffer.count - Int(stream.avail_out)
                        if count > 0, let base = buffer.baseAddress { output.append(base, count: count) }
                    }
                }
                if output.count > maximumBytes { return nil }
            } while status == Z_OK
            return status == Z_STREAM_END ? output : nil
        }
#else
        return nil
#endif
    }
}
