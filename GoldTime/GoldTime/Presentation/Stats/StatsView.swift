//
//  StatsView.swift
//  GoldTime
//

import Charts
import SwiftUI

struct StatsView: View {
    let viewModel: StatsViewModel

    init(
        groups: [SharedStore.ScreenTimeGroup],
        todayStats: SharedStore.DailyStats,
        weeklyStats: [SharedStore.DailyStats],
        previousWeekStats: [SharedStore.DailyStats],
        monthlyStats: [SharedStore.DailyStats],
        isMonitoring: Bool,
        adFreeStreakDays: Int,
        maxAdFreeStreakDays: Int
    ) {
        viewModel = StatsViewModel(
            groups: groups,
            todayStats: todayStats,
            weeklyStats: weeklyStats,
            previousWeekStats: previousWeekStats,
            monthlyStats: monthlyStats,
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
                    value: goldTimeDurationText(seconds: viewModel.todayStats.totalUnlockedSeconds),
                    caption: viewModel.todayDeltaCaption,
                    systemName: "clock.fill",
                    tint: .cyan,
                    trend: viewModel.todayTrend,
                    sentiment: viewModel.todaySentiment
                )

                DashboardMetricCard(
                    title: "이번 주 추가 사용",
                    value: goldTimeDurationText(seconds: viewModel.weeklyAdUnlockedSeconds),
                    caption: viewModel.weeklyDeltaCaption,
                    systemName: "calendar.badge.clock",
                    tint: .cyan,
                    trend: viewModel.weeklyTrend,
                    sentiment: viewModel.weeklySentiment
                )
            }
        }
    }

    private var weeklySection: some View {
        WeeklyGraphSection()
    }

    private var monthlySection: some View {
        MonthlyGraphSection()
    }
}

private struct WeeklyGraphSection: View {
    @State private var weekOffset = 0

    private var weekRange: (start: Date, end: Date) {
        SharedStore.calendarWeekRange(weekOffset: weekOffset)
    }

    private var stats: [SharedStore.DailyStats] {
        SharedStore.statsForCalendarWeek(weekOffset: weekOffset)
    }

    private var navigationLabel: String {
        guard weekOffset != 0 else { return "이번 주" }
        let (start, end) = weekRange
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "M/d"
        return "\(fmt.string(from: start)) - \(fmt.string(from: end))"
    }

    private var averageSeconds: Int {
        guard !stats.isEmpty else { return 0 }
        return stats.reduce(0) { $0 + $1.totalUnlockedSeconds } / stats.count
    }

    private var maxMinutes: Int {
        stats.map { $0.totalUnlockedSeconds / 60 }.max() ?? 0
    }

    private var hasData: Bool {
        stats.contains { $0.totalUnlockedSeconds > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "주간 기록", systemName: "chart.bar.xaxis")

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
                        BarMark(
                            x: .value("날짜", stat.date, unit: .day),
                            y: .value("추가 사용", stat.totalUnlockedSeconds / 60)
                        )
                        .foregroundStyle(Color.accent)
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
                    .chartYScale(domain: 0...max(5, maxMinutes))

                    if !hasData {
                        Text("기록 없음")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 180)
                .padding(.top, 8)

                HStack {
                    Text("일일 평균")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(goldTimeDurationText(seconds: averageSeconds))
                        .fontWeight(.bold)
                }
                .font(.subheadline)
            }
            .cardContainer()
        }
    }
}

private struct MonthlyGraphSection: View {
    @State private var monthOffset = 0

    private var monthRange: (start: Date, end: Date) {
        SharedStore.calendarMonthRange(monthOffset: monthOffset)
    }

    private var stats: [SharedStore.DailyStats] {
        SharedStore.statsForCalendarMonth(monthOffset: monthOffset)
    }

    private var navigationLabel: String {
        guard monthOffset != 0 else { return "이번 달" }
        let (start, _) = monthRange
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "yyyy년 M월"
        return fmt.string(from: start)
    }

    private var averageSeconds: Int {
        guard !stats.isEmpty else { return 0 }
        return stats.reduce(0) { $0 + $1.totalUnlockedSeconds } / stats.count
    }

    private var maxMinutes: Int {
        stats.map { $0.totalUnlockedSeconds / 60 }.max() ?? 0
    }

    private var hasData: Bool {
        stats.contains { $0.totalUnlockedSeconds > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "월간 기록", systemName: "chart.bar.xaxis")

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
                        BarMark(
                            x: .value("날짜", stat.date, unit: .day),
                            y: .value("추가 사용", stat.totalUnlockedSeconds / 60)
                        )
                        .foregroundStyle(Color.accent)
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
                    .chartYScale(domain: 0...max(5, maxMinutes))

                    if !hasData {
                        Text("기록 없음")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 180)
                .padding(.top, 8)

                HStack {
                    Text("일일 평균")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(goldTimeDurationText(seconds: averageSeconds))
                        .fontWeight(.bold)
                }
                .font(.subheadline)
            }
            .cardContainer()
        }
    }
}
