//
//  StatsView.swift
//  GoldTime
//

import Charts
import SwiftUI

struct StatsView: View {
    let viewModel: StatsViewModel

    init(
        groups: [ScreenTimeGroup],
        statsReport: StatsReport,
        isMonitoring: Bool,
        adFreeStreakDays: Int,
        maxAdFreeStreakDays: Int
    ) {
        viewModel = StatsViewModel(
            groups: groups,
            statsReport: statsReport,
            isMonitoring: isMonitoring,
            adFreeStreakDays: adFreeStreakDays,
            maxAdFreeStreakDays: maxAdFreeStreakDays
        )
    }

    private let metricColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                metricGrid
                weeklySection
                monthlySection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("통계")
        .navigationBarTitleDisplayMode(.large)
    }

    private var metricGrid: some View {
        VStack(spacing: 12) {
            StreakCard(
                current: viewModel.adFreeStreakDays,
                best: viewModel.maxAdFreeStreakDays,
                sentiment: viewModel.streakSentiment
            )
            LazyVGrid(columns: metricColumns, spacing: 12) {
                DashboardMetricCard(
                    title: "추가 사용",
                    value: goldTimeDurationText(seconds: viewModel.statsReport.todayStats.totalUnlockedSeconds),
                    caption: viewModel.todayDeltaCaption,
                    systemName: "clock.fill",
                    tint: .cyan,
                    trend: viewModel.statsReport.todayTrend,
                    sentiment: viewModel.todaySentiment
                )

                DashboardMetricCard(
                    title: "이번 주 추가 사용",
                    value: goldTimeDurationText(seconds: viewModel.statsReport.weeklyUnlockedSeconds),
                    caption: viewModel.weeklyDeltaCaption,
                    systemName: "calendar.badge.clock",
                    tint: .cyan,
                    trend: viewModel.statsReport.weeklyTrend,
                    sentiment: viewModel.weeklySentiment
                )
            }
        }
    }

    private var weeklySection: some View {
        WeeklyGraphSection(viewModel: viewModel)
    }

    private var monthlySection: some View {
        MonthlyGraphSection(viewModel: viewModel)
    }
}

private struct WeeklyGraphSection: View {
    let viewModel: StatsViewModel
    @State private var weekOffset = 0

    private var weekRange: (start: Date, end: Date)? {
        viewModel.calendarWeekRange(offset: weekOffset)
    }

    private var stats: [DailyStats] {
        viewModel.weeklyStats(offset: weekOffset)
    }

    private var navigationLabel: String {
        guard weekOffset != 0, let range = weekRange else { return "이번 주" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "M/d"
        return "\(fmt.string(from: range.start)) - \(fmt.string(from: range.end))"
    }

    private var averageSeconds: Int {
        viewModel.averageSeconds(for: stats)
    }

    private var maxMinutes: Double {
        stats.map { Double($0.totalUnlockedSeconds) / 60.0 }.max() ?? 0
    }

    private var hasData: Bool {
        stats.contains { $0.totalUnlockedSeconds > 0 }
    }

    private var comparisonAverageSeconds: Int {
        viewModel.averageSeconds(for: viewModel.monthlyStats(offset: 0))
    }

    private var comparisonLabel: String { "이번 달 평균" }
    private var comparisonDelta: Int { averageSeconds - comparisonAverageSeconds }

    private var shouldShowComparison: Bool {
        comparisonAverageSeconds > 0 && comparisonDelta != 0
    }

    private var comparisonCaption: String {
        let text = goldTimeDurationText(seconds: abs(comparisonDelta))
        return comparisonDelta > 0 ? "이번 달 평균보다 \(text) 많아요" : "이번 달 평균보다 \(text) 적어요"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "주간 기록")

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button { weekOffset -= 1 } label: {
                        Image(systemName: "chevron.left").fontWeight(.semibold)
                    }
                    Spacer()
                    Text(navigationLabel)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Group {
                        if weekOffset < 0 {
                            Button { weekOffset += 1 } label: {
                                Image(systemName: "chevron.right").fontWeight(.semibold)
                            }
                        } else {
                            Image(systemName: "chevron.right").fontWeight(.semibold).hidden()
                        }
                    }
                }
                .foregroundStyle(.primary)

