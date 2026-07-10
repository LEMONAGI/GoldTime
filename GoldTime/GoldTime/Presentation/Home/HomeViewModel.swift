//
//  HomeViewModel.swift
//  GoldTime
//

import Foundation
import FamilyControls
import SwiftUI

struct HomeViewModel {
    let groups: [ScreenTimeGroup]
    let todayStats: DailyStats
    let isMonitoring: Bool
    let isShieldActive: Bool
    let shieldOverrideUntil: Date?
    let successMessage: String?
    let errorMessage: String?
    let lockedGroupIDs: Set<UUID>
    let overrideGroupIDs: Set<UUID>
    let validGroupIDs: Set<UUID>
    let untrackedGroupIDs: Set<UUID>
    let overrideUntilByGroupID: [UUID: Date]
    let usedTimeByGroupID: [UUID: Int]
    let overrideBaselineUsedTimeByGroupID: [UUID: Int]
    let overrideGrantedMinutesByGroupID: [UUID: Int]
    let oneMinuteRemaining: Int
    let oneMinuteDailyLimit: Int
    let cooldownEndByGroupID: [UUID: Date]

    init(
        groups: [ScreenTimeGroup],
        todayStats: DailyStats,
        isMonitoring: Bool,
        isShieldActive: Bool,
        shieldOverrideUntil: Date?,
        successMessage: String?,
        errorMessage: String?,
        lockedGroupIDs: Set<UUID> = [],
        overrideGroupIDs: Set<UUID> = [],
        validGroupIDs: Set<UUID> = [],
        untrackedGroupIDs: Set<UUID> = [],
        overrideUntilByGroupID: [UUID: Date] = [:],
        usedTimeByGroupID: [UUID: Int] = [:],
        overrideBaselineUsedTimeByGroupID: [UUID: Int] = [:],
        overrideGrantedMinutesByGroupID: [UUID: Int] = [:],
        cooldownEndByGroupID: [UUID: Date] = [:],
        oneMinuteRemaining: Int = 0,
        oneMinuteDailyLimit: Int = ScreenTimeGroupPolicy.oneMinuteDailyLimit
    ) {
        self.groups = groups
        self.todayStats = todayStats
        self.isMonitoring = isMonitoring
        self.isShieldActive = isShieldActive
        self.shieldOverrideUntil = shieldOverrideUntil
        self.successMessage = successMessage
        self.errorMessage = errorMessage
        self.lockedGroupIDs = lockedGroupIDs
        self.overrideGroupIDs = overrideGroupIDs
        self.validGroupIDs = validGroupIDs
        self.untrackedGroupIDs = untrackedGroupIDs
        self.overrideUntilByGroupID = overrideUntilByGroupID
        self.usedTimeByGroupID = usedTimeByGroupID
        self.overrideBaselineUsedTimeByGroupID = overrideBaselineUsedTimeByGroupID
        self.overrideGrantedMinutesByGroupID = overrideGrantedMinutesByGroupID
        self.cooldownEndByGroupID = cooldownEndByGroupID
        self.oneMinuteRemaining = oneMinuteRemaining
        self.oneMinuteDailyLimit = oneMinuteDailyLimit
    }

    var maxGroupCount: Int { ScreenTimeGroupPolicy.maxGroupCount }
    var maxAppsPerGroup: Int { ScreenTimeGroupPolicy.maxAppsPerGroup }
    var isAtGroupLimit: Bool { groups.count >= maxGroupCount }

    var billTotalText: String {
        let total = todayStats.totalUnlockedSeconds
        guard total > 0 else { return String(localized: "home.bill.zero") }
        return String(localized: "home.bill.total \(goldTimeDurationText(seconds: total))")
    }

    var billComment: String {
        switch todayStats.totalUnlockedSeconds {
        case 0:
            return String(localized: "home.bill.comment0")
        case 1..<900:
            return String(localized: "home.bill.comment1")
        case 900..<1800:
            return String(localized: "home.bill.comment2")
        case 1800..<3600:
            return String(localized: "home.bill.comment3")
        case 3600..<5400:
            return String(localized: "home.bill.comment4")
        default:
            return String(localized: "home.bill.comment5")
        }
    }

