
import Foundation
import ManagedSettings

protocol ShieldRepository {
    var isShieldActive: Bool { get }
    var currentShieldOverrideUntil: Date? { get }
    var oneMinuteRemaining: Int { get }
    var lastRequestedUnlockApplicationToken: ApplicationToken? { get }

    func lockedGroups() -> [ScreenTimeGroup]
    func lockedGroups(containing token: ApplicationToken) -> [ScreenTimeGroup]
    func groupsInOverride() -> [ScreenTimeGroup]
    func hasPendingShieldOpenRequest() -> Bool
    func clearLastRequestedUnlockApplicationToken()
    func clearShieldOpenRequest()
    func recordWalkAway()
}
