
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

    var weeklyAverageSeconds: Int {
        averageUnlockedSeconds(from: weeklyStats)
    }

    var previousWeekAverageSeconds: Int {
        averageUnlockedSeconds(from: previousWeekStats)
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

    private func averageUnlockedSeconds(from stats: [DailyStats]) -> Int {
        let today = Calendar.current.startOfDay(for: Date())
        let floor: Date = trackingStartDate ?? .distantPast
        let relevant = stats.filter { $0.date >= floor && $0.date <= today }
        guard !relevant.isEmpty else { return 0 }
        return relevant.reduce(0) { $0 + $1.totalUnlockedSeconds } / relevant.count
    }
}
