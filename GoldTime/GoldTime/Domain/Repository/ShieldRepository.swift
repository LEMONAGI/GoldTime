
import Foundation
import ManagedSettings

protocol ShieldRepository {
    var isShieldActive: Bool { get }
    var currentShieldOverrideUntil: Date? { get }
    var overrideUntilByGroupID: [UUID: Date] { get }
    var usedTimeByGroupID: [UUID: Int] { get }
    var overrideBaselineUsedTimeByGroupID: [UUID: Int] { get }
    var overrideGrantedMinutesByGroupID: [UUID: Int] { get }
    var oneMinuteRemaining: Int { get }
    var lastRequestedUnlockApplicationToken: ApplicationToken? { get }
    var lastRequestedUnlockWebDomainToken: WebDomainToken? { get }

    func lockedGroups() -> [ScreenTimeGroup]
    func lockedGroups(containing token: ApplicationToken) -> [ScreenTimeGroup]
    func lockedGroups(containing token: WebDomainToken) -> [ScreenTimeGroup]
    func groupsInOverride() -> [ScreenTimeGroup]
    func hasPendingShieldOpenRequest() -> Bool
    func clearLastRequestedUnlockTokens()
    func clearShieldOpenRequest()
    func recordWalkAway()
}
