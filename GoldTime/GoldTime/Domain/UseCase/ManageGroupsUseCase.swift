
import Foundation
import FamilyControls

enum ManageGroupsError: LocalizedError {
    case maxGroupCountReached

    var errorDescription: String? {
        switch self {
        case .maxGroupCountReached:
            return String(localized: "group.error.tooMany \(SharedStore.maxGroupCount)")
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

    /// 그룹의 요일별 규칙을 갱신한다. non-nil이면 요일별 모드로 전환하고, nil이면 요일별 모드를 해제해
    /// 기존 base 규칙(ruleKind 등)이 다시 매일 적용된다.
    /// **쓰기 시점 강제**(Core/CLAUDE.md 계약): non-nil rules는 정확히 7개 + WeekdayRulePolicy 통과여야
    /// 저장한다. 위반 시 updateRule의 "잘못된 입력은 조용히 무시(guard else return)" 방식과 동일하게
    /// 아무 변경도 하지 않는다 — 디코더의 drop-to-nil은 최후 방어선이지 검증이 아니다.
    func updateWeekdayRules(id: UUID, rules: [DayRule]?, in groups: inout [ScreenTimeGroup]) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        if let rules {
            guard rules.count == 7,
                  WeekdayRulePolicy.firstInvalidReason(for: rules) == nil else { return }
            groups[index].weekdayRules = rules
        } else {
            groups[index].weekdayRules = nil
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

    /// 자정 근처(23:30+)라 편집해도 곧 사용량 추적이 멈추는 구간인지. 편집 화면에서 안내 문구를
    /// 띄울지 판단한다. 실제 모니터 재등록 차단은 23:45부터지만 연장 안내처럼 미리 알린다.
    func isNearMidnightEditNoticeWindow(now: Date = Date()) -> Bool {
        screenTimeRepository.isWithinNearMidnightNoticeWindow(now: now)
    }

    /// 자정 직전(23:45+)이라 모니터 등록이 intervalTooShort로 막혀, 방금 적용/수정한 규칙이
    /// 00:00부터야 실제로 추적되는 구간인지. 규칙 적용·수정 직후 확인 alert을 띄울지 판단한다.
    /// (편집 화면의 사전 인라인 안내 `isNearMidnightEditNoticeWindow`(23:30+)와 달리,
    ///  실제 등록이 막히는 23:45 경계를 본다.)
    func isNearMidnightMonitorTooShort(now: Date = Date()) -> Bool {
        screenTimeRepository.isNearMidnightOverrideCutoff(now: now)
    }
}
