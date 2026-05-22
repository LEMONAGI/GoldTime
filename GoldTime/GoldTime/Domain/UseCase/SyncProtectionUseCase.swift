
import Foundation

final class SyncProtectionUseCase {
    private let groupRepository: any GroupRepository
    private let screenTimeRepository: any ScreenTimeRepository

    init(
        groupRepository: any GroupRepository,
        screenTimeRepository: any ScreenTimeRepository
    ) {
        self.groupRepository = groupRepository
        self.screenTimeRepository = screenTimeRepository
    }

    // 앱 활성화 시 자정 리셋 + 만료된 override 재적용
    func prepareForAppActivation() {
        screenTimeRepository.rolloverCounterIfNeeded()
        screenTimeRepository.reapplyShieldIfOverrideExpired()
    }

    func syncIfAuthorized(groups: [ScreenTimeGroup], isAuthorized: Bool) throws {
        guard isAuthorized else { return }
        try screenTimeRepository.syncDailyMonitoring(groups: groups)
    }

    func reconnectMonitoring() throws {
        try screenTimeRepository.reconnectMonitoring()
    }

    func validGroups(from groups: [ScreenTimeGroup]) -> [ScreenTimeGroup] {
        screenTimeRepository.validDailyMonitoringGroups(from: groups)
    }
}
