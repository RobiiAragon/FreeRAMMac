import Foundation
import Darwin

enum RecoveryError: LocalizedError, Sendable {
    case operationInProgress
    case cancelled
    case kernelFailure(Int32)

    var errorDescription: String? {
        switch self {
        case .operationInProgress:
            return "Ya hay una solicitud de recuperación en curso."
        case .cancelled:
            return "La recuperación se canceló antes de iniciarse."
        case .kernelFailure(let code):
            let detail = String(cString: mach_error_string(code))
            return "macOS no aceptó la recuperación de memoria descartable (\(code): \(detail))."
        }
    }
}

/// Requests the kernel's global purge of volatile purgeable VM objects. These are
/// objects their owners explicitly declared discardable. This does not target a
/// process, ordinary private memory, all file cache, or the swap subsystem.
actor RecoveryService {
    // This public Mach API and control are provided by every macOS version in
    // the project's deployment range. Runtime denial is reported as an error.
    nonisolated static let isAvailable = true
    private var isRunning = false

    /// Called only after a deliberate user action. KERN_SUCCESS confirms the
    /// request, not a number of bytes freed. No root/helper/shell/large allocation.
    /// After launch the Mach call is allowed to finish; task cancellation cannot
    /// reverse a kernel operation or safely interrupt it.
    func reclaimPurgeableMemory() async throws {
        guard !isRunning else { throw RecoveryError.operationInProgress }
        guard !Task.isCancelled else { throw RecoveryError.cancelled }
        isRunning = true
        defer { isRunning = false }

        let code = await Task.detached(priority: .userInitiated) {
            var state: Int32 = 0
            return mach_vm_purgable_control(
                mach_task_self_, 0, vm_purgable_t(VM_PURGABLE_PURGE_ALL), &state
            )
        }.value
        guard code == KERN_SUCCESS else { throw RecoveryError.kernelFailure(code) }
    }
}
