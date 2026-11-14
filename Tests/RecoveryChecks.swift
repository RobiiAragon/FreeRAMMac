import Foundation
import Darwin

/// An integration check of actual discardable-memory recovery without admin.
/// Allocates one purgeable and one ordinary VM page, never creates pressure, and
/// does not use vfs purge, shell scripts, process controls, or private task ports.
@main
struct RecoveryChecks {
    static func main() async throws {
        try expect(geteuid() != 0, "Check runs as an ordinary user, without root")
        let pageSize = mach_vm_size_t(sysconf(_SC_PAGESIZE))
        var address: mach_vm_address_t = 0
        let allocation = mach_vm_allocate(
            mach_task_self_, &address, pageSize, VM_FLAGS_ANYWHERE | VM_FLAGS_PURGABLE
        )
        try expect(allocation == KERN_SUCCESS, "One purgeable VM page allocated (\(pageSize) bytes)")
        defer { _ = mach_vm_deallocate(mach_task_self_, address, pageSize) }

        guard let page = UnsafeMutableRawPointer(bitPattern: UInt(address)) else {
            throw CheckFailure(message: "Allocated page address is invalid")
        }
        page.initializeMemory(as: UInt8.self, repeating: 0xA5, count: Int(pageSize))
        var state = Int32(VM_PURGABLE_VOLATILE)
        let markVolatile = mach_vm_purgable_control(
            mach_task_self_, address, vm_purgable_t(VM_PURGABLE_SET_STATE), &state
        )
        try expect(markVolatile == KERN_SUCCESS, "Own page explicitly marked VOLATILE")

        // A separate kernel allocation prevents an optimized build from replacing
        // an ordinary-memory assertion with a compile-time constant array check.
        var ordinaryAddress: mach_vm_address_t = 0
        let ordinaryAllocation = mach_vm_allocate(
            mach_task_self_, &ordinaryAddress, pageSize, VM_FLAGS_ANYWHERE
        )
        try expect(ordinaryAllocation == KERN_SUCCESS, "One ordinary VM page allocated without PURGABLE")
        defer { _ = mach_vm_deallocate(mach_task_self_, ordinaryAddress, pageSize) }
        guard let ordinaryPage = UnsafeMutableRawPointer(bitPattern: UInt(ordinaryAddress)) else {
            throw CheckFailure(message: "Ordinary page address is invalid")
        }
        ordinaryPage.initializeMemory(as: UInt8.self, repeating: 0x5A, count: Int(pageSize))

        try await RecoveryService().reclaimPurgeableMemory()
        print("PASS: Global purgeable-memory request accepted without administrator authorization")

        state = 0
        let inspect = mach_vm_purgable_control(
            mach_task_self_, address, vm_purgable_t(VM_PURGABLE_GET_STATE), &state
        )
        try expect(inspect == KERN_SUCCESS, "Own purgeable page state can be queried")
        try expect(state & Int32(VM_PURGABLE_STATE_MASK) == Int32(VM_PURGABLE_EMPTY), "Previously VOLATILE page is EMPTY after recovery")

        state = Int32(VM_PURGABLE_NONVOLATILE)
        let lockContent = mach_vm_purgable_control(
            mach_task_self_, address, vm_purgable_t(VM_PURGABLE_SET_STATE), &state
        )
        try expect(lockContent == KERN_SUCCESS, "Content access restored before reading own page")
        try expect(page.load(as: UInt8.self) == 0, "Discarded page has demand-zero contents")
        let ordinaryContents = UnsafeRawBufferPointer(start: ordinaryPage, count: Int(pageSize))
        try expect(ordinaryContents.allSatisfy { $0 == 0x5A }, "Every byte of ordinary private VM page remains intact")

        print("All recovery checks passed. No elevated privileges or disk-cache purge used.")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CheckFailure(message: message) }
        print("PASS: \(message)")
    }

    private struct CheckFailure: Error {
        let message: String
    }
}
