import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject private var model: AccountsModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(model.slots) { slot in
                        AccountCard(slot: slot)
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 360)
            Divider()
            footer
        }
        .foregroundStyle(.primary)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Limit Bar")
                .font(.headline)
            Spacer()
            if model.isRefreshing || model.pendingAdd != nil {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                Task { await model.refreshAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .help("Refresh now")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private var footer: some View {
        Text("Auto-refreshes every minute")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

struct AccountCard: View {
    @EnvironmentObject private var model: AccountsModel
    let slot: AccountSlot
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .top, spacing: 8) {
                    ProviderIcon(provider: slot.provider, size: 22)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(slot.title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        if let planType = slot.planType {
                            Text(planType)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                statusControl
            }

            content
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.48))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.24), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var content: some View {
        switch slot.status {
        case .starting, .loading, .authenticating:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)

        case .unauthenticated:
            HStack {
                Text(slot.provider == .claude ? "Not connected to Claude" : "Not signed in")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

        case .ready, .loginRequired:
            VStack(alignment: .leading, spacing: 7) {
                if slot.status == .loginRequired {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                        Text("Login required · showing last known limits")
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.orange)
                }
                UsageBar(window: slot.weekly ?? placeholderWindow("Weekly limit"), showsResetDate: true)
                    .opacity(slot.displayDimmed ? 0.68 : 1)
                UsageBar(window: slot.fiveHour ?? placeholderWindow("5-hour limit"), showsResetDate: true)
                    .opacity(slot.displayDimmed ? 0.68 : 1)
            }

        case .error(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(3)
        }
    }

    @ViewBuilder
    private var statusControl: some View {
        let actions = slot.availableActions
        if actions.contains(.login) {
            HStack(spacing: 8) {
                Button("Log in") {
                    Task { await model.login(slot.id) }
                }
                .controlSize(.small)

                if actions.contains(.remove) {
                    Button("Remove", role: .destructive) {
                        model.removeAccount(slot.id)
                    }
                    .controlSize(.small)
                }
            }
        } else if slot.status == .authenticating {
            Text("Waiting")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Menu {
                if actions.contains(.refresh) {
                    Button {
                        Task { await model.refresh(slot.id) }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                if actions.contains(.remove) {
                    Button(role: .destructive) {
                        model.removeAccount(slot.id)
                    } label: {
                        Label("Remove", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } else if actions.contains(.logout) {
                    Button(role: .destructive) {
                        Task { await model.logout(slot.id) }
                    } label: {
                        Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .focusEffectDisabled()
            .help("Account actions")
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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(window.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(window.usedPercent)% used · \(window.remainingPercent)% left")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(nsColor: .quaternaryLabelColor))
                    Capsule()
                        .fill(color)
                        .frame(width: proxy.size.width * CGFloat(max(0, min(100, window.usedPercent))) / 100)
                }
            }
            .frame(height: 7)

            if showsResetDate, let resetsAt = window.resetsAt {
                Text("Resets \(Self.resetFormatter.string(from: resetsAt))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var color: Color {
        switch window.usedPercent {
        case 0..<65: .accentColor
        case 65..<88: .orange
        default: .red
        }
    }

    private static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
