import AppKit
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private enum MenuLayout {
        static let width: CGFloat = 360
    }

    private let model = AccountsModel()
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var menuContentItem: NSMenuItem?
    private var addCodexMenuItem: NSMenuItem?
    private var addClaudeMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
        configureStatusItem()
        Task {
            await LimitNotificationScheduler.shared.requestAuthorization()
            await model.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        menu?.cancelTracking()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.isVisible = true

        if let button = item.button {
            button.image = StatusIconFactory.makeImage()
            button.imagePosition = .imageOnly
            button.toolTip = "Limit Bar"
        }

        let rootView = MenuContentView()
            .environmentObject(model)
            .frame(width: MenuLayout.width)

        let hostingView = NSHostingView(rootView: rootView)
        let fittingHeight = hostingView.fittingSize.height
        hostingView.frame = NSRect(x: 0, y: 0, width: MenuLayout.width, height: fittingHeight)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        let contentItem = NSMenuItem()
        contentItem.view = hostingView

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(contentItem)
        menu.addItem(.separator())
        menu.addItem(makeAddAccountMenuItem())
        menu.addItem(.separator())
        menu.addItem(makeQuitMenuItem())
        menu.delegate = self
        item.menu = menu

        self.statusItem = item
        self.menu = menu
        self.menuContentItem = contentItem
    }

    private func makeAddAccountMenuItem() -> NSMenuItem {
        let addAccountMenu = NSMenu()

        let addCodex = NSMenuItem(
            title: "Add Codex",
            action: #selector(addCodexAccount(_:)),
            keyEquivalent: ""
        )
        addCodex.target = self
        addAccountMenu.addItem(addCodex)

        let addClaude = NSMenuItem(
            title: "Add Claude",
            action: #selector(addClaudeAccount(_:)),
            keyEquivalent: ""
        )
        addClaude.target = self
        addAccountMenu.addItem(addClaude)

        let addAccount = NSMenuItem(title: "Add account", action: nil, keyEquivalent: "")
        addAccount.submenu = addAccountMenu

        self.addCodexMenuItem = addCodex
        self.addClaudeMenuItem = addClaude
        return addAccount
    }

    private func makeQuitMenuItem() -> NSMenuItem {
        let quit = NSMenuItem(title: "Quit", action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self
        return quit
    }

    @objc private func addCodexAccount(_ sender: NSMenuItem) {
        guard model.pendingAdd == nil else { return }
        Task { await model.addCodexAccount() }
    }

    @objc private func addClaudeAccount(_ sender: NSMenuItem) {
        guard model.pendingAdd == nil else { return }
        Task { await model.addClaudeAccount() }
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(nil)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        let canAddAccount = model.pendingAdd == nil
        addCodexMenuItem?.isEnabled = canAddAccount
        addClaudeMenuItem?.isEnabled = canAddAccount

        if let hostingView = menuContentItem?.view {
            let fitting = hostingView.fittingSize
            hostingView.frame = NSRect(x: 0, y: 0, width: MenuLayout.width, height: fitting.height)
        }
    }
}
