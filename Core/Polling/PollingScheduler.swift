import Foundation

/// Owns the app's periodic work from one main-run-loop timer.
///
/// Jobs are keyed so repeated feature starts replace the existing job instead
/// of silently creating another polling loop. Actions run serially on the
/// main actor; feature code remains responsible for guarding async work that
/// can outlive the callback.
@MainActor
final class PollingScheduler {
    private struct Job {
        var interval: TimeInterval
        var lastRun: Date?
        let action: () -> Void
    }

    private var jobs: [String: Job] = [:]
    private var timer: Timer?
    private let tickInterval: TimeInterval = 0.25

    var registeredJobIDs: Set<String> {
        Set(jobs.keys)
    }

    func register(
        id: String,
        interval: TimeInterval,
        action: @escaping () -> Void
    ) {
        let safeInterval = max(0.1, interval)
        if let existing = jobs[id] {
            jobs[id] = Job(interval: safeInterval, lastRun: existing.lastRun, action: action)
        } else {
            jobs[id] = Job(interval: safeInterval, lastRun: nil, action: action)
        }
        startIfNeeded()
    }

    func unregister(id: String) {
        jobs.removeValue(forKey: id)
        if jobs.isEmpty {
            stop()
        }
    }

    func startIfNeeded() {
        guard timer == nil else { return }

        let nextTimer = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.fireDueJobs()
            }
        }
        timer = nextTimer
        RunLoop.main.add(nextTimer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        jobs.removeAll()
    }

    private func fireDueJobs(now: Date = Date()) {
        let jobIDs = Array(jobs.keys)
        for id in jobIDs {
            guard var job = jobs[id] else { continue }
            if let lastRun = job.lastRun,
               now.timeIntervalSince(lastRun) < job.interval {
                continue
            }

            // Mark the job before invoking user code. This prevents a nested
            // refresh from making the same job re-entrant.
            job.lastRun = now
            jobs[id] = job
            job.action()
        }
    }

    deinit {
        timer?.invalidate()
    }
}
