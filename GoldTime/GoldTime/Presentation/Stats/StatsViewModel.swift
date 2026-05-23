//
//  StatsViewModel.swift
//  GoldTime
//

import Foundation

func averageUnlockedSeconds(
    from stats: [SharedStore.DailyStats],
    today: Date = Calendar.current.startOfDay(for: Date()),
    oldest: Date? = nil
) -> Int {
    let floor: Date = oldest ?? .distantPast
    let relevant = stats.filter { $0.date >= floor && $0.date <= today }
    guard !relevant.isEmpty else { return 0 }
    return relevant.reduce(0) { $0 + $1.totalUnlockedSeconds } / relevant.count
}

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
    let monthlyStats: [SharedStore.DailyStats]
    let isMonitoring: Bool
    let adFreeStreakDays: Int
    let maxAdFreeStreakDays: Int

    // weeklyStats: 현재 달력 주(월 or 일 시작)의 7일 통계, 순서 = 주 시작일부터
    var yesterdayAdUnlockedSeconds: Int {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let key = fmt.string(from: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        return weeklyStats.first(where: { $0.dateKey == key })?.totalUnlockedSeconds ?? 0
    }

    var todayVsYesterdayDelta: Int {
        todayStats.totalUnlockedSeconds - yesterdayAdUnlockedSeconds
    }

    var todayDeltaCaption: String {
        let hasAnyData = yesterdayAdUnlockedSeconds > 0 || todayStats.totalUnlockedSeconds > 0
        guard hasAnyData else { return "어제도 오늘도 없어요" }
        let d = todayVsYesterdayDelta
        if d == 0 { return "어제와 같아요" }
        let text = goldTimeDurationText(seconds: abs(d))
        return d < 0 ? "어제보다 \(text) 적어요" : "어제보다 \(text) 많아요"
    }

    var weeklyAdUnlockedSeconds: Int {
        weeklyStats.reduce(0) { $0 + $1.totalUnlockedSeconds }
    }

    var previousWeekAdUnlockedSeconds: Int {
        previousWeekStats.reduce(0) { $0 + $1.totalUnlockedSeconds }
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

    var weeklyAverageSeconds: Int {
        averageUnlockedSeconds(from: weeklyStats, oldest: SharedStore.oldestStatDate)
    }

    var weeklyMaxMinutes: Int {
        weeklyStats.map { $0.totalUnlockedSeconds / 60 }.max() ?? 0
    }

    var monthlyAverageSeconds: Int {
        averageUnlockedSeconds(from: monthlyStats, oldest: SharedStore.oldestStatDate)
    }

    var monthlyMaxMinutes: Int {
        monthlyStats.map { $0.totalUnlockedSeconds / 60 }.max() ?? 0
    }

    var todayTrend: TrendDirection? {
        let hasAnyData = yesterdayAdUnlockedSeconds > 0 || todayStats.totalUnlockedSeconds > 0
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
