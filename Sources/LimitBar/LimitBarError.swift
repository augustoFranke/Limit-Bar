import Foundation

enum LimitBarError: LocalizedError, Equatable {
    case message(String)
    case loginRequired(detail: String? = nil)
    case transientNetwork(detail: String)
    case serverError(status: Int, detail: String)
    case invalidResponse
    case processUnavailable
    case requestTimedOut(detail: String)

    var errorDescription: String? {
        switch self {
        case .message(let value):
            return value
        case .loginRequired(let detail):
            return detail ?? "Sign-in required."
        case .transientNetwork(let detail):
            return "Network error. \(detail)"
        case .serverError(let status, let detail):
            return "Server error (HTTP \(status)). \(detail)"
        case .invalidResponse:
            return "Provider returned an invalid response."
        case .processUnavailable:
            return "Codex app-server is not running."
        case .requestTimedOut(let detail):
            return detail
        }
    }

    /// Stable classification used by the orchestrator instead of stringly-matching localized text.
    var isLoginRequired: Bool {
        if case .loginRequired = self { return true }
        return false
    }
}
