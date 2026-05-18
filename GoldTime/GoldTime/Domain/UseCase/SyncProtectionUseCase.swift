
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

    func syncIfAuthorized(groups: [ScreenTimeGroup], isAuthorized: Bool) throws {
        guard isAuthorized else { return }
        try screenTimeRepository.syncDailyMonitoring(groups: groups)
    }

    func resetProtectionState() throws {
        try screenTimeRepository.resetProtectionState()
    }

    func validGroups(from groups: [ScreenTimeGroup]) -> [ScreenTimeGroup] {
        screenTimeRepository.validDailyMonitoringGroups(from: groups)
    }
}
