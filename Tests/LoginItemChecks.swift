import Foundation
import ServiceManagement

/// Checks the login-item state mapping without registering anything.
@main
struct LoginItemChecks {
    @MainActor
    static func main() throws {
        try expect(LoginItemState(.notRegistered) == .disabled, "Not registered maps to disabled")
        try expect(LoginItemState(.enabled) == .enabled, "Enabled maps to enabled")
        try expect(LoginItemState(.requiresApproval) == .requiresApproval, "Requires approval is surfaced")
        try expect(LoginItemState(.notFound) == .unavailable, "Missing bundle maps to unavailable")

        try expect(!LoginItemState.disabled.isChecked && LoginItemState.disabled.nextEnabled, "Disabled: unchecked, click enables")
        try expect(LoginItemState.enabled.isChecked && !LoginItemState.enabled.nextEnabled, "Enabled: checked, click disables")
        try expect(LoginItemState.requiresApproval.isChecked && !LoginItemState.requiresApproval.nextEnabled,
                   "Pending approval: checked so a click can withdraw the request")
        try expect(LoginItemState.requiresApproval.menuTitle.contains("pendiente"), "Pending approval is explained in the menu")
        // Reading the status of a bare executable must not register it.
        _ = LoginItem().state
        print("All login item checks passed. Nothing was registered.")
    }

    static func expect(_ condition: Bool, _ message: String) throws {
        guard condition else {
            print("FAIL: \(message)")
            throw CheckFailure(message: message)
        }
        print("PASS: \(message)")
    }
}

struct CheckFailure: Error { let message: String }
