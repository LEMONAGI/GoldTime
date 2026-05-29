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
        self.oneMinuteRemaining = oneMinuteRemaining
        self.oneMinuteDailyLimit = oneMinuteDailyLimit
    }

    var maxGroupCount: Int { ScreenTimeGroupPolicy.maxGroupCount }
    var maxAppsPerGroup: Int { ScreenTimeGroupPolicy.maxAppsPerGroup }
    var isAtGroupLimit: Bool { groups.count >= maxGroupCount }

    var protectionStatusTitle: String {
        if isMonitoring {
            return "자동 적용 중"
        }
        if groups.isEmpty {
            return "설정 필요"
        }
        if validMonitoringGroups.isEmpty {
            return "설정 필요"
        }
        return "자동 적용 대기"
    }

    var protectionStatusCaption: String {
        if isMonitoring {
            let count = validMonitoringGroups.count
            return count > 1 ? "\(count)개 유효 그룹에 한도를 적용 중이에요" : "유효한 그룹에 한도를 적용 중이에요"
        }
        if groups.isEmpty {
            return "그룹을 만들고 항목을 담으면 바로 적용돼요"
        }
        if validMonitoringGroups.isEmpty {
            return "항목과 한도가 설정된 그룹이 필요해요"
        }
        return "자동 적용을 준비하고 있어요"
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
            return "아직 적용할 수 있는 그룹이 없어요. 앱이나 웹 사이트를 하나 이상 담고 한도를 정해주세요."
        }

        return "\(invalidCount)개 그룹은 설정이 덜 끝나서 자동 적용에서 제외됐어요."
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
            let count = lockedGroupIDs.count
            return count > 1 ? "\(count)개 그룹이 한도에 닿았어요" : "한도를 넘겼어요"
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
        if lockedGroupIDs.contains(group.id) {
            return "잠금 중"
        }
        if overrideGroupIDs.contains(group.id) {
            return "연장 중"
        }
        if ScreenTimeGroupPolicy.invalidReason(for: group.policySnapshot) != nil {
            return "설정 필요"
        }
        return isMonitoring ? "적용 중" : "대기 중"
    }

    func statusTint(for group: ScreenTimeGroup) -> Color {
        switch statusTitle(for: group) {
        case "잠금 중":
            return .red
        case "연장 중":
            return .blue
        case "적용 중", "대기 중":
            return .green
        case "설정 필요":
            return .orange
        default:
            return .secondary
        }
    }

    func remainingBeforeLockLabel(for group: ScreenTimeGroup) -> String? {
        guard validGroupIDs.contains(group.id),
              !lockedGroupIDs.contains(group.id),
              !overrideGroupIDs.contains(group.id) else { return nil }
        let used = usedTimeByGroupID[group.id] ?? 0
        let remaining = group.dailyLimitMinutes - used
        guard remaining > 0 else { return nil }
        let h = remaining / 60
        let m = remaining % 60
        if h > 0 {
            return "\(h)시간 \(m)분 남음"
        } else {
            return "\(m)분 남음"
        }
    }

    func overrideRemainingLabel(for group: ScreenTimeGroup) -> String? {
        guard overrideGroupIDs.contains(group.id) else { return nil }
        let baseline = overrideBaselineUsedTimeByGroupID[group.id] ?? 0
        let granted = overrideGrantedMinutesByGroupID[group.id] ?? 1
        let consumed = max(0, (usedTimeByGroupID[group.id] ?? 0) - baseline)
        let remaining = max(1, granted - consumed)
        return "\(remaining)분 남음"
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

    private var validMonitoringGroups: [ScreenTimeGroup] {
        groups.filter { validGroupIDs.contains($0.id) }
    }

    private var invalidMonitoringGroups: [ScreenTimeGroup] {
        groups.filter { group in
            ScreenTimeGroupPolicy.invalidReason(for: group.policySnapshot) != nil
        }
    }

    var hasBillCost: Bool {
        todayStats.totalUnlockedSeconds > 0
    }
}
