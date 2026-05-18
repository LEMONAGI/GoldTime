//
//  StatsViewModel.swift
//  GoldTime
//

import Foundation

struct StatsViewModel {
    let groups: [SharedStore.ScreenTimeGroup]
    let todayStats: SharedStore.DailyStats
    let weeklyStats: [SharedStore.DailyStats]
    let oneMinuteRemaining: Int
    let isMonitoring: Bool

    var groupLimitValue: String {
        if groups.isEmpty {
            return "0그룹"
        }
        if groups.count == 1, let first = groups.first {
            return "\(first.dailyLimitMinutes)분"
        }
        return "\(groups.count)그룹"
    }

    var protectionGroupCaption: String {
        isMonitoring ? "유효 그룹 자동 적용" : "설정 필요"
    }

    var weeklyWalkAwayCount: Int {
        weeklyStats.reduce(0) { $0 + $1.walkAwayCount }
    }

    var hasWeeklyWalkAway: Bool {
        weeklyStats.contains { $0.walkAwayCount > 0 }
    }
}
