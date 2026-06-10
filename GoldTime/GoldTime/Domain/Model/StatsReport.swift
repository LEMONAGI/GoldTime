
import Foundation

struct StatsReport {
    let todayStats: DailyStats
    let weeklyStats: [DailyStats]
    let previousWeekStats: [DailyStats]
    let monthlyStats: [DailyStats]
    /// 기록 추적 시작일. 이 날짜 이후의 0분 날도 평균 분모에 포함된다.
    let trackingStartDate: Date?

    var yesterdayUnlockedSeconds: Int {
        let key = DailyStats.dateKey(for: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        return (weeklyStats + previousWeekStats).first(where: { $0.dateKey == key })?.totalUnlockedSeconds ?? 0
    }

    var todayDelta: Int {
        todayStats.totalUnlockedSeconds - yesterdayUnlockedSeconds
    }

    var weeklyUnlockedSeconds: Int {
        weeklyStats.reduce(0) { $0 + $1.totalUnlockedSeconds }
    }

    var previousWeekUnlockedSeconds: Int {
        previousWeekStats.reduce(0) { $0 + $1.totalUnlockedSeconds }
    }

    var weeklyDelta: Int {
        weeklyUnlockedSeconds - previousWeekUnlockedSeconds
    }

    var weeklyAverageSeconds: Int {
        averageUnlockedSeconds(from: weeklyStats)
    }

    var previousWeekAverageSeconds: Int {
        averageUnlockedSeconds(from: previousWeekStats)
    }

    var weeklyAverageDelta: Int {
        weeklyAverageSeconds - previousWeekAverageSeconds
    }

    var monthlyAverageSeconds: Int {
        averageUnlockedSeconds(from: monthlyStats)
    }

    var weeklyMaxMinutes: Int {
        weeklyStats.map { $0.totalUnlockedSeconds / 60 }.max() ?? 0
    }

    var monthlyMaxMinutes: Int {
        monthlyStats.map { $0.totalUnlockedSeconds / 60 }.max() ?? 0
    }

    var todayTrend: TrendDirection? {
        let hasAnyData = yesterdayUnlockedSeconds > 0 || todayStats.totalUnlockedSeconds > 0
        guard hasAnyData else { return nil }
        if todayDelta > 0 { return .up }
        if todayDelta < 0 { return .down }
        return .flat
    }

    var weeklyTrend: TrendDirection? {
        guard previousWeekUnlockedSeconds > 0 else { return nil }
        if weeklyDelta > 0 { return .up }
        if weeklyDelta < 0 { return .down }
        return .flat
    }

    private func averageUnlockedSeconds(from stats: [DailyStats]) -> Int {
        let today = Calendar.current.startOfDay(for: Date())
        let floor: Date = trackingStartDate ?? .distantPast
        let relevant = stats.filter { $0.date >= floor && $0.date <= today }
        guard !relevant.isEmpty else { return 0 }
        return relevant.reduce(0) { $0 + $1.totalUnlockedSeconds } / relevant.count
    }
}
