import AppKit
import SwiftUI

@main
@MainActor
enum FreeRAMMacLauncher {
    static func main() {
        // This app has no main nib/storyboard to instantiate its delegate.
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover?
    private var helpWindow: NSWindow?
    private let idleImage = NSImage(systemSymbolName: "memorychip", accessibilityDescription: "Free RAM Mac")
    private let busyImage = NSImage(systemSymbolName: "memorychip.fill", accessibilityDescription: "Free RAM Mac")
    private let monitor = MemoryMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Fixed room for the chip and 100.0%; updates never shift adjacent items.
        statusItem = NSStatusBar.system.statusItem(withLength: 86)
        if let button = statusItem.button {
            idleImage?.isTemplate = true
            busyImage?.isTemplate = true
            button.image = idleImage
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            button.title = "—%"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Free RAM Mac · clic: recuperar memoria purgable · clic secundario: opciones"
            button.setAccessibilityLabel("Free RAM Mac")
            button.setAccessibilityHelp("Activar para recuperar memoria purgable. Clic secundario o Control-clic para opciones.")
        }
        monitor.onReadingChange = { [weak self] in self?.updateStatusReading() }
        monitor.onActionStateChange = { [weak self] _ in self?.updateStatusReading() }
        monitor.startUpdates()
        // Stay in the menu bar. Launching never opens a panel or starts recovery.
    }

    private func updateStatusReading() {
        guard let button = statusItem.button else { return }
        let value: String
        let reading: String
        if let error = monitor.readError {
            // A previous sample must not masquerade as a fresh percentage.
            value = "—%"
            reading = "Lectura no disponible: \(error)"
        } else if let snapshot = monitor.snapshot {
            value = MemoryFormat.usedPercentage(snapshot)
            reading = "RAM en uso estimada: \(value) de \(MemoryFormat.bytes(snapshot.physicalBytes)). Excluye caché de archivos; no equivale a toda la RAM recuperable."
        } else {
            value = "—%"
            reading = "Esperando lectura de RAM."
        }
        if button.title != value { button.title = value }
        // Busy state changes only the chip; the live measure stays legible.
        let image = monitor.isRecovering ? busyImage : idleImage
        if button.image !== image { button.image = image }
        button.appearsDisabled = false
        let action = monitor.isRecovering ? "Recuperando memoria descartable…" : monitor.actionMessage
        let tooltip = "Free RAM Mac · \(reading)\n\(action)\nClic: recuperar · clic secundario: detalles"
        if button.toolTip != tooltip { button.toolTip = tooltip }
        // Keep the control's name stable as the measurement changes.
        let accessibleValue = "\(reading) \(action)"
        if button.accessibilityValue() as? String != accessibleValue {
            button.setAccessibilityValue(accessibleValue)
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            recoverFromUserClick()
        }
    }

    @objc private func recoverFromUserClick() {
        // A primary click performs the action without activating the app or
        // opening a window. Details are available only from the secondary menu.
        popover?.performClose(nil)
        monitor.reclaimPurgeableMemory()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        return false
    }

    @objc private func showPopover() {
        guard let button = statusItem.button else { return }
        if popover == nil {
            let panel = NSPopover()
            panel.behavior = .transient
            panel.contentSize = NSSize(width: 420, height: 590)
            panel.delegate = self
            panel.contentViewController = NSHostingController(rootView: MenuBarView(
                monitor: monitor,
                recover: { [weak self] in self?.recoverFromUserClick() },
                showHelp: { [weak self] in self?.showHelp() }
            ))
            popover = panel
        }
        NSApp.activate(ignoringOtherApps: true)
        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func popoverDidShow(_ notification: Notification) {
        monitor.setDetailsVisible(true)
    }

    func popoverDidClose(_ notification: Notification) {
        monitor.setDetailsVisible(false)
    }

    private func showMenu() {
        popover?.performClose(nil)
        let menu = NSMenu(title: "Free RAM Mac")
        menu.autoenablesItems = false
        menu.addItem(menuItem("Ver detalles", action: #selector(showPopover)))
        menu.addItem(menuItem("Recuperar memoria purgable", action: #selector(recoverFromUserClick), enabled: !monitor.isRecovering))
        menu.addItem(.separator())
        menu.addItem(menuItem("Cómo funciona…", action: #selector(showHelp)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Salir de Free RAM Mac", action: #selector(quit), enabled: !monitor.isRecovering))
        if let button = statusItem.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY - 4), in: button)
        }
    }

    private func menuItem(_ title: String, action: Selector, enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        return item
    }

    @objc private func showHelp() {
        popover?.performClose(nil)
        if helpWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 590, height: 650),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Cómo funciona Free RAM Mac"
            window.contentViewController = NSHostingController(rootView: MemoryHelpView())
            window.isReleasedWhenClosed = false
            window.center()
            helpWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        helpWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        guard !monitor.isRecovering else { return }
        NSApp.terminate(nil)
    }
}
