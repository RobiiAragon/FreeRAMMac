import Foundation
import Darwin
import Dispatch

enum MemoryPressure: String, CaseIterable, Sendable {
    case normal
    case warning
    case critical
    case unknown
}

/// `freeBytes + cachedBytes + usedBytes == physicalBytes`.
/// Wired, compressed, anonymous and purgeable counters are details, not extra slices.
struct MemorySnapshot: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let physicalBytes: UInt64
    /// Truly free pages, excluding speculative file pages.
    let freeBytes: UInt64
    /// Resident file-backed pages, including speculative pages. A reclaimability estimate.
    let cachedBytes: UInt64
    /// Physical memory outside the two categories above; not an exact app-memory total.
    let usedBytes: UInt64
    let wiredBytes: UInt64
    /// Physical RAM occupied by the compressor, not its uncompressed logical contents.
    let compressedBytes: UInt64
    /// Informational overlapping counter. Do not add this to cached or free memory.
    let purgeableBytes: UInt64
    let anonymousBytes: UInt64
    /// Disk space used by swap. It is not RAM and is never added to the RAM chart.
    let swapUsedBytes: UInt64?
    let pressure: MemoryPressure
    /// Missing optional metrics or inconsistent sampling must remain visible to the UI.
    let diagnostics: [String]

    var estimatedAvailableBytes: UInt64 { freeBytes + cachedBytes }
    var usedFraction: Double { Double(usedBytes) / Double(physicalBytes) }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        physicalBytes: UInt64,
        freeBytes: UInt64,
        cachedBytes: UInt64,
        usedBytes: UInt64,
        wiredBytes: UInt64,
        compressedBytes: UInt64,
        purgeableBytes: UInt64,
        anonymousBytes: UInt64 = 0,
        swapUsedBytes: UInt64?,
        pressure: MemoryPressure,
        diagnostics: [String] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.physicalBytes = physicalBytes
        self.freeBytes = freeBytes
        self.cachedBytes = cachedBytes
        self.usedBytes = usedBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.purgeableBytes = purgeableBytes
        self.anonymousBytes = anonymousBytes
        self.swapUsedBytes = swapUsedBytes
        self.pressure = pressure
        self.diagnostics = diagnostics
    }
}

enum MemoryReaderError: LocalizedError {
    case mach(operation: String, code: kern_return_t)
    case incompleteStatistics
    case inconsistentStatistics

    var errorDescription: String? {
        switch self {
        case let .mach(operation, code):
            let detail = mach_error_string(code).map { String(cString: $0) } ?? "código \(code)"
            return "No se pudo leer la memoria (\(operation): \(detail))."
        case .incompleteStatistics:
            return "macOS devolvió contadores de memoria incompletos."
        case .inconsistentStatistics:
            return "Los contadores de memoria cambiaron durante la lectura. Vuelve a actualizar."
        }
    }
}

/// Read-only access. No allocation tricks, private pressure triggers or privileged calls.
enum MemoryReader {
    static func read(includeDetails: Bool = true) throws -> MemorySnapshot {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }

        var pageSize: vm_size_t = 0
        let pageResult = host_page_size(host, &pageSize)
        guard pageResult == KERN_SUCCESS else {
            throw MemoryReaderError.mach(operation: "host_page_size", code: pageResult)
        }

