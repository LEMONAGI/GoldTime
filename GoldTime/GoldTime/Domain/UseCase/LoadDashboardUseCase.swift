
import Foundation

struct DashboardState {
    let isShieldActive: Bool
    let oneMinuteRemaining: Int
    let shieldOverrideUntil: Date?
    let overrideUntilByGroupID: [UUID: Date]
    let todayStats: DailyStats
    let weeklyStats: [DailyStats]
    let previousWeekStats: [DailyStats]
    let adFreeStreakDays: Int
    let isDailyMonitoringEnabled: Bool
    let lockedGroupIDs: Set<UUID>
    let overrideGroupIDs: Set<UUID>
    let validGroupIDs: Set<UUID>
}

final class LoadDashboardUseCase {
    private let shieldRepository: any ShieldRepository
    private let statsRepository: any StatsRepository
    private let screenTimeRepository: any ScreenTimeRepository

    init(
        shieldRepository: any ShieldRepository,
        statsRepository: any StatsRepository,
        screenTimeRepository: any ScreenTimeRepository
    ) {
        self.shieldRepository = shieldRepository
        self.statsRepository = statsRepository
        self.screenTimeRepository = screenTimeRepository
    }

    func load(groups: [ScreenTimeGroup]) -> DashboardState {
        buildState(groups: groups)
    }

    // reapplyShieldIfOverrideExpired 포함 — 1초 타이머에서 호출
    func refresh(groups: [ScreenTimeGroup]) -> DashboardState {
        screenTimeRepository.reapplyShieldIfOverrideExpired()
        return buildState(groups: groups)
    }

    private func buildState(groups: [ScreenTimeGroup]) -> DashboardState {
        let validGroups = screenTimeRepository.validDailyMonitoringGroups(from: groups)
        return DashboardState(
            isShieldActive: shieldRepository.isShieldActive,
            oneMinuteRemaining: shieldRepository.oneMinuteRemaining,
            shieldOverrideUntil: shieldRepository.currentShieldOverrideUntil,
            overrideUntilByGroupID: shieldRepository.overrideUntilByGroupID,
            todayStats: statsRepository.todayStats,
            weeklyStats: statsRepository.lastSevenDayStats(),
            previousWeekStats: statsRepository.previousSevenDayStats(),
            adFreeStreakDays: calculateAdFreeStreak(),
            isDailyMonitoringEnabled: screenTimeRepository.isDailyMonitoringEnabled,
            lockedGroupIDs: Set(shieldRepository.lockedGroups().map(\.id)),
            overrideGroupIDs: Set(shieldRepository.groupsInOverride().map(\.id)),
            validGroupIDs: Set(validGroups.map(\.id))
        )
    }

    func calculateAdFreeStreak() -> Int {
        guard let firstDate = statsRepository.oldestStatDate else { return 0 }
        let stats = statsRepository.lastNDayStats(30)
        var streak = 0
        for dailyStat in stats.reversed() {
            guard dailyStat.date >= firstDate else { break }
            if dailyStat.adWatchCount > 0 { break }
            streak += 1
        }
        return streak
    }
}
