
import Foundation

// Core 타입 → Domain 타입 매핑 헬퍼
private extension ScreenTimeManager.ExtensionSource {
    var domain: ExtensionSource {
        switch self {
        case .oneMinute: return .oneMinute
        case .adReward: return .adReward
        }
    }
}

private extension ExtensionSource {
    var core: ScreenTimeManager.ExtensionSource {
        switch self {
        case .oneMinute: return .oneMinute
        case .adReward: return .adReward
        }
    }
}

private extension ScreenTimeManager.ExtensionFailure {
    var domain: ExtensionFailure {
        switch self {
        case .groupNotFound: return .groupNotFound
        case .oneMinuteLimitReached: return .oneMinuteLimitReached
        case .relockTimerRegistrationFailed: return .relockTimerRegistrationFailed
        }
    }
}

private extension ScreenTimeManager.GroupExtensionResult {
    var domain: GroupExtensionResult {
        GroupExtensionResult(
            group: group,
            durationSeconds: durationSeconds,
            overrideUntil: overrideUntil,
            remainingLockedGroups: remainingLockedGroups
        )
    }
}

struct ScreenTimeRepositoryImpl: ScreenTimeRepository {
    var isDailyMonitoringEnabled: Bool { SharedStore.isDailyMonitoringEnabled }

    func rolloverCounterIfNeeded() {
        ScreenTimeManager.rolloverCounterIfNeeded()
    }

    @discardableResult
    func reapplyShieldIfOverrideExpired() -> Bool {
        ScreenTimeManager.reapplyShieldIfOverrideExpired()
    }

    func syncDailyMonitoring(groups: [ScreenTimeGroup]) throws {
        try ScreenTimeManager.syncDailyMonitoring(groups: groups)
    }

    func reconnectMonitoring() throws {
        try ScreenTimeManager.reconnectMonitoring()
    }

    func validDailyMonitoringGroups(from groups: [ScreenTimeGroup]) -> [ScreenTimeGroup] {
        ScreenTimeManager.validDailyMonitoringGroups(from: groups)
    }

    func extendGroup(
        groupID: UUID,
        duration seconds: Int,
        source: ExtensionSource
    ) -> Result<GroupExtensionResult, ExtensionFailure> {
        let result = ScreenTimeManager.extendGroup(
            groupID: groupID,
            duration: seconds,
            source: source.core
        )
        switch result {
        case .success(let r): return .success(r.domain)
        case .failure(let f): return .failure(f.domain)
        }
    }
}
