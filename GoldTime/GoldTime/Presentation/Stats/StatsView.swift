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
        isMonitoring: Bool,
        adFreeStreakDays: Int,
        maxAdFreeStreakDays: Int
    ) {
        viewModel = StatsViewModel(
            groups: groups,
            todayStats: todayStats,
            weeklyStats: weeklyStats,
            previousWeekStats: previousWeekStats,
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
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("통계")
        .navigationBarTitleDisplayMode(.inline)
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