    func statusTitle(for group: ScreenTimeGroup) -> String {
        if !group.isApplied {
            return String(localized: "home.status.needSetup")
        }
        if lockedGroupIDs.contains(group.id) {
            return lockedBadgeTitle(for: group)
        }
        if overrideGroupIDs.contains(group.id) {
            // 자정 직전 광고 연장은 모니터 없이 "자정까지" 풀리는 시간 기반 override라
            // 부여 분 개념이 없다(granted 미기록). 분 대신 "23:59까지 추가 사용"으로 표기.
            if isNearMidnightOverride(group) {
                let until = overrideUntilByGroupID[group.id]
                let endText = until.map { goldTimeClockText(date: $0) } ?? String(localized: "home.status.midnight")
                return String(localized: "home.status.extraUntil \(endText)")
            }
            // 부여된 분(진행바가 나타내는 총 시간)을 함께 표기. 실시간 갱신 아님.
            let granted = overrideGrantedMinutesByGroupID[group.id] ?? 1
            return String(localized: "home.status.extraMinutes \(granted)")
        }
        // 오늘이 '제한 없음' 요일이면 invalidReason 검사보다 앞에서 중립 배지로 처리한다
        // (안 하면 투영 ruleKind nil이 .groupHasNoRule로 떨어져 "설정 필요"로 오표시된다).
        if group.isUnrestricted(on: Date()) {
            return String(localized: "home.status.unrestrictedToday")
        }
        // 자정 직전 편집으로 추적이 멈춘 그룹: 분 진행 개념이 없어 바 대신 "23:59까지 사용 가능"으로.
        if isUntrackedNearMidnight(group) {
            return String(localized: "home.status.usableUntilMidnight")
        }
        if ScreenTimeGroupPolicy.invalidReason(for: group.policySnapshot) != nil {
            return String(localized: "home.status.needSetup")
        }
        if !isMonitoring {
            return String(localized: "home.status.waiting")
        }
        return availableBadgeTitle(for: group)
    }

    /// 잠금 중 뱃지 문구. 규칙별로 "언제까지 잠금"을 HH:mm으로 표기.
    /// 일일 한도는 오늘이 끝날 때까지라 "23:59까지 잠금", 쿨다운은 휴식 종료 시각, 시간대는 연속 시간대의 마지막 종료.
    /// 요일별 그룹은 오늘 투영 규칙 기준으로 판정한다.
    private func lockedBadgeTitle(for group: ScreenTimeGroup) -> String {
        let today = group.resolved(on: Date())
        switch today.ruleKind ?? .dailyLimit {
        case .dailyLimit:
            return String(localized: "home.status.lockedUntilMidnight")
        case .cooldown:
            if let end = cooldownEndByGroupID[group.id] {
                return String(localized: "home.status.lockedUntil \(goldTimeClockText(date: end))")
            }
            return String(localized: "home.status.locked")
        case .timeWindows:
            let minute = TimeWindowPolicy.minuteOfDay(for: Date())
            if let end = TimeWindowPolicy.contiguousWindowEnd(minuteOfDay: minute, windows: today.timeWindows) {
                return String(localized: "home.status.lockedUntil \(goldTimeClockText(minuteOfDay: end))")
            }
            return String(localized: "home.status.locked")
        }
    }

    /// 사용 가능 뱃지 문구. 시간대 규칙은 다음 차단 시작 시각까지, 그 외는 그냥 "사용 가능".
    /// 요일별 그룹은 오늘 투영 규칙 기준으로 판정한다.
    private func availableBadgeTitle(for group: ScreenTimeGroup) -> String {
        let today = group.resolved(on: Date())
        guard (today.ruleKind ?? .dailyLimit) == .timeWindows else {
            return String(localized: "home.status.available")
        }
        let minute = TimeWindowPolicy.minuteOfDay(for: Date())
        if let start = TimeWindowPolicy.nextWindowStart(minuteOfDay: minute, windows: today.timeWindows) {
            // 차단은 start 분부터(inclusive) 막히므로 마지막 사용 가능 분은 start - 1.
            // start가 00:00이면 전날 23:59로 wrap.
            let lastUsable = (start + 24 * 60 - 1) % (24 * 60)
            return String(localized: "home.status.usableUntil \(goldTimeClockText(minuteOfDay: lastUsable))")
        }
        return String(localized: "home.status.available")
    }

    /// 그룹 카드 아이콘. 색을 칠하는 statusTint(for:)와 같은 분기 순서를 따른다.
    /// orange 상태(설정 중/설정 필요)는 빈 방패, 잠금은 자물쇠 방패, 나머지는 체크 방패.
    /// 잠금/추가사용은 invalidReason보다 먼저 잡아 색(red/blue)과 아이콘이 어긋나지 않게 한다.
    func statusIcon(for group: ScreenTimeGroup) -> String {
        if !group.isApplied {
            return "shield"
        }
        if lockedGroupIDs.contains(group.id) {
            return "lock.shield.fill"
        }
        if overrideGroupIDs.contains(group.id) {
            return "checkmark.shield.fill"
        }
        // 오늘 '제한 없음' 요일은 invalidReason보다 먼저 잡아 중립 아이콘으로 둔다.
        if group.isUnrestricted(on: Date()) {
            return "shield.slash"
        }
        if ScreenTimeGroupPolicy.invalidReason(for: group.policySnapshot) != nil {
            return "shield"
        }
        return "checkmark.shield.fill"
    }

