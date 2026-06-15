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
        guard total > 0 else { return "0분" }
        return "+\(goldTimeDurationText(seconds: total))"
    }

    var billComment: String {
        switch todayStats.totalUnlockedSeconds {
        case 0:
            return "좋은 날입니다. 저한텐 아니고요."
        case 1..<900:
            return "이 정도면 살짝 눈 감아드릴 수 있어요."
        case 900..<1800:
            return "계산서 나왔어요. 확인해보실래요?"
        case 1800..<3600:
            return "제법 하시는데요. 청구서 두께가 느껴지시죠?"
        case 3600..<5400:
            return "슬슬 기분이 좋아지는데요. 제가요."
        default:
            return "좋은 날입니다. 이번엔 저한테요."
        }
    }

    func statusTitle(for group: ScreenTimeGroup) -> String {
        if !group.isApplied {
            return "설정 필요"
        }
        if lockedGroupIDs.contains(group.id) {
            return lockedBadgeTitle(for: group)
        }
        if overrideGroupIDs.contains(group.id) {
            // 자정 직전 광고 연장은 모니터 없이 "자정까지" 풀리는 시간 기반 override라
            // 부여 분 개념이 없다(granted 미기록). 분 대신 "23:59까지 추가 사용"으로 표기.
            if isNearMidnightOverride(group) {
                let until = overrideUntilByGroupID[group.id]
                let endText = until.map { goldTimeClockText(date: $0) } ?? "자정"
                return "\(endText)까지 추가 사용"
            }
            // 부여된 분(진행바가 나타내는 총 시간)을 함께 표기. 실시간 갱신 아님.
            let granted = overrideGrantedMinutesByGroupID[group.id] ?? 1
            return "\(granted)분 추가 사용"
        }
        if ScreenTimeGroupPolicy.invalidReason(for: group.policySnapshot) != nil {
            return "설정 필요"
        }
        if !isMonitoring {
            return "대기 중"
        }
        return availableBadgeTitle(for: group)
    }

    /// 잠금 중 뱃지 문구. 규칙별로 "언제까지 잠금"을 HH:mm으로 표기.
    /// 일일 한도는 오늘이 끝날 때까지라 "23:59까지 잠금", 쿨다운은 휴식 종료 시각, 시간대는 연속 시간대의 마지막 종료.
    private func lockedBadgeTitle(for group: ScreenTimeGroup) -> String {
        switch group.ruleKind ?? .dailyLimit {
        case .dailyLimit:
            return "23:59까지 잠금"
        case .cooldown:
            if let end = cooldownEndByGroupID[group.id] {
                return "\(goldTimeClockText(date: end))까지 잠금"
            }
            return "잠금 중"
        case .timeWindows:
            let minute = TimeWindowPolicy.minuteOfDay(for: Date())
            if let end = TimeWindowPolicy.contiguousWindowEnd(minuteOfDay: minute, windows: group.timeWindows) {
                return "\(goldTimeClockText(minuteOfDay: end))까지 잠금"
            }
            return "잠금 중"
        }
    }

    /// 사용 가능 뱃지 문구. 시간대 규칙은 다음 차단 시작 시각까지, 그 외는 그냥 "사용 가능".
    private func availableBadgeTitle(for group: ScreenTimeGroup) -> String {
        guard (group.ruleKind ?? .dailyLimit) == .timeWindows else {
            return "사용 가능"
        }
        let minute = TimeWindowPolicy.minuteOfDay(for: Date())
        if let start = TimeWindowPolicy.nextWindowStart(minuteOfDay: minute, windows: group.timeWindows) {
            // 차단은 start 분부터(inclusive) 막히므로 마지막 사용 가능 분은 start - 1.
            // start가 00:00이면 전날 23:59로 wrap.
            let lastUsable = (start + 24 * 60 - 1) % (24 * 60)
            return "\(goldTimeClockText(minuteOfDay: lastUsable))까지 사용 가능"
        }
        return "사용 가능"
    }

    /// 그룹 카드 아이콘. 색을 칠하는 statusTint(for:)와 같은 분기 순서를 따른다.
    /// orange 상태(설정 중/설정 필요)는 빈 방패, 그 외(잠금·추가사용·사용 가능)는 체크 방패.
    /// 잠금/추가사용은 invalidReason보다 먼저 잡아 색(red/blue)과 아이콘이 어긋나지 않게 한다.
    func statusIcon(for group: ScreenTimeGroup) -> String {
        if !group.isApplied {
            return "shield"
        }
        if lockedGroupIDs.contains(group.id) || overrideGroupIDs.contains(group.id) {
            return "checkmark.shield.fill"
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
        return h > 0 ? "약 \(h)시간 \(m)분 남음" : "약 \(m)분 남음"
    }

    func lockProgress(for group: ScreenTimeGroup) -> SegmentProgress? {
        // 사용량 진행바는 일일 한도와 쿨다운 그룹에 의미가 있다(쿨다운은 휴식 전 사용 예산 잔여).
        // 시간대 차단 그룹은 진행바 대신 시간대 요약을 보여준다.
        let budget: Int
        switch group.ruleKind ?? .dailyLimit {
        case .dailyLimit:
            budget = group.dailyLimitMinutes
        case .cooldown:
            budget = group.cooldownUsageMinutes
        case .timeWindows:
            return nil
        }
        guard validGroupIDs.contains(group.id),
              !lockedGroupIDs.contains(group.id),
              !overrideGroupIDs.contains(group.id) else { return nil }
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
            return "\(h)시간 \(m)분 넘기면 이 그룹이 잠겨요"
        } else {
            return "\(m)분 넘기면 이 그룹이 잠겨요"
        }
    }

    /// 규칙 종류의 표시 이름. 그룹 카드 규칙 행 제목 등에 사용.
    func ruleDisplayName(_ kind: GroupRuleKind) -> String {
        switch kind {
        case .dailyLimit:
            return "일일 한도 제한"
        case .timeWindows:
            return "시간대별 차단"
        case .cooldown:
            return "쿨다운 잠금"
        }
    }

    /// 그룹 카드 규칙 행 제목. 규칙 미선택이면 "차단 규칙 선택", 선택했으면 규칙 이름.
    func ruleRowTitle(for group: ScreenTimeGroup) -> String {
        guard let kind = group.ruleKind else { return "차단 규칙 선택" }
        return ruleDisplayName(kind)
    }

    /// 그룹 카드 규칙 행 부제. 규칙 미선택이면 선택 안내, 선택했으면 규칙 요약.
    func ruleRowSubtitle(for group: ScreenTimeGroup) -> String {
        guard group.ruleKind != nil else { return "원하는 규칙을 선택하세요" }
        return ruleSummary(for: group)
    }

    /// 그룹 카드 "차단 규칙" 행의 짧은 요약 값. dailyLimit은 한도, timeWindows는 시간대 요약.
    func ruleSummary(for group: ScreenTimeGroup) -> String {
        switch group.ruleKind ?? .dailyLimit {
        case .dailyLimit:
            return limitLabel(group.dailyLimitMinutes)
        case .timeWindows:
            return timeWindowsSummary(group.timeWindows)
        case .cooldown:
            let usage = goldTimeDurationText(seconds: group.cooldownUsageMinutes * 60)
            let rest = goldTimeDurationText(seconds: group.cooldownDurationMinutes * 60)
            return "\(usage) 쓰면 \(rest) 휴식"
        }
    }

    /// "21:00–22:00, 22:00–23:00" 식으로 모든 시간대를 시작시각 순으로 나열. 비어 있으면 설정 안내.
    func timeWindowsSummary(_ windows: [TimeWindow]) -> String {
        let sorted = windows.sorted { $0.startMinuteOfDay < $1.startMinuteOfDay }
        guard !sorted.isEmpty else {
            return "차단 시간대를 추가해 주세요"
        }
        return sorted
            .map { "\(goldTimeClockText(minuteOfDay: $0.startMinuteOfDay))–\(goldTimeClockText(minuteOfDay: $0.endMinuteOfDay))" }
            .joined(separator: ", ")
    }

    var hasBillCost: Bool {
        todayStats.totalUnlockedSeconds > 0
    }
}
