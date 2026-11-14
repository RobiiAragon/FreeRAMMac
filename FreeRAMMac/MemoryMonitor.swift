import Combine
import Foundation

@MainActor
final class MemoryMonitor: ObservableObject {
    private(set) var snapshot: MemorySnapshot?
    @Published private(set) var readError: String?
    @Published private(set) var actionMessage = "Listo para recuperar memoria purgable"
    @Published private(set) var actionIsError = false
    @Published private(set) var isRecovering = false
    var onActionStateChange: ((Bool) -> Void)?
    var onReadingChange: (() -> Void)?
    private var timer: Timer?
    private var detailsVisible = false
    private let recovery = RecoveryService()

    func startUpdates() {
        guard timer == nil else { return }
        refresh()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            // Installed only on the main run loop. Read directly so menu
            // tracking does not defer a queued task or accumulate stale work.
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.25
        self.timer = timer
        // Keep the reading current even while a secondary menu is tracking.
        RunLoop.main.add(timer, forMode: .common)
    }

    func refresh() {
        do {
            let reading = try MemoryReader.read(includeDetails: detailsVisible)
            // The status item has its own callback. Only an open details view
            // needs a SwiftUI invalidation for each new snapshot.
            if detailsVisible { objectWillChange.send() }
            snapshot = reading
            if readError != nil { readError = nil }
        } catch {
            let message = error.localizedDescription
            if readError != message { readError = message }
        }
        onReadingChange?()
    }

    func setDetailsVisible(_ visible: Bool) {
        guard detailsVisible != visible else { return }
        detailsVisible = visible
        if visible { refresh() }
    }

    func reclaimPurgeableMemory() {
        guard !isRecovering else { return }
        isRecovering = true
        actionIsError = false
        actionMessage = "Recuperando memoria descartable…"
        refresh()
        onActionStateChange?(true)
        Task {
            defer {
                isRecovering = false
                refresh()
                onActionStateChange?(false)
            }
            do {
                try await recovery.reclaimPurgeableMemory()
                actionMessage = "Solicitud completada"
            } catch {
                actionIsError = true
                actionMessage = error.localizedDescription
            }
        }
    }
}

enum MemoryFormat {
    static func usedPercentage(_ snapshot: MemorySnapshot) -> String {
        number(snapshot.usedFraction * 100, digits: 1) + "%"
    }

    static func bytes(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        if value >= 1_000_000_000 {
            return number(value / 1_000_000_000, digits: 2) + " GB"
        }
        return number(value / 1_000_000, digits: value >= 10_000_000 ? 0 : 1) + " MB"
    }

    static func number(_ value: Double, digits: Int) -> String {
        value.formatted(.number.locale(Locale(identifier: "es_MX")).precision(.fractionLength(digits)))
    }
}