                ZStack {
                    Chart(stats) { stat in
                        let minutes = Double(stat.totalUnlockedSeconds) / 60.0
                        BarMark(
                            x: .value("날짜", stat.date, unit: .day),
                            y: .value("추가 사용", minutes > 0 ? minutes : 0.2)
                        )
                        .cornerRadius(4)
                        .foregroundStyle(minutes > 0 ? Color.accent : Color.accent.opacity(0.3))
                    }
                    .chartXAxis {
                        AxisMarks(values: stats.map(\.date)) {
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.weekday(.narrow).locale(Locale(identifier: "ko_KR")))
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading)
                    }
                    .chartYScale(domain: 0...max(5.0, maxMinutes))

                    if !hasData {
                        Text("추가 사용 기록 없음")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 180)
                .padding(.top, 8)
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("주간 평균")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(goldTimeDurationText(seconds: averageSeconds))
                                    .fontWeight(.bold)
                                    .foregroundStyle(
                                        shouldShowComparison
                                            ? (comparisonDelta > 0 ? Color.red : Color.green)
                                            : Color.primary
                                    )
                                if shouldShowComparison {
                                    Image(systemName: comparisonDelta > 0 ? "arrow.up" : "arrow.down")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(comparisonDelta > 0 ? Color.red : Color.green)
                                }
                            }
                        }
                        if comparisonAverageSeconds > 0 {
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(comparisonLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(goldTimeDurationText(seconds: comparisonAverageSeconds))
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if shouldShowComparison {
                        Text(comparisonCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
            }
            .cardContainer()
        }
    }
}

private struct MonthlyGraphSection: View {
    let viewModel: StatsViewModel
    @State private var monthOffset = 0

    private var monthRange: (start: Date, end: Date)? {
        viewModel.calendarMonthRange(offset: monthOffset)
    }

    private var stats: [DailyStats] {
        viewModel.monthlyStats(offset: monthOffset)
    }

    private var navigationLabel: String {
        guard monthOffset != 0, let range = monthRange else { return "이번 달" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "yyyy년 M월"
        return fmt.string(from: range.start)
    }

    private var averageSeconds: Int {
        viewModel.averageSeconds(for: stats)
    }

    private var maxMinutes: Double {
        stats.map { Double($0.totalUnlockedSeconds) / 60.0 }.max() ?? 0
    }

    private var hasData: Bool {
        stats.contains { $0.totalUnlockedSeconds > 0 }
    }

    private var displayYear: Int {
        let cal = Calendar.current
        if let start = monthRange?.start {
            return cal.component(.year, from: start)
        }
        return cal.component(.year, from: Date())
    }

    private var comparisonAverageSeconds: Int {
        let cal = Calendar.current
        let year = displayYear
        let yearStats = viewModel.allDailyStats().filter {
            cal.component(.year, from: $0.date) == year
        }
        guard !yearStats.isEmpty else { return 0 }
        return yearStats.reduce(0) { $0 + $1.totalUnlockedSeconds } / yearStats.count
    }

    private var comparisonLabel: String {
        let currentYear = Calendar.current.component(.year, from: Date())
        return displayYear == currentYear ? "올해 평균" : "\(displayYear)년 평균"
    }

    private var comparisonDelta: Int { averageSeconds - comparisonAverageSeconds }

    private var shouldShowComparison: Bool {
        comparisonAverageSeconds > 0 && comparisonDelta != 0
    }

    private var comparisonCaption: String {
        let text = goldTimeDurationText(seconds: abs(comparisonDelta))
        return comparisonDelta > 0 ? "\(comparisonLabel)보다 \(text) 많아요" : "\(comparisonLabel)보다 \(text) 적어요"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "월간 기록")

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button { monthOffset -= 1 } label: {
                        Image(systemName: "chevron.left").fontWeight(.semibold)
                    }
                    Spacer()
                    Text(navigationLabel)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Group {
                        if monthOffset < 0 {
                            Button { monthOffset += 1 } label: {
                                Image(systemName: "chevron.right").fontWeight(.semibold)
                            }
                        } else {
                            Image(systemName: "chevron.right").fontWeight(.semibold).hidden()
                        }
                    }
                }
                .foregroundStyle(.primary)

