import Foundation

// MARK: - Codex JSON-RPC DTOs

struct RateLimitResponse: Decodable {
    let rateLimits: RateLimitSnapshot
    let rateLimitsByLimitId: [String: RateLimitSnapshot]?

    var codexSnapshot: RateLimitSnapshot {
        rateLimitsByLimitId?["codex"] ?? rateLimits
    }
}

struct RateLimitSnapshot: Decodable {
    let limitId: String?
    let limitName: String?
    let primary: RateLimitWindowPayload?
    let secondary: RateLimitWindowPayload?
    let planType: String?
    let rateLimitReachedType: String?

    /// Maps Codex's primary/secondary windows to the domain's weekly/5-hour split.
    /// A window only lands in `fiveHour` if its `windowDurationMins` matches
    /// `fiveHourWindowMinutes`; only in `weekly` if it meets `weeklyWindowMinutes`.
    /// This is stricter than picking "the first window" (which mislabeled the
    /// secondary window if both happened to be of the same kind).
    var limitWindows: (weekly: LimitWindow?, fiveHour: LimitWindow?) {
        let windows = [primary, secondary].compactMap { $0?.limitWindow }
        let fiveHour = windows.first { $0.windowMinutes == LimitBarConstants.fiveHourWindowMinutes }
        let weekly = windows.first { window in
            guard let minutes = window.windowMinutes else { return false }
            return minutes >= LimitBarConstants.weeklyWindowMinutes
        }
        return (weekly, fiveHour)
    }
}

struct RateLimitWindowPayload: Decodable {
    let usedPercent: Int
    let windowDurationMins: Int?
    let resetsAt: Int?

    fileprivate var limitWindow: LimitWindow {
        let resetsAt = resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let label = windowDurationMins == LimitBarConstants.fiveHourWindowMinutes
            ? "5-hour limit"
            : "Weekly limit"
        return LimitWindow(
            label: label,
            usedPercent: usedPercent,
            windowMinutes: windowDurationMins,
            resetsAt: resetsAt
        )
    }
}

struct AccountReadResponse: Decodable {
    let account: AccountPayload?
    let requiresOpenaiAuth: Bool
}

struct AccountPayload: Decodable {
    let type: String
    let email: String?
    let planType: String?
}

struct LoginStartResponse: Decodable {
    let type: String
    let authUrl: String?
    let loginId: String?
}
