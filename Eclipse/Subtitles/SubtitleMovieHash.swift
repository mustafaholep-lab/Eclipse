import Foundation

/// OpenSubtitles OSHash: file size plus little-endian UInt64 sums of the
/// first and last 64 KiB, with wrapping arithmetic.
enum SubtitleMovieHash {
    static let blockSize = 65_536

    static func calculate(first: Data, last: Data, fileSize: Int64) -> String? {
        guard fileSize >= Int64(blockSize * 2),
              first.count == blockSize, last.count == blockSize else { return nil }
        var sum = UInt64(fileSize)
        for block in [first, last] {
            for offset in stride(from: 0, to: blockSize, by: 8) {
                var word: UInt64 = 0
                for byte in 0..<8 {
                    word |= UInt64(block[offset + byte]) << (byte * 8)
                }
                sum = sum &+ word
            }
        }
        return String(format: "%016llx", sum)
    }

    /// Returns nil when HTTP Range is unavailable or the server cannot prove
    /// that the two bounded responses belong to the requested file size.
    static func fromHTTP(url: URL, fileSize: Int64) async -> String? {
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              !["m3u8", "mpd"].contains(url.pathExtension.lowercased()),
              fileSize >= Int64(blockSize * 2) else { return nil }
        async let first = fetchRange(url: url, start: 0, size: fileSize)
        async let last = fetchRange(url: url, start: fileSize - Int64(blockSize), size: fileSize)
        guard let firstData = await first, let lastData = await last else { return nil }
        return calculate(first: firstData, last: lastData, fileSize: fileSize)
    }

    private static func fetchRange(url: URL, start: Int64, size: Int64) async -> Data? {
        let end = start + Int64(blockSize) - 1
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        do {
            let (data, response) = try await URLSession.shared.boundedData(
                for: request, maximumResponseBytes: blockSize
            )
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 206,
                  data.count == blockSize,
                  (http.value(forHTTPHeaderField: "Content-Range") ?? "")
                    .caseInsensitiveCompare("bytes \(start)-\(end)/\(size)") == .orderedSame else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }
}
