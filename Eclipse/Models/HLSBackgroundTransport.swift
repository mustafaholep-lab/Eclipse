import Foundation
import CryptoKit

#if os(iOS)
/// Serial delegate-backed transfers. Only the bounded response and an opaque identity
/// are checkpointed; protected provider requests must continue using their live proxy.
final class HLSBackgroundTransport: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let shared = HLSBackgroundTransport()
    static let identifier = "app.eclipse.soupy.hls-segments"
    private let queue = DispatchQueue(label: "app.eclipse.hls-background")
    private var session: URLSession!
    private var restoring = true
    private var waiting: [() -> Void] = []
    private var completionHandler: (() -> Void)?
    private var eventTimeout: DispatchWorkItem?

    private struct Flight {
        let task: URLSessionDownloadTask
        var continuation: CheckedContinuation<(Data, URLResponse), Error>?
        var limit: Int
        var cancellation: CancellationFlag? = nil
    }
    private var flights: [String: Flight] = [:]
    private let directory: URL

    private final class CancellationFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func cancel() { lock.lock(); value = true; lock.unlock() }
        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    }

    private override init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HLSBackgroundResponses", isDirectory: true)
        super.init()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var root = directory
        try? root.setResourceValues(values)
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.allowsCellularAccess = true
        configuration.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        session.getAllTasks { tasks in
            self.queue.async {
                for case let task as URLSessionDownloadTask in tasks {
                    guard task.state == .running || task.state == .suspended,
                          let key = task.taskDescription, Self.validKey(key),
                          self.flights[key] == nil else { task.cancel(); continue }
                    self.flights[key] = Flight(task: task, limit: HLSDownloader.maximumMediaObjectBytes)
                }
                self.restoring = false
                let waiting = self.waiting
                self.waiting.removeAll()
                waiting.forEach { $0() }
            }
        }
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private static func validKey(_ key: String) -> Bool {
        key.count == 129 && key.allSatisfy { $0 == "." || "0123456789abcdef".contains($0) }
    }

    func download(for request: URLRequest, downloadID: String, limit: Int) async throws -> (Data, URLResponse) {
        guard let url = request.url else { throw URLError(.badURL) }
        let key = Self.digest(downloadID) + "." + Self.digest(url.absoluteString)
        let cancellation = CancellationFlag()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    let begin = {
                        guard !cancellation.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                        if let result = self.cachedResponse(key: key, limit: limit) {
                            continuation.resume(with: result)
                            return
                        }
                        if var flight = self.flights[key] {
                            guard flight.continuation == nil else {
                                continuation.resume(throwing: URLError(.cannotLoadFromNetwork)); return
                            }
                            flight.continuation = continuation
                            flight.limit = limit
                            flight.cancellation = cancellation
                            self.flights[key] = flight
                            flight.task.resume()
                        } else {
                            let task = self.session.downloadTask(with: request)
                            task.taskDescription = key
                            self.flights[key] = Flight(task: task, continuation: continuation, limit: limit, cancellation: cancellation)
                            task.resume()
                        }
                        // A replacement transfer is now owned by the system. The previous
                        // event batch can finish without interrupting the packaging pipeline.
                        self.finishEvents()
                    }
                    if self.restoring { self.waiting.append(begin) } else { begin() }
                }
            }
        } onCancel: {
            cancellation.cancel()
            self.queue.async {
                // An old worker's cancellation must not cancel a newly resumed
                // attempt that happens to request the same URL.
                guard let flight = self.flights[key], flight.cancellation === cancellation else { return }
                self.flights.removeValue(forKey: key)
                flight.task.cancel()
                flight.continuation?.resume(throwing: CancellationError())
            }
        }
    }

    func cancel(downloadID: String) {
        let prefix = Self.digest(downloadID) + "."
        queue.async {
            let cancel = {
                for key in self.flights.keys.filter({ $0.hasPrefix(prefix) }) {
                    let flight = self.flights.removeValue(forKey: key)
                    flight?.task.cancel()
                    flight?.continuation?.resume(throwing: CancellationError())
                }
                self.removeResponses(prefix: prefix)
                self.finishEvents()
            }
            if self.restoring { self.waiting.append(cancel) } else { cancel() }
        }
    }

    func finishedProcessing(downloadID: String) {
        queue.async { self.removeResponses(prefix: Self.digest(downloadID) + "."); self.finishEvents() }
    }

    func handleBackgroundEvents(completion: @escaping () -> Void) {
        queue.async { self.completionHandler = completion }
    }

    func reconcile(downloadIDs: Set<String>) {
        let prefixes = Set(downloadIDs.map { Self.digest($0) + "." })
        queue.async {
            let reconcile = {
                for key in self.flights.keys.filter({ key in !prefixes.contains(String(key.prefix(65))) }) {
                    let flight = self.flights.removeValue(forKey: key)
                    flight?.task.cancel()
                    flight?.continuation?.resume(throwing: CancellationError())
                }
                for url in (try? FileManager.default.contentsOfDirectory(at: self.directory, includingPropertiesForKeys: nil)) ?? []
                where !prefixes.contains(String(url.lastPathComponent.prefix(65))) {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            if self.restoring { self.waiting.append(reconcile) } else { reconcile() }
        }
    }

    private func finishEvents() {
        eventTimeout?.cancel()
        eventTimeout = nil
        guard let completionHandler else { return }
        self.completionHandler = nil
        DispatchQueue.main.async(execute: completionHandler)
    }

    private func removeResponses(prefix: String) {
        for url in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        where url.lastPathComponent.hasPrefix(prefix) { try? FileManager.default.removeItem(at: url) }
    }

    private func cachedResponse(key: String, limit: Int) -> Result<(Data, URLResponse), Error>? {
        let body = directory.appendingPathComponent(key)
        let metadata = directory.appendingPathComponent(key + ".response")
        guard FileManager.default.fileExists(atPath: body.path) else { return nil }
        defer { try? FileManager.default.removeItem(at: body); try? FileManager.default.removeItem(at: metadata) }
        do {
            let bytes = try body.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard bytes <= limit else { throw URLError(.dataLengthExceedsMaximum) }
            let archived = try Data(contentsOf: metadata)
            guard let response = try NSKeyedUnarchiver.unarchivedObject(ofClass: HTTPURLResponse.self, from: archived) else {
                throw URLError(.badServerResponse)
            }
            return .success((try Data(contentsOf: body), response))
        } catch { return .failure(error) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let key = downloadTask.taskDescription, Self.validKey(key) else { return }
        // URLSession deletes its temporary URL after this delegate method returns.
        queue.sync {
            if let flight = flights[key], flight.task.taskIdentifier != downloadTask.taskIdentifier { return }
            do {
                guard let response = downloadTask.response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                let size = try location.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= (flights[key]?.limit ?? HLSDownloader.maximumMediaObjectBytes) else {
                    throw URLError(.dataLengthExceedsMaximum)
                }
                let body = directory.appendingPathComponent(key)
                try? FileManager.default.removeItem(at: body)
                try FileManager.default.moveItem(at: location, to: body)
                let archived = try NSKeyedArchiver.archivedData(withRootObject: response, requiringSecureCoding: true)
                try archived.write(to: directory.appendingPathComponent(key + ".response"), options: .atomic)
                if let flight = flights.removeValue(forKey: key), let continuation = flight.continuation {
                    continuation.resume(with: cachedResponse(key: key, limit: flight.limit) ?? .failure(URLError(.badServerResponse)))
                }
            } catch {
                flights.removeValue(forKey: key)?.continuation?.resume(throwing: error)
            }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let key = downloadTask.taskDescription else { return }
        queue.async {
            guard let flight = self.flights[key], flight.task.taskIdentifier == downloadTask.taskIdentifier,
                  totalBytesWritten > flight.limit else { return }
            self.flights.removeValue(forKey: key)?.continuation?.resume(throwing: URLError(.dataLengthExceedsMaximum))
            flight.task.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let key = task.taskDescription else { return }
        queue.async {
            guard self.flights[key]?.task.taskIdentifier == task.taskIdentifier else { return }
            self.flights.removeValue(forKey: key)?.continuation?.resume(throwing: error)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        queue.async {
            // If the worker was killed, its durable response is sufficient for launch
            // recovery. Bound event handling if no replacement request gets scheduled.
            let timeout = DispatchWorkItem { self.finishEvents() }
            self.eventTimeout?.cancel()
            self.eventTimeout = timeout
            self.queue.asyncAfter(deadline: .now() + 5, execute: timeout)
        }
    }
}
#endif
