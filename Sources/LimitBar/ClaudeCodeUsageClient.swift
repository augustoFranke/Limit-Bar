import Foundation

struct ClaudeCodeUsage: Equatable {
    let fiveHour: LimitWindow?
    let weekly: LimitWindow?
}

final class ClaudeCodeUsageClient {
    private let session: URLSession
    private let messagesURL = URL(string: "https://api.anthropic.com/v1/messages")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Probes the Messages API with a 1-token request and reads the unified
    /// rate-limit headers Anthropic returns alongside it. This mirrors the
    /// "Automatic Setup with Claude Code" path used by other community trackers.
    func fetchUsage(accessToken: String) async throws -> ClaudeCodeUsage {
        var request = URLRequest(url: messagesURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("claude-code/2.1.5", forHTTPHeaderField: "User-Agent")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "hi"]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LimitBarError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return parseUsage(from: httpResponse)
        case 401, 403:
            throw LimitBarError.loginRequired(
                detail: requestFailureMessage(
                    "Claude Code login is required. Run `claude login` and try again.",
                    statusCode: httpResponse.statusCode,
                    data: data
                )
            )
        case 429:
            // Session is at its rate limit. The headers still carry utilization;
            // surface them instead of throwing.
            return parseUsage(from: httpResponse)
        case 500...599:
            throw LimitBarError.serverError(
                status: httpResponse.statusCode,
                detail: requestFailureMessage(
                    "Claude API is temporarily unavailable.",
                    statusCode: httpResponse.statusCode,
                    data: data
                )
            )
        default:
            throw LimitBarError.message(
                requestFailureMessage(
                    "Claude usage request failed.",
                    statusCode: httpResponse.statusCode,
                    data: data
                )
            )
        }
    }

    private func parseUsage(from response: HTTPURLResponse) -> ClaudeCodeUsage {
        ClaudeCodeUsage(
            fiveHour: parseWindow(
                from: response,
                label: "5-hour limit",
                utilizationHeader: "anthropic-ratelimit-unified-5h-utilization",
                resetHeader: "anthropic-ratelimit-unified-5h-reset",
                windowMinutes: 300
            ),
            weekly: parseWindow(
                from: response,
                label: "Weekly limit",
                utilizationHeader: "anthropic-ratelimit-unified-7d-utilization",
                resetHeader: "anthropic-ratelimit-unified-7d-reset",
                windowMinutes: 7 * 24 * 60
            )
        )
    }

    private func parseWindow(
        from response: HTTPURLResponse,
        label: String,
        utilizationHeader: String,
        resetHeader: String,
        windowMinutes: Int
    ) -> LimitWindow? {
        guard let utilization = headerDouble(response, name: utilizationHeader) else {
            return nil
        }

        let percent = utilization <= 1 ? utilization * 100 : utilization
        let resetTimestamp = headerDouble(response, name: resetHeader) ?? 0
        let resetsAt: Date? = resetTimestamp > 0
            ? Date(timeIntervalSince1970: resetTimestamp)
            : nil

        // If the window has already elapsed, the reported utilization is stale.
        let normalizedPercent: Int
        if let resetsAt, resetsAt < Date() {
            normalizedPercent = 0
        } else {
            normalizedPercent = max(0, min(100, Int(percent.rounded())))
        }

        return LimitWindow(
            label: label,
            usedPercent: normalizedPercent,
            windowMinutes: windowMinutes,
            resetsAt: resetsAt
        )
    }

    private func headerDouble(_ response: HTTPURLResponse, name: String) -> Double? {
        guard let value = response.value(forHTTPHeaderField: name) else { return nil }
        return Double(value.trimmingCharacters(in: .whitespaces))
    }

    private func requestFailureMessage(_ summary: String, statusCode: Int, data: Data) -> String {
        let preview = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(180)
        let suffix = preview.map { "\nResponse: \($0)" } ?? ""
        return "\(summary)\nEndpoint: \(messagesURL.absoluteString)\nHTTP \(statusCode)\(suffix)"
    }
}
