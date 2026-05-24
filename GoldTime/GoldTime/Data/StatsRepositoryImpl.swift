
import Foundation

struct StatsRepositoryImpl: StatsRepository {
    var todayStats: DailyStats { SharedStore.todayStats.toDomain() }

    func lastSevenDayStats() -> [DailyStats] { SharedStore.lastSevenDayStats().map { $0.toDomain() } }
    func previousSevenDayStats() -> [DailyStats] { SharedStore.previousSevenDayStats().map { $0.toDomain() } }
    func lastNDayStats(_ n: Int) -> [DailyStats] { SharedStore.lastNDayStats(n).map { $0.toDomain() } }
    func statsForCalendarWeek(weekOffset: Int) -> [DailyStats] {
        SharedStore.statsForCalendarWeek(weekOffset: weekOffset).map { $0.toDomain() }
    }
    func statsForCalendarMonth(monthOffset: Int) -> [DailyStats] {
        SharedStore.statsForCalendarMonth(monthOffset: monthOffset).map { $0.toDomain() }
    }
    func calendarWeekRange(weekOffset: Int) -> (start: Date, end: Date)? {
        let range = SharedStore.calendarWeekRange(weekOffset: weekOffset)
        return (start: range.start, end: range.end)
    }
    func calendarMonthRange(monthOffset: Int) -> (start: Date, end: Date)? {
        let range = SharedStore.calendarMonthRange(monthOffset: monthOffset)
        return (start: range.start, end: range.end)
    }
    func allDailyStats() -> [DailyStats] { SharedStore.allDailyStats.map { $0.toDomain() } }
    var oldestStatDate: Date? { SharedStore.oldestStatDate }
}

private extension SharedStore.DailyStats {
    func toDomain() -> DailyStats {
        DailyStats(
            dateKey: dateKey,
            adWatchCount: adWatchCount,
            adUnlockedSeconds: adUnlockedSeconds,
            oneMinuteUsedCount: oneMinuteUsedCount,
            shieldHitCount: shieldHitCount,
            walkAwayCount: walkAwayCount
        )
    }
}
