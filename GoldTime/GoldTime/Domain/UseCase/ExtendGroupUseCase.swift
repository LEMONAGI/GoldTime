
import Foundation
import ManagedSettings

struct LockedGroupsState {
    let lockedGroups: [ScreenTimeGroup]
    let oneMinuteRemaining: Int
    let requestedToken: ApplicationToken?
    let requestedWebDomainToken: WebDomainToken?
    let cooldownEndByGroupID: [UUID: Date]
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
        let webDomainToken = shieldRepository.lastRequestedUnlockWebDomainToken

        var locked: [ScreenTimeGroup]
        if let token {
            locked = shieldRepository.lockedGroups(containing: token)
        } else if let webDomainToken {
            locked = shieldRepository.lockedGroups(containing: webDomainToken)
        } else {
            locked = []
        }

        if locked.isEmpty {
            locked = shieldRepository.lockedGroups()
        }

        shieldRepository.clearLastRequestedUnlockTokens()
        shieldRepository.clearShieldOpenRequest()

        return LockedGroupsState(
            lockedGroups: locked,
            oneMinuteRemaining: shieldRepository.oneMinuteRemaining,
            requestedToken: token,
            requestedWebDomainToken: webDomainToken,
            cooldownEndByGroupID: shieldRepository.cooldownEndByGroupID
        )
    }

    func extendOneMinute(groupID: UUID) -> Result<GroupExtensionResult, ExtensionFailure> {
        screenTimeRepository.extendGroup(groupID: groupID, duration: 60, source: .oneMinute)
    }

    func extendWithAd(groupID: UUID) -> Result<GroupExtensionResult, ExtensionFailure> {
        screenTimeRepository.extendGroup(groupID: groupID, duration: 10 * 60, source: .adReward)
    }

    func walkAway(lockedGroups: [ScreenTimeGroup]) {
        if !lockedGroups.isEmpty {
            shieldRepository.recordWalkAway()
        }
    }

    func lockedGroupsAfterExtension(
        result: GroupExtensionResult,
        requestedToken: ApplicationToken?,
        requestedWebDomainToken: WebDomainToken?
    ) -> [ScreenTimeGroup] {
        if let token = requestedToken {
            return shieldRepository.lockedGroups(containing: token)
        }
        if let requestedWebDomainToken {
            return shieldRepository.lockedGroups(containing: requestedWebDomainToken)
        }
        return result.remainingLockedGroups
    }

    func currentOneMinuteRemaining() -> Int {
        shieldRepository.oneMinuteRemaining
    }
}
