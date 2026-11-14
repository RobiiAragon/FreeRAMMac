import Foundation
import Darwin

@main
struct MemoryMetricsChecks {
    static func main() throws {
        let page: UInt64 = 16_384
        var sample = vm_statistics64_data_t()
        sample.free_count = 30
        sample.speculative_count = 10
        sample.external_page_count = 40 // Already includes the 10 speculative pages.
        sample.internal_page_count = 20
        sample.wire_count = 10
        sample.compressor_page_count = 5
        sample.total_uncompressed_pages_in_compressor = 15
        sample.purgeable_count = 8
        let snapshot = try MemoryReader.makeSnapshot(
            statistics: sample, pageSize: page, physicalBytes: 100 * page,
            swapUsedBytes: nil, pressure: .normal
        )
        require(snapshot.freeBytes == 20 * page, "Free excludes speculative file pages")
        require(snapshot.cachedBytes == 40 * page, "Cache must not count speculative pages twice")
        require(snapshot.usedBytes == 40 * page, "Residual is disjoint from cache and free")
        require(snapshot.estimatedAvailableBytes == 60 * page, "Purgeable is not added again")
        require(snapshot.compressedBytes == 5 * page, "Compression is physical storage, not logical size")
        require(snapshot.swapUsedBytes == nil, "Missing swap remains unavailable, not zero")

        var impossible = sample
        impossible.speculative_count = 31
        expectInvalid(impossible, pageSize: page, physicalBytes: 100 * page)
        impossible = sample
        impossible.external_page_count = 81
        expectInvalid(impossible, pageSize: page, physicalBytes: 100 * page)
        expectInvalid(sample, pageSize: UInt64.max, physicalBytes: UInt64.max)
        expectInvalid(sample, pageSize: 0, physicalBytes: 100 * page)

        require(MemoryReader.pressure(forDispatchLevel: 1) == .normal, "Dispatch normal is 1")
        require(MemoryReader.pressure(forDispatchLevel: 2) == .warning, "Dispatch warning is 2")
        require(MemoryReader.pressure(forDispatchLevel: 4) == .critical, "Dispatch critical is 4")
        require(MemoryReader.pressure(forDispatchLevel: 0) == .unknown, "Never confuse kernel enum with Dispatch flags")
        require(MemoryReader.pressure(forDispatchLevel: 3) == .unknown, "Unknown pressure flags remain unknown")

        for _ in 0..<5 {
            let live = try MemoryReader.read()
            require(live.physicalBytes == ProcessInfo.processInfo.physicalMemory, "Live physical RAM")
            require(live.freeBytes + live.cachedBytes + live.usedBytes == live.physicalBytes,
                    "Live disjoint categories sum to physical RAM")
            require(live.estimatedAvailableBytes <= live.physicalBytes, "Live estimated availability bounded by RAM")
            require(live.wiredBytes <= live.usedBytes, "Live wired memory belongs to used memory")
            require(live.compressedBytes <= live.usedBytes, "Live physical compressor belongs to used memory")
        }
        let live = try MemoryReader.read()
        print("PASS: accounting overlap, invalid samples, overflow, pressure mapping, 6 live reads")
        print("Live bytes: physical=\(live.physicalBytes), free=\(live.freeBytes), cached=\(live.cachedBytes), used=\(live.usedBytes), compressed=\(live.compressedBytes), swap=\(live.swapUsedBytes.map(String.init) ?? "unavailable"), pressure=\(live.pressure.rawValue)")
        for diagnostic in live.diagnostics { print("Diagnostic: \(diagnostic)") }
    }

    private static func require(_ condition: Bool, _ message: String) {
        precondition(condition, message)
    }

    private static func expectInvalid(_ statistics: vm_statistics64_data_t, pageSize: UInt64, physicalBytes: UInt64) {
        do {
            _ = try MemoryReader.makeSnapshot(statistics: statistics, pageSize: pageSize,
                                             physicalBytes: physicalBytes, swapUsedBytes: nil, pressure: .unknown)
            preconditionFailure("An invalid sample must not become valid-looking data")
        } catch MemoryReaderError.inconsistentStatistics {
            // Expected.
        } catch {
            preconditionFailure("Unexpected error: \(error)")
        }
    }
}
