//
//  StatsViewModel.swift
//  GoldTime
//

import Foundation

@MainActor
@Observable
final class StatsViewModel {
    private let statsRepository: any StatsRepository

    var groups: [ScreenTimeGroup]
    var statsReport: StatsReport
    var isMonitoring: Bool
    var adFreeStreakDays: Int
    var maxAdFreeStreakDays: Int

    init(
        groups: [ScreenTimeGroup],
        statsReport: StatsReport,
        isMonitoring: Bool,
        adFreeStreakDays: Int,
        maxAdFreeStreakDays: Int,
        statsRepository: (any StatsRepository)? = nil
    ) {
        self.groups = groups
        self.statsReport = statsReport
        self.isMonitoring = isMonitoring
        self.adFreeStreakDays = adFreeStreakDays
        self.maxAdFreeStreakDays = maxAdFreeStreakDays
        self.statsRepository = statsRepository ?? StatsRepositoryImpl()
    }

    // MARK: - On-demand paginated queries for graph sections

    func weeklyStats(offset: Int) -> [DailyStats] {
        statsRepository.statsForCalendarWeek(weekOffset: offset)
    }

    func monthlyStats(offset: Int) -> [DailyStats] {
        statsRepository.statsForCalendarMonth(monthOffset: offset)
    }

    func calendarWeekRange(offset: Int) -> (start: Date, end: Date)? {
        statsRepository.calendarWeekRange(weekOffset: offset)
    }

    func calendarMonthRange(offset: Int) -> (start: Date, end: Date)? {
        statsRepository.calendarMonthRange(monthOffset: offset)
    }

    func allDailyStats() -> [DailyStats] {
        statsRepository.allDailyStats()
    }

    var oldestStatDate: Date? {
        statsRepository.oldestStatDate
    }

    func averageSeconds(for stats: [DailyStats], today: Date = Date()) -> Int {
        let today = Calendar.current.startOfDay(for: today)
        let floor: Date = oldestStatDate ?? .distantPast
        let relevant = stats.filter { $0.date >= floor && $0.date <= today }
        guard !relevant.isEmpty else { return 0 }
        return relevant.reduce(0) { $0 + $1.totalUnlockedSeconds } / relevant.count
    }

    // MARK: - UI formatting only

    var todayDeltaCaption: String {
        let hasAnyData = statsReport.yesterdayUnlockedSeconds > 0 || statsReport.todayStats.totalUnlockedSeconds > 0
        guard hasAnyData else { return "어제도 오늘도 없어요" }
        let d = statsReport.todayDelta
        if d == 0 { return "어제와 같아요" }
        let text = goldTimeDurationText(seconds: abs(d))
        return d < 0 ? "어제보다 \(text) 적어요" : "어제보다 \(text) 많아요"
    }

    var weeklyDeltaCaption: String {
        guard statsReport.previousWeekUnlockedSeconds > 0 else { return "지난 주 기록 없음" }
        if statsReport.weeklyDelta == 0 { return "지난 주와 같아요" }
        let text = goldTimeDurationText(seconds: abs(statsReport.weeklyDelta))
        return statsReport.weeklyDelta < 0 ? "지난 주보다 \(text) 적어요" : "지난 주보다 \(text) 많아요"
    }

    var streakSentiment: CardSentiment {
        adFreeStreakDays > 0 ? .positive : .negative
    }

    var todaySentiment: CardSentiment? {
        switch statsReport.todayTrend {
        case .up: .negative
        case .down: .positive
        default: nil
        }
    }

    var weeklySentiment: CardSentiment? {
        switch statsReport.weeklyTrend {
        case .up: .negative
        case .down: .positive
        default: nil
        }
    }
}
