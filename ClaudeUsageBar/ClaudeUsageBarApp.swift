import SwiftUI

@main
struct ClaudeUsageBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var usageManager = UsageManager()
    var popover: NSPopover!
    var rightClickMenu: NSMenu!

    static let appVersion = "1.0.3"

    var showValues: Bool {
        UserDefaults.standard.bool(forKey: "showValues")
    }

    var showLabels: Bool {
        UserDefaults.standard.bool(forKey: "showLabels")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
            updateStatusButton()
        }

        // Create right-click menu
        rightClickMenu = NSMenu()
        let versionItem = NSMenuItem(title: "Version \(AppDelegate.appVersion)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        rightClickMenu.addItem(versionItem)
        rightClickMenu.addItem(NSMenuItem.separator())
        rightClickMenu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: ""))

        // Create popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 240)
        popover.behavior = .transient
        let detailView = UsageDetailView(usageManager: usageManager) { [weak self] in
            self?.updateStatusButton()
            self?.popover.performClose(nil)
        }
        popover.contentViewController = NSHostingController(rootView: detailView)

        // Start fetching usage
        usageManager.onUpdate = { [weak self] in
            DispatchQueue.main.async {
                self?.updateStatusButton()
            }
        }
        usageManager.startPolling()
    }

    func updateStatusButton() {
        guard let button = statusItem.button else { return }

        let sessionStatus = usageManager.sessionStatus
        let weeklyStatus = usageManager.weeklyStatus

        // Determine icon color based on priority:
        // Red: either > 90%
        // Orange: week off track
        // Yellow: session off track (but week OK)
        // Green: both on track
        let icon: String
        if sessionStatus == .red || weeklyStatus == .red {
            icon = "🔴"
        } else if weeklyStatus == .orange {
            icon = "🟠"
        } else if sessionStatus == .orange {
            icon = "🟡"
        } else if sessionStatus == .unknown || weeklyStatus == .unknown {
            icon = "⚪"
        } else {
            icon = "🟢"
        }

        if let session = usageManager.sessionUsage, let weekly = usageManager.weeklyUsage {
            if showValues && showLabels {
                button.title = "\(icon) S: \(Int(session))% · W: \(Int(weekly))%"
            } else if showValues {
                button.title = "\(icon) \(Int(session))% · \(Int(weekly))%"
            } else {
                button.title = icon
            }
        } else if usageManager.isLoading {
            if showValues && showLabels {
                button.title = "\(icon) S: ... - W: ..."
            } else if showValues {
                button.title = "\(icon) ..."
            } else {
                button.title = icon
            }
        } else if usageManager.error != nil {
            button.title = "⚠️"
        } else {
            button.title = icon
        }
    }

    @objc func handleClick() {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            // Right-click: show menu
            if let button = statusItem.button {
                rightClickMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
            }
        } else {
            // Left-click: toggle popover
            togglePopover()
        }
    }

    func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                // Refresh when opening
                usageManager.fetchUsage()
            }
        }
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }

}
