import Foundation
import os
import UserNotifications

actor LimitNotificationScheduler {
    static let shared = LimitNotificationScheduler()

    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            Log.notifications.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func scheduleResetNotifications(
        accountIndex: Int,
        provider: AccountProvider,
        email: String,
        fiveHour: LimitWindow?,
        weekly: LimitWindow?
    ) async {
        await schedule(window: fiveHour, kind: .fiveHour, accountIndex: accountIndex, provider: provider, email: email)
        await schedule(window: weekly, kind: .weekly, accountIndex: accountIndex, provider: provider, email: email)
    }

    func cancelNotifications(accountIndex: Int) async {
        center.removePendingNotificationRequests(withIdentifiers: LimitResetKind.allCases.map { identifier(accountIndex: accountIndex, kind: $0) })
    }

    private func schedule(
        window: LimitWindow?,
        kind: LimitResetKind,
        accountIndex: Int,
        provider: AccountProvider,
        email: String
    ) async {
        let requestID = identifier(accountIndex: accountIndex, kind: kind)
        guard let resetDate = window?.resetsAt,
              resetDate.timeIntervalSinceNow > LimitBarConstants.minNotificationLeadSeconds else {
            center.removePendingNotificationRequests(withIdentifiers: [requestID])
            return
        }

        let content = UNMutableNotificationContent()
        content.title = kind.title(provider: provider)
        content.body = "\(email) reset at \(Self.formatter.string(from: resetDate))."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: resetDate),
            repeats: false
        )

        let request = UNNotificationRequest(identifier: requestID, content: content, trigger: trigger)
        do {
            try await center.add(request)
        } catch {
            Log.notifications.error("Failed to schedule \(kind.rawValue, privacy: .public) notification for account \(accountIndex): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func identifier(accountIndex: Int, kind: LimitResetKind) -> String {
        "limitbar.account.\(accountIndex).\(kind.rawValue).reset"
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private enum LimitResetKind: String, CaseIterable {
    case fiveHour
    case weekly

    func title(provider: AccountProvider) -> String {
        switch self {
        case .fiveHour: "5-hour \(provider.displayName) limit reset"
        case .weekly: "Weekly \(provider.displayName) limit reset"
        }
    }
}
