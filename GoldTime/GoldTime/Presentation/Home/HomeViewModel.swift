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

    var protectionStatusTitle: String {
        if isMonitoring {
            return "차단 규칙 적용 중"
        }
        if groups.isEmpty {
            return "설정 필요"
        }
        if validMonitoringGroups.isEmpty {
            return "설정 필요"
        }
        return "차단 규칙 대기"
    }

    var protectionStatusCaption: String {
        if isMonitoring {
            let count = validMonitoringGroups.count
            return count > 1 ? "\(count)개 유효 그룹에 규칙을 적용 중이에요" : "유효한 그룹에 규칙을 적용 중이에요"
        }
        if groups.isEmpty {
            return "그룹을 만들고 적용하면 보호가 시작돼요"
        }
        if validMonitoringGroups.isEmpty {
            return "항목과 규칙을 정해 적용한 그룹이 필요해요"
        }
        return "차단 규칙을 준비하고 있어요"
    }

    var protectionStatusIcon: String {
        isMonitoring ? "checkmark.shield.fill" : "shield"
    }

    var protectionStatusTint: Color {
        if isMonitoring {
            return .green
        }
        return validMonitoringGroups.isEmpty ? .secondary : Color.accent
    }

    var protectionSetupMessage: String? {
        guard !groups.isEmpty else {
            return nil
        }

        let invalidCount = invalidMonitoringGroups.count
        guard invalidCount > 0 else {
            return nil
        }

        if validMonitoringGroups.isEmpty {
            return "아직 적용할 수 있는 그룹이 없어요. 앱이나 웹 사이트를 하나 이상 담고 규칙을 정해 적용해 주세요."
        }

        return "\(invalidCount)개 그룹은 설정이 덜 끝나서 차단 규칙 적용에서 제외됐어요."
    }

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

    var shieldStatusValue: String {
        if isShieldActive {
            return "잠금 중"
        }
        if !overrideGroupIDs.isEmpty {
            return "연장 중"
        }
        return isMonitoring ? "사용 가능" : "대기 중"
    }

    var shieldStatusCaption: String {
        if isShieldActive {
            let locked = groups.filter { lockedGroupIDs.contains($0.id) }
            if locked.count > 1 {
                return "\(locked.count)개 그룹이 잠겨 있어요"
            }
            // 잠금 사유에 맞는 문구: 시간대 차단·쿨다운은 한도 초과가 아니다.
            if let group = locked.first {
                switch group.ruleKind ?? .dailyLimit {
                case .timeWindows:
                    return "차단 시간대예요"
                case .cooldown:
                    if let end = cooldownEndByGroupID[group.id] {
                        return "\(goldTimeClockText(date: end))까지 쉬는 중"
                    }
                    return "쉬는 중이에요"
                case .dailyLimit:
                    break
                }
            }
            return "한도를 넘겼어요"
        }
        if !overrideGroupIDs.isEmpty {
            let shortest = groups
                .filter { overrideGroupIDs.contains($0.id) }
                .map { group -> Int in
                    let baseline = overrideBaselineUsedTimeByGroupID[group.id] ?? 0
                    let granted = overrideGrantedMinutesByGroupID[group.id] ?? 1
                    let consumed = max(0, (usedTimeByGroupID[group.id] ?? 0) - baseline)
                    return max(1, granted - consumed)
                }
                .min()
            if let shortest {
                return "\(shortest)분 남음"
            }
            return "연장 중"
        }
        return isMonitoring ? "아직 한도 안쪽" : "설정 필요"
    }

    func statusTitle(for group: ScreenTimeGroup) -> String {
        if !group.isApplied {
            return "설정 중"
        }
        if lockedGroupIDs.contains(group.id) {
            return lockedBadgeTitle(for: group)
        }
        if overrideGroupIDs.contains(group.id) {
            // 부여된 분(진행바가 나타내는 총 시간)을 함께 표기. 실시간 갱신 아님.
            let granted = overrideGrantedMinutesByGroupID[group.id] ?? 1
            return "\(granted)분 연장중"
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
    /// 일일 한도는 자정 리셋이라 "00:00까지 잠금", 쿨다운은 휴식 종료 시각, 시간대는 연속 시간대의 마지막 종료.
    private func lockedBadgeTitle(for group: ScreenTimeGroup) -> String {
        switch group.ruleKind ?? .dailyLimit {
        case .dailyLimit:
            return "00:00까지 잠금"
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
            return "\(goldTimeClockText(minuteOfDay: start))까지 사용 가능"
        }
        return "사용 가능"
    }

    func statusTint(for group: ScreenTimeGroup) -> Color {
        if !group.isApplied {
            return .secondary
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

    func overrideProgress(for group: ScreenTimeGroup) -> SegmentProgress? {
        guard overrideGroupIDs.contains(group.id) else { return nil }
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

    private var validMonitoringGroups: [ScreenTimeGroup] {
        groups.filter { validGroupIDs.contains($0.id) }
    }

    /// 적용된 그룹 중 설정 미비로 모니터링에서 빠진 그룹.
    /// draft(미적용)는 "설정이 덜 끝난 그룹"이 아니라 적용 대기 상태이므로 제외한다.
    private var invalidMonitoringGroups: [ScreenTimeGroup] {
        groups.filter { group in
            group.isApplied
                && ScreenTimeGroupPolicy.invalidReason(for: group.policySnapshot) != nil
        }
    }

    var hasBillCost: Bool {
        todayStats.totalUnlockedSeconds > 0
    }
}
