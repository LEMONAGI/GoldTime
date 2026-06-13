
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
        // 새 그룹은 draft로 시작한다. 규칙을 고르지 않았고(ruleKind = nil)
        // 아직 적용(commit) 전이라(isApplied = false) 모니터링에 등록되지 않는다.
        return SharedStore.ScreenTimeGroup(
            name: groupRepository.defaultGroupName(for: currentCount),
            ruleKind: nil,
            isApplied: false
        )
    }

    /// draft 그룹을 적용 상태로 전환한다. 적용 이후 규칙/제한 항목 수정·삭제는 광고 게이트를 거친다.
    func markApplied(id: UUID, in groups: inout [ScreenTimeGroup]) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].isApplied = true
    }

    func updateName(id: UUID, name: String, in groups: inout [ScreenTimeGroup]) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].name = name
    }

    /// 그룹의 차단 규칙을 갱신한다.
    /// 각 규칙별 값(일일 한도/시간대/쿨다운)은 규칙을 바꿔도 보존되도록, nil이면 기존 값을 유지한다.
    func updateRule(
        id: UUID,
        kind: GroupRuleKind,
        dailyLimitMinutes: Int? = nil,
        timeWindows: [TimeWindow]? = nil,
        cooldownUsageMinutes: Int? = nil,
        cooldownDurationMinutes: Int? = nil,
        in groups: inout [ScreenTimeGroup]
    ) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].ruleKind = kind
        if let dailyLimitMinutes {
            groups[index].dailyLimitMinutes = dailyLimitMinutes
        }
        if let timeWindows {
            groups[index].timeWindows = timeWindows
        }
        if let cooldownUsageMinutes {
            groups[index].cooldownUsageMinutes = cooldownUsageMinutes
        }
        if let cooldownDurationMinutes {
            groups[index].cooldownDurationMinutes = cooldownDurationMinutes
        }
    }

    func updateSelection(id: UUID, selection: FamilyActivitySelection, in groups: inout [ScreenTimeGroup]) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].selection = selection.supportedTokenSelection
    }

    func currentGroups() -> [ScreenTimeGroup] {
        groupRepository.screenTimeGroups
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
