import Foundation
import Darwin

/// Run only when no UI recovery fixture is active. Parent allocates two pages;
/// its own newly spawned CLI child invokes the production service exactly once.
/// No other application is started, stopped, signalled, or controlled.
@main
struct CrossProcessRecoveryChecks {
    static func main() async throws {
        guard geteuid() != 0 else { throw CheckFailure("Must run without root") }
        if CommandLine.arguments.dropFirst() == ["--reclaim-as-owned-child"] {
            try await RecoveryService().reclaimPurgeableMemory()
            print("CHILD SUCCESS: RecoveryService returned KERN_SUCCESS; uid=\(geteuid()) pid=\(getpid())")
            return
        }
        guard CommandLine.arguments.count == 1 else { throw CheckFailure("Unexpected arguments") }
        try runParentCheck()
    }

    private static func runParentCheck() throws {
        let size = sysconf(_SC_PAGESIZE)
        guard size > 0 else { throw CheckFailure("Cannot determine VM page size") }
        let pageSize = mach_vm_size_t(size)
        var volatileAddress: mach_vm_address_t = 0
        var normalAddress: mach_vm_address_t = 0
        try requireSuccess(mach_vm_allocate(
            mach_task_self_, &volatileAddress, pageSize, VM_FLAGS_ANYWHERE | VM_FLAGS_PURGABLE
        ), "Allocate parent's purgeable page")
        defer { _ = mach_vm_deallocate(mach_task_self_, volatileAddress, pageSize) }
        try requireSuccess(mach_vm_allocate(
            mach_task_self_, &normalAddress, pageSize, VM_FLAGS_ANYWHERE
        ), "Allocate parent's ordinary page")
        defer { _ = mach_vm_deallocate(mach_task_self_, normalAddress, pageSize) }
        guard let volatilePage = UnsafeMutableRawPointer(bitPattern: UInt(volatileAddress)),
              let normalPage = UnsafeMutableRawPointer(bitPattern: UInt(normalAddress)) else {
            throw CheckFailure("Allocated VM address was invalid")
        }
        volatilePage.initializeMemory(as: UInt8.self, repeating: 0xA5, count: Int(pageSize))
        normalPage.initializeMemory(as: UInt8.self, repeating: 0x5A, count: Int(pageSize))
        var state = Int32(VM_PURGABLE_VOLATILE)
        try requireSuccess(mach_vm_purgable_control(
            mach_task_self_, volatileAddress, vm_purgable_t(VM_PURGABLE_SET_STATE), &state
        ), "Mark parent's page VOLATILE")
        let before = try queryState(volatileAddress)
        guard before == Int32(VM_PURGABLE_VOLATILE) else {
            throw CheckFailure("Parent page was not VOLATILE immediately before child launch: \(before)")
        }
        print("PARENT BEFORE: uid=\(geteuid()) pid=\(getpid()); purgeable state=\(before) VOLATILE; total fixture=\(pageSize * 2) bytes")

        let child = Process()
        let output = Pipe()
        let errors = Pipe()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        child.arguments = ["--reclaim-as-owned-child"]
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = output
        child.standardError = errors
        try child.run()
        guard child.processIdentifier != getpid() else { throw CheckFailure("Child PID must differ from parent") }
        child.waitUntilExit()
        let childOutput = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let childErrors = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        print(childOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        guard child.terminationReason == .exit, child.terminationStatus == 0 else {
            throw CheckFailure("Owned child failed with status \(child.terminationStatus): \(childErrors)")
        }

        let after = try queryState(volatileAddress)
        print("PARENT AFTER: purgeable state=\(after) (EMPTY=2 expected), own child pid=\(child.processIdentifier)")
        guard after == Int32(VM_PURGABLE_EMPTY) else {
            throw CheckFailure("Cross-process recovery did not empty parent's volatile page: \(after)")
        }
        let contents = UnsafeRawBufferPointer(start: normalPage, count: Int(pageSize))
        guard contents.allSatisfy({ $0 == 0x5A }) else {
            throw CheckFailure("Parent's ordinary page contents changed")
        }
        print("PASS: Production RecoveryService in independent owned child empties parent's VOLATILE page; ordinary private page intact. Global cross-process effect confirmed without root.")
    }

    private static func queryState(_ address: mach_vm_address_t) throws -> Int32 {
        var state: Int32 = 0
        try requireSuccess(mach_vm_purgable_control(
            mach_task_self_, address, vm_purgable_t(VM_PURGABLE_GET_STATE), &state
        ), "Read parent's purgeable state")
        return state & Int32(VM_PURGABLE_STATE_MASK)
    }

    private static func requireSuccess(_ code: kern_return_t, _ operation: String) throws {
        guard code == KERN_SUCCESS else { throw CheckFailure("\(operation) failed: \(code)") }
    }

    private struct CheckFailure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
