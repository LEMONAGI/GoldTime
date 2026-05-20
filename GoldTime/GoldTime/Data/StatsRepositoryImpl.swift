
import Foundation

struct StatsRepositoryImpl: StatsRepository {
    var todayStats: DailyStats { SharedStore.todayStats }

    func lastSevenDayStats() -> [DailyStats] { SharedStore.lastSevenDayStats() }
    func previousSevenDayStats() -> [DailyStats] { SharedStore.previousSevenDayStats() }
    func lastNDayStats(_ n: Int) -> [DailyStats] { SharedStore.lastNDayStats(n) }
    var oldestStatDate: Date? { SharedStore.oldestStatDate }
}
