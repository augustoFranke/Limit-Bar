import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject private var model: AccountsModel

    var body: some View {
        Group {
            if model.slots.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.slots.enumerated()), id: \.element.id) { index, slot in
                        if index > 0 {
                            Divider()
                        }
                        AccountRow(slot: slot)
                    }
                }
            }
        }
        .foregroundStyle(.primary)
    }

    private var emptyState: some View {
        HStack {
            Text("No accounts")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct AccountRow: View {
    @EnvironmentObject private var model: AccountsModel
    let slot: AccountSlot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Text(slot.provider.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                trailingControl
            }

            if let email = slot.email {
                Text(email)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let planType = slot.planType {
                Text(planType)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            detail
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private var detail: some View {
        switch slot.status {
        case .starting, .loading, .authenticating:
            HStack(spacing: 7) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.8)
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

        case .unauthenticated:
            Text(slot.provider == .claude ? "Not connected to Claude" : "Not signed in")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
    
        case .ready, .loginRequired:
            VStack(alignment: .leading, spacing: 6) {
                if slot.status == .loginRequired {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                        Text("Login required · showing last known limits")
                            .font(.system(size: 11))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.orange)
                }
                UsageBar(window: slot.weekly ?? placeholderWindow("Weekly limit"), showsResetDate: true)
                    .opacity(slot.displayDimmed ? 0.6 : 1)
                UsageBar(window: slot.fiveHour ?? placeholderWindow("5-hour limit"), showsResetDate: true)
                    .opacity(slot.displayDimmed ? 0.6 : 1)
            }

        case .error(let message):
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .lineLimit(3)
            }
    }

    @ViewBuilder
    private var trailingControl: some View {
        let actions = slot.availableActions
        if actions.contains(.login) {
            HStack(spacing: 6) {
                Button("Log In") {
                    Task { await model.login(slot.id) }
                }
                .controlSize(.small)

                if actions.contains(.remove) {
                    Button {
                        model.removeAccount(slot.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Remove account")
                }
            }
        } else if slot.status == .authenticating {
            Text("Waiting")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        } else if actions.contains(.logout) {
            Button("Sign Out") {
                Task { await model.logout(slot.id) }
            }
            .controlSize(.small)
        } else if actions.contains(.remove) {
            Button {
                model.removeAccount(slot.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .foregroundStyle(.secondary)
            .focusEffectDisabled()
            .help("Remove account")
        }
    }

    private var statusText: String {
        switch slot.status {
        case .starting: "Starting \(slot.provider.displayName)"
        case .authenticating: slot.provider == .claude ? "Checking Claude login" : "Complete login in your browser"
        case .loading: "Loading limits"
        case .loginRequired: "Login required"
        default: ""
        }
    }

    private func placeholderWindow(_ label: String) -> LimitWindow {
        LimitWindow(label: label, usedPercent: 0, windowMinutes: nil, resetsAt: nil)
    }
}

struct UsageBar: View {
    let window: LimitWindow
    var showsResetDate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(window.label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(window.usedPercent)% used")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(nsColor: .quaternaryLabelColor))
                    Capsule()
                        .fill(Color(nsColor: .secondaryLabelColor))
                        .frame(width: proxy.size.width * CGFloat(max(0, min(100, window.usedPercent))) / 100)
                }
            }
            .frame(height: 5)

            if showsResetDate, let resetsAt = window.resetsAt {
                Text("Resets \(Self.resetFormatter.string(from: resetsAt))")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
