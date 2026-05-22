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
        oneMinuteRemaining: Int,
        isMonitoring: Bool,
        adFreeStreakDays: Int
    ) {
        viewModel = StatsViewModel(
            groups: groups,
            todayStats: todayStats,
            weeklyStats: weeklyStats,
            previousWeekStats: previousWeekStats,
            oneMinuteRemaining: oneMinuteRemaining,
            isMonitoring: isMonitoring,
            adFreeStreakDays: adFreeStreakDays
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
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("통계")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var metricGrid: some View {
        LazyVGrid(columns: metricColumns, spacing: 12) {
            DashboardMetricCard(
                title: "광고 없는 연속 일수",
                value: "\(viewModel.adFreeStreakDays)일",
                caption: viewModel.adFreeStreakDays == 0 ? "오늘 광고를 봤어요" : "광고 없이 연속",
                systemName: "flame.fill",
                tint: .orange,
                sentiment: viewModel.streakSentiment
            )

            DashboardMetricCard(
                title: "남은 1분",
                value: "\(viewModel.oneMinuteRemaining)회",
                caption: "오늘 무료 연장 잔여",
                systemName: "plus.forwardslash.minus",
                tint: .blue
            )

            DashboardMetricCard(
                title: "추가 사용",
                value: goldTimeDurationText(seconds: viewModel.todayStats.adUnlockedSeconds),
                caption: viewModel.todayDeltaCaption,
                systemName: "clock.fill",
                tint: .purple,
                trend: viewModel.todayTrend,
                sentiment: viewModel.todaySentiment
            )

            DashboardMetricCard(
                title: "이번 주 추가 사용",
                value: goldTimeDurationText(seconds: viewModel.weeklyAdUnlockedSeconds),
                caption: viewModel.weeklyDeltaCaption,
                systemName: "calendar.badge.clock",
                tint: .purple,
                trend: viewModel.weeklyTrend,
                sentiment: viewModel.weeklySentiment
            )
        }
    }

    private var weeklySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "7일간 추가 사용", systemName: "chart.bar.xaxis")

            VStack(alignment: .leading, spacing: 12) {
                Chart(viewModel.weeklyStats) { stat in
                    BarMark(
                        x: .value("날짜", stat.date, unit: .day),
                        y: .value("추가 사용", stat.adUnlockedSeconds / 60)
                    )
                    .foregroundStyle(Color.accent)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) {
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartYScale(domain: 0...max(5, viewModel.weeklyMaxMinutes))
                .frame(height: 180)

                HStack {
                    Text("최근 7일 합계")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(goldTimeDurationText(seconds: viewModel.weeklyAdUnlockedSeconds))
                        .fontWeight(.bold)
                }
                .font(.subheadline)
            }
            .cardContainer()
        }
    }
}
