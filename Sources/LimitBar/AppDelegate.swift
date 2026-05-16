import AppKit
import Combine
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private enum MenuLayout {
        static let width: CGFloat = 285
    }

    private let model = AccountsModel()
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var menuContentItem: NSMenuItem?
    private var refreshAllMenuItem: NSMenuItem?
    private var addCodexMenuItem: NSMenuItem?
    private var addClaudeMenuItem: NSMenuItem?
    private var modelCancellable: AnyCancellable?

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
        hostingView.sizingOptions = [.intrinsicContentSize]
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

        let refreshAll = NSMenuItem(
            title: "Refresh All",
            action: #selector(refreshAll(_:)),
            keyEquivalent: "r"
        )
        refreshAll.keyEquivalentModifierMask = [.command]
        refreshAll.target = self
        menu.addItem(refreshAll)

        menu.addItem(.separator())

        let addCodex = NSMenuItem(
            title: "Add Codex Account…",
            action: #selector(addCodexAccount(_:)),
            keyEquivalent: ""
        )
        addCodex.target = self
        menu.addItem(addCodex)

        let addClaude = NSMenuItem(
            title: "Add Claude Account…",
            action: #selector(addClaudeAccount(_:)),
            keyEquivalent: ""
        )
        addClaude.target = self
        menu.addItem(addClaude)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit Limit Bar",
            action: #selector(quit(_:)),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        menu.delegate = self
        item.menu = menu

        self.statusItem = item
        self.menu = menu
        self.menuContentItem = contentItem
        self.refreshAllMenuItem = refreshAll
        self.addCodexMenuItem = addCodex
        self.addClaudeMenuItem = addClaude

        modelCancellable = model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.resizeMenuContentToFit()
            }
    }

    /// Resize the SwiftUI-hosted menu item to its current intrinsic height so
    /// that adding/removing accounts (or other content changes) updates the
    /// open menu's bounds immediately, instead of staying clamped to the size
    /// captured when the menu last opened.
    private func resizeMenuContentToFit() {
        guard let hostingView = menuContentItem?.view else { return }
        let fitting = hostingView.fittingSize
        guard fitting.height > 0,
              abs(hostingView.frame.height - fitting.height) > 0.5 else { return }
        hostingView.frame = NSRect(x: 0, y: 0, width: MenuLayout.width, height: fitting.height)
    }

    @objc private func refreshAll(_ sender: NSMenuItem) {
        Task { await model.refreshAll() }
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
        Task { await model.refreshOnMenuOpen() }

        let canAddAccount = model.pendingAdd == nil
        addCodexMenuItem?.isEnabled = canAddAccount
        addClaudeMenuItem?.isEnabled = canAddAccount
        refreshAllMenuItem?.isEnabled = !model.slots.isEmpty && !model.isRefreshing

        resizeMenuContentToFit()
    }
}
