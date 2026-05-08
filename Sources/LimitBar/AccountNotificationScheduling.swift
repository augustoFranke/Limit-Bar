import Foundation

protocol AccountNotificationScheduling {
    func scheduleResetNotifications(
        accountIndex: Int,
        provider: AccountProvider,
        email: String,
        fiveHour: LimitWindow?,
        weekly: LimitWindow?
    ) async

    func cancelNotifications(accountIndex: Int) async
}

extension LimitNotificationScheduler: AccountNotificationScheduling {}
