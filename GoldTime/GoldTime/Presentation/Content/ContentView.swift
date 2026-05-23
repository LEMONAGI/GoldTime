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
    @AppStorage("weekStartDay", store: UserDefaults(suiteName: SharedStore.suiteName))
    private var weekStartDay: Int = 2

    var body: some View {
        if viewModel.isCheckingPermissions {
            Color(.systemBackground).ignoresSafeArea()
        } else if !viewModel.isFullyAuthorized {
            let startStep: OnboardingStep = viewModel.isAuthorized ? .notificationPermission : .intro
            OnboardingView(startStep: startStep, onAuthorized: viewModel.refreshAuthorization)
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
                    onDeleteGroup: viewModel.requestDeleteGroup,
                    onUpdateGroupName: viewModel.updateGroupName,
                    onPresentPicker: viewModel.requestPickerPresentation,
                    onPresentLimitPicker: viewModel.presentLimitPicker,
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
                    monthlyStats: viewModel.monthlyStats,
                    isMonitoring: viewModel.isMonitoring,
                    adFreeStreakDays: viewModel.adFreeStreakDays,
                    maxAdFreeStreakDays: viewModel.maxAdFreeStreakDays
                )
            }
            .tabItem {
                Label("통계", systemImage: "chart.bar.xaxis")
            }
            .tag(GoldTimeTab.stats)

            NavigationStack {
                SettingsView(
                    viewModel: settingsViewModel,
                    isReconnecting: viewModel.isReconnecting,
                    onRequestReconnect: viewModel.reconnectMonitoring
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
            .presentationDetents([.height(300)])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: viewModel.isPickerPresented) { _, newValue in
            viewModel.handlePickerPresentationChange(isPresented: newValue)
        }
        .onChange(of: showLockOptions) { _, newValue in
            if !newValue { viewModel.refreshDashboardState() }
        }
        .onChange(of: weekStartDay) { _, _ in
            viewModel.refreshDashboardState()
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
