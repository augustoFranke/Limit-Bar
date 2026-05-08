import SwiftUI

struct NativeAddAccountButton: View {
    let isBusy: Bool
    let addCodex: () -> Void
    let addClaude: () -> Void

    var body: some View {
        Menu {
            Button(AccountProvider.codex.addAccountTitle, action: addCodex)
            Button(AccountProvider.claude.addAccountTitle, action: addClaude)
        } label: {
            Text("Add account")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .controlSize(.small)
        .disabled(isBusy)
        .fixedSize()
        .focusEffectDisabled()
    }
}