    func statusTint(for group: ScreenTimeGroup) -> Color {
        if !group.isApplied {
            return .orange
        }
        if lockedGroupIDs.contains(group.id) {
            return .red
        }
        if overrideGroupIDs.contains(group.id) {
            return .blue
        }
        // 오늘 '제한 없음' 요일은 invalidReason보다 먼저 잡아 중립 색으로 둔다.
        if group.isUnrestricted(on: Date()) {
            return .gray
        }
        if ScreenTimeGroupPolicy.invalidReason(for: group.policySnapshot) != nil {
            return .orange
        }
        return .green   // 적용 중 / 대기 중
    }

    /// 남은 시간을 10칸 블록 바로 표현하기 위한 진행도. 칸 수는 항상 10 고정.
    struct SegmentProgress {
        let total: Int
        let remaining: Int
        let accessibilityLabel: String
    }

    /// 잔여 시간(분)을 10칸 중 몇 칸으로 채울지 계산. 남은 시간이 있으면 최소 1칸 보장.
    private func segments(remainingMinutes: Int, totalMinutes: Int, total: Int = 10) -> Int {
        guard totalMinutes > 0 else { return 0 }
        let raw = (Double(remainingMinutes) / Double(totalMinutes) * Double(total)).rounded()
        return min(max(Int(raw), 1), total)
    }

    private func remainingMinutesLabel(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return h > 0 ? String(localized: "home.remaining.hourMinute \(h) \(m)") : String(localized: "home.remaining.minute \(m)")
    }

    func lockProgress(for group: ScreenTimeGroup) -> SegmentProgress? {
        // 사용량 진행바는 일일 한도와 쿨다운 그룹에 의미가 있다(쿨다운은 휴식 전 사용 예산 잔여).
        // 시간대 차단 그룹은 진행바 대신 시간대 요약을 보여준다. 요일별 그룹은 오늘 투영 규칙 기준.
        let today = group.resolved(on: Date())
        // 오늘 '제한 없음'(투영 ruleKind nil)은 진행바 없음.
        guard let kind = today.ruleKind else { return nil }
        let budget: Int
        switch kind {
        case .dailyLimit:
            budget = today.dailyLimitMinutes
        case .cooldown:
            budget = today.cooldownUsageMinutes
        case .timeWindows:
            return nil
        }
        guard validGroupIDs.contains(group.id),
              !lockedGroupIDs.contains(group.id),
              !overrideGroupIDs.contains(group.id),
              !untrackedGroupIDs.contains(group.id) else { return nil }
        let used = usedTimeByGroupID[group.id] ?? 0
        let remainingMin = budget - used
        guard remainingMin > 0 else { return nil }
        return SegmentProgress(
            total: 10,
            remaining: segments(remainingMinutes: remainingMin, totalMinutes: budget),
            accessibilityLabel: remainingMinutesLabel(remainingMin)
        )
    }

    /// 자정 직전 광고 연장으로 생긴 시간 기반 override인지. 이 override만 `recordOverrideBaseline`을
    /// 호출하지 않아 granted가 비어 있다(`clearOverride`가 종료 시 granted를 지우므로 stale 오염 없음).
    /// 분 진행 개념이 없으므로 "남은 한도" 바를 숨기고 배지를 "자정까지" 형태로 바꾸는 데 쓴다.
    func isNearMidnightOverride(_ group: ScreenTimeGroup) -> Bool {
        overrideGroupIDs.contains(group.id) && overrideGrantedMinutesByGroupID[group.id] == nil
    }

    /// 자정 직전 편집으로 모니터가 빠져 사용량 추적이 멈춘(잠기지도 않는) 일일/쿨다운 그룹인지.
    /// 연장의 `isNearMidnightOverride`와 같은 역할 — "남은 한도" 바를 숨기고 "23:59까지 사용 가능"
    /// 배지로 바꾸는 데 쓴다. 바가 있던(잠금·override 아님) 자리에만 적용된다.
    func isUntrackedNearMidnight(_ group: ScreenTimeGroup) -> Bool {
        guard untrackedGroupIDs.contains(group.id),
              validGroupIDs.contains(group.id),
              !lockedGroupIDs.contains(group.id),
              !overrideGroupIDs.contains(group.id) else { return false }
        // 요일별 그룹은 오늘 투영 규칙 기준. 오늘 '제한 없음'이면 해당 없음.
        guard let kind = group.resolved(on: Date()).ruleKind else { return false }
        switch kind {
        case .dailyLimit, .cooldown: return true
        case .timeWindows: return false
        }
    }

