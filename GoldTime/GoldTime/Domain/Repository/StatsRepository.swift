
import Foundation

protocol StatsRepository {
    var todayStats: DailyStats { get }
    func lastSevenDayStats() -> [DailyStats]
}
