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

    let dailyTrend: UsageTrend?
    let weeklyTrend: UsageTrend?

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
        let repository = statsRepository ?? StatsRepositoryImpl()
        self.statsRepository = repository
        dailyTrend = Self.computeDailyTrend(repository: repository)
        weeklyTrend = Self.computeWeeklyTrend(repository: repository)
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
        guard statsReport.previousWeekAverageSeconds > 0 else { return "지난 주 기록 없음" }
        if statsReport.weeklyAverageDelta == 0 { return "지난 주 평균과 같아요" }
        let text = goldTimeDurationText(seconds: abs(statsReport.weeklyAverageDelta))
        return statsReport.weeklyAverageDelta < 0 ? "지난 주보다 평균 \(text) 적어요" : "지난 주보다 평균 \(text) 많아요"
    }

    var streakSentiment: CardSentiment {
        adFreeStreakDays > 0 ? .positive : .negative
    }

    var dailyTrendHeadline: String { Self.headline(for: dailyTrend, unit: "일") }
    var weeklyTrendHeadline: String { Self.headline(for: weeklyTrend, unit: "주") }

    var dailyTrendSentiment: CardSentiment? { Self.sentiment(for: dailyTrend) }
    var weeklyTrendSentiment: CardSentiment? { Self.sentiment(for: weeklyTrend) }

    private static func headline(for trend: UsageTrend?, unit: String) -> String {
        guard let trend else { return "비교할 기록 없음" }
        switch trend.direction {
        case .up: return "\(trend.streak)\(unit)째 증가 중"
        case .down: return "\(trend.streak)\(unit)째 감소 중"
        case .flat: return "변화 없음"
        }
    }

    private static func sentiment(for trend: UsageTrend?) -> CardSentiment? {
        switch trend?.direction {
        case .up: return .negative
        case .down: return .positive
        default: return nil
        }
    }

    // MARK: - Trend computation

    /// 최근 30일의 일별 추가 사용 합계로 일간 추세를 계산합니다. 데이터 시작일 이전은 제외합니다.
    private static func computeDailyTrend(repository: any StatsRepository) -> UsageTrend? {
        let floor = Calendar.current.startOfDay(for: repository.oldestStatDate ?? .distantPast)
        let today = Calendar.current.startOfDay(for: Date())
        let totals = repository.lastNDayStats(30)
            .filter { $0.date >= floor && $0.date <= today }
            .sorted { $0.date < $1.date }
            .map { $0.totalUnlockedSeconds }
        return UsageTrend.fromOrderedTotals(totals)
    }

    /// 최근 8주의 주별 "하루 평균" 추가 사용으로 주간 추세를 계산합니다.
    /// 합계가 아니라 평균이라 진행 중인 주(일수가 덜 찬 주)도 공정하게 비교됩니다.
    /// 데이터 시작일 이전과 미래 날짜는 평균에서 제외합니다.
    private static func computeWeeklyTrend(repository: any StatsRepository) -> UsageTrend? {
        let floor = Calendar.current.startOfDay(for: repository.oldestStatDate ?? .distantPast)
        let today = Calendar.current.startOfDay(for: Date())
        var averages: [Int] = []
        for offset in stride(from: -7, through: 0, by: 1) {
            let relevant = repository.statsForCalendarWeek(weekOffset: offset)
                .filter { $0.date >= floor && $0.date <= today }
            guard !relevant.isEmpty else { continue }
            averages.append(relevant.reduce(0) { $0 + $1.totalUnlockedSeconds } / relevant.count)
        }
        return UsageTrend.fromOrderedTotals(averages)
    }
}
