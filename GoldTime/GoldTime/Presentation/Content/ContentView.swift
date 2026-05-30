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
        } else if viewModel.shouldShowInitialOnboarding {
            let startStep: OnboardingStep = viewModel.isAuthorized ? .notificationPermission : .intro
            OnboardingView(startStep: startStep, onAuthorized: viewModel.refreshAuthorization)
        } else if viewModel.shouldShowNotificationOnboarding {
            OnboardingView(startStep: .notificationPermission, onAuthorized: viewModel.refreshAuthorization)
        } else {
            content
                .withConsentFlow()
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
                    usedTimeByGroupID: viewModel.usedTimeByGroupID,
                    overrideBaselineUsedTimeByGroupID: viewModel.overrideBaselineUsedTimeByGroupID,
                    overrideGrantedMinutesByGroupID: viewModel.overrideGrantedMinutesByGroupID,
                    overrideTickLog: viewModel.overrideTickLog,
                    oneMinuteRemaining: viewModel.oneMinuteRemaining,
                    oneMinuteDailyLimit: viewModel.oneMinuteDailyLimit,
                    onAddGroup: viewModel.addGroup,
                    onDeleteGroup: viewModel.requestDeleteGroup,
                    onUpdateGroupName: viewModel.updateGroupName,
                    onPresentPicker: viewModel.requestPickerPresentation,
                    onPresentLimitPicker: viewModel.requestLimitPickerPresentation,
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
                    statsReport: viewModel.statsReport,
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
        .fullScreenCover(isPresented: $viewModel.isScreenTimeRecoveryPresented) {
            ScreenTimeAuthorizationRecoveryView(
                isRequesting: viewModel.isRequestingScreenTimeAuthorization,
                errorMessage: viewModel.screenTimeRecoveryErrorMessage
            ) {
                Task { await viewModel.requestScreenTimeAuthorizationOnEntry() }
            }
            .interactiveDismissDisabled()
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
        ), onDismiss: {
            viewModel.handleLimitPickerDismiss()
        }) {
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
        .alert(item: $viewModel.pendingLimitLockWarning) { warning in
            Alert(
                title: Text("한도 변경 확인"),
                message: Text("이미 \(warning.usedMinutes)분 사용해서, \(warning.minutes)분으로 바꾸면 한도를 ‘\(warning.groupName)’ 그룹이 바로 잠겨요. 변경할까요?"),
                primaryButton: .destructive(Text("변경")) {
                    viewModel.confirmLimitLockChange(warning)
                },
                secondaryButton: .cancel(Text("취소")) {
                    viewModel.cancelLimitLockChange()
                }
            )
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

private struct ScreenTimeAuthorizationRecoveryView: View {
    let isRequesting: Bool
    let errorMessage: String?
    let onRequest: () -> Void

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(Color.accent.opacity(0.15))
                            .frame(width: 100, height: 100)
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.accent)
                    }

                    VStack(spacing: 12) {
                        Text("스크린타임 권한이 필요해요")
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                        Text("GoldTime이 앱 한도를 적용하려면 스크린타임 접근 권한을 다시 허용해야 해요.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }

                Spacer()

                VStack(spacing: 12) {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button(action: onRequest) {
                        Text(isRequesting ? "요청 중..." : "스크린타임 허용하기")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GoldTimeButtonStyle(background: Color.accent, foreground: .black, cornerRadius: 16))
                    .disabled(isRequesting)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 24)
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
