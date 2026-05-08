import Foundation

protocol AccountSlotStoring {
    func restoreSlots() -> [AccountSlot]
    func saveSlots(_ slots: [AccountSlot])
    func saveSlotIDs(_ slotIDs: [Int])
    func savedEmail(for index: Int) -> String?
    func saveEmail(_ email: String, for index: Int)
    func saveProvider(_ provider: AccountProvider, for index: Int)
    func deleteStoredAccount(for index: Int)
}

struct UserDefaultsAccountSlotStore: AccountSlotStoring {
    func restoreSlots() -> [AccountSlot] {
        AccountSlotStore.restoreSlots()
    }

    func saveSlots(_ slots: [AccountSlot]) {
        AccountSlotStore.saveSlots(slots)
    }

    func saveSlotIDs(_ slotIDs: [Int]) {
        AccountSlotStore.saveSlotIDs(slotIDs)
    }

    func savedEmail(for index: Int) -> String? {
        AccountSlotStore.savedEmail(for: index)
    }

    func saveEmail(_ email: String, for index: Int) {
        AccountSlotStore.saveEmail(email, for: index)
    }

    func saveProvider(_ provider: AccountProvider, for index: Int) {
        AccountSlotStore.saveProvider(provider, for: index)
    }

    func deleteStoredAccount(for index: Int) {
        AccountSlotStore.deleteStoredAccount(for: index)
    }
}
