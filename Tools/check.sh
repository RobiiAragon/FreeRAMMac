#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p Build/Checks
xcrun swiftc -swift-version 6 -strict-concurrency=complete -O FreeRAMMac/MemoryMetrics.swift Tests/MemoryMetricsChecks.swift -o Build/Checks/MemoryMetricsChecks
Build/Checks/MemoryMetricsChecks
xcrun swiftc -swift-version 6 -strict-concurrency=complete -O FreeRAMMac/RecoveryService.swift Tests/RecoveryChecks.swift -o Build/Checks/RecoveryChecks
Build/Checks/RecoveryChecks