                ZStack {
                    Chart(stats) { stat in
                        let minutes = Double(stat.totalUnlockedSeconds) / 60.0
                        BarMark(
                            x: .value("날짜", stat.date, unit: .day),
                            y: .value("추가 사용", minutes > 0 ? minutes : 0.2)
                        )
                        .cornerRadius(4)
                        .foregroundStyle(minutes > 0 ? Color.accent : Color.accent.opacity(0.3))
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 7)) {
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading)
                    }
                    .chartYScale(domain: 0...max(5.0, maxMinutes))

                    if !hasData {
                        Text("추가 사용 기록 없음")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 180)
                .padding(.top, 8)
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("월간 평균")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(goldTimeDurationText(seconds: averageSeconds))
                                    .fontWeight(.bold)
                                    .foregroundStyle(
                                        shouldShowComparison
                                            ? (comparisonDelta > 0 ? Color.red : Color.green)
                                            : Color.primary
                                    )
                                if shouldShowComparison {
                                    Image(systemName: comparisonDelta > 0 ? "arrow.up" : "arrow.down")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(comparisonDelta > 0 ? Color.red : Color.green)
                                }
                            }
                        }
                        if comparisonAverageSeconds > 0 {
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(comparisonLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(goldTimeDurationText(seconds: comparisonAverageSeconds))
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if shouldShowComparison {
                        Text(comparisonCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
            }
            .cardContainer()
        }
    }
}

#if DEBUG
private extension DailyStats {
    func toSharedStore() -> SharedStore.DailyStats {
        SharedStore.DailyStats(
            dateKey: dateKey,
            adWatchCount: adWatchCount,
            adUnlockedSeconds: adUnlockedSeconds,
            oneMinuteUsedCount: oneMinuteUsedCount,
            shieldHitCount: shieldHitCount,
            walkAwayCount: walkAwayCount
        )
    }
}

private func makePreviewStats(daysAgo: Int, minutes: Int) -> DailyStats {
    let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
    return DailyStats(dateKey: DailyStats.dateKey(for: date), adUnlockedSeconds: minutes * 60)
}

private func makeStatsView(allMock: [DailyStats]) -> some View {
    let today = DailyStats.dateKey(for: Date())
    let todayStats = allMock.first { $0.dateKey == today } ?? DailyStats(dateKey: today)
    let statsReport = StatsReport(
        todayStats: todayStats,
        weeklyStats: Array(allMock.prefix(min(7, allMock.count))),
        previousWeekStats: allMock.count >= 14 ? Array(allMock[7..<14]) : [],
        monthlyStats: Array(allMock.prefix(min(30, allMock.count))),
        oldestStatDate: allMock.last?.date
    )
    return NavigationStack {
        StatsView(
            groups: [],
            statsReport: statsReport,
            isMonitoring: true,
            adFreeStreakDays: 3,
            maxAdFreeStreakDays: 7
        )
    }
}
#Preview("평균보다 많음 ↗") {
    let all = (0..<60).map { makePreviewStats(daysAgo: $0, minutes: $0 < 7 ? 20 : ($0 < 30 ? 10 : 5)) }
    SharedStore.seedForPreview(all.map { $0.toSharedStore() })
    return makeStatsView(allMock: all)
}

#Preview("평균보다 적음 ↙") {
    let all = (0..<60).map { makePreviewStats(daysAgo: $0, minutes: $0 < 7 ? 3 : ($0 < 30 ? 10 : 15)) }
    SharedStore.seedForPreview(all.map { $0.toSharedStore() })
    return makeStatsView(allMock: all)
}

#Preview("데이터 없음") {
    SharedStore.seedForPreview([])
    return makeStatsView(allMock: [])
}
#endif
