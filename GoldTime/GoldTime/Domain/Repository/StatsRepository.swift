
import Foundation

protocol StatsRepository {
    var todayStats: DailyStats { get }
    func lastSevenDayStats() -> [DailyStats]
    func previousSevenDayStats() -> [DailyStats]
    func lastNDayStats(_ n: Int) -> [DailyStats]
    func statsForCalendarWeek(weekOffset: Int) -> [DailyStats]
    func statsForCalendarMonth(monthOffset: Int) -> [DailyStats]
    func calendarWeekRange(weekOffset: Int) -> (start: Date, end: Date)?
    func calendarMonthRange(monthOffset: Int) -> (start: Date, end: Date)?
    func allDailyStats() -> [DailyStats]
    var oldestStatDate: Date? { get }
}
