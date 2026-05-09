//
//  HomeView.swift
//  GoldTime
//
//  대시보드, 한도 설정, 차단 대상 선택, 모니터링 시작/중지, 현재 상태 표시.
//

import Charts
import FamilyControls
import SwiftUI
internal import Combine

struct HomeView: View {
    @Binding var showLockOptions: Bool

    @State private var auth = AuthorizationService.shared
    @State private var selection = FamilyActivitySelection()
    @State private var limitMinutes: Int = 30
    @State private var isPickerPresented = false
    @State private var isMonitoring = false
    @State private var errorMessage: String?

    @State private var isShieldActive = SharedStore.isShieldActive
    @State private var oneMinuteRemaining = SharedStore.oneMinuteRemaining
    @State private var shieldOverrideUntil: Date? = SharedStore.shieldOverrideUntil
    @State private var todayStats = SharedStore.todayStats
    @State private var weeklyStats = SharedStore.lastSevenDayStats()

    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let metricColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        if !auth.isAuthorized {
            OnboardingView(onAuthorized: { auth.refresh() })
        } else {
            content
                .onAppear(perform: loadState)
        }
    }

    private var content: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    revenueHero
                    metricGrid
                    weeklyRevenueSection
                    managementSection

                    if let errorMessage {
                        errorSection(errorMessage)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("GoldTime")
            .navigationBarTitleDisplayMode(.inline)
            .familyActivityPicker(isPresented: $isPickerPresented, selection: $selection)
            .onChange(of: selection) { _, newValue in
                SharedStore.selectedApps = newValue
            }
            .onChange(of: showLockOptions) { _, newValue in
                if !newValue { refreshDashboardState() }
            }
            .onReceive(refreshTimer) { _ in
                refreshDashboardState()
            }
        }
    }

    private var revenueHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("오늘 저한테")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                    Text("₩\(todayRevenue.formatted())")
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundStyle(Color.goldPrimary)
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)
                    Text("벌어줬어요")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                }

                Spacer(minLength: 12)

                StatusBadge(
                    title: shieldStatusValue,
                    systemName: isShieldActive ? "lock.fill" : "lock.open.fill",
                    tint: isShieldActive ? .red : .green
                )
            }

            Text("실제 수익과 무관하게 광고 1개당 \(SharedStore.estimatedWonPerAd)원으로 계산한 값이에요.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.68))

            Text("광고 \(todayStats.adWatchCount)개 · 1분 연장 \(todayStats.oneMinuteUsedCount)회 · 잠금 \(todayStats.shieldHitCount)회")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.86))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.deepBlack)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var metricGrid: some View {
        LazyVGrid(columns: metricColumns, spacing: 12) {
            DashboardMetricCard(
                title: "현재 상태",
                value: shieldStatusValue,
                caption: shieldStatusCaption,
                systemName: isShieldActive ? "shield.fill" : "shield",
                tint: isShieldActive ? .red : .green
            )

            DashboardMetricCard(
                title: "일일 한도",
                value: "\(limitMinutes)분",
                caption: isMonitoring ? "모니터링 중" : "시작 전",
                systemName: "timer",
                tint: Color.goldPrimary
            )

            DashboardMetricCard(
                title: "남은 1분",
                value: "\(oneMinuteRemaining)회",
                caption: "오늘 최대 \(SharedStore.oneMinuteDailyLimit)회",
                systemName: "plus.forwardslash.minus",
                tint: .blue
            )

            DashboardMetricCard(
                title: "오늘 광고",
                value: "\(todayStats.adWatchCount)개",
                caption: "수익 ₩\(todayRevenue.formatted())",
                systemName: "play.rectangle.fill",
                tint: .purple
            )

            DashboardMetricCard(
                title: "추가 사용",
                value: durationText(seconds: todayStats.totalUnlockedSeconds),
                caption: "광고 + 1분 연장",
                systemName: "clock.arrow.circlepath",
                tint: .orange
            )

            DashboardMetricCard(
                title: "잠금 발생",
                value: "\(todayStats.shieldHitCount)회",
                caption: "일일 한도 도달",
                systemName: "hand.raised.fill",
                tint: .pink
            )
        }
    }

    private var weeklyRevenueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "7일 광고 수익", systemName: "chart.bar.xaxis")

            VStack(alignment: .leading, spacing: 12) {
                if hasWeeklyRevenue {
                    Chart(weeklyStats) { stat in
                        BarMark(
                            x: .value("날짜", stat.date, unit: .day),
                            y: .value("수익", stat.estimatedAdRevenueWon)
                        )
                        .foregroundStyle(Color.goldPrimary)
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
                    Text("₩\(weeklyRevenue.formatted())")
                        .fontWeight(.bold)
                }
                .font(.subheadline)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var managementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "관리", systemName: "slider.horizontal.3")

            VStack(spacing: 0) {
                Button {
                    isPickerPresented = true
                } label: {
                    HStack(spacing: 12) {
                        IconTile(systemName: "square.grid.2x2", tint: Color.goldPrimary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("차단 대상")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(selectionSummary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(16)
                }
                .buttonStyle(.plain)

                Divider().padding(.leading, 60)

                HStack(spacing: 12) {
                    IconTile(systemName: "timer", tint: Color.goldPrimary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("일일 스크린타임 한도")
                            .font(.body.weight(.semibold))
                        Text("\(limitMinutes)분 넘기면 잠급니다")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Stepper("", value: $limitMinutes, in: 1...600, step: 5)
                        .labelsHidden()
                }
                .padding(16)

                Divider().padding(.leading, 60)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        IconTile(
                            systemName: isMonitoring ? "stop.fill" : "play.fill",
                            tint: isMonitoring ? .red : Color.goldPrimary
                        )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(isMonitoring ? "모니터링 중" : "모니터링 시작")
                                .font(.body.weight(.semibold))
                            Text(canStart ? "선택한 대상에 현재 한도를 적용합니다" : "차단 대상을 먼저 선택하세요")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    if isMonitoring {
                        Button(role: .destructive) {
                            ScreenTimeManager.stopAllMonitoring()
                            isMonitoring = false
                            refreshDashboardState()
                        } label: {
                            Label("모니터링 중지", systemImage: "stop.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(DashboardActionButtonStyle(background: .red, foreground: .white))
                    } else {
                        Button {
                            startMonitoring()
                        } label: {
                            Label("모니터링 시작", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(DashboardActionButtonStyle(background: Color.goldPrimary, foreground: .black))
                        .disabled(!canStart)
                        .opacity(canStart ? 1 : 0.45)
                    }
                }
                .padding(16)
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func errorSection(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var canStart: Bool {
        !(selection.applicationTokens.isEmpty
          && selection.categoryTokens.isEmpty
          && selection.webDomainTokens.isEmpty)
        && limitMinutes > 0
    }

    private var selectionSummary: String {
        let apps = selection.applicationTokens.count
        let cats = selection.categoryTokens.count
        let webs = selection.webDomainTokens.count
        let total = apps + cats + webs
        return total == 0 ? "선택 없음" : "앱 \(apps) · 카테고리 \(cats) · 웹 \(webs)"
    }

    private var todayRevenue: Int {
        todayStats.estimatedAdRevenueWon
    }

    private var weeklyRevenue: Int {
        weeklyStats.reduce(0) { $0 + $1.estimatedAdRevenueWon }
    }

    private var hasWeeklyRevenue: Bool {
        weeklyStats.contains { $0.estimatedAdRevenueWon > 0 }
    }

    private var shieldStatusValue: String {
        if isShieldActive {
            return "잠금 중"
        }
        if let shieldOverrideUntil, shieldOverrideUntil.timeIntervalSinceNow > 0.5 {
            return "연장 중"
        }
        return isMonitoring ? "사용 가능" : "대기 중"
    }

    private var shieldStatusCaption: String {
        if isShieldActive {
            return "한도를 넘겼어요"
        }
        if let shieldOverrideUntil, shieldOverrideUntil.timeIntervalSinceNow > 0.5 {
            let seconds = max(1, Int(shieldOverrideUntil.timeIntervalSinceNow.rounded(.up)))
            return "\(durationText(seconds: seconds)) 뒤 재잠금"
        }
        return isMonitoring ? "아직 한도 안쪽" : "모니터링 꺼짐"
    }

    private func durationText(seconds: Int) -> String {
        let minutes = Int((Double(max(0, seconds)) / 60.0).rounded(.up))
        if minutes < 60 {
            return "\(minutes)분"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 {
            return "\(hours)시간"
        }
        return "\(hours)시간 \(remainingMinutes)분"
    }

    private func loadState() {
        ScreenTimeManager.rolloverCounterIfNeeded()
        selection = SharedStore.selectedApps
        if SharedStore.dailyLimitMinutes > 0 {
            limitMinutes = SharedStore.dailyLimitMinutes
        }
        isMonitoring = SharedStore.isDailyMonitoringEnabled
        refreshDashboardState()
    }

    private func refreshDashboardState() {
        ScreenTimeManager.reapplyShieldIfOverrideExpired()
        isShieldActive = SharedStore.isShieldActive
        oneMinuteRemaining = SharedStore.oneMinuteRemaining
        shieldOverrideUntil = SharedStore.shieldOverrideUntil
        todayStats = SharedStore.todayStats
        weeklyStats = SharedStore.lastSevenDayStats()
    }

    private func startMonitoring() {
        do {
            try ScreenTimeManager.startDailyMonitoring(
                limitMinutes: limitMinutes,
                selection: selection
            )
            isMonitoring = true
            errorMessage = nil
            refreshDashboardState()
        } catch {
            errorMessage = "모니터링 시작 실패: \(error.localizedDescription)"
        }
    }
}

private struct SectionHeader: View {
    let title: String
    let systemName: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.goldPrimary)
            Text(title)
                .font(.headline)
        }
    }
}

private struct DashboardMetricCard: View {
    let title: String
    let value: String
    let caption: String
    let systemName: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                IconTile(systemName: systemName, tint: tint)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct StatusBadge: View {
    let title: String
    let systemName: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.caption.weight(.bold))
            Text(title)
                .font(.caption.weight(.bold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct IconTile: View {
    let systemName: String
    let tint: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 32, height: 32)
            .background(tint.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct EmptyChartState: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.goldPrimary)
            Text("광고 기록이 생기면 7일 흐름을 보여줄게요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DashboardActionButtonStyle: ButtonStyle {
    let background: Color
    let foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.vertical, 14)
            .foregroundStyle(foreground)
            .background(background.opacity(configuration.isPressed ? 0.82 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
