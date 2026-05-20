//
//  ContentView.swift
//  GoldTime
//

import FamilyControls
import SwiftUI
internal import Combine

struct ContentView: View {
    @Bindable var viewModel: ContentViewModel
    @Bindable var settingsViewModel: SettingsViewModel
    @Binding var showLockOptions: Bool

    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        if !viewModel.isAuthorized {
            OnboardingView(onAuthorized: viewModel.refreshAuthorization)
        } else {
            content
                .onAppear(perform: viewModel.loadState)
        }
    }

    private var content: some View {
        TabView(selection: $viewModel.selectedTab) {
            NavigationStack {
                HomeView(
                    groups: viewModel.groups,
                    todayStats: viewModel.todayStats,
                    isMonitoring: viewModel.isMonitoring,
                    isShieldActive: viewModel.isShieldActive,
                    shieldOverrideUntil: viewModel.shieldOverrideUntil,
                    successMessage: viewModel.successMessage,
                    errorMessage: viewModel.errorMessage,
                    lockedGroupIDs: viewModel.lockedGroupIDs,
                    overrideGroupIDs: viewModel.overrideGroupIDs,
                    validGroupIDs: viewModel.validGroupIDs,
                    overrideUntilByGroupID: viewModel.overrideUntilByGroupID,
                    onAddGroup: viewModel.addGroup,
                    onDeleteGroup: viewModel.deleteGroup,
                    onUpdateGroupName: viewModel.updateGroupName,
                    onPresentPicker: viewModel.presentPicker,
                    onPresentLimitPicker: viewModel.presentLimitPicker,
                    onRequestResetProtection: viewModel.requestResetProtection,
                    onUnlockGroup: viewModel.presentUnlockSheet
                )
            }
            .tabItem {
                Label("홈", systemImage: "house.fill")
            }
            .tag(GoldTimeTab.home)

            NavigationStack {
                StatsView(
                    groups: viewModel.groups,
                    todayStats: viewModel.todayStats,
                    weeklyStats: viewModel.weeklyStats,
                    previousWeekStats: viewModel.previousWeekStats,
                    oneMinuteRemaining: viewModel.oneMinuteRemaining,
                    isMonitoring: viewModel.isMonitoring,
                    adFreeStreakDays: viewModel.adFreeStreakDays
                )
            }
            .tabItem {
                Label("통계", systemImage: "chart.bar.xaxis")
            }
            .tag(GoldTimeTab.stats)

            NavigationStack {
                SettingsView(
                    viewModel: settingsViewModel,
                    onRequestResetProtection: viewModel.requestResetProtection
                )
            }
            .tabItem {
                Label("설정", systemImage: "gearshape")
            }
            .tag(GoldTimeTab.settings)
        }
        .tint(Color.accent)
        .sheet(isPresented: $viewModel.isPickerPresented) {
            AppPickerSheet(selection: $viewModel.pickerSelection) {
                viewModel.commitPickerSelection()
            }
        }
        .alert(item: $viewModel.alertMessage) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("확인"))
            )
        }
        .confirmationDialog(
            "전체 보호 초기화",
            isPresented: $viewModel.isResetProtectionConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("초기화", role: .destructive) {
                viewModel.resetProtectionState()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("모든 모니터링과 현재 잠금을 초기화합니다. 그룹 설정은 유지됩니다.")
        }
        .sheet(isPresented: Binding(
            get: { viewModel.isLimitPickerPresented },
            set: { viewModel.setLimitPickerPresented($0) }
        )) {
            LimitPickerSheet(
                hours: $viewModel.limitPickerHours,
                minutes: $viewModel.limitPickerMinutes,
                onConfirm: {
                    viewModel.commitLimitPickerSelection()
                },
                onCancel: { viewModel.setLimitPickerPresented(false) }
            )
            .presentationDetents([.height(320)])
        }
        .onChange(of: viewModel.isPickerPresented) { _, newValue in
            viewModel.handlePickerPresentationChange(isPresented: newValue)
        }
        .onChange(of: showLockOptions) { _, newValue in
            if !newValue { viewModel.refreshDashboardState() }
        }
        .onReceive(refreshTimer) { _ in
            viewModel.refreshDashboardState()
        }
    }
}

#Preview {
    ContentView(
        viewModel: ContentViewModel(),
        settingsViewModel: SettingsViewModel(),
        showLockOptions: .constant(false)
    )
}
