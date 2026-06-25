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

    var trackingStartDate: Date? {
        statsRepository.trackingStartDate
    }

    /// 해당 날짜를 "기록 있음"으로 취급할지. 추적 시작 이후 ~ 오늘까지는 0분도 기록으로 본다.
    /// 추적 시작 이전(설치/제한 적용 전)과 미래 날짜는 기록 없음.
    func hasRecord(_ stat: DailyStats, today: Date = Date()) -> Bool {
        if stat.totalUnlockedSeconds > 0 { return true }
        guard let start = trackingStartDate else { return false }
        let calendar = Calendar.current
        return stat.date >= calendar.startOfDay(for: start)
            && stat.date <= calendar.startOfDay(for: today)
    }

    func averageSeconds(for stats: [DailyStats], today: Date = Date()) -> Int {
        let today = Calendar.current.startOfDay(for: today)
        let floor: Date = trackingStartDate ?? .distantPast
        let relevant = stats.filter { $0.date >= floor && $0.date <= today }
        guard !relevant.isEmpty else { return 0 }
        return relevant.reduce(0) { $0 + $1.totalUnlockedSeconds } / relevant.count
    }

    // MARK: - 기록 카드 비교 (주간 vs 이번 달 / 월간 vs 올해)

    enum StatsPeriod {
        case weekly
        case monthly
    }

    struct StatsComparison {
        /// 비교 대상(이번 달 평균 또는 올해 평균)의 초 단위 평균.
        let comparisonAverageSeconds: Int
        let comparisonLabel: String
        /// 화면에 보이는 두 평균(올림된 분)의 차이. 양수면 현재가 더 많음.
        let deltaMinutes: Int

        /// 비교 대상 데이터가 있을 때만 비교 UI(색·화살표·문구)를 표시한다.
        var shouldShow: Bool { comparisonAverageSeconds > 0 }

        var trend: TrendDirection {
            if deltaMinutes > 0 { return .up }
            if deltaMinutes < 0 { return .down }
            return .flat
        }

        var caption: String {
            switch trend {
            case .up:
                return String(localized: "stats.caption.more \(comparisonLabel) \(goldTimeDurationText(seconds: deltaMinutes * 60))")
            case .down:
                return String(localized: "stats.caption.less \(comparisonLabel) \(goldTimeDurationText(seconds: -deltaMinutes * 60))")
            case .flat:
                return String(localized: "stats.caption.same \(comparisonLabel)")
            }
        }
    }

    /// 표시값(`goldTimeDurationText`)과 동일하게 올림한 분.
    func displayMinutes(_ seconds: Int) -> Int {
        Int((Double(max(0, seconds)) / 60.0).rounded(.up))
    }

    /// 현재 기간 평균과 비교 대상(이번 달/올해) 평균을 분 단위로 비교한다.
    /// 초 단위로 비교하면 두 값이 같은 분으로 표시되는데도 "1분 적어요"가 떠서 분 단위로 계산한다.
    func comparison(
        period: StatsPeriod,
        currentAverageSeconds: Int,
        displayYear: Int,
        today: Date = Date()
    ) -> StatsComparison {
        let comparisonAverageSeconds: Int
        let label: String
        switch period {
        case .weekly:
            comparisonAverageSeconds = averageSeconds(for: monthlyStats(offset: 0), today: today)
            label = String(localized: "stats.compare.thisMonth")
        case .monthly:
            let calendar = Calendar.current
            let yearStats = statsForDisplayYear(displayYear, today: today)
            comparisonAverageSeconds = averageSeconds(for: yearStats, today: today)
            let currentYear = calendar.component(.year, from: today)
            label = displayYear == currentYear ? String(localized: "stats.compare.thisYear") : String(localized: "stats.compare.year \(String(displayYear))")
        }
        let deltaMinutes = displayMinutes(currentAverageSeconds) - displayMinutes(comparisonAverageSeconds)
        return StatsComparison(
            comparisonAverageSeconds: comparisonAverageSeconds,
            comparisonLabel: label,
            deltaMinutes: deltaMinutes
        )
    }

    private func statsForDisplayYear(_ displayYear: Int, today: Date) -> [DailyStats] {
        let calendar = Calendar.current
        guard let yearStart = calendar.date(from: DateComponents(year: displayYear, month: 1, day: 1)),
              let nextYearStart = calendar.date(from: DateComponents(year: displayYear + 1, month: 1, day: 1)),
              let yearEnd = calendar.date(byAdding: .day, value: -1, to: nextYearStart) else {
            return []
        }

        let currentYear = calendar.component(.year, from: today)
        let rangeEnd = displayYear == currentYear ? calendar.startOfDay(for: today) : yearEnd
        guard rangeEnd >= yearStart else { return [] }

        var storedStatsByKey: [String: DailyStats] = [:]
        for stat in allDailyStats() {
            storedStatsByKey[stat.dateKey] = stat
        }
        let dayCount = (calendar.dateComponents([.day], from: yearStart, to: rangeEnd).day ?? 0) + 1
        return (0..<dayCount).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: yearStart) ?? yearStart
            let key = DailyStats.dateKey(for: date)
            return storedStatsByKey[key] ?? DailyStats(dateKey: key)
        }
    }

    // MARK: - UI formatting only

    var todayDeltaCaption: String {
        let hasAnyData = statsReport.yesterdayUnlockedSeconds > 0 || statsReport.todayStats.totalUnlockedSeconds > 0
        guard hasAnyData else { return String(localized: "stats.delta.none") }
        let deltaMinutes = displayMinutes(statsReport.todayStats.totalUnlockedSeconds) - displayMinutes(statsReport.yesterdayUnlockedSeconds)
        if deltaMinutes == 0 { return String(localized: "stats.delta.same") }
        let text = goldTimeDurationText(seconds: abs(deltaMinutes) * 60)
        return deltaMinutes < 0 ? String(localized: "stats.delta.less \(text)") : String(localized: "stats.delta.more \(text)")
    }

    var weeklyDeltaCaption: String {
        guard statsReport.previousWeekAverageSeconds > 0 else { return String(localized: "stats.weekDelta.none") }
        let deltaMinutes = displayMinutes(statsReport.weeklyAverageSeconds) - displayMinutes(statsReport.previousWeekAverageSeconds)
        if deltaMinutes == 0 { return String(localized: "stats.weekDelta.same") }
        let text = goldTimeDurationText(seconds: abs(deltaMinutes) * 60)
        return deltaMinutes < 0 ? String(localized: "stats.weekDelta.less \(text)") : String(localized: "stats.weekDelta.more \(text)")
    }

    var streakSentiment: CardSentiment {
        adFreeStreakDays > 0 ? .positive : .negative
    }

    /// 표시값(올림 분)을 기준으로 추세를 판단해 카드의 값·화살표·문구가 항상 일치하게 한다.
    /// 초 단위로 비교하면 두 값이 같은 분으로 표시되는데도 화살표가 떠서 분 단위로 계산한다.
    private func displayTrend(current: Int, comparison: Int) -> TrendDirection {
        let deltaMinutes = displayMinutes(current) - displayMinutes(comparison)
        if deltaMinutes > 0 { return .up }
        if deltaMinutes < 0 { return .down }
        return .flat
    }

    var todayTrend: TrendDirection? {
        let hasAnyData = statsReport.yesterdayUnlockedSeconds > 0 || statsReport.todayStats.totalUnlockedSeconds > 0
        guard hasAnyData else { return nil }
        return displayTrend(current: statsReport.todayStats.totalUnlockedSeconds, comparison: statsReport.yesterdayUnlockedSeconds)
    }

    var weeklyTrend: TrendDirection? {
        guard statsReport.previousWeekAverageSeconds > 0 else { return nil }
        return displayTrend(current: statsReport.weeklyAverageSeconds, comparison: statsReport.previousWeekAverageSeconds)
    }

    var todaySentiment: CardSentiment? {
        switch todayTrend {
        case .up: .negative
        case .down: .positive
        case .flat: .neutral
        case nil: nil
        }
    }

    var weeklySentiment: CardSentiment? {
        switch weeklyTrend {
        case .up: .negative
        case .down: .positive
        case .flat: .neutral
        case nil: nil
        }
    }
}
