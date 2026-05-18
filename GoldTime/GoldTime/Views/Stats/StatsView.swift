//
//  StatsView.swift
//  GoldTime
//

import Charts
import SwiftUI

struct StatsView: View {
    let groups: [SharedStore.ScreenTimeGroup]
    let todayStats: SharedStore.DailyStats
    let weeklyStats: [SharedStore.DailyStats]
    let oneMinuteRemaining: Int
    let isMonitoring: Bool

    private let metricColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                metricGrid
                weeklyBillSection
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
                title: "시간을 아낀 선택",
                value: "\(todayStats.walkAwayCount)회",
                caption: "광고도 1분도 안 사고 닫았어요.",
                systemName: "checkmark.seal.fill",
                tint: .green
            )

            DashboardMetricCard(
                title: "광고로 산 시간",
                value: goldTimeDurationText(seconds: todayStats.adUnlockedSeconds),
                caption: "광고 \(todayStats.adWatchCount)개",
                systemName: "play.rectangle.fill",
                tint: .orange
            )

            DashboardMetricCard(
                title: "남은 1분",
                value: "\(oneMinuteRemaining)회",
                caption: "오늘 무료 연장 잔여",
                systemName: "plus.forwardslash.minus",
                tint: .blue
            )

            DashboardMetricCard(
                title: "전체 추가 사용",
                value: goldTimeDurationText(seconds: todayStats.totalUnlockedSeconds),
                caption: "광고 + 1분 연장",
                systemName: "clock.arrow.circlepath",
                tint: .purple
            )

            DashboardMetricCard(
                title: "잠금 도달",
                value: "\(todayStats.shieldHitCount)회",
                caption: "그룹 한도 도달",
                systemName: "hand.raised.fill",
                tint: .pink
            )

            DashboardMetricCard(
                title: "보호 그룹",
                value: groupLimitValue,
                caption: isMonitoring ? "유효 그룹 자동 적용" : "설정 필요",
                systemName: "rectangle.3.group",
                tint: Color.accent
            )
        }
    }

    private var weeklyBillSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "7일간 시간을 아낀 선택", systemName: "chart.bar.xaxis")

            VStack(alignment: .leading, spacing: 12) {
                if hasWeeklyWalkAway {
                    Chart(weeklyStats) { stat in
                        BarMark(
                            x: .value("날짜", stat.date, unit: .day),
                            y: .value("선택", stat.walkAwayCount)
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
                    .frame(height: 180)
                } else {
                    EmptyChartState()
                        .frame(height: 180)
                }

                HStack {
                    Text("최근 7일 합계")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(weeklyWalkAwayCount)회")
                        .fontWeight(.bold)
                }
                .font(.subheadline)
            }
            .cardContainer()
        }
    }

    private var groupLimitValue: String {
        if groups.isEmpty {
            return "0그룹"
        }
        if groups.count == 1, let first = groups.first {
            return "\(first.dailyLimitMinutes)분"
        }
        return "\(groups.count)그룹"
    }

    private var weeklyWalkAwayCount: Int {
        weeklyStats.reduce(0) { $0 + $1.walkAwayCount }
    }

    private var hasWeeklyWalkAway: Bool {
        weeklyStats.contains { $0.walkAwayCount > 0 }
    }
}
