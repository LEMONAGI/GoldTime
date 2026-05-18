
import Foundation
import FamilyControls

enum ManageGroupsError: LocalizedError {
    case maxGroupCountReached

    var errorDescription: String? {
        switch self {
        case .maxGroupCountReached:
            return "그룹은 \(SharedStore.maxGroupCount)개까지예요."
        }
    }
}

final class ManageGroupsUseCase {
    private var groupRepository: any GroupRepository
    private let screenTimeRepository: any ScreenTimeRepository

    init(
        groupRepository: any GroupRepository,
        screenTimeRepository: any ScreenTimeRepository
    ) {
        self.groupRepository = groupRepository
        self.screenTimeRepository = screenTimeRepository
    }

    func makeNewGroup(currentCount: Int) throws -> ScreenTimeGroup {
        guard currentCount < SharedStore.maxGroupCount else {
            throw ManageGroupsError.maxGroupCountReached
        }
        return SharedStore.ScreenTimeGroup(
            name: groupRepository.defaultGroupName(for: currentCount)
        )
    }

    func updateName(id: UUID, name: String, in groups: inout [ScreenTimeGroup]) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].name = name
    }

    func updateLimit(id: UUID, minutes: Int, in groups: inout [ScreenTimeGroup]) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].dailyLimitMinutes = minutes
    }

    func updateSelection(id: UUID, selection: FamilyActivitySelection, in groups: inout [ScreenTimeGroup]) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].selection = selection.appOnly
    }

    func persist(_ groups: [ScreenTimeGroup]) {
        groupRepository.screenTimeGroups = groups
    }

    func persistAndSync(_ groups: [ScreenTimeGroup]) throws {
        groupRepository.screenTimeGroups = groups
        let saved = groupRepository.screenTimeGroups
        try screenTimeRepository.syncDailyMonitoring(groups: saved)
    }
}
