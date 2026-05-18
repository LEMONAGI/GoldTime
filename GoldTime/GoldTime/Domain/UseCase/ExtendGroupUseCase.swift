
import Foundation
import ManagedSettings

struct LockedGroupsState {
    let lockedGroups: [ScreenTimeGroup]
    let oneMinuteRemaining: Int
    let requestedToken: ApplicationToken?
}

final class ExtendGroupUseCase {
    private let shieldRepository: any ShieldRepository
    private let screenTimeRepository: any ScreenTimeRepository

    init(
        shieldRepository: any ShieldRepository,
        screenTimeRepository: any ScreenTimeRepository
    ) {
        self.shieldRepository = shieldRepository
        self.screenTimeRepository = screenTimeRepository
    }

    func refreshState() -> LockedGroupsState {
        screenTimeRepository.reapplyShieldIfOverrideExpired()
        let token = shieldRepository.lastRequestedUnlockApplicationToken

        var locked: [ScreenTimeGroup]
        if let token {
            locked = shieldRepository.lockedGroups(containing: token)
        } else {
            locked = []
        }

        if locked.isEmpty {
            locked = shieldRepository.lockedGroups()
        }

        shieldRepository.clearLastRequestedUnlockApplicationToken()
        shieldRepository.clearShieldOpenRequest()

        return LockedGroupsState(
            lockedGroups: locked,
            oneMinuteRemaining: shieldRepository.oneMinuteRemaining,
            requestedToken: token
        )
    }

    func extendOneMinute(groupID: UUID) -> Result<GroupExtensionResult, ExtensionFailure> {
        screenTimeRepository.extendGroup(groupID: groupID, duration: 60, source: .oneMinute)
    }

    func extendWithAd(groupID: UUID) -> Result<GroupExtensionResult, ExtensionFailure> {
        screenTimeRepository.extendGroup(groupID: groupID, duration: 15 * 60, source: .adReward)
    }

    func walkAway(lockedGroups: [ScreenTimeGroup]) {
        if !lockedGroups.isEmpty {
            shieldRepository.recordWalkAway()
        }
    }

    func lockedGroupsAfterExtension(
        result: GroupExtensionResult,
        requestedToken: ApplicationToken?
    ) -> [ScreenTimeGroup] {
        if let token = requestedToken {
            return shieldRepository.lockedGroups(containing: token)
        }
        return result.remainingLockedGroups
    }

    func currentOneMinuteRemaining() -> Int {
        shieldRepository.oneMinuteRemaining
    }
}
