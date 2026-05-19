
import Foundation
import ManagedSettings

struct ShieldRepositoryImpl: ShieldRepository {
    var isShieldActive: Bool { SharedStore.isShieldActive }
    var currentShieldOverrideUntil: Date? { SharedStore.currentShieldOverrideUntil }
    var overrideUntilByGroupID: [UUID: Date] { SharedStore.overrideUntilByGroupID }
    var oneMinuteRemaining: Int { SharedStore.oneMinuteRemaining }
    var lastRequestedUnlockApplicationToken: ApplicationToken? {
        SharedStore.lastRequestedUnlockApplicationToken
    }

    func lockedGroups() -> [ScreenTimeGroup] {
        SharedStore.lockedGroups()
    }

    func lockedGroups(containing token: ApplicationToken) -> [ScreenTimeGroup] {
        SharedStore.lockedGroups(containing: token)
    }

    func groupsInOverride() -> [ScreenTimeGroup] {
        SharedStore.groupsInOverride()
    }

    func hasPendingShieldOpenRequest() -> Bool {
        SharedStore.hasPendingShieldOpenRequest()
    }

    func clearLastRequestedUnlockApplicationToken() {
        SharedStore.clearLastRequestedUnlockApplicationToken()
    }

    func clearShieldOpenRequest() {
        SharedStore.clearShieldOpenRequest()
    }

    func recordWalkAway() {
        SharedStore.recordWalkAway()
    }
}
