
import Foundation
import ManagedSettings

struct ShieldRepositoryImpl: ShieldRepository {
    var isShieldActive: Bool { SharedStore.isShieldActive }
    var currentShieldOverrideUntil: Date? { SharedStore.currentShieldOverrideUntil }
    var overrideUntilByGroupID: [UUID: Date] { SharedStore.overrideUntilByGroupID }
    var usedTimeByGroupID: [UUID: Int] { SharedStore.usedTimeByGroupID }
    var overrideBaselineUsedTimeByGroupID: [UUID: Int] {
        SharedStore.overrideBaselineUsedTimeByGroupID
    }
    var overrideGrantedMinutesByGroupID: [UUID: Int] {
        SharedStore.overrideGrantedMinutesByGroupID
    }
    var oneMinuteRemaining: Int { SharedStore.oneMinuteRemaining }
    var lastRequestedUnlockApplicationToken: ApplicationToken? {
        SharedStore.lastRequestedUnlockApplicationToken
    }
    var lastRequestedUnlockWebDomainToken: WebDomainToken? {
        SharedStore.lastRequestedUnlockWebDomainToken
    }

    func lockedGroups() -> [ScreenTimeGroup] {
        SharedStore.lockedGroups()
    }

    func lockedGroups(containing token: ApplicationToken) -> [ScreenTimeGroup] {
        SharedStore.lockedGroups(containing: token)
    }

    func lockedGroups(containing token: WebDomainToken) -> [ScreenTimeGroup] {
        SharedStore.lockedGroups(containing: token)
    }

    func groupsInOverride() -> [ScreenTimeGroup] {
        SharedStore.groupsInOverride()
    }

    func hasPendingShieldOpenRequest() -> Bool {
        SharedStore.hasPendingShieldOpenRequest()
    }

    func clearLastRequestedUnlockTokens() {
        SharedStore.clearLastRequestedUnlockTokens()
    }

    func clearShieldOpenRequest() {
        SharedStore.clearShieldOpenRequest()
    }

    func recordWalkAway() {
        SharedStore.recordWalkAway()
    }
}
