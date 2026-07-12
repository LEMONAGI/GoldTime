
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
        guard !isStrictLocked(groupID: groupID) else { return .failure(.strictLockActive) }
        return screenTimeRepository.extendGroup(groupID: groupID, duration: 60, source: .oneMinute)
    }

    func extendWithAd(groupID: UUID) -> Result<GroupExtensionResult, ExtensionFailure> {
        guard !isStrictLocked(groupID: groupID) else { return .failure(.strictLockActive) }
        return screenTimeRepository.extendGroup(groupID: groupID, duration: 10 * 60, source: .adReward)
    }

    /// 금고 약정 판정은 원본 그룹에서 한다(투영본은 strict 필드가 스트립됨).
    private func isStrictLocked(groupID: UUID, now: Date = Date()) -> Bool {
        shieldRepository.lockedGroups().first { $0.id == groupID }?.isStrictLockActive(at: now) ?? false
    }

    /// 자정까지 < 15분이라 1분 연장(정확 차감)이 불가능한 시점인지. = 23:45부터.
    func isNearMidnightCutoff(now: Date = Date()) -> Bool {
        screenTimeRepository.isNearMidnightOverrideCutoff(now: now)
    }

    /// 자정 근처 안내 문구를 보여줄 구간인지. = 23:30부터(행동 변화 23:45 전 미리 알림).
    func isNearMidnightNoticeWindow(now: Date = Date()) -> Bool {
        screenTimeRepository.isWithinNearMidnightNoticeWindow(now: now)
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