    func overrideProgress(for group: ScreenTimeGroup) -> SegmentProgress? {
        guard overrideGroupIDs.contains(group.id) else { return nil }
        // 시간 기반(자정까지) override는 분 진행 개념이 없어 진행바를 숨긴다.
        guard !isNearMidnightOverride(group) else { return nil }
        let baseline = overrideBaselineUsedTimeByGroupID[group.id] ?? 0
        let granted = overrideGrantedMinutesByGroupID[group.id] ?? 1
        let consumed = max(0, (usedTimeByGroupID[group.id] ?? 0) - baseline)
        let remainingMin = max(1, granted - consumed)
        // 칸 수는 분 단위로 끊으므로 granted 기준(최대 10). 1분 연장은 1칸, 광고 10분은 10칸.
        let cellCount = min(granted, 10)
        return SegmentProgress(
            total: cellCount,
            remaining: segments(remainingMinutes: remainingMin, totalMinutes: granted, total: cellCount),
            accessibilityLabel: remainingMinutesLabel(remainingMin)
        )
    }

    func groupHasDuplicateApps(_ group: ScreenTimeGroup) -> Bool {
        groups.contains { other in
            other.id != group.id
                && !other.selection.applicationTokens.isDisjoint(with: group.selection.applicationTokens)
        }
    }

    func limitLabel(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 {
            return String(localized: "home.limit.hourMinute \(h) \(m)")
        } else {
            return String(localized: "home.limit.minute \(m)")
        }
    }

    /// 규칙 종류의 표시 이름. 그룹 카드 규칙 행 제목 등에 사용.
    func ruleDisplayName(_ kind: GroupRuleKind) -> String {
        switch kind {
        case .dailyLimit:
            return String(localized: "rule.dailyLimit.title")
        case .timeWindows:
            return String(localized: "rule.timeWindows.title")
        case .cooldown:
            return String(localized: "rule.cooldown.title")
        }
    }

    /// 그룹 카드 규칙 행 제목. 요일별 그룹이면 "요일별 규칙", 규칙 미선택이면 "차단 규칙 선택", 선택했으면 규칙 이름.
    func ruleRowTitle(for group: ScreenTimeGroup) -> String {
        if group.usesWeekdayRules {
            return String(localized: "rule.weekday.title")
        }
        guard let kind = group.ruleKind else { return String(localized: "rule.selectPrompt") }
        return ruleDisplayName(kind)
    }

    /// 그룹 카드 규칙 행 부제. 요일별 그룹이면 "오늘: {오늘 규칙 요약}", 규칙 미선택이면 선택 안내, 선택했으면 규칙 요약.
    func ruleRowSubtitle(for group: ScreenTimeGroup) -> String {
        if group.usesWeekdayRules {
            return String(localized: "rule.weekday.today \(todayRuleSummary(for: group))")
        }
        guard group.ruleKind != nil else { return String(localized: "rule.selectSubtitle") }
        return ruleSummary(for: group)
    }

    /// 요일별 그룹의 오늘 규칙 짧은 요약. 오늘이 '제한 없음'이면 그 문구를, 아니면 규칙 요약을 돌려준다.
    private func todayRuleSummary(for group: ScreenTimeGroup) -> String {
        guard group.resolved(on: Date()).ruleKind != nil else {
            return String(localized: "rule.weekday.unrestricted")
        }
        return ruleSummary(for: group)
    }

    /// 그룹 카드 "차단 규칙" 행의 짧은 요약 값. dailyLimit은 한도, timeWindows는 시간대 요약.
    /// 요일별 그룹은 오늘 투영 규칙 기준으로 요약한다.
    func ruleSummary(for group: ScreenTimeGroup) -> String {
        let today = group.resolved(on: Date())
        switch today.ruleKind ?? .dailyLimit {
        case .dailyLimit:
            return limitLabel(today.dailyLimitMinutes)
        case .timeWindows:
            return timeWindowsSummary(today.timeWindows)
        case .cooldown:
            let usage = goldTimeDurationText(seconds: today.cooldownUsageMinutes * 60)
            let rest = goldTimeDurationText(seconds: today.cooldownDurationMinutes * 60)
            return String(localized: "rule.cooldown.summary \(usage) \(rest)")
        }
    }

    /// "21:00–22:00, 22:00–23:00" 식으로 모든 시간대를 시작시각 순으로 나열. 비어 있으면 설정 안내.
    func timeWindowsSummary(_ windows: [TimeWindow]) -> String {
        let sorted = windows.sorted { $0.startMinuteOfDay < $1.startMinuteOfDay }
        guard !sorted.isEmpty else {
            return String(localized: "rule.timeWindows.addPrompt")
        }
        return sorted
            .map { "\(goldTimeClockText(minuteOfDay: $0.startMinuteOfDay))–\(goldTimeClockText(minuteOfDay: $0.endMinuteOfDay))" }
            .joined(separator: ", ")
    }

    var hasBillCost: Bool {
        todayStats.totalUnlockedSeconds > 0
    }
}
