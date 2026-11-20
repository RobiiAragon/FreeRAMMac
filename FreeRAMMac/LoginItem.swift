import Foundation
import ServiceManagement

/// What the menu shows for "Abrir al iniciar sesión". Kept free of AppKit so the
/// mapping can be checked by a standalone executable (Tests/LoginItemChecks.swift).
enum LoginItemState: Equatable, Sendable {
    case disabled
    case enabled
    /// Registered, but the user must allow it in System Settings → Login Items.
    case requiresApproval
    /// macOS could not find the app bundle (e.g. running from a translocated path).
    case unavailable

    init(_ status: SMAppService.Status) {
        switch status {
        case .enabled: self = .enabled
        case .requiresApproval: self = .requiresApproval
        case .notRegistered: self = .disabled
        case .notFound: self = .unavailable
        @unknown default: self = .unavailable
        }
    }

    var isChecked: Bool { self == .enabled || self == .requiresApproval }

    var menuTitle: String {
        switch self {
        case .requiresApproval: return "Abrir al iniciar sesión (pendiente de aprobación)"
        default: return "Abrir al iniciar sesión"
        }
    }

    /// The toggle the menu item performs from this state.
    var nextEnabled: Bool { !isChecked }
}

/// Opt-in launch at login through `SMAppService.mainApp` (macOS 13+). Nothing is
/// registered unless the user picks the menu item; there is no helper or daemon.
@MainActor
final class LoginItem {
    private let service = SMAppService.mainApp

    var state: LoginItemState { LoginItemState(service.status) }

    /// Returns the resulting state; throws the ServiceManagement error as-is.
    @discardableResult
    func setEnabled(_ enabled: Bool) throws -> LoginItemState {
        if enabled {
            if service.status != .enabled { try service.register() }
        } else if service.status != .notRegistered {
            try service.unregister()
        }
        return state
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
