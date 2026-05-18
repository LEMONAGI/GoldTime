//
//  ContentView.swift
//  GoldTime
//

import FamilyControls
import SwiftUI
internal import Combine

private enum GoldTimeTab: Hashable {
    case home
    case stats
    case settings
}

struct ContentView: View {
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

    @State private var limitPickerGroupID: UUID?
    @State private var limitPickerHours = 0
    @State private var limitPickerMinutes = 30

    @State private var isShieldActive = SharedStore.isShieldActive
    @State private var oneMinuteRemaining = SharedStore.oneMinuteRemaining
    @State private var shieldOverrideUntil: Date? = SharedStore.currentShieldOverrideUntil
    @State private var todayStats = SharedStore.todayStats
    @State private var weeklyStats = SharedStore.lastSevenDayStats()

    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

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
                HomeView(
                    groups: groups,
                    todayStats: todayStats,
                    isMonitoring: isMonitoring,
                    isShieldActive: isShieldActive,
                    shieldOverrideUntil: shieldOverrideUntil,
                    successMessage: successMessage,
                    errorMessage: errorMessage,
                    onAddGroup: addGroup,
                    onDeleteGroup: deleteGroup,
                    onUpdateGroupName: updateGroupName,
                    onPresentPicker: presentPicker,
                    onPresentLimitPicker: presentLimitPicker,
                    onRequestResetProtection: { isResetProtectionConfirmationPresented = true }
                )
            }
            .tabItem {
                Label("홈", systemImage: "house.fill")
            }
            .tag(GoldTimeTab.home)

            NavigationStack {
                StatsView(
                    groups: groups,
                    todayStats: todayStats,
                    weeklyStats: weeklyStats,
                    oneMinuteRemaining: oneMinuteRemaining,
                    isMonitoring: isMonitoring
                )
            }
            .tabItem {
                Label("통계", systemImage: "chart.bar.xaxis")
            }
            .tag(GoldTimeTab.stats)

            NavigationStack {
                SettingsView(
                    auth: auth,
                    onRequestResetProtection: { isResetProtectionConfirmationPresented = true }
                )
            }
            .tabItem {
                Label("설정", systemImage: "gearshape")
            }
            .tag(GoldTimeTab.settings)
        }
        .sheet(isPresented: $isPickerPresented) {
            AppPickerSheet(selection: $pickerSelection) {
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

    private func presentLimitPicker(for group: SharedStore.ScreenTimeGroup) {
        limitPickerHours = group.dailyLimitMinutes / 60
        limitPickerMinutes = group.dailyLimitMinutes % 60
        limitPickerGroupID = group.id
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

private struct AlertMessage: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

#Preview {
    ContentView(showLockOptions: .constant(false))
}
