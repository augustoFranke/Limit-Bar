import Foundation

/// Tunables for refresh cadence, login deadlines, and limit-window classification.
/// Pulled out of inline call sites so the cadence is reviewable in one place.
enum LimitBarConstants {
    /// How often the refresh scheduler fires.
    static let refreshInterval: TimeInterval = 60

    /// Minimum time between two consecutive refreshes of the same slot.
    /// Prevents the manual Refresh button from racing the auto-refresh tick.
    static let refreshDebounce: TimeInterval = 15

    /// Total time we wait for the user to complete an interactive Codex login.
    static let codexLoginDeadline: TimeInterval = 180

    /// How often we poll Codex's `account/read` while waiting for sign-in.
    static let codexLoginPollNanoseconds: UInt64 = 3 * 1_000_000_000

    /// Maximum time to wait for one Codex app-server JSON-RPC response.
    static let codexRequestTimeoutNanoseconds: UInt64 = 30 * 1_000_000_000

    /// Codex flags a 5-hour window with this `windowDurationMins` value.
    static let fiveHourWindowMinutes = 300

    /// Lower bound (inclusive) for "weekly" classification, in minutes.
    static let weeklyWindowMinutes = 7 * 24 * 60

    /// Minimum lead time before scheduling a reset notification.
    static let minNotificationLeadSeconds: TimeInterval = 5
}
