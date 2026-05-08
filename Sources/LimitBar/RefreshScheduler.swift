import AppKit
import Foundation

/// Drives periodic and event-triggered refreshes for AccountsModel.
///
/// Owns: the recurring tick task and the wake-from-sleep observer.
/// Does not own slot state — the model passes closures for the per-slot
/// refresh and for fetching the current slot ID list at fan-out time.
@MainActor
final class RefreshScheduler {
    private let refreshSlot: @MainActor (Int, Bool) async -> Void
    private let slotIDs: @MainActor () -> [Int]

    private var tickTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    init(
        refreshSlot: @escaping @MainActor (Int, Bool) async -> Void,
        slotIDs: @escaping @MainActor () -> [Int]
    ) {
        self.refreshSlot = refreshSlot
        self.slotIDs = slotIDs
    }

    func start() {
        stop()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(LimitBarConstants.refreshInterval * 1_000_000_000))
                if Task.isCancelled { break }
                await self?.fanOut(force: false)
            }
        }

        let center = NSWorkspace.shared.notificationCenter
        wakeObserver = center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.fanOut(force: true)
            }
        }
    }

    func stop() {
        tickTask?.cancel()
        tickTask = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    func kick(force: Bool = true) async {
        await fanOut(force: force)
    }

    private func fanOut(force: Bool) async {
        let ids = slotIDs()
        await withTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask { @MainActor [refreshSlot] in
                    await refreshSlot(id, force)
                }
            }
        }
    }

    deinit {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        tickTask?.cancel()
    }
}
