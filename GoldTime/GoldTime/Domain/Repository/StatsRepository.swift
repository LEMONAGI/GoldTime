
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
    /// 기록 추적 시작일. 이 날짜 이후로는 통계가 없는 날도 "0분 기록"으로 취급한다.
    var trackingStartDate: Date? { get }
}
