//
//  HomeView.swift
//  GoldTime
//
//  대시보드, 그룹별 앱 한도 설정, 자동 보호 적용, 현재 상태 표시.
//

import Charts
import FamilyControls
import SwiftUI
internal import Combine

private enum GoldTimeTab: Hashable {
    case home
    case stats
    case settings
}

struct HomeView: View {
    @Binding var showLockOptions: Bool

    @State private var selectedTab = GoldTimeTab.home
    @State private var auth = AuthorizationService.shared
    @State private var groups: [SharedStore.ScreenTimeGroup] = []
    @State private var pickerSelection = FamilyActivitySelection()
    @State private var pickerGroupID: UUID?
    @State private var isPickerPresented = false
    @State private var isMonitoring = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var alertMessage: AlertMessage?
    @State private var isResetProtectionConfirmationPresented = false

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
        TabView(selection: $selectedTab) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        timeBillHero
                        currentStatusSection
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
            }
            .tabItem {
                Label("홈", systemImage: "house.fill")
            }
            .tag(GoldTimeTab.home)

            NavigationStack {
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
            .tabItem {
                Label("통계", systemImage: "chart.bar.xaxis")
            }
            .tag(GoldTimeTab.stats)

            NavigationStack {
                ScrollView {
                    settingsSection
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle("설정")
                .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("설정", systemImage: "gearshape")
            }
            .tag(GoldTimeTab.settings)
        }
            .sheet(isPresented: $isPickerPresented) {
                PickerSheet(selection: $pickerSelection) {
                    commitPickerSelection()
                }
            }
            .alert(item: $alertMessage) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("확인"))
                )
            }
            .confirmationDialog(
                "전체 보호 초기화",
                isPresented: $isResetProtectionConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("초기화", role: .destructive) {
                    resetProtectionState()
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("모든 모니터링과 현재 잠금을 초기화합니다. 그룹 설정은 유지됩니다.")
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

    private var timeBillHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("오늘의 시간 청구서")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                    Text(billSummaryLine)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(billComment)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                StatusBadge(
                    title: shieldStatusValue,
                    systemName: isShieldActive ? "lock.fill" : "lock.open.fill",
                    tint: isShieldActive ? .red : .green
                )
            }

            HStack(spacing: 10) {
                BillPill(title: "광고", value: "\(todayStats.adWatchCount)개")
                BillPill(title: "추가 사용", value: durationText(seconds: todayStats.adUnlockedSeconds))
            }

            HStack(spacing: 10) {
                BillPill(title: "1분 연장", value: "\(todayStats.oneMinuteUsedCount)회")
                BillPill(title: "시간을 아낀 선택", value: "\(todayStats.walkAwayCount)회")
            }

            Text("한도 넘긴 뒤의 선택만 기록합니다.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.68))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color("gray100"))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var currentStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "현재 상태", systemName: "shield")

            HStack(spacing: 12) {
                IconTile(
                    systemName: isShieldActive ? "lock.fill" : "lock.open.fill",
                    tint: isShieldActive ? .red : protectionStatusTint
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(shieldStatusValue)
                        .font(.headline)
                    Text(shieldStatusCaption)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                GroupStatusBadge(title: protectionStatusTitle, tint: protectionStatusTint)
            }
            .cardContainer()
        }
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
                value: durationText(seconds: todayStats.adUnlockedSeconds),
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
                value: durationText(seconds: todayStats.totalUnlockedSeconds),
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

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "권한", systemName: "checkmark.shield")

                VStack(spacing: 10) {
                    settingsRow(
                        title: "스크린 타임 권한",
                        subtitle: auth.isAuthorized ? "허용됨" : "확인이 필요해요",
                        systemName: auth.isAuthorized ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                        tint: auth.isAuthorized ? .green : .orange
                    )
                }
                .cardContainer()
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "알림과 언어", systemName: "bell.badge")

                VStack(spacing: 10) {
                    settingsRow(
                        title: "알림",
                        subtitle: "Shield에서 GoldTime으로 돌아올 때 사용",
                        systemName: "bell",
                        tint: Color.accent
                    )
                    settingsRow(
                        title: "언어",
                        subtitle: "현재는 시스템 언어를 사용",
                        systemName: "globe",
                        tint: .blue
                    )
                }
                .cardContainer()
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "문제 해결", systemName: "wrench.and.screwdriver")

                Button(role: .destructive) {
                    isResetProtectionConfirmationPresented = true
                } label: {
                    actionRow(
                        title: "전체 보호 초기화",
                        subtitle: "그룹 설정은 유지하고 현재 잠금과 모니터링만 다시 맞춤",
                        systemName: "arrow.clockwise"
                    )
                }
                .buttonStyle(.plain)
                .cardContainer()
            }
        }
    }

    private var managementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "보호 그룹", systemName: "rectangle.3.group")
                Spacer()
                Text("그룹 \(groups.count)/\(SharedStore.maxGroupCount)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(groups.count >= SharedStore.maxGroupCount ? .red : .secondary)
            }

            monitoringControls

            if groups.isEmpty {
                emptyGroupState
            } else {
                VStack(spacing: 12) {
                    ForEach(groups) { group in
                        groupCard(group)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(Color.accent)
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
                .buttonStyle(GoldTimeButtonStyle(background: Color.accent, foreground: .black))
                .disabled(groups.count >= SharedStore.maxGroupCount)
                .opacity(groups.count >= SharedStore.maxGroupCount ? 0.45 : 1)

                if groups.count >= SharedStore.maxGroupCount {
                    Text("그룹은 5개까지예요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .cardContainer()
        }
    }

    private var emptyGroupState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.accent)
            Text("아직 그룹이 없어요.")
                .font(.headline)
            Text("그룹을 만들고 앱을 담으면, 그룹별로 다른 일일 한도를 걸 수 있어요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .cardContainer(padding: 20)
        .frame(maxWidth: .infinity)
    }

    private func groupCard(_ group: SharedStore.ScreenTimeGroup) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                IconTile(systemName: "app.badge", tint: Color.accent)

                VStack(alignment: .leading, spacing: 8) {
                    TextField("그룹명", text: Binding(
                        get: { group.name },
                        set: { updateGroupName(group.id, name: $0) }
                    ))
                    .font(.headline)

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

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button {
                        presentPicker(for: group)
                    } label: {
                        Label("앱 선택", systemImage: "square.grid.2x2")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GoldTimeButtonStyle(background: Color(.tertiarySystemGroupedBackground), foreground: .primary))
                }

                Text("카테고리와 웹은 아직 제외")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                appTokenList(for: group)
            }
        }
        .cardContainer()
    }

    @ViewBuilder
    private func appTokenList(for group: SharedStore.ScreenTimeGroup) -> some View {
        if group.selection.applicationTokens.isEmpty {
            Text("선택된 앱 없음")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .rowContainer()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(group.selection.applicationTokens), id: \.self) { token in
                    Label(token)
                        .font(.subheadline)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .rowContainer()
        }
    }

    private var monitoringControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                IconTile(
                    systemName: protectionStatusIcon,
                    tint: protectionStatusTint
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(protectionStatusTitle)
                        .font(.body.weight(.semibold))
                    Text(protectionStatusCaption)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Menu {
                    Button(role: .destructive) {
                        isResetProtectionConfirmationPresented = true
                    } label: {
                        Label("전체 보호 초기화", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            if let setupMessage = protectionSetupMessage {
                Text(setupMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .cardContainer()
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

    private func actionRow(title: String, subtitle: String, systemName: String) -> some View {
        HStack(spacing: 12) {
            IconTile(systemName: systemName, tint: Color.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rowContainer()
    }

    private func settingsRow(title: String, subtitle: String, systemName: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            IconTile(systemName: systemName, tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rowContainer()
    }

    private var validMonitoringGroups: [SharedStore.ScreenTimeGroup] {
        ScreenTimeManager.validDailyMonitoringGroups(from: groups)
    }

    private var invalidMonitoringGroups: [SharedStore.ScreenTimeGroup] {
        groups.filter { group in
            ScreenTimeGroupPolicy.invalidReason(for: group.policySnapshot) != nil
        }
    }

    private var protectionStatusTitle: String {
        if isMonitoring {
            return "자동 적용 중"
        }
        if groups.isEmpty {
            return "설정 필요"
        }
        if validMonitoringGroups.isEmpty {
            return "설정 필요"
        }
        return "자동 적용 대기"
    }

    private var protectionStatusCaption: String {
        if isMonitoring {
            let count = validMonitoringGroups.count
            return count > 1 ? "\(count)개 유효 그룹에 한도를 적용 중이에요" : "유효한 그룹에 한도를 적용 중이에요"
        }
        if groups.isEmpty {
            return "그룹을 만들고 앱을 담으면 바로 적용돼요"
        }
        if validMonitoringGroups.isEmpty {
            return "앱과 한도가 설정된 그룹이 필요해요"
        }
        return "자동 적용을 준비하고 있어요"
    }

    private var protectionStatusIcon: String {
        isMonitoring ? "checkmark.shield.fill" : "shield"
    }

    private var protectionStatusTint: Color {
        if isMonitoring {
            return .green
        }
        return validMonitoringGroups.isEmpty ? .secondary : Color.accent
    }

    private var protectionSetupMessage: String? {
        guard !groups.isEmpty else {
            return nil
        }

        let invalidCount = invalidMonitoringGroups.count
        guard invalidCount > 0 else {
            return nil
        }

        if validMonitoringGroups.isEmpty {
            return "아직 적용할 수 있는 그룹이 없어요. 앱을 하나 이상 담고 한도를 정해주세요."
        }

        return "\(invalidCount)개 그룹은 설정이 덜 끝나서 자동 적용에서 제외됐어요."
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

    private var billSummaryLine: String {
        "광고 \(todayStats.adWatchCount)개. 추가 사용 \(durationText(seconds: todayStats.adUnlockedSeconds))."
    }

    private var billComment: String {
        if !hasBillCost, todayStats.walkAwayCount > 0 {
            return "광고 안 보면 당신 승리예요. 저는 손해고요."
        }
        if !hasBillCost {
            return "좋은 날입니다. 저한텐 아니고요."
        }
        return "시간이 금이면, 오늘 좀 썼네요."
    }

    private var hasBillCost: Bool {
        todayStats.adWatchCount > 0
            || todayStats.adUnlockedSeconds > 0
            || todayStats.oneMinuteUsedCount > 0
    }

    private var weeklyWalkAwayCount: Int {
        weeklyStats.reduce(0) { $0 + $1.walkAwayCount }
    }

    private var hasWeeklyWalkAway: Bool {
        weeklyStats.contains { $0.walkAwayCount > 0 }
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
        return isMonitoring ? "아직 한도 안쪽" : "설정 필요"
    }

    private func statusTitle(for group: SharedStore.ScreenTimeGroup) -> String {
        if SharedStore.lockedGroups().contains(where: { $0.id == group.id }) {
            return "잠금 중"
        }
        if SharedStore.groupsInOverride().contains(where: { $0.id == group.id }) {
            return "연장 중"
        }
        if ScreenTimeGroupPolicy.invalidReason(for: group.policySnapshot) != nil {
            return "설정 필요"
        }
        return isMonitoring ? "적용 중" : "대기 중"
    }

    private func statusTint(for group: SharedStore.ScreenTimeGroup) -> Color {
        switch statusTitle(for: group) {
        case "잠금 중":
            return .red
        case "연장 중":
            return .blue
        case "적용 중", "대기 중":
            return .green
        case "설정 필요":
            return .orange
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
        syncProtectionRules()
    }

    private func refreshDashboardState() {
        ScreenTimeManager.reapplyShieldIfOverrideExpired()
        isMonitoring = SharedStore.isDailyMonitoringEnabled
        isShieldActive = SharedStore.isShieldActive
        oneMinuteRemaining = SharedStore.oneMinuteRemaining
        shieldOverrideUntil = SharedStore.currentShieldOverrideUntil
        todayStats = SharedStore.todayStats
        weeklyStats = SharedStore.lastSevenDayStats()
    }

    private func persistGroups(shouldSyncProtection: Bool = true) {
        SharedStore.screenTimeGroups = groups
        groups = SharedStore.screenTimeGroups
        if shouldSyncProtection {
            syncProtectionRules()
        } else {
            isMonitoring = SharedStore.isDailyMonitoringEnabled
            refreshDashboardState()
        }
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
        persistGroups(shouldSyncProtection: false)
        successMessage = nil
        errorMessage = nil
    }

    private func deleteGroup(_ id: UUID) {
        groups.removeAll { $0.id == id }
        successMessage = nil
        errorMessage = nil
        persistGroups()
    }

    private func updateGroupName(_ id: UUID, name: String) {
        updateGroup(id, shouldSyncProtection: false) { group in
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

    private func updateGroup(
        _ id: UUID,
        shouldSyncProtection: Bool = true,
        update: (inout SharedStore.ScreenTimeGroup) -> Void
    ) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else {
            return
        }
        update(&groups[index])
        successMessage = nil
        errorMessage = nil
        persistGroups(shouldSyncProtection: shouldSyncProtection)
    }

    private func presentPicker(for group: SharedStore.ScreenTimeGroup) {
        pickerGroupID = group.id
        pickerSelection = group.selection
        isPickerPresented = true
    }

    private func commitPickerSelection() {
        guard let groupID = pickerGroupID else { return }
        updateGroup(groupID) { group in
            group.selection = pickerSelection.appOnly
        }
    }

    private func syncProtectionRules(showSuccess: Bool = false) {
        do {
            try ScreenTimeManager.syncDailyMonitoring(groups: groups)
            groups = SharedStore.screenTimeGroups
            isMonitoring = SharedStore.isDailyMonitoringEnabled
            errorMessage = nil
            if showSuccess {
                let count = ScreenTimeManager.validDailyMonitoringGroups(from: groups).count
                successMessage = count > 0 ? "\(count)개 유효 그룹을 다시 적용했어요." : "적용할 그룹이 없어 보호를 비웠어요."
            }
            refreshDashboardState()
        } catch {
            isMonitoring = SharedStore.isDailyMonitoringEnabled
            successMessage = nil
            errorMessage = "자동 적용 실패: \(error.localizedDescription)"
            refreshDashboardState()
        }
    }

    private func resetProtectionState() {
        do {
            try ScreenTimeManager.resetProtectionState()
            groups = SharedStore.screenTimeGroups
            isMonitoring = SharedStore.isDailyMonitoringEnabled
            errorMessage = nil
            successMessage = "보호 상태를 초기화하고 유효한 그룹을 다시 적용했어요."
            refreshDashboardState()
        } catch {
            isMonitoring = SharedStore.isDailyMonitoringEnabled
            successMessage = nil
            errorMessage = "전체 보호 초기화 실패: \(error.localizedDescription)"
            refreshDashboardState()
        }
    }
}
private struct PickerSheet: View {
    @Binding var selection: FamilyActivitySelection
    @Environment(\.dismiss) private var dismiss
    let onCommit: () -> Void

    private var warnings: [String] {
        var list: [String] = []
        let hasCategory = !selection.categoryTokens.isEmpty
        let hasWeb = !selection.webDomainTokens.isEmpty
        if hasCategory && hasWeb {
            list.append("카테고리와 웹사이트는 아직 지원하지 않아요. 앱만 선택해주세요.")
        } else if hasCategory {
            list.append("카테고리는 아직 지원하지 않아요. 앱만 선택해주세요.")
        } else if hasWeb {
            list.append("웹사이트는 아직 지원하지 않아요. 앱만 선택해주세요.")
        }
        let count = selection.applicationTokens.count
        if count > SharedStore.maxAppsPerGroup {
            list.append("앱을 \(SharedStore.maxAppsPerGroup)개 이하로 선택해주세요 (\(count)/\(SharedStore.maxAppsPerGroup))")
        }
        return list
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.circle.fill")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.red)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.systemBackground))
                    Divider()
                }
                FamilyActivityPicker(selection: $selection)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") {
                        onCommit()
                        dismiss()
                    }
                    .disabled(!warnings.isEmpty)
                }
            }
            .navigationTitle("앱 선택")
            .navigationBarTitleDisplayMode(.inline)
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
                .foregroundStyle(Color.accent)
            Text(title)
                .font(.headline)
        }
    }
}

private struct BillPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.68))
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}


private struct EmptyChartState: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.accent)
            Text("시간을 아낀 선택이 생기면 여기에 쌓입니다.")
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

            HStack(spacing: 0) {
                Picker("시간", selection: $hours) {
                    ForEach(0..<24, id: \.self) { h in
                        Text("\(h)시간").tag(h)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)

                Picker("분", selection: $minutes) {
                    ForEach(0..<60, id: \.self) { m in
                        Text("\(m)분").tag(m)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
            }
            .frame(height: 216)
        }
    }
}
