//
//  HomeView.swift
//  GoldTime
//
//  대시보드, 그룹별 앱 한도 설정, 모니터링 시작/중지, 현재 상태 표시.
//

import Charts
import FamilyControls
import SwiftUI
internal import Combine

struct HomeView: View {
    @Binding var showLockOptions: Bool

    @State private var auth = AuthorizationService.shared
    @State private var groups: [SharedStore.ScreenTimeGroup] = []
    @State private var pickerSelection = FamilyActivitySelection()
    @State private var pickerGroupID: UUID?
    @State private var isPickerPresented = false
    @State private var isMonitoring = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var alertMessage: AlertMessage?

    @State private var limitPickerGroupID: UUID? = nil
    @State private var limitPickerHours: Int = 0
    @State private var limitPickerMinutes: Int = 30

    @State private var isShieldActive = SharedStore.isShieldActive
    @State private var oneMinuteRemaining = SharedStore.oneMinuteRemaining
    @State private var shieldOverrideUntil: Date? = SharedStore.currentShieldOverrideUntil
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

                    if let successMessage {
                        statusSection(successMessage, tint: .green, systemName: "checkmark.circle.fill")
                    }

                    if let errorMessage {
                        statusSection(errorMessage, tint: .red, systemName: "exclamationmark.triangle.fill")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("GoldTime")
            .navigationBarTitleDisplayMode(.inline)
            .familyActivityPicker(isPresented: $isPickerPresented, selection: $pickerSelection)
            .alert(item: $alertMessage) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("확인"))
                )
            }
            .sheet(isPresented: Binding(
                get: { limitPickerGroupID != nil },
                set: { if !$0 { limitPickerGroupID = nil } }
            )) {
                LimitPickerSheet(
                    hours: $limitPickerHours,
                    minutes: $limitPickerMinutes,
                    onConfirm: {
                        if let id = limitPickerGroupID {
                            updateGroupLimit(id, minutes: limitPickerHours * 60 + limitPickerMinutes)
                        }
                        limitPickerGroupID = nil
                    },
                    onCancel: { limitPickerGroupID = nil }
                )
                .presentationDetents([.height(320)])
            }
            .onChange(of: pickerSelection) { _, newValue in
                handlePickerSelection(newValue)
            }
            .onChange(of: isPickerPresented) { _, newValue in
                if !newValue {
                    pickerGroupID = nil
                }
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
                title: "그룹 한도",
                value: groupLimitValue,
                caption: isMonitoring ? "그룹별 독립 적용" : "시작 전",
                systemName: "timer",
                tint: Color.goldPrimary
            )

            DashboardMetricCard(
                title: "남은 1분",
                value: "\(oneMinuteRemaining)회",
                caption: "전체 그룹 공유 · 오늘 최대 \(SharedStore.oneMinuteDailyLimit)회",
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
                caption: "그룹 한도 도달",
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
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "그룹 관리", systemName: "rectangle.3.group")
                Spacer()
                Text("그룹 \(groups.count)/\(SharedStore.maxGroupCount)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(groups.count >= SharedStore.maxGroupCount ? .red : .secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(Color.goldPrimary)
                    Text("그룹당 앱 \(SharedStore.maxAppsPerGroup)개까지 · 카테고리와 웹은 아직 제외 · 같은 앱은 여러 그룹에 넣을 수 있어요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button {
                    addGroup()
                } label: {
                    Label("그룹 추가", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DashboardActionButtonStyle(background: Color.goldPrimary, foreground: .black))
                .disabled(isMonitoring || groups.count >= SharedStore.maxGroupCount)
                .opacity(isMonitoring || groups.count >= SharedStore.maxGroupCount ? 0.45 : 1)

                if groups.count >= SharedStore.maxGroupCount {
                    Text("그룹은 5개까지예요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if isMonitoring {
                    Text("그룹을 바꾸려면 모니터링을 잠깐 중지하세요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if groups.isEmpty {
                emptyGroupState
            } else {
                VStack(spacing: 12) {
                    ForEach(groups) { group in
                        groupCard(group)
                    }
                }
            }

            monitoringControls
        }
    }

    private var emptyGroupState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.goldPrimary)
            Text("아직 그룹이 없어요.")
                .font(.headline)
            Text("그룹을 만들고 앱을 담으면, 그룹별로 다른 일일 한도를 걸 수 있어요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func groupCard(_ group: SharedStore.ScreenTimeGroup) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                IconTile(systemName: "app.badge", tint: Color.goldPrimary)

                VStack(alignment: .leading, spacing: 8) {
                    TextField("그룹명", text: Binding(
                        get: { group.name },
                        set: { updateGroupName(group.id, name: $0) }
                    ))
                    .font(.headline)
                    .disabled(isMonitoring)

                    HStack(spacing: 8) {
                        GroupStatusBadge(title: statusTitle(for: group), tint: statusTint(for: group))
                        GroupStatusBadge(
                            title: "앱 \(group.appCount)/\(SharedStore.maxAppsPerGroup)",
                            tint: group.appCount >= 8 ? .orange : .secondary
                        )
                        if groupHasDuplicateApps(group) {
                            GroupStatusBadge(title: "중복 포함 앱 있음", tint: .blue)
                        }
                    }
                }

                Spacer(minLength: 8)

                Button(role: .destructive) {
                    deleteGroup(group.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.plain)
                .disabled(isMonitoring)
                .opacity(isMonitoring ? 0.35 : 1)
            }

            Button {
                limitPickerHours = group.dailyLimitMinutes / 60
                limitPickerMinutes = group.dailyLimitMinutes % 60
                limitPickerGroupID = group.id
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("일일 한도")
                            .font(.subheadline.weight(.semibold))
                        Text(limitLabel(group.dailyLimitMinutes))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .disabled(isMonitoring)
            .opacity(isMonitoring ? 0.45 : 1)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button {
                        presentPicker(for: group)
                    } label: {
                        Label("앱 선택", systemImage: "square.grid.2x2")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(DashboardActionButtonStyle(background: Color(.tertiarySystemGroupedBackground), foreground: .primary))
                    .disabled(isMonitoring)
                    .opacity(isMonitoring ? 0.45 : 1)
                }

                Text("카테고리와 웹은 아직 제외")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                appTokenList(for: group)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func appTokenList(for group: SharedStore.ScreenTimeGroup) -> some View {
        if group.selection.applicationTokens.isEmpty {
            Text("선택된 앱 없음")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(group.selection.applicationTokens), id: \.self) { token in
                    Label(token)
                        .font(.subheadline)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var monitoringControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                IconTile(
                    systemName: isMonitoring ? "stop.fill" : "play.fill",
                    tint: isMonitoring ? .red : Color.goldPrimary
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(isMonitoring ? "모니터링 중" : "모니터링 시작")
                        .font(.body.weight(.semibold))
                    Text(isMonitoring ? "그룹별 한도가 적용 중이에요" : "유효한 그룹에 일일 한도를 적용합니다")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let startDisabledMessage, !isMonitoring {
                Text(startDisabledMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if isMonitoring {
                Button(role: .destructive) {
                    ScreenTimeManager.stopAllMonitoring()
                    isMonitoring = false
                    successMessage = "모니터링을 중지했어요."
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
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func statusSection(_ message: String, tint: Color, systemName: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemName)
                .foregroundStyle(tint)
            Text(message)
                .font(.footnote)
                .foregroundStyle(tint)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var canStart: Bool {
        !groups.isEmpty && startInvalidReason == nil
    }

    private var startInvalidReason: ScreenTimeGroupPolicy.InvalidReason? {
        ScreenTimeGroupPolicy.firstInvalidReason(for: groups.policySnapshots)
    }

    private var startDisabledMessage: String? {
        if groups.isEmpty {
            return "그룹을 하나 만들고 앱을 담아주세요."
        }
        return startInvalidReason?.userMessage
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
            let count = SharedStore.lockedGroups().count
            return count > 1 ? "\(count)개 그룹이 한도에 닿았어요" : "한도를 넘겼어요"
        }
        if let shieldOverrideUntil, shieldOverrideUntil.timeIntervalSinceNow > 0.5 {
            let seconds = max(1, Int(shieldOverrideUntil.timeIntervalSinceNow.rounded(.up)))
            return "\(durationText(seconds: seconds)) 뒤 재잠금"
        }
        return isMonitoring ? "아직 한도 안쪽" : "모니터링 꺼짐"
    }

    private func statusTitle(for group: SharedStore.ScreenTimeGroup) -> String {
        if SharedStore.lockedGroups().contains(where: { $0.id == group.id }) {
            return "잠금 중"
        }
        if SharedStore.groupsInOverride().contains(where: { $0.id == group.id }) {
            return "연장 중"
        }
        return isMonitoring ? "대기 중" : "시작 전"
    }

    private func statusTint(for group: SharedStore.ScreenTimeGroup) -> Color {
        switch statusTitle(for: group) {
        case "잠금 중":
            return .red
        case "연장 중":
            return .blue
        case "대기 중":
            return .green
        default:
            return .secondary
        }
    }

    private func groupHasDuplicateApps(_ group: SharedStore.ScreenTimeGroup) -> Bool {
        groups.contains { other in
            other.id != group.id
                && !other.selection.applicationTokens.isDisjoint(with: group.selection.applicationTokens)
        }
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
        groups = SharedStore.screenTimeGroups
        isMonitoring = SharedStore.isDailyMonitoringEnabled
        refreshDashboardState()
    }

    private func refreshDashboardState() {
        ScreenTimeManager.reapplyShieldIfOverrideExpired()
        isShieldActive = SharedStore.isShieldActive
        oneMinuteRemaining = SharedStore.oneMinuteRemaining
        shieldOverrideUntil = SharedStore.currentShieldOverrideUntil
        todayStats = SharedStore.todayStats
        weeklyStats = SharedStore.lastSevenDayStats()
    }

    private func persistGroups() {
        SharedStore.screenTimeGroups = groups
        groups = SharedStore.screenTimeGroups
    }

    private func addGroup() {
        guard groups.count < SharedStore.maxGroupCount else {
            alertMessage = AlertMessage(title: "그룹 제한", message: "그룹은 5개까지예요.")
            return
        }
        let group = SharedStore.ScreenTimeGroup(
            name: SharedStore.defaultGroupName(for: groups.count)
        )
        groups.append(group)
        persistGroups()
        successMessage = nil
        errorMessage = nil
    }

    private func deleteGroup(_ id: UUID) {
        groups.removeAll { $0.id == id }
        persistGroups()
        successMessage = nil
    }

    private func updateGroupName(_ id: UUID, name: String) {
        updateGroup(id) { group in
            group.name = name
        }
    }

    private func limitLabel(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 {
            return "\(h)시간 \(m)분 넘기면 이 그룹만 잠겨요"
        } else {
            return "\(m)분 넘기면 이 그룹만 잠겨요"
        }
    }

    private func updateGroupLimit(_ id: UUID, minutes: Int) {
        updateGroup(id) { group in
            group.dailyLimitMinutes = minutes
        }
    }

    private func updateGroup(_ id: UUID, update: (inout SharedStore.ScreenTimeGroup) -> Void) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else {
            return
        }
        update(&groups[index])
        persistGroups()
        successMessage = nil
        errorMessage = nil
    }

    private func presentPicker(for group: SharedStore.ScreenTimeGroup) {
        pickerGroupID = group.id
        pickerSelection = group.selection
        isPickerPresented = true
    }

    private func handlePickerSelection(_ selection: FamilyActivitySelection) {
        guard let groupID = pickerGroupID, isPickerPresented else {
            return
        }

        if !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty {
            restorePickerSelection(for: groupID)
            alertMessage = AlertMessage(
                title: "앱만 선택",
                message: "이번 버전은 앱만 골라주세요."
            )
            return
        }

        if selection.applicationTokens.count > SharedStore.maxAppsPerGroup {
            restorePickerSelection(for: groupID)
            alertMessage = AlertMessage(
                title: "앱 개수 제한",
                message: "그룹당 앱은 9개까지예요."
            )
            return
        }

        updateGroup(groupID) { group in
            group.selection = selection.appOnly
        }
    }

    private func restorePickerSelection(for groupID: UUID) {
        let current = groups.first { $0.id == groupID }?.selection ?? FamilyActivitySelection()
        if pickerSelection != current {
            pickerSelection = current
        }
    }

    private func startMonitoring() {
        do {
            try ScreenTimeManager.startDailyMonitoring(groups: groups)
            groups = SharedStore.screenTimeGroups
            isMonitoring = true
            errorMessage = nil
            successMessage = "\(groups.count)개 그룹 한도를 적용했어요."
            refreshDashboardState()
        } catch {
            successMessage = nil
            errorMessage = "모니터링 시작 실패: \(error.localizedDescription)"
        }
    }
}

private struct AlertMessage: Identifiable {
    let id = UUID()
    let title: String
    let message: String
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

private struct GroupStatusBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .lineLimit(1)
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

private struct LimitPickerSheet: View {
    @Binding var hours: Int
    @Binding var minutes: Int
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("취소", action: onCancel)
                Spacer()
                Button("완료") { onConfirm() }
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            DurationWheelPicker(hours: $hours, minutes: $minutes)
                .frame(height: 216)
        }
    }
}

private struct DurationWheelPicker: UIViewRepresentable {
    @Binding var hours: Int
    @Binding var minutes: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.dataSource = context.coordinator
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIView(_ uiView: UIPickerView, context: Context) {
        uiView.selectRow(hours, inComponent: 0, animated: false)
        uiView.selectRow(minutes, inComponent: 1, animated: false)
    }

    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
        var parent: DurationWheelPicker

        init(_ parent: DurationWheelPicker) { self.parent = parent }

        func numberOfComponents(in pickerView: UIPickerView) -> Int { 2 }

        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            component == 0 ? 24 : 60
        }

        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            let label = (view as? UILabel) ?? UILabel()
            label.textAlignment = .center
            label.font = .systemFont(ofSize: 20, weight: .regular)
            label.text = component == 0 ? "\(row)시간" : "\(row)분"
            return label
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            if component == 0 { parent.hours = row }
            else { parent.minutes = row }
        }
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
