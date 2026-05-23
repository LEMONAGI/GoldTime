
import Foundation

protocol StatsRepository {
    var todayStats: DailyStats { get }
    func lastSevenDayStats() -> [DailyStats]
    func previousSevenDayStats() -> [DailyStats]
    func lastNDayStats(_ n: Int) -> [DailyStats]
    func statsForCalendarWeek(weekOffset: Int) -> [DailyStats]
    var oldestStatDate: Date? { get }
}
