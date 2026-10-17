import Foundation

#if os(iOS)
import UIKit
import BackgroundTasks

struct DownloadBackgroundProgress {
    let id: String
    let fraction: Double
    let pending: Bool
    let succeeded: Bool
}

/// Keeps the validated local provider proxy and HLS packager executing, without
/// replacing them with an unvalidated remote background request or silent audio.
enum DownloadBackgroundExecution {
    @available(iOS 26.0, *) private static let worker = ContinuedDownloadWork()

    static var mayContinue: Bool {
        if #available(iOS 26.0, *) { return worker.mayContinue }
        return false
    }

    static func begin(ids: Set<String>, title: String, subtitle: String,
                      ready: @escaping () -> Void, expired: @escaping (Set<String>) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        if #available(iOS 26.0, *) {
            worker.begin(ids: ids, title: title, subtitle: subtitle, ready: ready, expired: expired)
        }
    }

    static func update(_ progress: [DownloadBackgroundProgress]) {
        dispatchPrecondition(condition: .onQueue(.main))
        if #available(iOS 26.0, *) { worker.update(progress) }
    }
}

@available(iOS 26.0, *)
private final class ContinuedDownloadWork {
    private let identifier = (Bundle.main.bundleIdentifier ?? "app.Eclipse.Soupy") + ".downloads.continued"
    private var registered = false
    private var requested = false
    private var task: BGContinuedProcessingTask?
    private var ids = Set<String>()
    private var onReady: (() -> Void)?
    private var onExpired: ((Set<String>) -> Void)?
    private let lock = NSLock()
    private var protectedExecution = false

    var mayContinue: Bool {
        lock.lock(); defer { lock.unlock() }
        return protectedExecution
    }

    private func setProtection(_ value: Bool) {
        lock.lock(); protectedExecution = value; lock.unlock()
    }

    func begin(ids newIDs: Set<String>, title: String, subtitle: String,
               ready: @escaping () -> Void, expired: @escaping (Set<String>) -> Void) {
        guard !newIDs.isEmpty, UIApplication.shared.applicationState == .active else { return }
        ids.formUnion(newIDs)
        onReady = ready
        onExpired = expired
        guard !requested, task == nil else { return }
        if !registered {
            registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { [weak self] rawTask in
                guard let self, let continued = rawTask as? BGContinuedProcessingTask,
                      self.requested else {
                    rawTask.setTaskCompleted(success: false)
                    return
                }
                self.task = continued
                continued.expirationHandler = { [weak self, weak continued] in
                    DispatchQueue.main.async {
                        guard let self, let continued, self.task === continued else { return }
                        let affected = self.ids
                        let expired = self.onExpired
                        self.setProtection(false)
                        expired?(affected)
                        self.finish(success: false)
                    }
                }
                self.onReady?()
            }
        }
        guard registered else { return }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title, subtitle: subtitle)
        // If the system cannot grant execution now, retain the existing safe
        // foreground path rather than pretending a queued request is running.
        request.strategy = .fail
        requested = true
        do {
            try BGTaskScheduler.shared.submit(request)
            setProtection(true)
        } catch {
            requested = false
            setProtection(false)
            NSLog("Download background processing could not start: %@", error.localizedDescription)
        }
    }

    func update(_ snapshots: [DownloadBackgroundProgress]) {
        guard requested || task != nil else { return }
        let tracked = snapshots.filter { ids.contains($0.id) }
        guard tracked.contains(where: \.pending) else {
            finish(success: tracked.count == ids.count && tracked.allSatisfy(\.succeeded))
            return
        }
        guard let task else { return }
        task.progress.totalUnitCount = Int64(ids.count) * 1_000
        task.progress.completedUnitCount = tracked.reduce(Int64(0)) { total, item in
            let fraction = item.succeeded ? 1 : (item.fraction.isFinite ? min(max(item.fraction, 0), 1) : 0)
            return total + Int64(fraction * 1_000)
        }
        task.updateTitle(task.title, subtitle: "\(Int(task.progress.fractionCompleted * 100))%")
    }

    private func finish(success: Bool) {
        if let task {
            task.expirationHandler = nil
            task.setTaskCompleted(success: success)
        } else if requested {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        }
        task = nil
        requested = false
        setProtection(false)
        ids.removeAll()
        onReady = nil
        onExpired = nil
    }
}
#endif