        var statistics = vm_statistics64_data_t()
        let capacity = MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        var count = mach_msg_type_number_t(capacity)
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            throw MemoryReaderError.mach(operation: "host_statistics64", code: result)
        }

        // Only revision 1 fields are needed, so SDK additions in newer macOS releases
        // do not make this reader depend on the newest kernel struct revision.
        let revision1Bytes = MemoryLayout<vm_statistics64_data_t>.offset(
            of: \.total_uncompressed_pages_in_compressor
        )! + MemoryLayout<UInt64>.size
        guard Int(count) * MemoryLayout<integer_t>.size >= revision1Bytes else {
            throw MemoryReaderError.incompleteStatistics
        }

        var diagnostics: [String] = []
        // The menu-bar percentage only needs the VM counters. Optional sysctls
        // are sampled while the details panel is visible.
        let swap = includeDetails ? readSwap(diagnostics: &diagnostics) : nil
        let pressure = includeDetails ? readPressure(diagnostics: &diagnostics) : .unknown
        return try makeSnapshot(
            statistics: statistics,
            pageSize: UInt64(pageSize),
            physicalBytes: ProcessInfo.processInfo.physicalMemory,
            swapUsedBytes: swap,
            pressure: pressure,
            diagnostics: diagnostics
        )
    }

    /// Kept separate from I/O so counter overlap and invalid samples can be checked.
    static func makeSnapshot(
        statistics: vm_statistics64_data_t,
        pageSize: UInt64,
        physicalBytes: UInt64,
        swapUsedBytes: UInt64?,
        pressure: MemoryPressure,
        diagnostics: [String] = []
    ) throws -> MemorySnapshot {
        let freePages = UInt64(statistics.free_count)
        let speculativePages = UInt64(statistics.speculative_count)
        guard pageSize > 0, physicalBytes > 0, freePages >= speculativePages else {
            throw MemoryReaderError.inconsistentStatistics
        }

        func bytes(_ pages: UInt64) throws -> UInt64 {
            let result = pages.multipliedReportingOverflow(by: pageSize)
            guard !result.overflow, result.partialValue <= physicalBytes else {
                throw MemoryReaderError.inconsistentStatistics
            }
            return result.partialValue
        }

        // Apple XNU host.c includes speculative pages in free_count. XNU
        // vm_page_speculate() also increments vm_page_pageable_external_count,
        // which host.c exports as external_page_count. Subtract them from free
        // and count external pages once. Adding speculative to external is wrong.
        let free = try bytes(freePages - speculativePages)
        let cached = try bytes(UInt64(statistics.external_page_count))
        guard cached <= physicalBytes - free else {
            // Counters are sampled without a global VM lock. An inconsistent sample
            // is an error, rather than silently clamping it into an invented result.
            throw MemoryReaderError.inconsistentStatistics
        }
        return MemorySnapshot(
            physicalBytes: physicalBytes,
            freeBytes: free,
            cachedBytes: cached,
            usedBytes: physicalBytes - free - cached,
            wiredBytes: try bytes(UInt64(statistics.wire_count)),
            compressedBytes: try bytes(UInt64(statistics.compressor_page_count)),
            purgeableBytes: try bytes(UInt64(statistics.purgeable_count)),
            anonymousBytes: try bytes(UInt64(statistics.internal_page_count)),
            swapUsedBytes: swapUsedBytes,
            pressure: pressure,
            diagnostics: diagnostics
        )
    }

    private static func readSwap(diagnostics: inout [String]) -> UInt64? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let result = sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
        guard result == 0, size == MemoryLayout<xsw_usage>.size else {
            diagnostics.append("Swap no disponible (vm.swapusage: \(systemError(result))).")
            return nil
        }
        return usage.xsu_used
    }

    private static func readPressure(diagnostics: inout [String]) -> MemoryPressure {
        var level: UInt32 = 0
        var size = MemoryLayout<UInt32>.size
        let result = sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        guard result == 0, size == MemoryLayout<UInt32>.size else {
            diagnostics.append("Presión no disponible (kern.memorystatus_vm_pressure_level: \(systemError(result))).")
            return .unknown
        }
        let pressure = pressure(forDispatchLevel: level)
        if pressure == .unknown {
            diagnostics.append("macOS devolvió un nivel de presión desconocido (\(level)).")
        }
        return pressure
    }

    static func pressure(forDispatchLevel level: UInt32) -> MemoryPressure {
        // This sysctl exports DISPATCH_MEMORYPRESSURE_* flags (1, 2, 4),
        // NOT the kernel's internal kVMPressure enum (0, 1, 2, 3).
        switch level {
        case UInt32(DispatchSource.MemoryPressureEvent.normal.rawValue): return .normal
        case UInt32(DispatchSource.MemoryPressureEvent.warning.rawValue): return .warning
        case UInt32(DispatchSource.MemoryPressureEvent.critical.rawValue): return .critical
        default: return .unknown
        }
    }

    private static func systemError(_ result: Int32) -> String {
        result == 0 ? "tamaño inesperado" : String(cString: strerror(errno))
    }
}
