
import Foundation

struct StatsRepositoryImpl: StatsRepository {
    var todayStats: DailyStats { SharedStore.todayStats }

    func lastSevenDayStats() -> [DailyStats] {
        SharedStore.lastSevenDayStats()
    }
}
