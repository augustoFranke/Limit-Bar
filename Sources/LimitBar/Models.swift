import Foundation

enum AccountProvider: String, CaseIterable, Equatable {
    case codex
    case claude

    var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        }
    }

    var addAccountTitle: String {
        "Add \(displayName) Account"
    }
}

enum AccountStatus: Equatable {
    case starting
    case unauthenticated
    case authenticating
    case loginRequired
    case loading
    case ready
    case error(String)

    var canRemoveAccount: Bool {
        switch self {
        case .unauthenticated, .loginRequired, .error:
            true
        case .starting, .authenticating, .loading, .ready:
            false
        }
    }
}

struct LimitWindow: Equatable {
    let label: String
    let usedPercent: Int
    let windowMinutes: Int?
    let resetsAt: Date?

    var remainingPercent: Int {
        max(0, min(100, 100 - usedPercent))
    }
}

struct AccountSlot: Identifiable, Equatable {
    let id: Int
    var provider: AccountProvider = .codex
    var email: String?
    var planType: String?
    var status: AccountStatus = .starting
    var weekly: LimitWindow?
    var fiveHour: LimitWindow?
    var lastRefresh: Date?

    var title: String {
        email ?? "\(provider.displayName) Account \(id + 1)"
    }
}

extension AccountSlot {
    /// Action affordances the menu can show for this slot. Computed from `status`
    /// and the presence of last-known limits. View consumes this directly so
    /// the view stays a pure function of state.
    enum Action: Hashable {
        case login
        case refresh
        case logout
        case remove
    }

    var availableActions: Set<Action> {
        switch status {
        case .starting, .loading, .authenticating:
            return []
        case .unauthenticated, .loginRequired, .error:
            return [.login, .remove]
        case .ready:
            return [.refresh, .logout]
        }
    }

    /// True when usage bars should render dimmed (last-known data, not current).
    var displayDimmed: Bool {
        status == .loginRequired
    }
}

struct PendingAccountAdd: Equatable {
    let provider: AccountProvider
    var statusText: String
    var errorText: String?
}

