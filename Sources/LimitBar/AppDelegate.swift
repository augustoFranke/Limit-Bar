import AppKit
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let model = AccountsModel()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?

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
        popover?.performClose(nil)
        stopOutsideClickMonitoring()
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
            button.target = self
            button.action = #selector(togglePopover(_:))
        }

        let rootView = MenuContentView()
            .environmentObject(model)
            .frame(width: 360, height: 500)

        let hostingController = NSHostingController(rootView: rootView)
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 360, height: 500)

        let popover = NSPopover()
        popover.contentViewController = hostingController
        popover.contentSize = NSSize(width: 360, height: 500)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        self.statusItem = item
        self.popover = popover
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            closePopover(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            startOutsideClickMonitoring()
        }
    }

    private func closePopover(_ sender: AnyObject?) {
        popover?.performClose(sender)
        stopOutsideClickMonitoring()
    }

    private func startOutsideClickMonitoring() {
        stopOutsideClickMonitoring()

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            return self.handleLocalMouseDown(event)
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.closePopover(nil)
            }
        }
    }

    private func stopOutsideClickMonitoring() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }

    private func handleLocalMouseDown(_ event: NSEvent) -> NSEvent? {
        guard popover?.isShown == true else { return event }
        if event.window == popover?.contentViewController?.view.window {
            return event
        }
        closePopover(nil)
        return clickIsInStatusItem(event) ? nil : event
    }

    private func clickIsInStatusItem(_ event: NSEvent) -> Bool {
        guard let button = statusItem?.button,
              event.window == button.window else {
            return false
        }
        let point = button.convert(event.locationInWindow, from: nil)
        return button.bounds.contains(point)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

extension AppDelegate: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        stopOutsideClickMonitoring()
    }
}
