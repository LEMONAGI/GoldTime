
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
        // 연장 불가 기간 중엔 규칙/앱 선택 편집 전면 차단(강화 방향 포함 — 판별 없이 단순 차단).
        guard !groups[index].isStrictLockActive() else { return }
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
        // 연장 불가 기간 중엔 규칙/앱 선택 편집 전면 차단(강화 방향 포함 — 판별 없이 단순 차단).
        guard !groups[index].isStrictLockActive() else { return }
        if let rules {
            guard rules.count == 7,
                  WeekdayRulePolicy.firstInvalidReason(for: rules) == nil else { return }
            groups[index].weekdayRules = rules
            // base ruleKind가 nil(draft 출신)이면 첫 제한 요일 규칙을 base 필드에도 기록한다.
            // 디코딩 폴백(weekdayRules 7개 아님 → drop-to-nil)이나 1.1.x 다운그레이드 시
            // "base 규칙이 보호를 이어받는다"는 계약(Core/CLAUDE.md)이 draft 출신 그룹에서
            // 무보호(groupHasNoRule로 모니터링 제외)로 전락하는 것을 막는다.
            // 첫 제한 요일은 항상 존재한다(전부 제한 없음은 위 정책 검증에서 거부됨).
            if groups[index].ruleKind == nil,
               let fallback = rules.first(where: { $0.kind != .unrestricted }) {
                switch fallback.kind {
                case .dailyLimit: groups[index].ruleKind = .dailyLimit
                case .timeWindows: groups[index].ruleKind = .timeWindows
                case .cooldown: groups[index].ruleKind = .cooldown
                case .unrestricted: break
                }
                groups[index].dailyLimitMinutes = fallback.dailyLimitMinutes
                groups[index].timeWindows = fallback.timeWindows
                groups[index].cooldownUsageMinutes = fallback.cooldownUsageMinutes
                groups[index].cooldownDurationMinutes = fallback.cooldownDurationMinutes
            }
        } else {
            groups[index].weekdayRules = nil
        }
    }

    func updateSelection(id: UUID, selection: FamilyActivitySelection, in groups: inout [ScreenTimeGroup]) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        // 연장 불가 기간 중엔 규칙/앱 선택 편집 전면 차단(강화 방향 포함 — 판별 없이 단순 차단).
        guard !groups[index].isStrictLockActive() else { return }
        groups[index].selection = selection.supportedTokenSelection
    }

    /// 그룹을 삭제한다. 연장 불가 기간 중이면 삭제하지 않고 false를 반환한다.
    @discardableResult
    func deleteGroup(id: UUID, in groups: inout [ScreenTimeGroup]) -> Bool {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return false }
        guard !groups[index].isStrictLockActive() else { return false }
        groups.remove(at: index)
        return true
    }

    /// 연장 불가 기간 빠른 선택 칩(일). 그 외 기간은 커스텀 입력(`strictLockDayRange`).
    static let strictLockDayPresets: [Int] = [1, 3, 7]

    /// 커스텀 입력 포함 허용 범위. **상한 30일은 실수 보호** — 한 번 걸면 어떤 수단으로도 못 풀기
    /// 때문에 무한정 긴 기간은 도움이 아니라 사고가 된다. 이 상한을 올리기 전에 반드시 재고할 것.
    static let strictLockDayRange: ClosedRange<Int> = 1...30

    /// 시트를 열었을 때 기본으로 잡히는 기간. **가장 짧은 프리셋(1일)** — 한 번 걸면 못 푸는
    /// 모드라 기본값은 사용자가 가장 잃을 게 적은 쪽이어야 한다. **프리셋에 있는 값이라 시트가
    /// "1일 칩 선택 + 휠 접힘" 상태로 열린다**(2026-07-31 변경 — 이전 기본값 14일은 커스텀 칩이
    /// 선택된 채 휠이 펼쳐져 열려서, 처음 보는 화면이 곧바로 2주 잠금을 권하는 모양이었다).
    static let strictLockDefaultDays = 1

    /// 커스텀 칩을 눌렀을 때 휠이 처음 잡는 기간. **프리셋에 없는 값이어야** 커스텀 칩이 선택된
    /// 상태로 표시된다(프리셋 값이면 칩 선택이 프리셋으로 되돌아간다).
    static let strictLockCustomSeedDays = 14

    /// 연장 불가 모드를 쓸 수 있는지(설정 토글, **기본 On**, 2026-09-01 재도입). Off면 그룹 카드에서
    /// 연장 불가 기간 행이 숨겨져 카드가 가벼워진다(안 쓰는 사용자용) — 새로 걸기·연장도 막힌다.
    /// **게이트는 "새로 걸기·연장"만 막는다**: 집행부는 이 값을 보지 않고 `strictUntil`만 보므로
    /// Off로 내려도 진행 중 잠금은 유지·집행되고, 행도 `HomeViewModel.showsStrictRow`가 잠긴 동안
    /// 계속 보인다(`strictRowStaysVisibleWhileLockedEvenIfGateClosed`).
    ///
    /// 저장은 `groupRepository.isStrictLockEnabled` → **새 키** `SharedStore.isStrictLockOptionEnabled`.
    /// 구 토글 키(`isStrictLockEnabled`, 기본 Off 시절)는 재사용하지 않는다 — 재사용하면 과거 Off
    /// 사용자가 업데이트 후 못 쓴다(하위 호환). 정식 출시 때는 이 값 ∧ 구독 entitlement로 합성한다.
    var isStrictLockEnabled: Bool { groupRepository.isStrictLockEnabled }

    /// 연장 불가 모드 옵션 토글(설정). **끄기를 막지 않는다**(구 `canDisableStrictLock`/`setStrictLockEnabled`
    /// false 반환 방어는 되살리지 않는다): 집행부가 게이트를 안 보므로 Off로 내려도 진행 중 잠금은
    /// 그대로 유지·집행되고 잠긴 행도 계속 보인다 — "끄기로 우회 해제" 구멍이 애초에 없다.
    func setStrictLockEnabled(_ enabled: Bool) {
        groupRepository.isStrictLockEnabled = enabled
    }

    /// 연장 불가 기간을 시작하거나 연장한다(만료가 늘어나는 방향만 — 축소 불가).
    /// applied + 유효 규칙 그룹만. 성공 시 true.
    @discardableResult
    func activateStrictLock(id: UUID, days: Int, now: Date = Date(), in groups: inout [ScreenTimeGroup]) -> Bool {
        // 기능 게이트가 닫혀 있으면 켤 수 없다(UI가 진입을 막지만 집행부에서도 방어 —
        // 구독 페이월이 붙으면 이 guard가 미구독자를 막는 자리가 된다).
        guard isStrictLockEnabled,
              Self.strictLockDayRange.contains(days),
              let index = groups.firstIndex(where: { $0.id == id }),
              groups[index].isApplied,
              ScreenTimeGroupPolicy.invalidReason(for: groups[index].policySnapshot) == nil,
              let expiry = ScreenTimeGroup.strictLockExpiry(days: days, from: now) else { return false }
        // 이미 진행 중인 기간이 있으면 연장만 허용(축소 거부), 시작 시각은 최초 적용 값을 유지.
        if let current = groups[index].strictUntil, groups[index].isStrictLockActive(at: now) {
            guard expiry > current else { return false }
        } else {
            groups[index].strictStartedAt = now
        }
        groups[index].strictUntil = expiry
        return true
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
