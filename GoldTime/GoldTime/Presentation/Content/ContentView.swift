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

    // 한 뷰에 .alert(item:)를 여러 개 붙이면 SwiftUI가 하나만 살리고 나머지를 무시한다.
    // alertMessage(단순 통지)와 pendingLimitLockWarning(2버튼 확인)을 하나의 alert로 합친다.
    private enum ActiveAlert: Identifiable {
        case notice(GoldTimeAlertMessage)
        case limitWarning(LimitLockWarning)
        case applyConfirmation(ApplyGroupConfirmation)
        var id: String {
            switch self {
            case .notice(let m): return "notice-\(m.id)"
            case .limitWarning(let w): return "warn-\(w.id)"
            case .applyConfirmation(let c): return "apply-\(c.id)"
            }
        }
    }

    private var activeAlert: Binding<ActiveAlert?> {
        Binding(
            get: {
                if let m = viewModel.alertMessage { return .notice(m) }
                if let w = viewModel.pendingLimitLockWarning { return .limitWarning(w) }
                if let c = viewModel.pendingApplyConfirmation { return .applyConfirmation(c) }
                return nil
            },
            set: { newValue in
                if newValue == nil {
                    viewModel.alertMessage = nil
                    viewModel.pendingLimitLockWarning = nil
                    viewModel.pendingApplyConfirmation = nil
                }
            }
        )
    }

    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @AppStorage("weekStartDay", store: UserDefaults(suiteName: SharedStore.suiteName))
    private var weekStartDay: Int = 2

    var body: some View {
        if viewModel.isCheckingPermissions {
            Color(.systemBackground).ignoresSafeArea()
        } else if viewModel.shouldShowInitialOnboarding {
            OnboardingView(startStep: viewModel.onboardingStartStep, onAuthorized: viewModel.refreshAuthorization)
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
                    oneMinuteRemaining: viewModel.oneMinuteRemaining,
                    oneMinuteDailyLimit: viewModel.oneMinuteDailyLimit,
                    onAddGroup: viewModel.addGroup,
                    onDeleteGroup: viewModel.requestDeleteGroup,
                    onUpdateGroupName: viewModel.updateGroupName,
                    onPresentPicker: viewModel.requestPickerPresentation,
                    onPresentRuleEditor: viewModel.requestRuleEditorPresentation,
                    onUnlockGroup: viewModel.presentUnlockSheet,
                    onApplyGroup: viewModel.requestApplyGroup
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
        .sheet(isPresented: Binding(
            get: { viewModel.isRuleEditorPresented },
            set: { viewModel.setRuleEditorPresented($0) }
        ), onDismiss: {
            viewModel.handleRuleEditorDismiss()
        }) {
            RuleEditorSheet(
                selectedKind: $viewModel.ruleEditorSelectedKind,
                hours: $viewModel.limitPickerHours,
                minutes: $viewModel.limitPickerMinutes,
                timeWindows: $viewModel.ruleEditorTimeWindows,
                currentKind: viewModel.ruleEditorSelectedKind,
                onConfirm: {
                    viewModel.commitRuleSelection()
                },
                onCancel: { viewModel.setRuleEditorPresented(false) }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert(item: activeAlert) { active in
            switch active {
            case .notice(let message):
                Alert(
                    title: Text(message.title),
                    message: Text(message.message),
                    dismissButton: .default(Text("확인"))
                )
            case .limitWarning(let warning):
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
            case .applyConfirmation(let confirmation):
                Alert(
                    title: Text("그룹을 적용할까요?"),
                    message: Text("‘\(confirmation.groupName)’ 그룹을 적용하면 바로 보호가 시작돼요. 이후 규칙 변경, 제한 항목 수정, 삭제에는 광고 시청이 필요해요."),
                    primaryButton: .default(Text("적용하기")) {
                        viewModel.confirmApplyGroup(confirmation)
                    },
                    secondaryButton: .cancel(Text("취소")) {
                        viewModel.cancelApplyGroup()
                    }
                )
            }
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
