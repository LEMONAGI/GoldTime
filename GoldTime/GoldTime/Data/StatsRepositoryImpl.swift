
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
    // 모니터링 시작 마커와 첫 통계 기록 중 더 이른 날. 마커 도입 전 설치된 기기도 기존 기록을 보존한다.
    var trackingStartDate: Date? {
        [SharedStore.statsTrackingStartDate, SharedStore.oldestStatDate].compactMap { $0 }.min()
    }
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
