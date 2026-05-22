//
//  StatsViewModel.swift
//  GoldTime
//

import Foundation

enum TrendDirection {
    case up
    case down
    case flat
}

struct StatsViewModel {
    let groups: [SharedStore.ScreenTimeGroup]
    let todayStats: SharedStore.DailyStats
    let weeklyStats: [SharedStore.DailyStats]
    let previousWeekStats: [SharedStore.DailyStats]
    let isMonitoring: Bool
    let adFreeStreakDays: Int
    let maxAdFreeStreakDays: Int

    // weeklyStats: [today-6, today-5, ..., today-1, today] (index 5 = yesterday, index 6 = today)
    var yesterdayAdUnlockedSeconds: Int {
        weeklyStats.count >= 6 ? weeklyStats[5].adUnlockedSeconds : 0
    }

    var todayVsYesterdayDelta: Int {
        todayStats.adUnlockedSeconds - yesterdayAdUnlockedSeconds
    }

    var todayDeltaCaption: String {
        let hasAnyData = yesterdayAdUnlockedSeconds > 0 || todayStats.adUnlockedSeconds > 0
        guard hasAnyData else { return "어제도 오늘도 없어요" }
        let d = todayVsYesterdayDelta
        if d == 0 { return "어제와 같아요" }
        let text = goldTimeDurationText(seconds: abs(d))
        return d < 0 ? "어제보다 \(text) 적어요" : "어제보다 \(text) 많아요"
    }

    var weeklyAdUnlockedSeconds: Int {
        weeklyStats.reduce(0) { $0 + $1.adUnlockedSeconds }
    }

    var previousWeekAdUnlockedSeconds: Int {
        previousWeekStats.reduce(0) { $0 + $1.adUnlockedSeconds }
    }

    var weeklyDelta: Int {
        weeklyAdUnlockedSeconds - previousWeekAdUnlockedSeconds
    }

    var weeklyDeltaCaption: String {
        guard previousWeekAdUnlockedSeconds > 0 else { return "지난 주 기록 없음" }
        if weeklyDelta == 0 { return "지난 주와 같아요" }
        let text = goldTimeDurationText(seconds: abs(weeklyDelta))
        return weeklyDelta < 0 ? "지난 주보다 \(text) 적어요" : "지난 주보다 \(text) 많아요"
    }

    var weeklyMaxMinutes: Int {
        weeklyStats.map { $0.adUnlockedSeconds / 60 }.max() ?? 0
    }

    var todayTrend: TrendDirection? {
        let hasAnyData = yesterdayAdUnlockedSeconds > 0 || todayStats.adUnlockedSeconds > 0
        guard hasAnyData else { return nil }
        if todayVsYesterdayDelta > 0 { return .up }
        if todayVsYesterdayDelta < 0 { return .down }
        return .flat
    }

    var weeklyTrend: TrendDirection? {
        guard previousWeekAdUnlockedSeconds > 0 else { return nil }
        if weeklyDelta > 0 { return .up }
        if weeklyDelta < 0 { return .down }
        return .flat
    }

    var streakSentiment: CardSentiment {
        adFreeStreakDays > 0 ? .positive : .negative
    }

    var todaySentiment: CardSentiment? {
        switch todayTrend {
        case .up: .negative
        case .down: .positive
        default: nil
        }
    }

    var weeklySentiment: CardSentiment? {
        switch weeklyTrend {
        case .up: .negative
        case .down: .positive
        default: nil
        }
    }
}
