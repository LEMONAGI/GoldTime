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
    @State private var isStrictLockBetaAnnouncementPresented = false

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
                    untrackedGroupIDs: viewModel.untrackedGroupIDs,
                    overrideUntilByGroupID: viewModel.overrideUntilByGroupID,
                    usedTimeByGroupID: viewModel.usedTimeByGroupID,
                    overrideBaselineUsedTimeByGroupID: viewModel.overrideBaselineUsedTimeByGroupID,
                    overrideGrantedMinutesByGroupID: viewModel.overrideGrantedMinutesByGroupID,
                    cooldownEndByGroupID: viewModel.cooldownEndByGroupID,
                    oneMinuteRemaining: viewModel.oneMinuteRemaining,
                    oneMinuteDailyLimit: viewModel.oneMinuteDailyLimit,
                    onAddGroup: viewModel.addGroup,
                    onDeleteGroup: viewModel.requestDeleteGroup,
                    onUpdateGroupName: viewModel.updateGroupName,
                    onPresentPicker: viewModel.requestPickerPresentation,
                    onPresentRuleEditor: viewModel.presentRuleEditor,
                    onUnlockGroup: viewModel.presentUnlockSheet,
                    onApplyGroup: viewModel.requestApplyGroup,
                    onPresentStrictLock: viewModel.presentStrictLockSheet,
                    isStrictLockFeatureEnabled: viewModel.isStrictLockFeatureEnabled,
                    isStrictLockBetaBannerGlowing: viewModel.isStrictLockBetaBannerGlowing,
                    onTapStrictLockBetaBanner: {
                        viewModel.markStrictLockBetaAnnouncementSeen()
                        isStrictLockBetaAnnouncementPresented = true
                    }
                )
            }
            .tabItem {
                Label("home.title", systemImage: "house.fill")
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
                Label("stats.title", systemImage: "chart.bar.xaxis")
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
                Label("settings.title", systemImage: "gearshape")
            }
            .tag(GoldTimeTab.settings)
        }
        .tint(Color.accent)
        .sheet(isPresented: $viewModel.isPickerPresented) {
            AppPickerSheet(selection: $viewModel.pickerSelection) {
                viewModel.commitPickerSelection()
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.strictLockSheetGroupID != nil },
            set: { viewModel.setStrictLockSheetPresented($0) }
        )) {
            if let group = viewModel.strictLockSheetGroup {
                StrictLockSheet(group: group) { days in
                    viewModel.confirmStrictLock(days: days)
                }
            }
        }
        .fullScreenCover(isPresented: $viewModel.isScreenTimeRecoveryPresented) {
            ScreenTimeAuthorizationRecoveryView(
                isRequesting: viewModel.isRequestingScreenTimeAuthorization,
                errorMessage: viewModel.screenTimeRecoveryErrorMessage,
                showsStrictNotice: viewModel.hasActiveStrictCommitment
            ) {
                Task { await viewModel.requestScreenTimeAuthorizationOnEntry() }
            }
            .interactiveDismissDisabled()
            .onAppear { viewModel.handleScreenTimeRecoveryAppear() }
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
                cooldownUsageMinutes: $viewModel.ruleEditorCooldownUsageMinutes,
                cooldownDurationMinutes: $viewModel.ruleEditorCooldownDurationMinutes,
                weekdayRules: $viewModel.ruleEditorWeekdayRules,
                weekStartDay: weekStartDay,
                currentKind: viewModel.ruleEditorCurrentKind,
                nearMidnightNotice: viewModel.nearMidnightEditNotice,
                onConfirm: {
                    if viewModel.isRuleCommitAdGateRequired {
                        // 광고 게이트 cover는 자체 등장 연출(scrim 페이드 + 카드 rise)을 쓰므로
                        // 시스템 슬라이드 프레젠테이션을 끈다. 커밋 경로(else)는 기존 애니메이션 유지.
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { viewModel.commitRuleSelection() }
                    } else {
                        viewModel.commitRuleSelection()
                    }
                },
                onCancel: { viewModel.setRuleEditorPresented(false) }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .fullScreenCover(isPresented: $viewModel.isRuleCommitAdGatePresented, onDismiss: {
                viewModel.handleRuleCommitAdGateDismiss()
            }) {
                RuleCommitAdGateView(
                    onComplete: viewModel.ruleCommitAdGateCompleted,
                    onCancel: viewModel.ruleCommitAdGateCancelled
                )
            }
        }
        .sheet(isPresented: $isStrictLockBetaAnnouncementPresented) {
            StrictLockBetaSheet()
        }
        .alert(item: activeAlert) { active in
            switch active {
            case .notice(let message):
                Alert(
                    title: Text(message.title),
                    message: Text(message.message),
                    dismissButton: .default(Text("common.confirm"))
                )
            case .limitWarning(let warning):
                Alert(
                    title: Text(limitWarningTitle(warning)),
                    message: Text(limitWarningMessage(warning)),
                    primaryButton: .destructive(Text("common.change")) {
                        viewModel.confirmLimitLockChange(warning)
                    },
                    secondaryButton: .cancel(Text("common.cancel")) {
                        viewModel.cancelLimitLockChange()
                    }
                )
            case .applyConfirmation(let confirmation):
                Alert(
                    title: Text("content.apply.title"),
                    message: Text("content.apply.message \(confirmation.groupName)"),
                    primaryButton: .default(Text("group.apply")) {
                        viewModel.confirmApplyGroup(confirmation)
                    },
                    secondaryButton: .cancel(Text("common.cancel")) {
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

    private func limitWarningTitle(_ warning: LimitLockWarning) -> String {
        switch warning.rule {
        case .dailyLimit: return String(localized: "content.limitWarning.dailyLimit.title")
        case .cooldown: return String(localized: "content.limitWarning.cooldown.title")
        }
    }

    private func limitWarningMessage(_ warning: LimitLockWarning) -> String {
        switch warning.rule {
        case .dailyLimit(let minutes):
            return String(localized: "content.limitWarning.dailyLimit.message \(warning.usedMinutes) \(minutes) \(warning.groupName)")
        case .cooldown(let usage, _):
            return String(localized: "content.limitWarning.cooldown.message \(warning.usedMinutes) \(usage) \(warning.groupName)")
        }
    }

}

private struct ScreenTimeAuthorizationRecoveryView: View {
    let isRequesting: Bool
    let errorMessage: String?
    /// 연장 불가 기간이 살아 있으면 재승인 시 그대로 이어진다는 안내를 강조한다.
    var showsStrictNotice: Bool = false
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
                        Text("content.recovery.title")
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                        Text("content.recovery.message")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        if showsStrictNotice {
                            Text("recovery.strictNotice")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.accent)
                                .multilineTextAlignment(.center)
                        }
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
                        Text(isRequesting ? "common.requesting" : "onboarding.screenTime.button")
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

/// 규칙 변경 완료 광고 게이트. 안내(1단계 확인 카드)와 광고(2단계 `RewardedAdView`)를
/// **하나의 fullScreenCover 안에서** 전환한다 — 시트 안에서 confirmationDialog → cover 연쇄는
/// 어떤 타이밍 처방으로도 dismiss/present 글리치(UIKit 거부·재표시)가 남아 presentation을
/// 하나로 합쳤다(Presentation/CLAUDE.md "presentation 전환 타이밍" 참조).
/// 1단계는 기존 안내 다이얼로그와 같은 느낌의 하단 카드 — 배경 탭/취소 = 편집 유지.
private struct RuleCommitAdGateView: View {
    let onComplete: () -> Void
    let onCancel: () -> Void

    @State private var isShowingAd = false
    /// 등장 연출은 cover의 시스템 슬라이드 대신 직접 한다(프레젠테이션 애니메이션은 ContentView가
    /// 끔): scrim은 opacity 페이드(시트 dim 느낌), 카드는 페이드+살짝 떠오르기. 검은 막·카드가
    /// 화면 아래에서 통째로 슉 올라오는 어색함 방지 — 취소(페이드아웃) 연출과 대칭.
    @State private var isScrimVisible = false
    @State private var isCardVisible = false

    var body: some View {
        Group {
            if isShowingAd {
                RewardedAdView(
                    placement: .groupEditGate,
                    fallbackLabel: String(localized: "content.adGate.change"),
                    onComplete: onComplete,
                    onCancel: onCancel
                )
            } else {
                confirmStage
            }
        }
        .presentationBackground(.clear)
    }

    private var confirmStage: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(isScrimVisible ? 0.45 : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: cancelWithScrimFade)

            confirmCard
                .opacity(isCardVisible ? 1 : 0)
                .offset(y: isCardVisible ? 0 : 32)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) { isScrimVisible = true }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { isCardVisible = true }
        }
    }

    /// 취소는 scrim·카드를 먼저 페이드아웃한 뒤 cover를 내린다(등장과 대칭).
    /// 지연은 페이드 시간만큼만이라 체감 지연 없음.
    private func cancelWithScrimFade() {
        withAnimation(.easeIn(duration: 0.18)) {
            isScrimVisible = false
            isCardVisible = false
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            onCancel()
        }
    }

    /// iOS 26+는 Liquid Glass(연속 코너 28 + 캡슐형 확인 버튼), 미만은 기존 material 카드.
    /// glass 안에 glass 버튼을 중첩하지 않는다(HIG — 취소는 시스템 알럿처럼 텍스트 행).
    @ViewBuilder
    private var confirmCard: some View {
        if #available(iOS 26.0, *) {
            cardContent(buttonCornerRadius: 25)
                .glassEffect(.regular, in: .rect(cornerRadius: 28, style: .continuous))
        } else {
            cardContent(buttonCornerRadius: 12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func cardContent(buttonCornerRadius: CGFloat) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("group.restricted.title")
                    .font(.headline)
                Text("rule.commit.adNotice.message")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isShowingAd = true }
                } label: {
                    Text("group.ad.change")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GoldTimeButtonStyle(background: Color.accent, foreground: .black, cornerRadius: buttonCornerRadius))
                Button("common.cancel", role: .cancel, action: cancelWithScrimFade)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
    }
}

#Preview("완료 광고 게이트 — 안내 카드") {
    RuleCommitAdGateView(onComplete: {}, onCancel: {})
}

#Preview {
    ContentView(
        viewModel: ContentViewModel(),
        settingsViewModel: SettingsViewModel(),
        showLockOptions: .constant(false)
    )
}
