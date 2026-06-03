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
                TrendChartSection(viewModel: viewModel)
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
                    title: "주간 평균",
                    value: goldTimeDurationText(seconds: viewModel.statsReport.weeklyAverageSeconds),
                    caption: viewModel.weeklyDeltaCaption,
                    systemName: "calendar.badge.clock",
                    tint: .cyan,
                    trend: viewModel.statsReport.weeklyTrend,
                    sentiment: viewModel.weeklySentiment
                )
            }
        }
    }

}

private struct TrendChartSection: View {
    let viewModel: StatsViewModel

    enum Mode: String, CaseIterable, Identifiable {
        case weekly = "주간"
        case monthly = "월간"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .weekly
    @State private var weekOffset = 0
    @State private var monthOffset = 0

    private var stats: [DailyStats] {
        switch mode {
        case .weekly: viewModel.weeklyStats(offset: weekOffset)
        case .monthly: viewModel.monthlyStats(offset: monthOffset)
        }
    }

    private var range: (start: Date, end: Date)? {
        switch mode {
        case .weekly: viewModel.calendarWeekRange(offset: weekOffset)
        case .monthly: viewModel.calendarMonthRange(offset: monthOffset)
        }
    }

    private var canGoForward: Bool {
        mode == .weekly ? weekOffset < 0 : monthOffset < 0
    }

    private func goBackward() {
        if mode == .weekly { weekOffset -= 1 } else { monthOffset -= 1 }
    }

    private func goForward() {
        if mode == .weekly { weekOffset += 1 } else { monthOffset += 1 }
    }

    private var navigationLabel: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        switch mode {
        case .weekly:
            guard weekOffset != 0, let range else { return "이번 주" }
            fmt.dateFormat = "M/d"
            return "\(fmt.string(from: range.start)) - \(fmt.string(from: range.end))"
        case .monthly:
            guard monthOffset != 0, let range else { return "이번 달" }
            fmt.dateFormat = "yyyy년 M월"
            return fmt.string(from: range.start)
        }
    }

    private var averageSeconds: Int { viewModel.averageSeconds(for: stats) }
    private var averageLabel: String { mode == .weekly ? "주간 평균" : "월간 평균" }

    private var maxMinutes: Double {
        stats.map { Double($0.totalUnlockedSeconds) / 60.0 }.max() ?? 0
    }

    private var hasData: Bool {
        stats.contains { $0.totalUnlockedSeconds > 0 }
    }

    private var displayYear: Int {
        let cal = Calendar.current
        if let start = range?.start {
            return cal.component(.year, from: start)
        }
        return cal.component(.year, from: Date())
    }

    private var averageMinutes: Double { Double(averageSeconds) / 60.0 }

    private var comparison: StatsViewModel.StatsComparison {
        viewModel.comparison(
            period: mode == .weekly ? .weekly : .monthly,
            currentAverageSeconds: averageSeconds,
            displayYear: displayYear
        )
    }

    private func trendColor(_ trend: TrendDirection) -> Color {
        switch trend {
        case .up: .red
        case .down: .green
        case .flat: .orange
        }
    }

    private func trendSymbol(_ trend: TrendDirection) -> String {
        switch trend {
        case .up: "arrow.up"
        case .down: "arrow.down"
        case .flat: "arrow.right"
        }
    }

    // MARK: - Y축 (시간 단위)

    private var dataMaxMinutes: Double { max(maxMinutes, averageMinutes) }

    /// 데이터 최대값을 올림한 도메인 상단(시간). 최소 1시간.
    private var yDomainTopHours: Int {
        max(1, Int((dataMaxMinutes / 60.0).rounded(.up)))
    }

    /// 눈금이 최대 3개가 되도록 시간 간격을 고릅니다(짝수 시간 우선).
    private var yHourStep: Int {
        let top = yDomainTopHours
        for step in [1, 2, 4, 6, 12, 24] where top / step <= 3 {
            return step
        }
        return 24
    }

    /// 0과 시간 눈금 위치(분 단위)들.
    private var yTickMinutes: [Double] {
        var values: [Double] = [0]
        var hour = yHourStep
        while hour <= yDomainTopHours {
            values.append(Double(hour * 60))
            hour += yHourStep
        }
        return values
    }

    private func yAxisLabel(forMinutes minutes: Double) -> String {
        let hours = Int((minutes / 60.0).rounded())
        return hours == 0 ? "0" : "\(hours)시간"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "기록")

            VStack(alignment: .leading, spacing: 12) {
                Picker("기간", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack {
                    Button { goBackward() } label: {
                        Image(systemName: "chevron.left").fontWeight(.semibold)
                    }
                    Spacer()
                    Text(navigationLabel)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Group {
                        if canGoForward {
                            Button { goForward() } label: {
                                Image(systemName: "chevron.right").fontWeight(.semibold)
                            }
                        } else {
                            Image(systemName: "chevron.right").fontWeight(.semibold).hidden()
                        }
                    }
                }
                .foregroundStyle(.primary)

                chart
                    .frame(height: 180)
                    .padding(.top, 8)

                Divider()
                comparisonSummary
            }
            .cardContainer()
        }
    }

    private var chart: some View {
        ZStack {
            Chart {
                ForEach(stats) { stat in
                    let minutes = Double(stat.totalUnlockedSeconds) / 60.0
                    BarMark(
                        x: .value("날짜", stat.date, unit: .day),
                        y: .value("추가 사용", minutes > 0 ? minutes : 0.2)
                    )
                    .cornerRadius(4)
                    .foregroundStyle(minutes > 0 ? Color.accent : Color.accent.opacity(0.3))
                }
                if averageSeconds > 0 {
                    RuleMark(y: .value("평균", averageMinutes))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis {
                if mode == .weekly {
                    AxisMarks(values: stats.map(\.date)) {
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.weekday(.narrow).locale(Locale(identifier: "ko_KR")))
                    }
                } else {
                    AxisMarks(values: .stride(by: .day, count: 7)) {
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: yTickMinutes) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let minutes = value.as(Double.self) {
                            Text(yAxisLabel(forMinutes: minutes))
                        }
                    }
                }
                if averageSeconds > 0 {
                    AxisMarks(position: .trailing, values: [averageMinutes]) { _ in
                        AxisValueLabel {
                            Text("평균")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartYScale(domain: 0...Double(yDomainTopHours * 60))

            if !hasData {
                Text("추가 사용 기록 없음")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var comparisonSummary: some View {
        let comparison = comparison
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(averageLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(goldTimeDurationText(seconds: averageSeconds))
                            .fontWeight(.bold)
                            .foregroundStyle(
                                comparison.shouldShow ? trendColor(comparison.trend) : Color.primary
                            )
                        if comparison.shouldShow {
                            Image(systemName: trendSymbol(comparison.trend))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(trendColor(comparison.trend))
                        }
                    }
                }
                if comparison.comparisonAverageSeconds > 0 {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(comparison.comparisonLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(goldTimeDurationText(seconds: comparison.comparisonAverageSeconds))
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if comparison.shouldShow {
                Text(comparison.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
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
