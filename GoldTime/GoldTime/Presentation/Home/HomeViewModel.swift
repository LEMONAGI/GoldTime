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
        overrideUntilByGroupID: [UUID: Date] = [:]
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
    }

    var maxGroupCount: Int { SharedStore.maxGroupCount }
    var maxAppsPerGroup: Int { SharedStore.maxAppsPerGroup }
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
            return "그룹을 만들고 앱을 담으면 바로 적용돼요"
        }
        if validMonitoringGroups.isEmpty {
            return "앱과 한도가 설정된 그룹이 필요해요"
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
            return "아직 적용할 수 있는 그룹이 없어요. 앱을 하나 이상 담고 한도를 정해주세요."
        }

        return "\(invalidCount)개 그룹은 설정이 덜 끝나서 자동 적용에서 제외됐어요."
    }

    var billSummaryLine: String {
        if hasBillCost {
            return "광고 \(todayStats.adWatchCount)개. 추가 사용 \(goldTimeDurationText(seconds: todayStats.adUnlockedSeconds))."
        }
        return "광고 없음. 추가 사용 없음."
    }

    var billComment: String {
        if !hasBillCost, todayStats.walkAwayCount > 0 {
            return "광고 안 보면 당신 승리예요. 저는 손해고요."
        }
        if !hasBillCost {
            return "좋은 날입니다. 저한텐 아니고요."
        }
        return "계산서 나왔어요."
    }

    var shieldStatusValue: String {
        if isShieldActive {
            return "잠금 중"
        }
        if let shieldOverrideUntil, shieldOverrideUntil.timeIntervalSinceNow > 0.5 {
            return "연장 중"
        }
        return isMonitoring ? "사용 가능" : "대기 중"
    }

    var shieldStatusCaption: String {
        if isShieldActive {
            let count = lockedGroupIDs.count
            return count > 1 ? "\(count)개 그룹이 한도에 닿았어요" : "한도를 넘겼어요"
        }
        if let shieldOverrideUntil, shieldOverrideUntil.timeIntervalSinceNow > 0.5 {
            let seconds = max(1, Int(shieldOverrideUntil.timeIntervalSinceNow.rounded(.up)))
            return "\(goldTimeDurationText(seconds: seconds)) 뒤 재잠금"
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

    func overrideRemainingLabel(for group: ScreenTimeGroup) -> String? {
        guard let until = overrideUntilByGroupID[group.id] else { return nil }
        let seconds = until.timeIntervalSinceNow
        guard seconds > 0.5 else { return nil }
        return "\(goldTimeDurationText(seconds: Int(seconds.rounded(.up)))) 뒤 재잠금"
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
            return "\(h)시간 \(m)분 넘기면 이 그룹만 잠겨요"
        } else {
            return "\(m)분 넘기면 이 그룹만 잠겨요"
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
        todayStats.adWatchCount > 0
            || todayStats.adUnlockedSeconds > 0
            || todayStats.oneMinuteUsedCount > 0
    }
}
