import AppKit
import SwiftUI

enum ProviderIconLoader {
    static func icon(for provider: AccountProvider) -> NSImage? {
        let path: String
        switch provider {
        case .codex:
            path = "/Applications/Codex.app"
        case .claude:
            path = "/Applications/Claude.app"
        }

        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 28, height: 28)
        return image
    }
}

struct ProviderIcon: View {
    let provider: AccountProvider
    var size: CGFloat = 24

    var body: some View {
        Group {
            if let image = ProviderIconLoader.icon(for: provider) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: fallbackSymbol)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var fallbackSymbol: String {
        switch provider {
        case .codex: "curlybraces.square"
        case .claude: "sparkles"
        }
    }
}
