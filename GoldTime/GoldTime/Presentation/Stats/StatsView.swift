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
        .navigationTitle("stats.title")
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
                    title: String(localized: "stats.extraUse"),
                    value: goldTimeDurationText(seconds: viewModel.statsReport.todayStats.totalUnlockedSeconds),
                    caption: viewModel.todayDeltaCaption,
                    systemName: "clock.fill",
                    tint: .cyan,
                    trend: viewModel.statsReport.todayTrend,
                    sentiment: viewModel.todaySentiment
                )

                DashboardMetricCard(
                    title: String(localized: "stats.weeklyAverage"),
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
    @Environment(\.locale) private var locale

    enum Mode: String, CaseIterable, Identifiable {
        case weekly
        case monthly
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .weekly: "stats.mode.weekly"
            case .monthly: "stats.mode.monthly"
            }
        }
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
        switch mode {
        case .weekly:
            guard weekOffset != 0, let range else { return String(localized: "stats.thisWeek") }
            let style = Date.FormatStyle.dateTime
                .month(.defaultDigits)
                .day()
                .locale(locale)
            return "\(range.start.formatted(style)) - \(range.end.formatted(style))"
        case .monthly:
            guard monthOffset != 0, let range else { return String(localized: "stats.thisMonth") }
            return range.start.formatted(
                Date.FormatStyle.dateTime.year().month(.wide).locale(locale)
            )
        }
    }

    private var averageSeconds: Int { viewModel.averageSeconds(for: stats) }
    private var averageLabel: String { mode == .weekly ? String(localized: "stats.weeklyAverage") : String(localized: "stats.monthlyAverage") }

    private var maxMinutes: Double {
        stats.map { Double($0.totalUnlockedSeconds) / 60.0 }.max() ?? 0
    }

    private var hasAnyRecord: Bool {
        stats.contains { viewModel.hasRecord($0) }
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

    // MARK: - Y축 (최대값 기반 눈금)

    private var dataMaxMinutes: Double { max(maxMinutes, averageMinutes) }

    /// 눈금 간격 후보(분).
    private static let yStepCandidates: [Double] = [5, 10, 15, 20, 30, 60, 120, 180, 240, 360, 480, 720]

    /// 데이터 최대값이 3칸 안에 들어오는 가장 작은 간격. 데이터가 없으면 도메인이 1시간이 되는 20분.
    private var yStepMinutes: Double {
        guard dataMaxMinutes > 0 else { return 20 }
        return Self.yStepCandidates.first { dataMaxMinutes <= $0 * 3 } ?? 720
    }

    /// 도메인 상단(분): 최대값이 딱 들어오는 3칸 (위로 여유 칸 없음).
    private var yDomainTopMinutes: Double { yStepMinutes * 3 }

    /// 0 포함 4개 눈금 위치(분 단위).
    private var yTickMinutes: [Double] {
        [0, yStepMinutes, yStepMinutes * 2, yStepMinutes * 3]
    }

    private func yAxisLabel(forMinutes minutes: Double) -> String {
        let total = Int(minutes.rounded())
        guard total > 0 else { return "0" }
        let hours = total / 60
        let mins = total % 60
        if hours > 0 && mins > 0 { return String(localized: "stats.chart.yAxis.hourMinute \(hours) \(mins)") }
        return hours > 0 ? String(localized: "stats.chart.yAxis.hours \(hours)") : String(localized: "stats.chart.yAxis.minutes \(mins)")
    }

    /// 기록은 있지만 0분인 날의 스텁 막대 높이(분). 도메인 상단에 비례해 어느 도메인에서든 같은 높이로 보인다.
    private var zeroRecordStubMinutes: Double {
        yDomainTopMinutes * 0.025
    }

    /// 기록 없는 날(설치/제한 적용 전, 미래)은 막대만 투명 처리해 축·그리드 골격은 동일하게 유지한다.
    private func barColor(for stat: DailyStats, minutes: Double) -> Color {
        guard viewModel.hasRecord(stat) else { return .clear }
        return minutes > 0 ? .accent : Color.accent.opacity(0.3)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "stats.section.record")

            VStack(alignment: .leading, spacing: 12) {
                Picker("stats.period", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
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
                        x: .value("stats.chart.date", stat.date, unit: .day),
                        y: .value("stats.chart.extraUse", minutes > 0 ? minutes : zeroRecordStubMinutes)
                    )
                    .cornerRadius(4)
                    .foregroundStyle(barColor(for: stat, minutes: minutes))
                }
                if averageSeconds > 0 {
                    RuleMark(y: .value("stats.chart.average", averageMinutes))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.orange)
                        .annotation(
                            position: .top,
                            alignment: .trailing,
                            spacing: 2,
                            overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                        ) {
                            Text("stats.chart.averageLabel")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.orange)
                        }
                }
            }
            .chartXAxis {
                if mode == .weekly {
                    AxisMarks(values: stats.map(\.date)) {
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated).locale(locale))
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
            }
            .chartYScale(domain: 0...yDomainTopMinutes)

            if !hasAnyRecord {
                Text("stats.noRecord")
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
        trackingStartDate: allMock.last?.date
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
