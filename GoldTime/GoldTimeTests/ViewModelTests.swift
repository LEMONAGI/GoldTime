//
//  ViewModelTests.swift
//  GoldTimeTests
//

import Foundation
import FamilyControls
import ManagedSettings
import SwiftUI
import Testing
import UIKit
@testable import GoldTime

@MainActor
struct ViewModelTests {

    // MARK: - ContentViewModel

    @Test func contentViewModelUsesInjectedAuthorizationStateOnInit() {
        let viewModel = ContentViewModel(
            syncProtectionUseCase: makeSyncProtectionUseCase(),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )

        #expect(viewModel.isAuthorized)
    }

    @Test func contentViewModelUpdatesWhenAuthorizationStateChanges() {
        let authRepo = FakeAuthorizationRepository(isAuthorized: false)
        let viewModel = ContentViewModel(
            syncProtectionUseCase: makeSyncProtectionUseCase(),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: AuthorizeUseCase(
                authRepository: authRepo,
                notificationRepository: FakeNotificationRepository()
            ),
            userDefaults: makeUserDefaults()
        )

        authRepo.setAuthorized(true)

        #expect(viewModel.isAuthorized)
    }

    @Test func contentViewModelIsNotFullyAuthorizedWhenNotificationDenied() async throws {
        let notifRepo = FakeNotificationRepository()
        notifRepo.authorizationStateValue = .denied
        let viewModel = ContentViewModel(
            syncProtectionUseCase: makeSyncProtectionUseCase(),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: AuthorizeUseCase(
                authRepository: FakeAuthorizationRepository(isAuthorized: true),
                notificationRepository: notifRepo
            ),
            userDefaults: makeUserDefaults()
        )
        while viewModel.isCheckingPermissions {
            try await Task.sleep(for: .milliseconds(1))
        }

        #expect(viewModel.isAuthorized)
        #expect(!viewModel.isNotificationAuthorized)
        #expect(!viewModel.isFullyAuthorized)
        // 알림은 선택 권한이므로 거부해도 홈 진입이 막히면 안 된다.
        #expect(viewModel.hasCompletedInitialHomeEntry)
        #expect(!viewModel.shouldShowInitialOnboarding)
    }

    @Test func contentViewModelIsFullyAuthorizedWhenBothGranted() async throws {
        let notifRepo = FakeNotificationRepository()
        notifRepo.authorizationStateValue = .authorized
        let viewModel = ContentViewModel(
            syncProtectionUseCase: makeSyncProtectionUseCase(),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: AuthorizeUseCase(
                authRepository: FakeAuthorizationRepository(isAuthorized: true),
                notificationRepository: notifRepo
            ),
            userDefaults: makeUserDefaults()
        )
        while viewModel.isCheckingPermissions {
            try await Task.sleep(for: .milliseconds(1))
        }

        #expect(viewModel.isAuthorized)
        #expect(viewModel.isNotificationAuthorized)
        #expect(viewModel.isFullyAuthorized)
        #expect(viewModel.hasCompletedInitialHomeEntry)
    }

    @Test func contentViewModelKeepsFirstUserInOnboardingWhenScreenTimeMissing() async throws {
        let notifRepo = FakeNotificationRepository()
        notifRepo.authorizationStateValue = .authorized
        let viewModel = ContentViewModel(
            syncProtectionUseCase: makeSyncProtectionUseCase(),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: AuthorizeUseCase(
                authRepository: FakeAuthorizationRepository(isAuthorized: false),
                notificationRepository: notifRepo
            ),
            userDefaults: makeUserDefaults()
        )
        while viewModel.isCheckingPermissions {
            try await Task.sleep(for: .milliseconds(1))
        }

        #expect(viewModel.shouldShowInitialOnboarding)
        #expect(!viewModel.isScreenTimeRecoveryPresented)
    }

    @Test func contentViewModelKeepsOnboardingWhenStepSavedDespiteScreenTimeGranted() async throws {
        // 알림 단계까지 갔다가 앱을 종료한 상태를 재현한다(스크린타임은 이미 허용됨).
        // 재실행해도 권한만 보고 홈으로 건너뛰지 않고 온보딩을 유지해야 한다.
        let defaults = makeUserDefaults()
        defaults.set(OnboardingStep.notificationPermission.rawValue, forKey: OnboardingViewModel.savedStepKey)
        let notifRepo = FakeNotificationRepository()
        notifRepo.authorizationStateValue = .notDetermined
        let viewModel = ContentViewModel(
            syncProtectionUseCase: makeSyncProtectionUseCase(),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: AuthorizeUseCase(
                authRepository: FakeAuthorizationRepository(isAuthorized: true),
                notificationRepository: notifRepo
            ),
            userDefaults: defaults
        )
        while viewModel.isCheckingPermissions {
            try await Task.sleep(for: .milliseconds(1))
        }

        #expect(viewModel.shouldShowInitialOnboarding)
        #expect(viewModel.onboardingStartStep == .notificationPermission)
    }

    @Test func contentViewModelDoesNotShowRecoveryForTransientMissingScreenTimeState() {
        let defaults = makeUserDefaults(hasCompletedInitialHomeEntry: true)
        let authRepo = FakeAuthorizationRepository(isAuthorized: false)
        let viewModel = ContentViewModel(
            syncProtectionUseCase: makeSyncProtectionUseCase(),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: AuthorizeUseCase(
                authRepository: authRepo,
                notificationRepository: FakeNotificationRepository()
            ),
            userDefaults: defaults
        )

        #expect(!viewModel.shouldShowInitialOnboarding)
        #expect(!viewModel.isScreenTimeRecoveryPresented)

        authRepo.setAuthorized(true)

        #expect(viewModel.isAuthorized)
        #expect(!viewModel.isScreenTimeRecoveryPresented)
    }

    @Test func contentViewModelShowsRecoveryAfterStartedUserLosesScreenTime() async throws {
        let defaults = makeUserDefaults(hasCompletedInitialHomeEntry: true)
        let authRepo = FakeAuthorizationRepository(isAuthorized: false)
        authRepo.requestError = TestAuthorizationError.denied
        let notifRepo = FakeNotificationRepository()
        notifRepo.authorizationStateValue = .authorized
        let viewModel = ContentViewModel(
            syncProtectionUseCase: makeSyncProtectionUseCase(),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: AuthorizeUseCase(
                authRepository: authRepo,
                notificationRepository: notifRepo
            ),
            userDefaults: defaults
        )
        while viewModel.isCheckingPermissions {
            try await Task.sleep(for: .milliseconds(1))
        }

        await viewModel.requestScreenTimeAuthorizationOnEntry()

        #expect(authRepo.requestCallCount == 1)
        #expect(!viewModel.shouldShowInitialOnboarding)
        #expect(viewModel.isScreenTimeRecoveryPresented)
    }

    @Test func contentViewModelDismissesRecoveryWhenScreenTimeRequestSucceeds() async throws {
        let defaults = makeUserDefaults(hasCompletedInitialHomeEntry: true)
        let authRepo = FakeAuthorizationRepository(isAuthorized: false)
        authRepo.requestResultIsAuthorized = true
        let notifRepo = FakeNotificationRepository()
        notifRepo.authorizationStateValue = .authorized
        let viewModel = ContentViewModel(
            syncProtectionUseCase: makeSyncProtectionUseCase(),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: AuthorizeUseCase(
                authRepository: authRepo,
                notificationRepository: notifRepo
            ),
            userDefaults: defaults
        )
        while viewModel.isCheckingPermissions {
            try await Task.sleep(for: .milliseconds(1))
        }

        await viewModel.requestScreenTimeAuthorizationOnEntry()

        #expect(authRepo.requestCallCount == 1)
        #expect(viewModel.isAuthorized)
        #expect(!viewModel.isScreenTimeRecoveryPresented)
    }

    @Test func contentViewModelSkipsScreenTimeRequestOnHomeLoadWhenAlreadyAuthorized() async throws {
        let defaults = makeUserDefaults(hasCompletedInitialHomeEntry: true)
        let authRepo = FakeAuthorizationRepository(isAuthorized: true)
        authRepo.requestResultIsAuthorized = true
        let notifRepo = FakeNotificationRepository()
        notifRepo.authorizationStateValue = .authorized
        let viewModel = ContentViewModel(
            syncProtectionUseCase: makeSyncProtectionUseCase(),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: AuthorizeUseCase(
                authRepository: authRepo,
                notificationRepository: notifRepo
            ),
            userDefaults: defaults
        )
        while viewModel.isCheckingPermissions {
            try await Task.sleep(for: .milliseconds(1))
        }

        viewModel.loadState()
        try await Task.sleep(for: .milliseconds(10))

        #expect(authRepo.requestCallCount == 0)
    }

    // MARK: - SettingsViewModel

    @Test func settingsViewModelLoadsPermissionStates() async {
        let authRepo = FakeAuthorizationRepository(isAuthorized: true)
        let notifRepo = FakeNotificationRepository()
        notifRepo.authorizationStateValue = .denied
        let viewModel = SettingsViewModel(
            manageSettingsUseCase: ManageSettingsUseCase(
                authRepository: authRepo,
                notificationRepository: notifRepo
            )
        )

        await viewModel.loadState()

        #expect(viewModel.isScreenTimeAuthorized)
        #expect(viewModel.notificationPermissionState == .denied)
        #expect(notifRepo.authorizationStateCallCount == 1)
    }

    @Test func settingsViewModelRequestsNotificationAuthorization() async {
        let notifRepo = FakeNotificationRepository()
        notifRepo.requestAuthorizationResult = .authorized
        let viewModel = SettingsViewModel(
            manageSettingsUseCase: ManageSettingsUseCase(
                authRepository: FakeAuthorizationRepository(isAuthorized: true),
                notificationRepository: notifRepo
            )
        )

        await viewModel.requestNotificationAuthorization()

        #expect(notifRepo.requestCallCount == 1)
        #expect(viewModel.notificationPermissionState == .authorized)
        #expect(!viewModel.isRequestingNotificationAuthorization)
    }

    @Test func settingsViewModelRequestsScreenTimeAuthorization() async {
        let authRepo = FakeAuthorizationRepository(isAuthorized: false)
        authRepo.requestResultIsAuthorized = true
        let viewModel = SettingsViewModel(
            manageSettingsUseCase: ManageSettingsUseCase(
                authRepository: authRepo,
                notificationRepository: FakeNotificationRepository()
            )
        )

        await viewModel.requestScreenTimeAuthorization()

        #expect(authRepo.requestCallCount == 1)
        #expect(viewModel.isScreenTimeAuthorized)
        #expect(viewModel.alertMessage == nil)
        #expect(!viewModel.isRequestingScreenTimeAuthorization)
    }

    @Test func settingsViewModelAlertsWhenScreenTimeAuthorizationStillMissing() async {
        let authRepo = FakeAuthorizationRepository(isAuthorized: false)
        authRepo.requestResultIsAuthorized = false
        let viewModel = SettingsViewModel(
            manageSettingsUseCase: ManageSettingsUseCase(
                authRepository: authRepo,
                notificationRepository: FakeNotificationRepository()
            )
        )

        await viewModel.requestScreenTimeAuthorization()

        #expect(!viewModel.isScreenTimeAuthorized)
        #expect(viewModel.alertMessage?.title == "스크린 타임 권한 필요")
    }

    @Test func settingsViewModelLoadsDailyMorningNotificationPreference() async {
        let notifRepo = FakeNotificationRepository()
        notifRepo.isDailyMorningNotificationEnabled = false
        let viewModel = SettingsViewModel(
            manageSettingsUseCase: ManageSettingsUseCase(
                authRepository: FakeAuthorizationRepository(isAuthorized: true),
                notificationRepository: notifRepo
            )
        )

        #expect(!viewModel.isDailyMorningNotificationEnabled)

        notifRepo.isDailyMorningNotificationEnabled = true
        await viewModel.loadState()

        #expect(viewModel.isDailyMorningNotificationEnabled)
    }

    @Test func settingsViewModelLoadsScheduledSummaryDeferral() async {
        let notifRepo = FakeNotificationRepository()
        notifRepo.authorizationStateValue = .authorized
        notifRepo.isDeferredByScheduledSummary = true
        let viewModel = SettingsViewModel(
            manageSettingsUseCase: ManageSettingsUseCase(
                authRepository: FakeAuthorizationRepository(isAuthorized: true),
                notificationRepository: notifRepo
            )
        )

        await viewModel.loadState()

        #expect(viewModel.isNotificationDeferredBySummary)
    }

    @Test func settingsViewModelTogglesDailyMorningNotification() {
        let notifRepo = FakeNotificationRepository()
        let viewModel = SettingsViewModel(
            manageSettingsUseCase: ManageSettingsUseCase(
                authRepository: FakeAuthorizationRepository(isAuthorized: true),
                notificationRepository: notifRepo
            )
        )

        viewModel.setDailyMorningNotificationEnabled(false)

        #expect(!viewModel.isDailyMorningNotificationEnabled)
        #expect(notifRepo.setDailyMorningEnabledCalls == [false])

        viewModel.setDailyMorningNotificationEnabled(true)

        #expect(viewModel.isDailyMorningNotificationEnabled)
        #expect(notifRepo.setDailyMorningEnabledCalls == [false, true])
    }

    // MARK: - Ad Gate

    @Test func adGateSkippedForDraftGroup() {
        // draft(미적용) 그룹은 잠금/연장과 무관하게 광고 게이트 없이 바로 앱 선택 편집에 들어간다.
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "SNS", ruleKind: nil, isApplied: false)
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: FakeGroupRepository(),
                screenTimeRepository: FakeScreenTimeRepository()
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]

        viewModel.requestPickerPresentation(for: group)
        #expect(!viewModel.isAdGatePresented)
        #expect(viewModel.isPickerPresented)
    }

    @Test func adGateSkippedForDraftDelete() {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "SNS", ruleKind: nil, isApplied: false)
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo,
                screenTimeRepository: FakeScreenTimeRepository()
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]

        viewModel.requestDeleteGroup(group.id)

        #expect(!viewModel.isAdGatePresented)
        #expect(!viewModel.groups.contains(where: { $0.id == group.id }))
    }

    @Test func adGateOpenedForAppliedUnlockedGroup() {
        // 적용된 그룹은 잠겨 있지 않아도 앱 선택 편집/삭제에 진입 광고 게이트가 뜬다
        // (규칙 변경은 진입이 아니라 완료 게이트 — 아래 Rule Commit Ad Gate 섹션에서 검증).
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "SNS")
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: FakeGroupRepository(),
                screenTimeRepository: FakeScreenTimeRepository()
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]

        viewModel.requestPickerPresentation(for: group)
        #expect(viewModel.isAdGatePresented)
        #expect(!viewModel.isPickerPresented)

        viewModel.adGateCancelled()
        viewModel.requestDeleteGroup(group.id)
        #expect(viewModel.isAdGatePresented)
    }

    @Test func adGateOpenedForLockedGroupEdit() {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임")
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: FakeGroupRepository(),
                screenTimeRepository: FakeScreenTimeRepository()
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]
        viewModel.lockedGroupIDs = [group.id]

        viewModel.requestPickerPresentation(for: group)

        #expect(viewModel.isAdGatePresented)
        #expect(viewModel.adGateFallbackLabel == "그래도 편집하기")
        #expect(!viewModel.isPickerPresented)
    }

    @Test func adGateOpenedForLockedGroupDelete() {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임")
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: FakeGroupRepository(),
                screenTimeRepository: FakeScreenTimeRepository()
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]
        viewModel.lockedGroupIDs = [group.id]

        viewModel.requestDeleteGroup(group.id)

        #expect(viewModel.isAdGatePresented)
        #expect(viewModel.adGateFallbackLabel == "그래도 삭제하기")
    }

    @Test func adGateOpenedForOverrideGroupEdit() {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임")
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: FakeGroupRepository(),
                screenTimeRepository: FakeScreenTimeRepository()
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]
        viewModel.overrideGroupIDs = [group.id]

        viewModel.requestPickerPresentation(for: group)

        #expect(viewModel.isAdGatePresented)
        #expect(viewModel.adGateFallbackLabel == "그래도 편집하기")
        #expect(!viewModel.isPickerPresented)
    }

    @Test func adGateOpenedForOverrideGroupDelete() {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임")
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: FakeGroupRepository(),
                screenTimeRepository: FakeScreenTimeRepository()
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]
        viewModel.overrideGroupIDs = [group.id]

        viewModel.requestDeleteGroup(group.id)

        #expect(viewModel.isAdGatePresented)
        #expect(viewModel.adGateFallbackLabel == "그래도 삭제하기")
    }

    @Test func regularGroupDeleteShowsCompletionAlertWithName() async {
        // draft(미적용) 그룹은 광고 게이트 없이 바로 삭제되고 완료 알럿이 뜬다.
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임", ruleKind: nil, isApplied: false)
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo,
                screenTimeRepository: FakeScreenTimeRepository()
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]

        viewModel.requestDeleteGroup(group.id)
        // 알럿은 다음 런루프에 설정되므로 대기한다.
        try? await Task.sleep(for: .milliseconds(50))

        #expect(!viewModel.isAdGatePresented)
        #expect(viewModel.alertMessage?.title == "삭제 완료")
        #expect(viewModel.alertMessage?.message.contains("게임") == true)
    }

    @Test func lockedGroupDeleteShowsCompletionAlertAfterAdGateDismiss() async {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임")
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo,
                screenTimeRepository: FakeScreenTimeRepository()
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]
        viewModel.lockedGroupIDs = [group.id]

        viewModel.requestDeleteGroup(group.id)
        // 광고 게이트만 열리고 아직 완료 알럿은 없다(시트와 alert 동시 표시 방지).
        #expect(viewModel.isAdGatePresented)
        #expect(viewModel.alertMessage == nil)

        viewModel.adGateCompleted()
        // 시트가 완전히 닫힌 뒤에야 완료 알럿을 띄운다.
        viewModel.handleAdGateDismiss()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.alertMessage?.title == "삭제 완료")
        #expect(viewModel.alertMessage?.message.contains("게임") == true)
    }

    @Test func adGateCancelDoesNotShowDeletionAlert() async {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임")
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo,
                screenTimeRepository: FakeScreenTimeRepository()
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]
        viewModel.lockedGroupIDs = [group.id]

        viewModel.requestDeleteGroup(group.id)
        viewModel.adGateCancelled()
        viewModel.handleAdGateDismiss()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.alertMessage == nil)
        #expect(viewModel.groups.contains(where: { $0.id == group.id }))
    }

    @Test func adGateCompletedRunsPendingActionOnce() {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임")
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo,
                screenTimeRepository: FakeScreenTimeRepository()
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]
        viewModel.lockedGroupIDs = [group.id]
        viewModel.requestPickerPresentation(for: group)

        viewModel.adGateCompleted()
        viewModel.adGateCompleted()

        #expect(!viewModel.isAdGatePresented)
        #expect(viewModel.isPickerPresented)
        #expect(viewModel.pickerGroupID == group.id)
    }

    @Test func adGateCancelledClearsPendingAction() {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임")
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: FakeGroupRepository(),
                screenTimeRepository: FakeScreenTimeRepository()
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]
        viewModel.lockedGroupIDs = [group.id]
        viewModel.requestPickerPresentation(for: group)

        viewModel.adGateCancelled()

        #expect(!viewModel.isAdGatePresented)
        #expect(!viewModel.isPickerPresented)
    }

    // MARK: - Draft / Apply (commit)

    @Test func makeNewGroupStartsAsDraft() throws {
        let useCase = ManageGroupsUseCase(
            groupRepository: FakeGroupRepository(),
            screenTimeRepository: FakeScreenTimeRepository()
        )

        let group = try useCase.makeNewGroup(currentCount: 0)

        #expect(group.isApplied == false)
        #expect(group.ruleKind == nil)
    }

    @Test func updateWeekdayRulesEnforcesValidityAndToggle() {
        let useCase = ManageGroupsUseCase(
            groupRepository: FakeGroupRepository(),
            screenTimeRepository: FakeScreenTimeRepository()
        )
        let id = UUID()
        var groups = [SharedStore.ScreenTimeGroup(id: id, name: "SNS", ruleKind: .dailyLimit, isApplied: true)]

        // 유효한 7개 → 저장(요일별 모드 전환).
        let valid = (0..<7).map { SharedStore.DayRule(kind: .dailyLimit, dailyLimitMinutes: 10 + $0) }
        useCase.updateWeekdayRules(id: id, rules: valid, in: &groups)
        #expect(groups[0].weekdayRules == valid)

        // 무효(6개) → 거부: 직전 유효 규칙이 그대로 유지되고 아무 변경도 없다.
        useCase.updateWeekdayRules(id: id, rules: Array(valid.prefix(6)), in: &groups)
        #expect(groups[0].weekdayRules == valid)

        // 무효(전부 제한 없음) → 거부.
        let allUnrestricted = (0..<7).map { _ in SharedStore.DayRule(kind: .unrestricted) }
        useCase.updateWeekdayRules(id: id, rules: allUnrestricted, in: &groups)
        #expect(groups[0].weekdayRules == valid)

        // nil → 요일별 모드 해제(기존 base 규칙이 다시 적용).
        useCase.updateWeekdayRules(id: id, rules: nil, in: &groups)
        #expect(groups[0].weekdayRules == nil)
        #expect(groups[0].ruleKind == .dailyLimit)
    }

    @Test func updateWeekdayRulesBackfillsBaseRuleForDraftGroup() {
        // draft(ruleKind nil) 그룹의 요일 커밋은 첫 제한 요일 규칙을 base 필드에도 기록한다 —
        // 디코딩 폴백(weekdayRules drop-to-nil)·1.1.x 다운그레이드 시 base 규칙이 보호를
        // 이어받는 계약 유지(무보호 draft 전락 방지).
        let useCase = ManageGroupsUseCase(
            groupRepository: FakeGroupRepository(),
            screenTimeRepository: FakeScreenTimeRepository()
        )
        let id = UUID()
        var rules = (0..<7).map { _ in SharedStore.DayRule(kind: .unrestricted) }
        rules[3] = SharedStore.DayRule(kind: .cooldown, cooldownUsageMinutes: 25, cooldownDurationMinutes: 90)

        var draftGroups = [SharedStore.ScreenTimeGroup(id: id, name: "SNS", ruleKind: nil, isApplied: false)]
        useCase.updateWeekdayRules(id: id, rules: rules, in: &draftGroups)
        #expect(draftGroups[0].weekdayRules == rules)
        #expect(draftGroups[0].ruleKind == .cooldown)              // 백필
        #expect(draftGroups[0].cooldownUsageMinutes == 25)
        #expect(draftGroups[0].cooldownDurationMinutes == 90)

        // base 규칙이 이미 있으면 백필하지 않는다(사용자의 기존 단일 규칙을 폴백으로 보존).
        var existingGroups = [SharedStore.ScreenTimeGroup(
            id: id, name: "SNS", dailyLimitMinutes: 45, ruleKind: .dailyLimit, isApplied: true
        )]
        useCase.updateWeekdayRules(id: id, rules: rules, in: &existingGroups)
        #expect(existingGroups[0].ruleKind == .dailyLimit)
        #expect(existingGroups[0].dailyLimitMinutes == 45)
    }

    @Test func requestApplyBlockedWhenRuleNotChosen() {
        // 규칙 미선택 draft는 적용할 수 없고 안내 alert만 뜬다.
        // (테스트 환경에선 실제 ApplicationToken을 만들 수 없어 selection도 비어 있다.
        //  invalidReason은 선택 누락을 먼저 잡으므로 어떤 경우든 적용은 막히고 안내가 뜬다.)
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(),
            name: "SNS",
            ruleKind: nil,
            isApplied: false
        )
        let viewModel = makeApplyViewModel(with: group)

        viewModel.requestApplyGroup(id: group.id)

        #expect(viewModel.pendingApplyConfirmation == nil)
        #expect(viewModel.alertMessage?.title == "적용할 수 없어요")
        #expect(viewModel.groups.first?.isApplied == false)
    }

    @Test func confirmApplyMarksGroupAppliedAndSyncs() {
        // requestApplyGroup의 유효성 검증은 실제 ApplicationToken 의존(selectionCount)이라 테스트에서
        // 만족시킬 수 없다. 확인 단계 이후의 commit 동작(isApplied 전환 + sync)을 직접 검증한다.
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(),
            name: "SNS",
            dailyLimitMinutes: 30,
            ruleKind: .dailyLimit,
            isApplied: false
        )
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo,
                screenTimeRepository: screenTimeRepo
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]

        let confirmation = ApplyGroupConfirmation(groupID: group.id, groupName: group.name)
        viewModel.pendingApplyConfirmation = confirmation
        viewModel.confirmApplyGroup(confirmation)

        #expect(viewModel.pendingApplyConfirmation == nil)
        #expect(viewModel.groups.first?.isApplied == true)
        #expect(groupRepo.screenTimeGroups.first?.isApplied == true)
        #expect(screenTimeRepo.syncCallCount == 1)
    }

    @Test func confirmApplyLogsRuleAnalyticsAfterSuccessfulRegistration() {
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(),
            name: "SNS",
            dailyLimitMinutes: 75,
            ruleKind: .dailyLimit,
            isApplied: false
        )
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        screenTimeRepo.validGroupsOverride = [group]
        let analyticsRepo = FakeAnalyticsRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo,
                screenTimeRepository: screenTimeRepo
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(screenTimeRepo: screenTimeRepo),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            analyticsRepository: analyticsRepo,
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]

        let confirmation = ApplyGroupConfirmation(groupID: group.id, groupName: group.name)
        viewModel.confirmApplyGroup(confirmation)

        let applied = analyticsRepo.parameters(for: "group_applied")
        #expect(applied?["rule_kind"] as? String == "dailyLimit")
        #expect(applied?["rule_config_bucket"] as? String == "daily_61_120m")

        let registered = analyticsRepo.parameters(for: "rule_monitoring_registered")
        #expect(registered?["rule_kind"] as? String == "dailyLimit")
        #expect(registered?["rule_config_bucket"] as? String == "daily_61_120m")
    }

    @Test func confirmApplyDoesNotLogMonitoringRegistrationWhenSyncFails() {
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(),
            name: "SNS",
            dailyLimitMinutes: 30,
            ruleKind: .dailyLimit,
            isApplied: false
        )
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        screenTimeRepo.syncError = TestScreenTimeError.failed
        let analyticsRepo = FakeAnalyticsRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo,
                screenTimeRepository: screenTimeRepo
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(screenTimeRepo: screenTimeRepo),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            analyticsRepository: analyticsRepo,
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]

        viewModel.confirmApplyGroup(ApplyGroupConfirmation(groupID: group.id, groupName: group.name))

        #expect(analyticsRepo.parameters(for: "group_applied") != nil)
        #expect(analyticsRepo.parameters(for: "rule_monitoring_registered") == nil)
    }

    private func makeApplyViewModel(with group: SharedStore.ScreenTimeGroup) -> ContentViewModel {
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo,
                screenTimeRepository: FakeScreenTimeRepository()
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]
        return viewModel
    }

    @Test func contentViewModelAddsGroupAndPersistsWithoutSync() {
        let groupRepo = FakeGroupRepository()
        let screenTimeRepo = FakeScreenTimeRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo,
                screenTimeRepository: screenTimeRepo
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )

        viewModel.addGroup()

        #expect(viewModel.groups.count == 1)
        #expect(groupRepo.screenTimeGroups.count == 1)
        #expect(screenTimeRepo.syncCallCount == 0)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func contentViewModelBlocksSixthGroup() {
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = (0..<SharedStore.maxGroupCount).map {
            SharedStore.ScreenTimeGroup(name: "그룹 \($0 + 1)")
        }
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo,
                screenTimeRepository: FakeScreenTimeRepository()
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = groupRepo.screenTimeGroups

        viewModel.addGroup()

        #expect(viewModel.groups.count == SharedStore.maxGroupCount)
        #expect(viewModel.alertMessage?.title == "그룹 제한")
    }

    @Test func contentViewModelUsesCategoryExpandingPickerSelection() {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "SNS")
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: FakeGroupRepository(),
                screenTimeRepository: FakeScreenTimeRepository()
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )

        #expect(viewModel.pickerSelection.includeEntireCategory)

        viewModel.presentPicker(for: group)

        #expect(viewModel.pickerSelection.includeEntireCategory)
        #expect(viewModel.pickerGroupID == group.id)
        #expect(viewModel.isPickerPresented)
    }

    @Test func contentViewModelCommitsDailyLimitRule() {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "SNS", dailyLimitMinutes: 30)
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo,
                screenTimeRepository: screenTimeRepo
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]

        viewModel.presentRuleEditor(for: group)
        viewModel.ruleEditorSelectedKind = .dailyLimit
        viewModel.limitPickerHours = 1
        viewModel.limitPickerMinutes = 15
        viewModel.performRuleCommit()

        #expect(viewModel.groups.first?.dailyLimitMinutes == 75)
        #expect(viewModel.groups.first?.ruleKind == .dailyLimit)
        #expect(groupRepo.screenTimeGroups.first?.dailyLimitMinutes == 75)
        #expect(screenTimeRepo.syncCallCount == 1)
    }

    @Test func appliedRuleEditLogsMonitoringRegistration() {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "SNS", dailyLimitMinutes: 30)
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        screenTimeRepo.validGroupsOverride = [group]
        let analyticsRepo = FakeAnalyticsRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo,
                screenTimeRepository: screenTimeRepo
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(screenTimeRepo: screenTimeRepo),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            analyticsRepository: analyticsRepo,
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]

        viewModel.presentRuleEditor(for: group)
        viewModel.ruleEditorSelectedKind = .dailyLimit
        viewModel.limitPickerHours = 1
        viewModel.limitPickerMinutes = 15
        viewModel.performRuleCommit()

        let registered = analyticsRepo.parameters(for: "rule_monitoring_registered")
        #expect(registered?["rule_kind"] as? String == "dailyLimit")
        #expect(registered?["rule_config_bucket"] as? String == "daily_61_120m")
    }

    // MARK: - rule_changed (모드 전환 관찰)

    @Test func switchingRuleModeLogsRuleChanged() {
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(), name: "SNS", dailyLimitMinutes: 30, ruleKind: .dailyLimit, isApplied: true
        )
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        let analyticsRepo = FakeAnalyticsRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo, screenTimeRepository: screenTimeRepo
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(screenTimeRepo: screenTimeRepo),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            analyticsRepository: analyticsRepo,
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]

        viewModel.presentRuleEditor(for: group)
        viewModel.ruleEditorSelectedKind = .cooldown
        viewModel.ruleEditorCooldownUsageMinutes = 15
        viewModel.ruleEditorCooldownDurationMinutes = 60
        viewModel.performRuleCommit()

        let changed = analyticsRepo.parameters(for: "rule_changed")
        #expect(changed?["from_rule"] as? String == "dailyLimit")
        #expect(changed?["to_rule"] as? String == "cooldown")
        #expect(changed?["was_locked"] as? Bool == false)
        #expect(changed?["caused_lock"] as? Bool == false)
    }

    @Test func sameRuleModeValueChangeDoesNotLogRuleChanged() {
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(), name: "SNS", dailyLimitMinutes: 30, ruleKind: .dailyLimit, isApplied: true
        )
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        let analyticsRepo = FakeAnalyticsRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo, screenTimeRepository: screenTimeRepo
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(screenTimeRepo: screenTimeRepo),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            analyticsRepository: analyticsRepo,
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]

        viewModel.presentRuleEditor(for: group)
        viewModel.ruleEditorSelectedKind = .dailyLimit
        viewModel.limitPickerHours = 1
        viewModel.limitPickerMinutes = 15
        viewModel.performRuleCommit()

        #expect(analyticsRepo.parameters(for: "rule_changed") == nil)
    }

    @Test func switchingRuleModeWhileLockedLogsWasLocked() {
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(), name: "SNS", dailyLimitMinutes: 30, ruleKind: .dailyLimit, isApplied: true
        )
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        let analyticsRepo = FakeAnalyticsRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo, screenTimeRepository: screenTimeRepo
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(screenTimeRepo: screenTimeRepo),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            analyticsRepository: analyticsRepo,
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]
        viewModel.lockedGroupIDs = [group.id]

        viewModel.presentRuleEditor(for: group)
        viewModel.ruleEditorSelectedKind = .cooldown
        viewModel.ruleEditorCooldownUsageMinutes = 15
        viewModel.ruleEditorCooldownDurationMinutes = 60
        viewModel.performRuleCommit()

        #expect(analyticsRepo.parameters(for: "rule_changed")?["was_locked"] as? Bool == true)
    }

    @Test func switchingToSmallerBudgetLogsCausedLock() {
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(), name: "SNS", dailyLimitMinutes: 30, ruleKind: .dailyLimit, isApplied: true
        )
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        let analyticsRepo = FakeAnalyticsRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo, screenTimeRepository: screenTimeRepo
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(screenTimeRepo: screenTimeRepo),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            analyticsRepository: analyticsRepo,
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]
        viewModel.usedTimeByGroupID = [group.id: 20]

        viewModel.presentRuleEditor(for: group)
        viewModel.ruleEditorSelectedKind = .cooldown
        viewModel.ruleEditorCooldownUsageMinutes = 5
        viewModel.ruleEditorCooldownDurationMinutes = 60
        viewModel.performRuleCommit()

        let changed = analyticsRepo.parameters(for: "rule_changed")
        #expect(changed?["caused_lock"] as? Bool == true)
        #expect(changed?["used_bucket"] as? String == "used_16_30m")
    }

    @Test func usedBucketBuckets() {
        #expect(RuleAnalyticsPayload.usedBucket(0) == "used_0m")
        #expect(RuleAnalyticsPayload.usedBucket(15) == "used_1_15m")
        #expect(RuleAnalyticsPayload.usedBucket(16) == "used_16_30m")
        #expect(RuleAnalyticsPayload.usedBucket(60) == "used_31_60m")
        #expect(RuleAnalyticsPayload.usedBucket(120) == "used_61_120m")
        #expect(RuleAnalyticsPayload.usedBucket(121) == "used_121m_plus")
    }

    @Test func draftRuleEditDoesNotLogMonitoringRegistration() {
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(),
            name: "SNS",
            dailyLimitMinutes: 30,
            ruleKind: .dailyLimit,
            isApplied: false
        )
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        screenTimeRepo.validGroupsOverride = [group]
        let analyticsRepo = FakeAnalyticsRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo,
                screenTimeRepository: screenTimeRepo
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(screenTimeRepo: screenTimeRepo),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            analyticsRepository: analyticsRepo,
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]

        viewModel.presentRuleEditor(for: group)
        viewModel.ruleEditorSelectedKind = .dailyLimit
        viewModel.limitPickerHours = 1
        viewModel.limitPickerMinutes = 15
        viewModel.performRuleCommit()

        #expect(analyticsRepo.parameters(for: "rule_monitoring_registered") == nil)
    }

    @Test func dailyLimitRuleWarnsAndDefersWhenNewLimitBelowUsedTime() {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "SNS", dailyLimitMinutes: 30)
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo,
                screenTimeRepository: screenTimeRepo
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]
        viewModel.usedTimeByGroupID = [group.id: 20]

        // 20분 사용 중인 그룹에 10분 한도 → 즉시 잠김. 적용하지 말고 경고를 대기시킨다.
        viewModel.presentRuleEditor(for: group)
        viewModel.ruleEditorSelectedKind = .dailyLimit
        viewModel.limitPickerHours = 0
        viewModel.limitPickerMinutes = 10
        viewModel.performRuleCommit()
        viewModel.handleRuleEditorDismiss()

        #expect(viewModel.pendingLimitLockWarning != nil)
        #expect(viewModel.pendingLimitLockWarning?.rule == .dailyLimit(minutes: 10))
        #expect(viewModel.pendingLimitLockWarning?.usedMinutes == 20)
        #expect(viewModel.groups.first?.dailyLimitMinutes == 30)   // 아직 미적용
        #expect(screenTimeRepo.syncCallCount == 0)

        // 변경 확정 → 적용. (.alert(item:)이 버튼 액션 전 바인딩을 nil로 만드는 상황 재현)
        let warning = viewModel.pendingLimitLockWarning!
        viewModel.pendingLimitLockWarning = nil
        viewModel.confirmLimitLockChange(warning)
        #expect(viewModel.pendingLimitLockWarning == nil)
        #expect(viewModel.groups.first?.dailyLimitMinutes == 10)
        #expect(groupRepo.screenTimeGroups.first?.dailyLimitMinutes == 10)
        #expect(screenTimeRepo.syncCallCount == 1)
    }

    @Test func dailyLimitRuleCancelKeepsOriginalLimit() {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "SNS", dailyLimitMinutes: 30)
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo,
                screenTimeRepository: screenTimeRepo
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]
        viewModel.usedTimeByGroupID = [group.id: 20]

        viewModel.presentRuleEditor(for: group)
        viewModel.ruleEditorSelectedKind = .dailyLimit
        viewModel.limitPickerHours = 0
        viewModel.limitPickerMinutes = 10
        viewModel.performRuleCommit()
        viewModel.handleRuleEditorDismiss()
        viewModel.cancelLimitLockChange()

        #expect(viewModel.pendingLimitLockWarning == nil)
        #expect(viewModel.groups.first?.dailyLimitMinutes == 30)   // 그대로
        #expect(screenTimeRepo.syncCallCount == 0)
    }

    @Test func dailyLimitRuleAppliesWithoutWarningWhenAboveUsedTime() {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "SNS", dailyLimitMinutes: 30)
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo,
                screenTimeRepository: screenTimeRepo
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]
        viewModel.usedTimeByGroupID = [group.id: 5]

        // 5분 사용 < 20분 한도 → 경고 없이 즉시 적용.
        viewModel.presentRuleEditor(for: group)
        viewModel.ruleEditorSelectedKind = .dailyLimit
        viewModel.limitPickerHours = 0
        viewModel.limitPickerMinutes = 20
        viewModel.performRuleCommit()

        #expect(viewModel.pendingLimitLockWarning == nil)
        #expect(viewModel.groups.first?.dailyLimitMinutes == 20)
        #expect(screenTimeRepo.syncCallCount == 1)
    }

    // MARK: - 규칙 편집기 (시간대 차단)

    @Test func presentRuleEditorLoadsExistingRuleAndWindows() {
        let windows = [TimeWindow(startMinuteOfDay: 9 * 60, endMinuteOfDay: 10 * 60)]
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(),
            name: "SNS",
            dailyLimitMinutes: 45,
            ruleKind: .timeWindows,
            timeWindows: windows
        )
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: FakeGroupRepository(),
                screenTimeRepository: FakeScreenTimeRepository()
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]

        viewModel.presentRuleEditor(for: group)

        #expect(viewModel.ruleEditorSelectedKind == .timeWindows)
        #expect(viewModel.ruleEditorTimeWindows == windows)
        #expect(viewModel.isRuleEditorPresented)
    }

    @Test func timeWindowsRuleWithOverlapAlertsAndDoesNotChangeGroup() {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "SNS", dailyLimitMinutes: 30)
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo,
                screenTimeRepository: screenTimeRepo
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]

        viewModel.presentRuleEditor(for: group)
        viewModel.ruleEditorSelectedKind = .timeWindows
        viewModel.ruleEditorTimeWindows = [
            TimeWindow(startMinuteOfDay: 9 * 60, endMinuteOfDay: 11 * 60),
            TimeWindow(startMinuteOfDay: 10 * 60, endMinuteOfDay: 12 * 60)   // 겹침
        ]
        viewModel.performRuleCommit()

        #expect(viewModel.alertMessage != nil)
        #expect(viewModel.groups.first?.ruleKind == .dailyLimit)   // 미변경
        #expect(viewModel.groups.first?.timeWindows.isEmpty == true)
        #expect(screenTimeRepo.syncCallCount == 0)
    }

    @Test func timeWindowsRuleWithValidWindowsUpdatesGroupAndSyncs() {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "SNS", dailyLimitMinutes: 30)
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo,
                screenTimeRepository: screenTimeRepo
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]

        let windows = [
            TimeWindow(startMinuteOfDay: 9 * 60, endMinuteOfDay: 10 * 60),
            TimeWindow(startMinuteOfDay: 14 * 60, endMinuteOfDay: 15 * 60)
        ]
        viewModel.presentRuleEditor(for: group)
        viewModel.ruleEditorSelectedKind = .timeWindows
        viewModel.ruleEditorTimeWindows = windows
        viewModel.performRuleCommit()

        #expect(viewModel.alertMessage == nil)
        #expect(viewModel.groups.first?.ruleKind == .timeWindows)
        #expect(viewModel.groups.first?.timeWindows == windows)
        #expect(groupRepo.screenTimeGroups.first?.timeWindows == windows)
        #expect(screenTimeRepo.syncCallCount == 1)
    }

    @Test func cooldownRuleWithValidValuesUpdatesGroupAndSyncs() {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "SNS", dailyLimitMinutes: 30)
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo,
                screenTimeRepository: screenTimeRepo
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]

        viewModel.presentRuleEditor(for: group)
        viewModel.ruleEditorSelectedKind = .cooldown
        viewModel.ruleEditorCooldownUsageMinutes = 15
        viewModel.ruleEditorCooldownDurationMinutes = 240
        viewModel.performRuleCommit()

        #expect(viewModel.alertMessage == nil)
        #expect(viewModel.groups.first?.ruleKind == .cooldown)
        #expect(viewModel.groups.first?.cooldownUsageMinutes == 15)
        #expect(viewModel.groups.first?.cooldownDurationMinutes == 240)
        #expect(groupRepo.screenTimeGroups.first?.cooldownUsageMinutes == 15)
        #expect(screenTimeRepo.syncCallCount == 1)
    }

    @Test func cooldownRuleWarnsAndDefersWhenNewBudgetBelowUsedTime() {
        // 사용자 시나리오: 쿨다운 20분/1시간휴식, 15분 사용 후 예산 5분으로 변경.
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(), name: "SNS", ruleKind: .cooldown, isApplied: true,
            cooldownUsageMinutes: 20, cooldownDurationMinutes: 60
        )
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo,
                screenTimeRepository: screenTimeRepo
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]
        viewModel.usedTimeByGroupID = [group.id: 15]

        viewModel.presentRuleEditor(for: group)
        viewModel.ruleEditorSelectedKind = .cooldown
        viewModel.ruleEditorCooldownUsageMinutes = 5
        viewModel.ruleEditorCooldownDurationMinutes = 60
        viewModel.performRuleCommit()
        viewModel.handleRuleEditorDismiss()

        // 즉시 적용하지 않고 휴식 진입 경고를 대기시킨다.
        #expect(viewModel.pendingLimitLockWarning != nil)
        #expect(viewModel.pendingLimitLockWarning?.rule == .cooldown(usageMinutes: 5, durationMinutes: 60))
        #expect(viewModel.pendingLimitLockWarning?.usedMinutes == 15)
        #expect(viewModel.groups.first?.cooldownUsageMinutes == 20)   // 아직 미적용
        #expect(screenTimeRepo.syncCallCount == 0)

        // 변경 확정 → 적용.
        let warning = viewModel.pendingLimitLockWarning!
        viewModel.pendingLimitLockWarning = nil
        viewModel.confirmLimitLockChange(warning)
        #expect(viewModel.pendingLimitLockWarning == nil)
        #expect(viewModel.groups.first?.cooldownUsageMinutes == 5)
        #expect(groupRepo.screenTimeGroups.first?.cooldownUsageMinutes == 5)
        #expect(screenTimeRepo.syncCallCount == 1)
    }

    @Test func cooldownRuleAppliesWithoutWarningWhenBudgetAboveUsedTime() {
        // 예산이 사용량보다 크면 경고 없이 즉시 적용(회귀 가드).
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(), name: "SNS", ruleKind: .cooldown, isApplied: true,
            cooldownUsageMinutes: 20, cooldownDurationMinutes: 60
        )
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo,
                screenTimeRepository: screenTimeRepo
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]
        viewModel.usedTimeByGroupID = [group.id: 5]

        viewModel.presentRuleEditor(for: group)
        viewModel.ruleEditorSelectedKind = .cooldown
        viewModel.ruleEditorCooldownUsageMinutes = 30
        viewModel.ruleEditorCooldownDurationMinutes = 60
        viewModel.performRuleCommit()

        #expect(viewModel.pendingLimitLockWarning == nil)
        #expect(viewModel.groups.first?.cooldownUsageMinutes == 30)
        #expect(screenTimeRepo.syncCallCount == 1)
    }

    @Test func cooldownRuleSkipsWarningWhenAlreadyResting() {
        // 이미 휴식 중(잠김)인 그룹은 휴식 간격만 바꿔도(예산 ≤ used여도) 경고 없이 바로 적용.
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(), name: "SNS", ruleKind: .cooldown, isApplied: true,
            cooldownUsageMinutes: 5, cooldownDurationMinutes: 60
        )
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo,
                screenTimeRepository: screenTimeRepo
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]
        viewModel.usedTimeByGroupID = [group.id: 7]
        viewModel.lockedGroupIDs = [group.id]   // 이미 휴식 중 → 잠김 집합에 포함
        viewModel.cooldownEndByGroupID = [group.id: Date().addingTimeInterval(600)]  // 휴식 진행 중

        viewModel.presentRuleEditor(for: group)
        viewModel.ruleEditorSelectedKind = .cooldown
        viewModel.ruleEditorCooldownUsageMinutes = 5     // 예산 그대로(5 ≤ used 7)
        viewModel.ruleEditorCooldownDurationMinutes = 90  // 휴식 간격만 변경
        viewModel.performRuleCommit()
        viewModel.handleRuleEditorDismiss()

        #expect(viewModel.pendingLimitLockWarning == nil)   // 즉시 잠금 경고 없음
        #expect(viewModel.groups.first?.cooldownDurationMinutes == 90)   // 바로 적용
        #expect(screenTimeRepo.syncCallCount == 1)
        // 휴식 중 변경 → "다음 주기부터 적용" 안내 알럿(예산·휴식 어느 쪽이든).
        #expect(viewModel.alertMessage?.message == "변경된 설정은 다음 주기부터 적용돼요.")
    }

    @Test func cooldownRestingBudgetOnlyChangeShowsInfoAlert() {
        // 휴식 중엔 예산만 바꿔도 다음 주기부터 적용 → 동일 안내 알럿.
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(), name: "SNS", ruleKind: .cooldown, isApplied: true,
            cooldownUsageMinutes: 5, cooldownDurationMinutes: 60
        )
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo,
                screenTimeRepository: screenTimeRepo
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]
        viewModel.usedTimeByGroupID = [group.id: 7]
        viewModel.lockedGroupIDs = [group.id]
        viewModel.cooldownEndByGroupID = [group.id: Date().addingTimeInterval(600)]

        viewModel.presentRuleEditor(for: group)
        viewModel.ruleEditorSelectedKind = .cooldown
        viewModel.ruleEditorCooldownUsageMinutes = 20    // 예산만 변경
        viewModel.ruleEditorCooldownDurationMinutes = 60  // 휴식 간격 동일
        viewModel.performRuleCommit()
        viewModel.handleRuleEditorDismiss()

        #expect(viewModel.pendingLimitLockWarning == nil)
        #expect(viewModel.alertMessage?.message == "변경된 설정은 다음 주기부터 적용돼요.")
    }

    @Test func cooldownRestingNoChangeShowsNoInfoAlert() {
        // 휴식 중에 아무것도 안 바꾸고 닫으면 안내 없음.
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(), name: "SNS", ruleKind: .cooldown, isApplied: true,
            cooldownUsageMinutes: 5, cooldownDurationMinutes: 60
        )
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo,
                screenTimeRepository: screenTimeRepo
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]
        viewModel.usedTimeByGroupID = [group.id: 7]
        viewModel.lockedGroupIDs = [group.id]
        viewModel.cooldownEndByGroupID = [group.id: Date().addingTimeInterval(600)]

        viewModel.presentRuleEditor(for: group)
        viewModel.ruleEditorSelectedKind = .cooldown
        viewModel.ruleEditorCooldownUsageMinutes = 5     // 동일
        viewModel.ruleEditorCooldownDurationMinutes = 60  // 동일
        viewModel.performRuleCommit()
        viewModel.handleRuleEditorDismiss()

        #expect(viewModel.alertMessage == nil)
    }

    @Test func dailyLimitRuleSkipsWarningWhenAlreadyLocked() {
        // 이미 잠긴 일일 한도 그룹은 한도를 더 낮춰도 경고 없이 바로 적용(잠금 유지).
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "SNS", dailyLimitMinutes: 30)
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo,
                screenTimeRepository: screenTimeRepo
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]
        viewModel.usedTimeByGroupID = [group.id: 30]
        viewModel.lockedGroupIDs = [group.id]   // 이미 잠김

        viewModel.presentRuleEditor(for: group)
        viewModel.ruleEditorSelectedKind = .dailyLimit
        viewModel.limitPickerHours = 0
        viewModel.limitPickerMinutes = 5
        viewModel.performRuleCommit()
        viewModel.handleRuleEditorDismiss()

        #expect(viewModel.pendingLimitLockWarning == nil)   // 경고 없음
        #expect(viewModel.groups.first?.dailyLimitMinutes == 5)   // 바로 적용
        #expect(screenTimeRepo.syncCallCount == 1)
    }

    @Test func cooldownRuleWithInvalidValuesAlertsAndDoesNotChangeGroup() {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "SNS", dailyLimitMinutes: 30)
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo,
                screenTimeRepository: screenTimeRepo
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]

        viewModel.presentRuleEditor(for: group)
        viewModel.ruleEditorSelectedKind = .cooldown
        viewModel.ruleEditorCooldownUsageMinutes = 0          // 범위 밖
        viewModel.ruleEditorCooldownDurationMinutes = 240
        viewModel.performRuleCommit()

        #expect(viewModel.alertMessage != nil)
        #expect(viewModel.groups.first?.ruleKind == .dailyLimit)   // 미변경
        #expect(screenTimeRepo.syncCallCount == 0)
    }

    @Test func nearMidnightEditNoticeShownOnlyWithinCutoff() {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "SNS", dailyLimitMinutes: 30)
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo,
                screenTimeRepository: screenTimeRepo
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )

        // 자정 직전이 아니면 안내 없음.
        screenTimeRepo.nearMidnightCutoff = false
        #expect(viewModel.nearMidnightEditNotice == nil)

        // 자정 직전(23:45+)이면 안내 노출.
        screenTimeRepo.nearMidnightCutoff = true
        #expect(viewModel.nearMidnightEditNotice == "23:45부터 설정한 규칙은 사용량 추적이 불가능해 00:00부터 다시 정확히 적용됩니다.")
    }

    @Test func dailyLimitRuleEditShowsApplyNoticeWhenNearMidnightTooShort() {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "SNS", dailyLimitMinutes: 30)
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        screenTimeRepo.nearMidnightCutoff = true   // 23:45+ too short
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo,
                screenTimeRepository: screenTimeRepo
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]
        viewModel.usedTimeByGroupID = [group.id: 5]

        // 5분 사용 < 20분 한도 → 즉시 잠금 경고 없이 적용. 자정 직전이라 적용 안내 alert.
        viewModel.presentRuleEditor(for: group)
        viewModel.ruleEditorSelectedKind = .dailyLimit
        viewModel.limitPickerHours = 0
        viewModel.limitPickerMinutes = 20
        viewModel.performRuleCommit()
        viewModel.handleRuleEditorDismiss()

        #expect(viewModel.alertMessage?.title == "적용 안내")
        #expect(viewModel.alertMessage?.message == "23:45부터는 사용량 추적이 불가능해 23:59까지 잠금이 해제되며, 00:00부터 규칙이 적용됩니다.")
    }

    @Test func dailyLimitRuleEditSkipsApplyNoticeWhenNotNearMidnight() {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "SNS", dailyLimitMinutes: 30)
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        screenTimeRepo.nearMidnightCutoff = false   // 자정 전 아님
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo,
                screenTimeRepository: screenTimeRepo
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]
        viewModel.usedTimeByGroupID = [group.id: 5]

        viewModel.presentRuleEditor(for: group)
        viewModel.ruleEditorSelectedKind = .dailyLimit
        viewModel.limitPickerHours = 0
        viewModel.limitPickerMinutes = 20
        viewModel.performRuleCommit()
        viewModel.handleRuleEditorDismiss()

        #expect(viewModel.alertMessage == nil)
    }

    @Test func timeWindowsRuleEditSkipsApplyNoticeEvenWhenNearMidnight() {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "SNS", dailyLimitMinutes: 30)
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        screenTimeRepo.nearMidnightCutoff = true   // too short여도 시간대 차단은 측정창과 무관
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo,
                screenTimeRepository: screenTimeRepo
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]

        viewModel.presentRuleEditor(for: group)
        viewModel.ruleEditorSelectedKind = .timeWindows
        viewModel.ruleEditorTimeWindows = [
            TimeWindow(startMinuteOfDay: 9 * 60, endMinuteOfDay: 10 * 60)
        ]
        viewModel.performRuleCommit()
        viewModel.handleRuleEditorDismiss()

        #expect(viewModel.alertMessage == nil)
    }

    @Test func unchangedDailyLimitCommitSkipsApplyNoticeNearMidnight() {
        // 무변경 완료는 churn 가드(syncDailyMonitoring의 last != group)가 재등록을 건너뛰어
        // 모니터가 빠질 일이 없다 → 자정 직전이어도 적용 안내를 띄우지 않는다.
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "SNS", dailyLimitMinutes: 30)
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        screenTimeRepo.nearMidnightCutoff = true   // 23:45+ too short
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo,
                screenTimeRepository: screenTimeRepo
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]

        // 편집기 진입 후 아무것도 바꾸지 않고 완료(30분 → 30분).
        viewModel.presentRuleEditor(for: group)
        viewModel.performRuleCommit()
        viewModel.handleRuleEditorDismiss()

        #expect(viewModel.alertMessage == nil)
    }

    @Test func weekdayCommitEditingOtherDayOnlySkipsApplyNoticeNearMidnight() {
        // 1.2.0 false positive 회귀: 오늘이 아닌 요일만 바꾼 커밋은 오늘 투영(resolved(on:))이
        // 그대로라 churn 가드가 재등록을 건너뛴다 — 자정 안내가 뜨면 거짓 정보다.
        let todayIndex = WeekdayRulePolicy.weekdayIndex(for: Date())
        let otherIndex = (todayIndex + 1) % 7
        let rules = (0..<7).map { _ in SharedStore.DayRule(kind: .dailyLimit, dailyLimitMinutes: 30) }
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(), name: "SNS", ruleKind: .dailyLimit, weekdayRules: rules
        )
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        screenTimeRepo.nearMidnightCutoff = true   // 23:45+ too short
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo,
                screenTimeRepository: screenTimeRepo
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]

        viewModel.presentRuleEditor(for: group)
        var edited = rules
        edited[otherIndex] = SharedStore.DayRule(kind: .dailyLimit, dailyLimitMinutes: 45)
        viewModel.ruleEditorWeekdayRules = edited
        viewModel.performRuleCommit()
        viewModel.handleRuleEditorDismiss()

        #expect(viewModel.alertMessage == nil)
        // 안내만 건너뛸 뿐 커밋 자체는 수행된다.
        #expect(viewModel.groups.first?.weekdayRules?[otherIndex].dailyLimitMinutes == 45)
    }

    @Test func weekdayCommitEditingTodayShowsApplyNoticeNearMidnight() {
        // 오늘 투영을 실제로 바꾸는 요일 커밋은 기존대로 자정 안내를 띄운다.
        let todayIndex = WeekdayRulePolicy.weekdayIndex(for: Date())
        let rules = (0..<7).map { _ in SharedStore.DayRule(kind: .dailyLimit, dailyLimitMinutes: 30) }
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(), name: "SNS", ruleKind: .dailyLimit, weekdayRules: rules
        )
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        screenTimeRepo.nearMidnightCutoff = true   // 23:45+ too short
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo,
                screenTimeRepository: screenTimeRepo
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]

        viewModel.presentRuleEditor(for: group)
        var edited = rules
        edited[todayIndex] = SharedStore.DayRule(kind: .dailyLimit, dailyLimitMinutes: 45)
        viewModel.ruleEditorWeekdayRules = edited
        viewModel.performRuleCommit()
        viewModel.handleRuleEditorDismiss()

        #expect(viewModel.alertMessage?.title == "적용 안내")
        #expect(viewModel.alertMessage?.message == "23:45부터는 사용량 추적이 불가능해 23:59까지 잠금이 해제되며, 00:00부터 규칙이 적용됩니다.")
    }

    @Test func applyGroupShowsApplyNoticeWhenNearMidnightTooShort() async {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "SNS", dailyLimitMinutes: 30)
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        screenTimeRepo.nearMidnightCutoff = true   // 23:45+ too short
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo,
                screenTimeRepository: screenTimeRepo
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]

        // 적용하기 확정 → 자정 직전이라 적용 안내 alert(확인 다이얼로그 닫힌 뒤 비동기 표시).
        viewModel.confirmApplyGroup(ApplyGroupConfirmation(groupID: group.id, groupName: group.name))
        try? await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.alertMessage?.title == "적용 안내")
        #expect(viewModel.alertMessage?.message == "23:45부터는 사용량 추적이 불가능해 23:59까지 잠금이 해제되며, 00:00부터 규칙이 적용됩니다.")
    }

    @Test func switchingToTimeWindowsPreservesDailyLimitMinutes() {
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(),
            name: "SNS",
            dailyLimitMinutes: 42,
            ruleKind: .dailyLimit
        )
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(
                groupRepository: groupRepo,
                screenTimeRepository: screenTimeRepo
            ),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]

        viewModel.presentRuleEditor(for: group)
        viewModel.ruleEditorSelectedKind = .timeWindows
        viewModel.ruleEditorTimeWindows = [
            TimeWindow(startMinuteOfDay: 9 * 60, endMinuteOfDay: 10 * 60)
        ]
        viewModel.performRuleCommit()

        #expect(viewModel.groups.first?.ruleKind == .timeWindows)
        #expect(viewModel.groups.first?.dailyLimitMinutes == 42)   // 보존
        #expect(groupRepo.screenTimeGroups.first?.dailyLimitMinutes == 42)
    }

    // MARK: - HomeViewModel

    @Test func appPickerWarningsAllowCategories() {
        let warnings = AppPickerSheetViewModel.warnings(
            for: AppPickerSheetViewModel.SelectionSummary(
                appCount: SharedStore.maxAppsPerGroup,
                webDomainCount: 0,
                hasCategory: true
            )
        )

        #expect(warnings.isEmpty)
    }

    @Test func appPickerWarningsAllowWebDomains() {
        let warnings = AppPickerSheetViewModel.warnings(
            for: AppPickerSheetViewModel.SelectionSummary(
                appCount: 1,
                webDomainCount: 1,
                hasCategory: false
            )
        )
        let notices = AppPickerSheetViewModel.notices(
            for: AppPickerSheetViewModel.SelectionSummary(
                appCount: 1,
                webDomainCount: 1,
                hasCategory: false
            )
        )

        #expect(warnings.isEmpty)
        #expect(notices == ["웹 사이트는 사파리에서 사용할 때만 적용됩니다."])
    }

    @Test func appPickerWarningsCountAppsAndWebDomains() {
        let warnings = AppPickerSheetViewModel.warnings(
            for: AppPickerSheetViewModel.SelectionSummary(
                appCount: SharedStore.maxAppsPerGroup,
                webDomainCount: 1,
                hasCategory: true
            )
        )

        #expect(warnings.count == 1)
        #expect(warnings[0].contains("한 그룹에 9개 항목까지만 가능해요"))
        #expect(warnings[0].contains("10/9"))
    }

    @Test func homeViewModelDescribesShieldAndOverrideStates() {
        let lockedGroup = SharedStore.ScreenTimeGroup(name: "게임")
        let viewModel = HomeViewModel(
            groups: [lockedGroup],
            todayStats: DailyStats(dateKey: "2026-05-18"),
            isMonitoring: true,
            isShieldActive: true,
            shieldOverrideUntil: nil,
            successMessage: nil,
            errorMessage: nil,
            lockedGroupIDs: [lockedGroup.id],
            overrideGroupIDs: [],
            validGroupIDs: [lockedGroup.id]
        )

        #expect(viewModel.statusIcon(for: lockedGroup) == "lock.shield.fill")
        #expect(viewModel.statusTint(for: lockedGroup) == .red)
        #expect(viewModel.statusTitle(for: lockedGroup) == "23:59까지 잠금")
    }

    @Test func homeViewModelBillUsesSingleTotal() {
        let viewModel = HomeViewModel(
            groups: [],
            todayStats: DailyStats(
                dateKey: "2026-05-18",
                adWatchCount: 2,
                adUnlockedSeconds: 17 * 60,
                oneMinuteUsedCount: 1
            ),
            isMonitoring: false,
            isShieldActive: false,
            shieldOverrideUntil: nil,
            successMessage: nil,
            errorMessage: nil,
            oneMinuteRemaining: 1,
            oneMinuteDailyLimit: 5
        )

        #expect(viewModel.billTotalText == "+18분")
        #expect(viewModel.billComment == "계산서 나왔어요. 확인해보실래요?")
        #expect(viewModel.oneMinuteRemaining == 1)
        #expect(viewModel.oneMinuteDailyLimit == 5)
    }

    @Test func homeViewModelLockProgressFillsTenSegmentsByUsage() {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "SNS", dailyLimitMinutes: 60)
        func progress(used: Int) -> HomeViewModel.SegmentProgress? {
            HomeViewModel(
                groups: [group],
                todayStats: DailyStats(dateKey: "2026-05-30"),
                isMonitoring: true,
                isShieldActive: false,
                shieldOverrideUntil: nil,
                successMessage: nil,
                errorMessage: nil,
                validGroupIDs: [group.id],
                usedTimeByGroupID: [group.id: used]
            ).lockProgress(for: group)
        }

        #expect(progress(used: 0)?.total == 10)
        #expect(progress(used: 0)?.remaining == 10)
        #expect(progress(used: 30)?.remaining == 5)   // 30/60 → 5칸
        #expect(progress(used: 54)?.remaining == 1)   // 6분 남음 → 최소 1칸
        #expect(progress(used: 60) == nil)            // 소진 → nil(잠금 임박)
    }

    @Test func homeViewModelLockProgressUsesCooldownBudget() {
        // 쿨다운 그룹도 휴식 전 사용 예산(cooldownUsageMinutes) 기준으로 초록 진행바를 보여준다.
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(),
            name: "게임",
            ruleKind: .cooldown,
            cooldownUsageMinutes: 20,
            cooldownDurationMinutes: 300
        )
        func progress(used: Int) -> HomeViewModel.SegmentProgress? {
            HomeViewModel(
                groups: [group],
                todayStats: DailyStats(dateKey: "2026-05-30"),
                isMonitoring: true,
                isShieldActive: false,
                shieldOverrideUntil: nil,
                successMessage: nil,
                errorMessage: nil,
                validGroupIDs: [group.id],
                usedTimeByGroupID: [group.id: used]
            ).lockProgress(for: group)
        }

        #expect(progress(used: 0)?.remaining == 10)   // 예산 20분, 0 사용 → 가득
        #expect(progress(used: 10)?.remaining == 5)    // 10/20 → 5칸
        #expect(progress(used: 20) == nil)             // 예산 소진 → nil(잠금 임박)
    }

    @Test func homeViewModelOverrideProgressFillsTenSegmentsByUsage() {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임", dailyLimitMinutes: 30)
        func progress(used: Int) -> HomeViewModel.SegmentProgress? {
            HomeViewModel(
                groups: [group],
                todayStats: DailyStats(dateKey: "2026-05-30"),
                isMonitoring: true,
                isShieldActive: false,
                shieldOverrideUntil: nil,
                successMessage: nil,
                errorMessage: nil,
                overrideGroupIDs: [group.id],
                usedTimeByGroupID: [group.id: used],
                overrideBaselineUsedTimeByGroupID: [group.id: 30],
                overrideGrantedMinutesByGroupID: [group.id: 10]
            ).overrideProgress(for: group)
        }

        #expect(progress(used: 30)?.total == 10)
        #expect(progress(used: 30)?.remaining == 10)  // baseline 직후
        #expect(progress(used: 35)?.remaining == 5)   // 5분 소비 → 5칸
        #expect(progress(used: 39)?.remaining == 1)   // 1분 남음 → 1칸
    }

    @Test func homeViewModelOneMinuteOverrideShowsSingleCell() {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임", dailyLimitMinutes: 30)
        let progress = HomeViewModel(
            groups: [group],
            todayStats: DailyStats(dateKey: "2026-05-30"),
            isMonitoring: true,
            isShieldActive: false,
            shieldOverrideUntil: nil,
            successMessage: nil,
            errorMessage: nil,
            overrideGroupIDs: [group.id],
            usedTimeByGroupID: [group.id: 30],
            overrideBaselineUsedTimeByGroupID: [group.id: 30],
            overrideGrantedMinutesByGroupID: [group.id: 1]
        ).overrideProgress(for: group)

        // 1분 연장(granted=1)은 1칸 바.
        #expect(progress?.total == 1)
        #expect(progress?.remaining == 1)
    }

    @Test func homeViewModelNearMidnightOverrideShowsClockBadgeAndHidesProgress() {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임", dailyLimitMinutes: 30)
        let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: Date())!
        let viewModel = HomeViewModel(
            groups: [group],
            todayStats: DailyStats(dateKey: "2026-05-30"),
            isMonitoring: true,
            isShieldActive: false,
            shieldOverrideUntil: nil,
            successMessage: nil,
            errorMessage: nil,
            overrideGroupIDs: [group.id],
            overrideUntilByGroupID: [group.id: endOfDay],
            usedTimeByGroupID: [group.id: 30]
            // 자정 fallback override는 granted/baseline을 기록하지 않는다.
        )

        // 시간 기반 override → "23:59까지 추가 사용" 배지, 진행바는 숨김.
        // (배지 색은 기존 override와 동일한 .blue로 변경 없음.)
        #expect(viewModel.isNearMidnightOverride(group))
        #expect(viewModel.statusTitle(for: group) == "23:59까지 추가 사용")
        #expect(viewModel.overrideProgress(for: group) == nil)
    }

    @Test func homeViewModelUntrackedGroupHidesBarAndShowsAvailableBadge() {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임", dailyLimitMinutes: 30)
        let viewModel = HomeViewModel(
            groups: [group],
            todayStats: DailyStats(dateKey: "2026-05-30"),
            isMonitoring: true,
            isShieldActive: false,
            shieldOverrideUntil: nil,
            successMessage: nil,
            errorMessage: nil,
            validGroupIDs: [group.id],
            untrackedGroupIDs: [group.id],   // 자정 직전 편집으로 추적 멈춤
            usedTimeByGroupID: [group.id: 10]
        )

        // 추적이 멈췄으니 "남은 한도" 바 숨김 + "23:59까지 사용 가능" 배지.
        #expect(viewModel.isUntrackedNearMidnight(group))
        #expect(viewModel.lockProgress(for: group) == nil)
        #expect(viewModel.statusTitle(for: group) == "23:59까지 사용 가능")
    }

    @Test func homeViewModelTrackedGroupKeepsBarAndAvailableBadge() {
        // 회귀 가드: untrackedGroupIDs에 없으면 바 유지 + "사용 가능".
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임", dailyLimitMinutes: 30)
        let viewModel = HomeViewModel(
            groups: [group],
            todayStats: DailyStats(dateKey: "2026-05-30"),
            isMonitoring: true,
            isShieldActive: false,
            shieldOverrideUntil: nil,
            successMessage: nil,
            errorMessage: nil,
            validGroupIDs: [group.id],
            usedTimeByGroupID: [group.id: 10]
        )

        #expect(!viewModel.isUntrackedNearMidnight(group))
        #expect(viewModel.lockProgress(for: group) != nil)   // 바 유지
        // tracked 그룹엔 untracked 배지가 붙지 않는다(토큰 없는 테스트 그룹은 "설정 필요" 반환).
        #expect(viewModel.statusTitle(for: group) != "23:59까지 사용 가능")
    }

    @Test func homeViewModelUntrackedButLockedKeepsLockBadge() {
        // 추적 멈춤이어도 잠긴 그룹은 잠금 배지가 우선, 사용가능 배지 미적용.
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임", dailyLimitMinutes: 30)
        let viewModel = HomeViewModel(
            groups: [group],
            todayStats: DailyStats(dateKey: "2026-05-30"),
            isMonitoring: true,
            isShieldActive: false,
            shieldOverrideUntil: nil,
            successMessage: nil,
            errorMessage: nil,
            lockedGroupIDs: [group.id],
            validGroupIDs: [group.id],
            untrackedGroupIDs: [group.id],
            usedTimeByGroupID: [group.id: 30]
        )

        #expect(!viewModel.isUntrackedNearMidnight(group))
        #expect(viewModel.statusTitle(for: group) == "23:59까지 잠금")
    }

    @Test func dashboardUntrackedEmptyWhenMonitoringDisabled() {
        // 회귀 가드: 모니터링이 꺼져 있으면(등록 그룹 0) 유효 그룹을 untracked로 잡지 않는다.
        // 잡으면 "대기 중"이어야 할 카드에 "23:59까지 사용 가능" 배지가 잘못 뜬다.
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임", dailyLimitMinutes: 30)
        let screenTimeRepo = FakeScreenTimeRepository()
        screenTimeRepo.validGroupsOverride = [group]
        screenTimeRepo.monitoredIDs = []   // 등록된 모니터 없음
        let useCase = LoadDashboardUseCase(
            shieldRepository: FakeShieldRepository(),
            statsRepository: FakeStatsRepository(),
            screenTimeRepository: screenTimeRepo
        )

        screenTimeRepo.isDailyMonitoringEnabled = false
        #expect(useCase.load(groups: [group]).untrackedGroupIDs.isEmpty)

        // 모니터링이 켜진 뒤 등록에서 빠진 그룹은 정상적으로 untracked로 잡힌다.
        screenTimeRepo.isDailyMonitoringEnabled = true
        #expect(useCase.load(groups: [group]).untrackedGroupIDs == [group.id])
    }

    @Test func homeViewModelBillCommentTier1Under15Min() {
        let viewModel = HomeViewModel(
            groups: [],
            todayStats: DailyStats(
                dateKey: "2026-05-18",
                adUnlockedSeconds: 60
            ),
            isMonitoring: false,
            isShieldActive: false,
            shieldOverrideUntil: nil,
            successMessage: nil,
            errorMessage: nil
        )
        #expect(viewModel.billComment == "이 정도면 살짝 눈 감아드릴 수 있어요.")
    }

    @Test func homeViewModelBillCommentTier2Under30Min() {
        let viewModel = HomeViewModel(
            groups: [],
            todayStats: DailyStats(
                dateKey: "2026-05-18",
                adUnlockedSeconds: 900
            ),
            isMonitoring: false,
            isShieldActive: false,
            shieldOverrideUntil: nil,
            successMessage: nil,
            errorMessage: nil
        )
        #expect(viewModel.billComment == "계산서 나왔어요. 확인해보실래요?")
    }

    @Test func homeViewModelBillCommentTier3Under60Min() {
        let viewModel = HomeViewModel(
            groups: [],
            todayStats: DailyStats(
                dateKey: "2026-05-18",
                adUnlockedSeconds: 1800
            ),
            isMonitoring: false,
            isShieldActive: false,
            shieldOverrideUntil: nil,
            successMessage: nil,
            errorMessage: nil
        )
        #expect(viewModel.billComment == "제법 하시는데요. 청구서 두께가 느껴지시죠?")
    }

    @Test func homeViewModelBillCommentTier4Under90Min() {
        let viewModel = HomeViewModel(
            groups: [],
            todayStats: DailyStats(
                dateKey: "2026-05-18",
                adUnlockedSeconds: 3600
            ),
            isMonitoring: false,
            isShieldActive: false,
            shieldOverrideUntil: nil,
            successMessage: nil,
            errorMessage: nil
        )
        #expect(viewModel.billComment == "슬슬 기분이 좋아지는데요. 제가요.")
    }

    @Test func homeViewModelBillCommentTier5Over90Min() {
        let viewModel = HomeViewModel(
            groups: [],
            todayStats: DailyStats(
                dateKey: "2026-05-18",
                adUnlockedSeconds: 5400
            ),
            isMonitoring: false,
            isShieldActive: false,
            shieldOverrideUntil: nil,
            successMessage: nil,
            errorMessage: nil
        )
        #expect(viewModel.billComment == "좋은 날입니다. 이번엔 저한테요.")
    }

    @Test func homeViewModelBillZeroStateIgnoresWalkAwayCount() {
        let viewModel = HomeViewModel(
            groups: [],
            todayStats: DailyStats(
                dateKey: "2026-05-18",
                walkAwayCount: 3
            ),
            isMonitoring: false,
            isShieldActive: false,
            shieldOverrideUntil: nil,
            successMessage: nil,
            errorMessage: nil
        )

        #expect(viewModel.billTotalText == "0분")
        #expect(viewModel.billComment == "좋은 날입니다. 저한텐 아니고요.")
        #expect(viewModel.hasBillCost == false)
    }

    // MARK: - StatsViewModel

    private func makeWeeklyStats(
        adUnlockedSecondsPerDay: [Int] = Array(repeating: 0, count: 7)
    ) -> [DailyStats] {
        let baseDate = Calendar.current.date(
            byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date())
        )!
        return (0..<7).map { offset in
            let date = Calendar.current.date(byAdding: .day, value: offset, to: baseDate)!
            let key = DailyStats.dateKey(for: date)
            return DailyStats(
                dateKey: key,
                adUnlockedSeconds: adUnlockedSecondsPerDay[offset]
            )
        }
    }

    @Test func statsViewModelTodayDeltaCaptionLess() {
        let weekly = makeWeeklyStats(adUnlockedSecondsPerDay: [0, 0, 0, 0, 0, 600, 0])
        let todayStats = DailyStats(dateKey: weekly[6].dateKey, adUnlockedSeconds: 300)
        let viewModel = StatsViewModel(
            groups: [],
            statsReport: StatsReport(
                todayStats: todayStats,
                weeklyStats: weekly,
                previousWeekStats: Array(repeating: DailyStats(dateKey: ""), count: 7),
                monthlyStats: Array(repeating: DailyStats(dateKey: ""), count: 30),
                trackingStartDate: nil
            ),
            isMonitoring: true,
            adFreeStreakDays: 0,
            maxAdFreeStreakDays: 7
        )

        #expect(viewModel.statsReport.yesterdayUnlockedSeconds == 600)
        #expect(viewModel.todayDeltaCaption == "어제보다 5분 적어요")
    }

    @Test func statsViewModelTodayDeltaCaptionMore() {
        let weekly = makeWeeklyStats(adUnlockedSecondsPerDay: [0, 0, 0, 0, 0, 300, 0])
        let todayStats = DailyStats(dateKey: weekly[6].dateKey, adUnlockedSeconds: 600)
        let viewModel = StatsViewModel(
            groups: [],
            statsReport: StatsReport(
                todayStats: todayStats,
                weeklyStats: weekly,
                previousWeekStats: Array(repeating: DailyStats(dateKey: ""), count: 7),
                monthlyStats: Array(repeating: DailyStats(dateKey: ""), count: 30),
                trackingStartDate: nil
            ),
            isMonitoring: true,
            adFreeStreakDays: 0,
            maxAdFreeStreakDays: 7
        )

        #expect(viewModel.todayDeltaCaption == "어제보다 5분 많아요")
    }

    @Test func statsViewModelTodayDeltaCaptionNoneYesterday() {
        let weekly = makeWeeklyStats(adUnlockedSecondsPerDay: [0, 0, 0, 0, 0, 0, 0])
        let todayStats = DailyStats(dateKey: weekly[6].dateKey, adUnlockedSeconds: 0)
        let viewModel = StatsViewModel(
            groups: [],
            statsReport: StatsReport(
                todayStats: todayStats,
                weeklyStats: weekly,
                previousWeekStats: Array(repeating: DailyStats(dateKey: ""), count: 7),
                monthlyStats: Array(repeating: DailyStats(dateKey: ""), count: 30),
                trackingStartDate: nil
            ),
            isMonitoring: false,
            adFreeStreakDays: 0,
            maxAdFreeStreakDays: 7
        )

        #expect(viewModel.todayDeltaCaption == "어제도 오늘도 없어요")
    }

    @Test func statsViewModelTodayDeltaCorrectAcrossWeekBoundary() {
        let cal = Calendar.current
        let sundayKey = DailyStats.dateKey(
            for: cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: Date()))!
        )
        let mondayKey = DailyStats.dateKey(for: cal.startOfDay(for: Date()))

        var prevWeek = Array(repeating: DailyStats(dateKey: ""), count: 7)
        prevWeek[6] = DailyStats(dateKey: sundayKey, adUnlockedSeconds: 2700) // 45분

        var thisWeek = Array(repeating: DailyStats(dateKey: ""), count: 7)
        thisWeek[0] = DailyStats(dateKey: mondayKey, adUnlockedSeconds: 60) // 1분

        let report = StatsReport(
            todayStats: DailyStats(dateKey: mondayKey, adUnlockedSeconds: 60),
            weeklyStats: thisWeek,
            previousWeekStats: prevWeek,
            monthlyStats: [],
            trackingStartDate: nil
        )

        #expect(report.yesterdayUnlockedSeconds == 2700)
    }

    @Test func statsViewModelWeeklyDeltaCaptionLess() {
        let thisWeek = makeWeeklyStats(adUnlockedSecondsPerDay: [0, 0, 0, 600, 600, 0, 0])
        let prevWeek = makeWeeklyStats(adUnlockedSecondsPerDay: [600, 600, 600, 600, 600, 600, 0])
        let viewModel = StatsViewModel(
            groups: [],
            statsReport: StatsReport(
                todayStats: DailyStats(dateKey: thisWeek[6].dateKey),
                weeklyStats: thisWeek,
                previousWeekStats: prevWeek,
                monthlyStats: Array(repeating: DailyStats(dateKey: ""), count: 30),
                trackingStartDate: nil
            ),
            isMonitoring: true,
            adFreeStreakDays: 0,
            maxAdFreeStreakDays: 7
        )

        // 캡션은 하루 평균 기준: thisWeek avg = 1200/7 = 171s, prevWeek avg = 3600/7 = 514s
        // → delta = -343s → 올림 6분
        #expect(viewModel.statsReport.weeklyAverageSeconds == 171)
        #expect(viewModel.statsReport.previousWeekAverageSeconds == 514)
        #expect(viewModel.weeklyDeltaCaption == "지난 주보다 평균 6분 적어요")
    }

    /// 회귀: 주간 카드 추세는 합계가 아니라 평균으로 판단해야 한다.
    /// 이번 주 합계는 더 크지만(기록일 더 많음) 평균은 더 작은 경우, 카드는 평균을
    /// 보여주므로 화살표·색은 감소(.down/.positive)여야 한다. 합계 기반이면 .up으로 뒤집힌다.
    @Test func statsViewModelWeeklyTrendUsesAverageNotSum() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // 이번 주: 7일 모두 14분(840s) → 합계 5880s, 평균 840s.
        let thisWeek = (0..<7).map { offset -> DailyStats in
            let date = cal.date(byAdding: .day, value: -offset, to: today)!
            return DailyStats(dateKey: DailyStats.dateKey(for: date), adUnlockedSeconds: 840)
        }
        // 지난주: 4일만 20분(1200s) → 합계 4800s, 평균 1200s. 합계는 이번 주가 크지만 평균은 작다.
        let prevWeek = (7..<11).map { offset -> DailyStats in
            let date = cal.date(byAdding: .day, value: -offset, to: today)!
            return DailyStats(dateKey: DailyStats.dateKey(for: date), adUnlockedSeconds: 1200)
        }
        let viewModel = StatsViewModel(
            groups: [],
            statsReport: StatsReport(
                todayStats: thisWeek[0],
                weeklyStats: thisWeek,
                previousWeekStats: prevWeek,
                monthlyStats: Array(repeating: DailyStats(dateKey: ""), count: 30),
                trackingStartDate: nil
            ),
            isMonitoring: true,
            adFreeStreakDays: 0,
            maxAdFreeStreakDays: 7
        )

        #expect(viewModel.statsReport.weeklyAverageSeconds == 840)
        #expect(viewModel.statsReport.previousWeekAverageSeconds == 1200)
        #expect(viewModel.weeklyTrend == .down)
        #expect(viewModel.weeklySentiment == .positive)
        #expect(viewModel.weeklyDeltaCaption == "지난 주보다 평균 6분 적어요")
    }

    /// 회귀: 분 단위 통일. 두 평균이 초 단위론 다르지만 올림 분(둘 다 15분)이 같으면
    /// 표시값이 같으므로 카드 화살표·색이 뜨지 않아야 한다(.flat/.neutral).
    @Test func statsViewModelWeeklyTrendIgnoresSubMinuteDifference() {
        let thisWeek = makeWeeklyStats(adUnlockedSecondsPerDay: Array(repeating: 870, count: 7)) // 평균 870s → 올림 15분
        let prevWeek = makeWeeklyStats(adUnlockedSecondsPerDay: Array(repeating: 850, count: 7)) // 평균 850s → 올림 15분
        let viewModel = StatsViewModel(
            groups: [],
            statsReport: StatsReport(
                todayStats: DailyStats(dateKey: thisWeek[6].dateKey),
                weeklyStats: thisWeek,
                previousWeekStats: prevWeek,
                monthlyStats: Array(repeating: DailyStats(dateKey: ""), count: 30),
                trackingStartDate: nil
            ),
            isMonitoring: true,
            adFreeStreakDays: 0,
            maxAdFreeStreakDays: 7
        )

        #expect(viewModel.statsReport.weeklyAverageSeconds == 870)
        #expect(viewModel.statsReport.previousWeekAverageSeconds == 850)
        #expect(viewModel.weeklyTrend == .flat)
        #expect(viewModel.weeklySentiment == .neutral)
    }

    @Test func statsViewModelWeeklyDeltaCaptionNoPrevData() {
        let viewModel = StatsViewModel(
            groups: [],
            statsReport: StatsReport(
                todayStats: DailyStats(dateKey: "2026-05-20"),
                weeklyStats: makeWeeklyStats(),
                previousWeekStats: Array(repeating: DailyStats(dateKey: ""), count: 7),
                monthlyStats: Array(repeating: DailyStats(dateKey: ""), count: 30),
                trackingStartDate: nil
            ),
            isMonitoring: true,
            adFreeStreakDays: 0,
            maxAdFreeStreakDays: 7
        )

        #expect(viewModel.weeklyDeltaCaption == "지난 주 기록 없음")
    }

    // MARK: - 기록 카드 비교 (월간 vs 올해)

    private func makeComparisonVM(repo: FakeStatsRepository) -> StatsViewModel {
        StatsViewModel(
            groups: [],
            statsReport: StatsReport(
                todayStats: DailyStats(dateKey: ""),
                weeklyStats: [],
                previousWeekStats: [],
                monthlyStats: [],
                trackingStartDate: nil
            ),
            isMonitoring: false,
            adFreeStreakDays: 0,
            maxAdFreeStreakDays: 7,
            statsRepository: repo
        )
    }

    /// 두 평균이 같은 분으로 올림 표시되면(초 단위로만 다르면) "1분 적어요"가 아니라 "같음(flat)"이어야 한다.
    @Test func statsComparisonIsFlatWhenMonthlyAndYearlyRoundToSameMinute() {
        let repo = FakeStatsRepository()
        // 2025년 데이터 평균 = (2080 + 2100) / 2 = 2090초 → 올림 35분
        repo.weeklyStatsValue = [DailyStats(dateKey: "2025-01-10", adUnlockedSeconds: 2080)]
        repo.previousWeekStatsValue = [DailyStats(dateKey: "2025-01-11", adUnlockedSeconds: 2100)]
        repo.trackingStartDateValue = Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 10))!
        let vm = makeComparisonVM(repo: repo)
        let today = Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 11))!

        // 현재 월간 평균 2050초 → 올림 35분 (올해 평균 2090초도 올림 35분)
        let comparison = vm.comparison(
            period: .monthly, currentAverageSeconds: 2050, displayYear: 2025, today: today
        )

        #expect(vm.displayMinutes(2050) == 35)
        #expect(comparison.comparisonAverageSeconds == 2090)
        #expect(vm.displayMinutes(comparison.comparisonAverageSeconds) == 35)
        #expect(comparison.deltaMinutes == 0)
        #expect(comparison.trend == .flat)
        #expect(comparison.shouldShow) // 비교 데이터가 있으면 같음도 표시(orange + →)
        #expect(comparison.caption == "올해 평균과 같아요")
    }

    /// 표시 분이 실제로 다르면 분 단위 차이로 문구가 떠야 한다.
    @Test func statsComparisonShowsMinuteDeltaForMonthly() {
        let repo = FakeStatsRepository()
        // 2025년 데이터 평균 = 1980초 → 올림 33분
        repo.weeklyStatsValue = [DailyStats(dateKey: "2025-03-01", adUnlockedSeconds: 1980)]
        repo.previousWeekStatsValue = []
        repo.trackingStartDateValue = Calendar.current.date(from: DateComponents(year: 2025, month: 3, day: 1))!
        let vm = makeComparisonVM(repo: repo)
        let today = Calendar.current.date(from: DateComponents(year: 2025, month: 3, day: 1))!

        // 현재 월간 평균 2100초 → 올림 35분, 올해 평균 33분 → delta +2분
        let comparison = vm.comparison(
            period: .monthly, currentAverageSeconds: 2100, displayYear: 2025, today: today
        )

        #expect(comparison.comparisonAverageSeconds == 1980)
        #expect(comparison.deltaMinutes == 2)
        #expect(comparison.trend == .up)
        #expect(comparison.shouldShow)
        #expect(comparison.comparisonLabel == "올해 평균")
        #expect(comparison.caption == "올해 평균보다 2분 많아요")
    }

    @Test func yearlyAverageIncludesZeroDaysAfterTrackingStart() {
        let repo = FakeStatsRepository()
        repo.weeklyStatsValue = [
            DailyStats(dateKey: "2025-01-01", adUnlockedSeconds: 180)
        ]
        repo.previousWeekStatsValue = []
        repo.trackingStartDateValue = Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        let vm = makeComparisonVM(repo: repo)
        let today = Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 3))!

        let comparison = vm.comparison(
            period: .monthly, currentAverageSeconds: 60, displayYear: 2025, today: today
        )

        // 1/1 기록 180초 + 1/2 0초 + 1/3 0초 = 60초 평균.
        #expect(comparison.comparisonAverageSeconds == 60)
        #expect(comparison.deltaMinutes == 0)
        #expect(comparison.trend == .flat)
    }

    @Test func yearlyAverageExcludesDaysBeforeTrackingStartAndFutureDays() {
        let repo = FakeStatsRepository()
        repo.weeklyStatsValue = [
            DailyStats(dateKey: "2025-01-01", adUnlockedSeconds: 600),
            DailyStats(dateKey: "2025-01-03", adUnlockedSeconds: 90),
            DailyStats(dateKey: "2025-01-06", adUnlockedSeconds: 900)
        ]
        repo.previousWeekStatsValue = []
        repo.trackingStartDateValue = Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 3))!
        let vm = makeComparisonVM(repo: repo)
        let today = Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 5))!

        let comparison = vm.comparison(
            period: .monthly, currentAverageSeconds: 30, displayYear: 2025, today: today
        )

        // 1/1은 추적 전, 1/6은 미래라 제외. 1/3 90초 + 1/4 0초 + 1/5 0초 = 30초 평균.
        #expect(comparison.comparisonAverageSeconds == 30)
        #expect(comparison.deltaMinutes == 0)
        #expect(comparison.trend == .flat)
    }

    // MARK: - averageUnlockedSeconds

    private func makeAverageVM(oldest: Date? = nil) -> StatsViewModel {
        let repo = FakeStatsRepository()
        repo.oldestStatDateValue = oldest
        return StatsViewModel(
            groups: [],
            statsReport: StatsReport(
                todayStats: DailyStats(dateKey: ""),
                weeklyStats: [],
                previousWeekStats: [],
                monthlyStats: [],
                trackingStartDate: oldest
            ),
            isMonitoring: false,
            adFreeStreakDays: 0,
            maxAdFreeStreakDays: 7,
            statsRepository: repo
        )
    }

    @Test func averageUnlockedSecondsExcludesFutureDays() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // 7일치 stats: 과거 5일(각 60s) + 미래 2일(0s)
        let stats: [DailyStats] = (0..<7).map { offset in
            let date = cal.date(byAdding: .day, value: offset - 4, to: today)!
            let key = DailyStats.dateKey(for: date)
            let isFuture = date > today
            return DailyStats(dateKey: key, adUnlockedSeconds: isFuture ? 0 : 60)
        }
        // 기대: 60s (= 300 / 5), 버그 시: 42s (= 300 / 7)
        #expect(makeAverageVM().averageSeconds(for: stats, today: today) == 60)
    }

    @Test func averageUnlockedSecondsExcludesPreInstallDays() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let oldest = cal.date(byAdding: .day, value: -3, to: today)!
        // 7일치 stats: 설치 이후 4일(각 60s) + 설치 이전 3일(0s)
        let stats: [DailyStats] = (0..<7).map { offset in
            let date = cal.date(byAdding: .day, value: offset - 6, to: today)!
            let key = DailyStats.dateKey(for: date)
            let isBeforeInstall = date < oldest
            return DailyStats(dateKey: key, adUnlockedSeconds: isBeforeInstall ? 0 : 60)
        }
        // 기대: 60s (= 240 / 4), 버그 시: 34s (= 240 / 7)
        #expect(makeAverageVM(oldest: oldest).averageSeconds(for: stats, today: today) == 60)
    }

    @Test func averageUnlockedSecondsWithFixedWeekExcludesFutureDays() {
        // 월요일 시작 주를 고정 날짜로 만들어 검증
        // 월(60s), 화(60s), 수(60s) → today = 수요일, 목~일(0s) = 미래
        let cal = Calendar.current
        let fixedMonday = cal.date(from: DateComponents(year: 2026, month: 5, day: 18))! // 2026-05-18 월요일
        let fixedWednesday = cal.date(byAdding: .day, value: 2, to: fixedMonday)! // 수요일 = today
        let stats: [DailyStats] = (0..<7).map { offset in
            let date = cal.date(byAdding: .day, value: offset, to: fixedMonday)!
            let key = DailyStats.dateKey(for: date)
            let isFuture = date > fixedWednesday
            return DailyStats(dateKey: key, adUnlockedSeconds: isFuture ? 0 : 60)
        }
        // 기대: 60s (= 180 / 3), 버그 시: 25s (= 180 / 7)
        #expect(makeAverageVM().averageSeconds(for: stats, today: fixedWednesday) == 60)
    }

    @Test func averageUnlockedSecondsReturnsZeroWhenNoRelevantData() {
        let today = Calendar.current.startOfDay(for: Date())
        let emptyStats: [DailyStats] = []
        #expect(makeAverageVM().averageSeconds(for: emptyStats, today: today) == 0)
    }

    // MARK: - hasRecord (그래프의 기록 없음 / 0분 구분)

    private func makeTrackingVM(trackingStart: Date?) -> StatsViewModel {
        let repo = FakeStatsRepository()
        repo.trackingStartDateValue = trackingStart
        return makeComparisonVM(repo: repo)
    }

    private func zeroStat(daysFromToday offset: Int, today: Date) -> DailyStats {
        let date = Calendar.current.date(byAdding: .day, value: offset, to: today)!
        return DailyStats(dateKey: DailyStats.dateKey(for: date))
    }

    @Test func hasRecordIsTrueForPositiveUsageEvenWithoutTracking() {
        let today = Calendar.current.startOfDay(for: Date())
        let stat = DailyStats(dateKey: DailyStats.dateKey(for: today), adUnlockedSeconds: 60)
        #expect(makeTrackingVM(trackingStart: nil).hasRecord(stat, today: today))
    }

    @Test func hasRecordIsFalseForZeroUsageWithoutTracking() {
        let today = Calendar.current.startOfDay(for: Date())
        let vm = makeTrackingVM(trackingStart: nil)
        #expect(!vm.hasRecord(zeroStat(daysFromToday: 0, today: today), today: today))
    }

    @Test func hasRecordTreatsZeroUsageAsRecordAfterTrackingStart() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let trackingStart = cal.date(byAdding: .day, value: -3, to: today)!
        let vm = makeTrackingVM(trackingStart: trackingStart)
        #expect(vm.hasRecord(zeroStat(daysFromToday: -3, today: today), today: today))
        #expect(vm.hasRecord(zeroStat(daysFromToday: 0, today: today), today: today))
    }

    @Test func hasRecordIsFalseBeforeTrackingStart() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let trackingStart = cal.date(byAdding: .day, value: -3, to: today)!
        let vm = makeTrackingVM(trackingStart: trackingStart)
        #expect(!vm.hasRecord(zeroStat(daysFromToday: -4, today: today), today: today))
    }

    @Test func hasRecordIsFalseForFutureDays() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let trackingStart = cal.date(byAdding: .day, value: -3, to: today)!
        let vm = makeTrackingVM(trackingStart: trackingStart)
        #expect(!vm.hasRecord(zeroStat(daysFromToday: 1, today: today), today: today))
    }

    // MARK: - LoadDashboardUseCase streak

    @Test func adFreeStreakIsOneOnFirstInstallWithNoAds() {
        let statsRepo = FakeStatsRepository()
        statsRepo.oldestStatDateValue = nil
        // nDayStatsValue 기본값 [] → 오늘 광고 없음 → 1일
        let useCase = LoadDashboardUseCase(
            shieldRepository: FakeShieldRepository(),
            statsRepository: statsRepo,
            screenTimeRepository: FakeScreenTimeRepository()
        )

        #expect(useCase.calculateAdFreeStreak() == 1)
        #expect(useCase.calculateMaxAdFreeStreak() == 1)
    }

    @Test func adFreeStreakIsZeroOnFirstInstallWhenTodayHasAd() {
        let statsRepo = FakeStatsRepository()
        statsRepo.oldestStatDateValue = nil
        statsRepo.nDayStatsValue = [
            DailyStats(dateKey: DailyStats.dateKey(for: Date()), adWatchCount: 1)
        ]
        let useCase = LoadDashboardUseCase(
            shieldRepository: FakeShieldRepository(),
            statsRepository: statsRepo,
            screenTimeRepository: FakeScreenTimeRepository()
        )

        #expect(useCase.calculateAdFreeStreak() == 0)
        #expect(useCase.calculateMaxAdFreeStreak() == 0)
    }

    @Test func adFreeStreakIsZeroWhenTodayHasAd() {
        let statsRepo = FakeStatsRepository()
        let today = Calendar.current.startOfDay(for: Date())
        statsRepo.oldestStatDateValue = today
        statsRepo.nDayStatsValue = [
            DailyStats(dateKey: DailyStats.dateKey(for: today), adWatchCount: 1)
        ]
        let useCase = LoadDashboardUseCase(
            shieldRepository: FakeShieldRepository(),
            statsRepository: statsRepo,
            screenTimeRepository: FakeScreenTimeRepository()
        )

        #expect(useCase.calculateAdFreeStreak() == 0)
    }

    @Test func adFreeStreakCountsConsecutiveDays() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: today)!

        let statsRepo = FakeStatsRepository()
        statsRepo.oldestStatDateValue = threeDaysAgo
        statsRepo.nDayStatsValue = [
            DailyStats(dateKey: DailyStats.dateKey(for: threeDaysAgo), adWatchCount: 2),
            DailyStats(dateKey: DailyStats.dateKey(for: calendar.date(byAdding: .day, value: -2, to: today)!), adWatchCount: 0),
            DailyStats(dateKey: DailyStats.dateKey(for: calendar.date(byAdding: .day, value: -1, to: today)!), adWatchCount: 0),
            DailyStats(dateKey: DailyStats.dateKey(for: today), adWatchCount: 0)
        ]
        let useCase = LoadDashboardUseCase(
            shieldRepository: FakeShieldRepository(),
            statsRepository: statsRepo,
            screenTimeRepository: FakeScreenTimeRepository()
        )

        #expect(useCase.calculateAdFreeStreak() == 3)
    }

    @Test func adFreeStreakStopsAtOldestDate() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!
        let fourDaysAgo = calendar.date(byAdding: .day, value: -4, to: today)!

        let statsRepo = FakeStatsRepository()
        statsRepo.oldestStatDateValue = twoDaysAgo
        // 앱 설치 이전 데이터(4일 전, 3일 전)도 포함된 경우 → oldestDate 이전은 무시
        statsRepo.nDayStatsValue = [
            DailyStats(dateKey: DailyStats.dateKey(for: fourDaysAgo), adWatchCount: 0),
            DailyStats(dateKey: DailyStats.dateKey(for: calendar.date(byAdding: .day, value: -3, to: today)!), adWatchCount: 0),
            DailyStats(dateKey: DailyStats.dateKey(for: twoDaysAgo), adWatchCount: 0),
            DailyStats(dateKey: DailyStats.dateKey(for: calendar.date(byAdding: .day, value: -1, to: today)!), adWatchCount: 0),
            DailyStats(dateKey: DailyStats.dateKey(for: today), adWatchCount: 0)
        ]
        let useCase = LoadDashboardUseCase(
            shieldRepository: FakeShieldRepository(),
            statsRepository: statsRepo,
            screenTimeRepository: FakeScreenTimeRepository()
        )

        #expect(useCase.calculateAdFreeStreak() == 3)
    }

    // MARK: - LockOptionsViewModel

    @Test func lockOptionsViewModelExtendsSelectedGroupWithOneMinute() {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임")
        let shieldRepo = FakeShieldRepository()
        shieldRepo.lockedGroupsValue = [group]
        shieldRepo.oneMinuteRemainingValue = 5
        let screenTimeRepo = FakeScreenTimeRepository()
        screenTimeRepo.extendResult = .success(GroupExtensionResult(
            group: group,
            durationSeconds: 60,
            overrideUntil: Date().addingTimeInterval(60),
            remainingLockedGroups: []
        ))
        let viewModel = LockOptionsViewModel(
            extendGroupUseCase: ExtendGroupUseCase(
                shieldRepository: shieldRepo,
                screenTimeRepository: screenTimeRepo
            )
        )

        viewModel.onAppear()
        viewModel.tapOneMinute()

        #expect(screenTimeRepo.extendCallCount == 1)
        #expect(screenTimeRepo.lastExtensionSource == .oneMinute)
        #expect(viewModel.completionAlert?.title == "연장 완료")
        #expect(viewModel.lockedGroups.isEmpty)
    }

    @Test func lockOptionsViewModelDoesNotLogAdUnlockForOneMinuteExtension() {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임")
        let shieldRepo = FakeShieldRepository()
        shieldRepo.lockedGroupsValue = [group]
        shieldRepo.oneMinuteRemainingValue = 5
        let screenTimeRepo = FakeScreenTimeRepository()
        screenTimeRepo.extendResult = .success(GroupExtensionResult(
            group: group,
            durationSeconds: 60,
            overrideUntil: Date().addingTimeInterval(60),
            remainingLockedGroups: []
        ))
        let analyticsRepo = FakeAnalyticsRepository()
        let viewModel = LockOptionsViewModel(
            extendGroupUseCase: ExtendGroupUseCase(
                shieldRepository: shieldRepo,
                screenTimeRepository: screenTimeRepo
            ),
            analyticsRepository: analyticsRepo
        )

        viewModel.onAppear()
        viewModel.tapOneMinute()

        #expect(analyticsRepo.parameters(for: "one_minute_unlock") != nil)
        #expect(analyticsRepo.parameters(for: "ad_unlock") == nil)
    }

    @Test func lockOptionsViewModelLogsAdUnlockWithRulePayload() {
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(),
            name: "게임",
            ruleKind: .cooldown,
            cooldownUsageMinutes: 30,
            cooldownDurationMinutes: 90
        )
        let shieldRepo = FakeShieldRepository()
        shieldRepo.lockedGroupsValue = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        screenTimeRepo.extendResult = .success(GroupExtensionResult(
            group: group,
            durationSeconds: 10 * 60,
            overrideUntil: Date().addingTimeInterval(10 * 60),
            remainingLockedGroups: []
        ))
        let analyticsRepo = FakeAnalyticsRepository()
        let viewModel = LockOptionsViewModel(
            extendGroupUseCase: ExtendGroupUseCase(
                shieldRepository: shieldRepo,
                screenTimeRepository: screenTimeRepo
            ),
            analyticsRepository: analyticsRepo
        )

        viewModel.onAppear()
        viewModel.startAdFlow()
        viewModel.rewardedAdDismissed()

        let event = analyticsRepo.parameters(for: "ad_unlock")
        #expect(event?["seconds"] as? Int == 10 * 60)
        #expect(event?["rule_kind"] as? String == "cooldown")
        #expect(event?["rule_config_bucket"] as? String == "usage_16_30m_rest_61_120m")
    }

    @Test func lockOptionsViewModelDoesNotLogAdUnlockWhenAdCancelled() {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임")
        let shieldRepo = FakeShieldRepository()
        shieldRepo.lockedGroupsValue = [group]
        let analyticsRepo = FakeAnalyticsRepository()
        let viewModel = LockOptionsViewModel(
            extendGroupUseCase: ExtendGroupUseCase(
                shieldRepository: shieldRepo,
                screenTimeRepository: FakeScreenTimeRepository()
            ),
            analyticsRepository: analyticsRepo
        )

        viewModel.onAppear()
        viewModel.startAdFlow()
        viewModel.rewardedAdDidCancel()
        viewModel.rewardedAdDismissed()

        #expect(analyticsRepo.parameters(for: "ad_unlock") == nil)
    }

    @Test func lockOptionsViewModelDoesNotLogAdUnlockWhenAdExtensionFails() {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임")
        let shieldRepo = FakeShieldRepository()
        shieldRepo.lockedGroupsValue = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        screenTimeRepo.extendResult = .failure(.groupNotFound)
        let analyticsRepo = FakeAnalyticsRepository()
        let viewModel = LockOptionsViewModel(
            extendGroupUseCase: ExtendGroupUseCase(
                shieldRepository: shieldRepo,
                screenTimeRepository: screenTimeRepo
            ),
            analyticsRepository: analyticsRepo
        )

        viewModel.onAppear()
        viewModel.startAdFlow()
        viewModel.rewardedAdDismissed()

        #expect(screenTimeRepo.extendCallCount == 1)
        #expect(analyticsRepo.parameters(for: "ad_unlock") == nil)
    }

    @Test func lockOptionsViewModelCanRetryRelockRegistrationFailure() {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임")
        let shieldRepo = FakeShieldRepository()
        shieldRepo.lockedGroupsValue = [group]
        shieldRepo.oneMinuteRemainingValue = 5
        let screenTimeRepo = FakeScreenTimeRepository()
        screenTimeRepo.extendResults = [
            .failure(.relockTimerRegistrationFailed),
            .success(GroupExtensionResult(
                group: group,
                durationSeconds: 60,
                overrideUntil: Date().addingTimeInterval(60),
                remainingLockedGroups: []
            ))
        ]
        let viewModel = LockOptionsViewModel(
            extendGroupUseCase: ExtendGroupUseCase(
                shieldRepository: shieldRepo,
                screenTimeRepository: screenTimeRepo
            )
        )

        viewModel.onAppear()
        viewModel.tapOneMinute()

        #expect(screenTimeRepo.extendCallCount == 1)
        #expect(viewModel.canRetryRelockRegistration)
        #expect(viewModel.infoMessage?.contains("재잠금 타이머 등록 실패") == true)

        viewModel.retryRelockRegistration()

        #expect(screenTimeRepo.extendCallCount == 2)
        #expect(!viewModel.canRetryRelockRegistration)
        #expect(viewModel.completionAlert?.title == "연장 완료")
    }

    @Test func lockOptionsViewModelRecordsWalkAwayOnlyWhenLockedGroupExists() {
        let shieldRepo = FakeShieldRepository()
        shieldRepo.lockedGroupsValue = [SharedStore.ScreenTimeGroup(name: "SNS")]
        let viewModel = LockOptionsViewModel(
            extendGroupUseCase: ExtendGroupUseCase(
                shieldRepository: shieldRepo,
                screenTimeRepository: FakeScreenTimeRepository()
            )
        )

        viewModel.onAppear()
        _ = viewModel.tapWalkAway()

        #expect(shieldRepo.recordWalkAwayCallCount == 1)
    }

    @Test func lockOptionsViewModelDisablesOneMinuteNearMidnight() {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임")
        let shieldRepo = FakeShieldRepository()
        shieldRepo.lockedGroupsValue = [group]
        shieldRepo.oneMinuteRemainingValue = 5
        let screenTimeRepo = FakeScreenTimeRepository()
        screenTimeRepo.nearMidnightCutoff = true
        let viewModel = LockOptionsViewModel(
            extendGroupUseCase: ExtendGroupUseCase(
                shieldRepository: shieldRepo,
                screenTimeRepository: screenTimeRepo
            )
        )

        viewModel.onAppear()

        // 자정 직전: 1분 연장은 막히고(남은 횟수가 있어도), 광고 연장은 계속 가능.
        #expect(viewModel.isNearMidnightCutoff)
        #expect(!viewModel.canExtendOneMinute)
        #expect(viewModel.canExtendWithAd)
        #expect(viewModel.nearMidnightNotice == "23:45부터는 연장 시 사용량 추적이 불가능해 23:59까지 잠금이 해제되며, 00:00부터 규칙이 다시 적용됩니다.")
        #expect(viewModel.adButtonTitle == "광고 보고 자정까지 열기")
    }

    @Test func lockOptionsViewModelShowsNearMidnightNoticeBeforeCutoffWithoutChangingActions() {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임")
        let shieldRepo = FakeShieldRepository()
        shieldRepo.lockedGroupsValue = [group]
        shieldRepo.oneMinuteRemainingValue = 5
        let screenTimeRepo = FakeScreenTimeRepository()
        screenTimeRepo.nearMidnightNoticeWindow = true
        let viewModel = LockOptionsViewModel(
            extendGroupUseCase: ExtendGroupUseCase(
                shieldRepository: shieldRepo,
                screenTimeRepository: screenTimeRepo
            )
        )

        viewModel.onAppear()

        #expect(!viewModel.isNearMidnightCutoff)
        #expect(viewModel.nearMidnightNotice == "23:45부터는 연장 시 사용량 추적이 불가능해 23:59까지 잠금이 해제되며, 00:00부터 규칙이 다시 적용됩니다.")
        #expect(viewModel.canExtendOneMinute)
        #expect(viewModel.canExtendWithAd)
        #expect(viewModel.adButtonTitle == "광고 보고 10분 구매하기")
    }

    @Test func lockOptionsViewModelBlocksOneMinuteIfCutoffBeginsAfterScreenAppears() {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임")
        let shieldRepo = FakeShieldRepository()
        shieldRepo.lockedGroupsValue = [group]
        shieldRepo.oneMinuteRemainingValue = 5
        let screenTimeRepo = FakeScreenTimeRepository()
        let viewModel = LockOptionsViewModel(
            extendGroupUseCase: ExtendGroupUseCase(
                shieldRepository: shieldRepo,
                screenTimeRepository: screenTimeRepo
            )
        )

        viewModel.onAppear()
        #expect(viewModel.canExtendOneMinute)

        screenTimeRepo.nearMidnightCutoff = true
        viewModel.tapOneMinute()

        #expect(screenTimeRepo.extendCallCount == 0)
        #expect(!viewModel.canExtendOneMinute)
    }

    @Test func lockOptionsViewModelNearMidnightCompletionMessageUsesClockTime() {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임")
        let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: Date())!
        let shieldRepo = FakeShieldRepository()
        shieldRepo.lockedGroupsValue = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        screenTimeRepo.nearMidnightCutoff = true
        screenTimeRepo.extendResult = .success(GroupExtensionResult(
            group: group,
            durationSeconds: 10 * 60,
            overrideUntil: endOfDay,
            remainingLockedGroups: []
        ))
        let viewModel = LockOptionsViewModel(
            extendGroupUseCase: ExtendGroupUseCase(
                shieldRepository: shieldRepo,
                screenTimeRepository: screenTimeRepo
            )
        )

        viewModel.onAppear()
        viewModel.startAdFlow()      // 광고 표시
        viewModel.rewardedAdDismissed()   // 광고 완료 → 연장 수행

        // 자정 근처 완료 문구는 "분 더 쓰면 잠김"이 아니라 "23:59까지 사용할 수 있어요".
        let message = viewModel.completionAlert?.message ?? ""
        #expect(message.contains("23:59까지 사용할 수 있어요"))
        #expect(!message.contains("더 쓰면"))
    }

    @Test func lockOptionsViewModelStillPresentsAdNearMidnight() {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임")
        let shieldRepo = FakeShieldRepository()
        shieldRepo.lockedGroupsValue = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        screenTimeRepo.nearMidnightCutoff = true
        let viewModel = LockOptionsViewModel(
            extendGroupUseCase: ExtendGroupUseCase(
                shieldRepository: shieldRepo,
                screenTimeRepository: screenTimeRepo
            )
        )

        viewModel.onAppear()
        viewModel.startAdFlow()

        // 자정 근처에도 광고를 띄우고(rewarded 표시), 광고 완료 전에는 연장하지 않는다.
        #expect(viewModel.isRewardedAdPresented)
        #expect(screenTimeRepo.extendCallCount == 0)
        // 버튼 제목은 "자정까지"로 정직하게 표기하되 광고는 필수.
        #expect(viewModel.adButtonTitle == "광고 보고 자정까지 열기")
    }

    // MARK: - OnboardingViewModel

    @Test func onboardingViewModelScreenTimeApprovalMovesToNotificationStep() async {
        let authRepo = FakeAuthorizationRepository(isAuthorized: false)
        authRepo.requestResultIsAuthorized = true
        let viewModel = OnboardingViewModel(
            authorizeUseCase: AuthorizeUseCase(
                authRepository: authRepo,
                notificationRepository: FakeNotificationRepository()
            ),
            onAuthorized: {}
        )

        await viewModel.requestScreenTime()

        #expect(authRepo.requestCallCount == 1)
        #expect(viewModel.currentStep == .notificationPermission)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func onboardingViewModelScreenTimeDenialStaysOnSameStep() async {
        let authRepo = FakeAuthorizationRepository(isAuthorized: false)
        authRepo.requestResultIsAuthorized = false
        let viewModel = OnboardingViewModel(
            authorizeUseCase: AuthorizeUseCase(
                authRepository: authRepo,
                notificationRepository: FakeNotificationRepository()
            ),
            startStep: .screenTimePermission,
            onAuthorized: {}
        )

        await viewModel.requestScreenTime()

        #expect(viewModel.currentStep == .screenTimePermission)
        #expect(viewModel.errorMessage != nil)
    }

    @Test func onboardingViewModelNotificationApprovalMovesToTrackingStep() async {
        let notifRepo = FakeNotificationRepository()
        notifRepo.requestAuthorizationResult = .authorized
        let viewModel = OnboardingViewModel(
            authorizeUseCase: AuthorizeUseCase(
                authRepository: FakeAuthorizationRepository(isAuthorized: true),
                notificationRepository: notifRepo
            ),
            startStep: .notificationPermission,
            onAuthorized: {}
        )

        await viewModel.requestNotification()

        #expect(notifRepo.requestCallCount == 1)
        #expect(viewModel.currentStep == .trackingPermission)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func onboardingViewModelNotificationDenialStillMovesToTrackingStep() async {
        let notifRepo = FakeNotificationRepository()
        notifRepo.requestAuthorizationResult = .denied
        var didAuthorize = false
        let viewModel = OnboardingViewModel(
            authorizeUseCase: AuthorizeUseCase(
                authRepository: FakeAuthorizationRepository(isAuthorized: true),
                notificationRepository: notifRepo
            ),
            startStep: .notificationPermission,
            onAuthorized: { didAuthorize = true }
        )

        await viewModel.requestNotification()

        // 알림은 선택 권한이므로 거부해도 다음 단계로 넘어간다.
        #expect(notifRepo.requestCallCount == 1)
        #expect(viewModel.currentStep == .trackingPermission)
        #expect(viewModel.errorMessage == nil)
        #expect(!didAuthorize)
    }

    @Test func onboardingViewModelSkipNotificationMovesToTrackingStepWithoutRequesting() {
        let notifRepo = FakeNotificationRepository()
        let viewModel = OnboardingViewModel(
            authorizeUseCase: AuthorizeUseCase(
                authRepository: FakeAuthorizationRepository(isAuthorized: true),
                notificationRepository: notifRepo
            ),
            startStep: .notificationPermission,
            onAuthorized: {}
        )

        viewModel.skipNotification()

        #expect(notifRepo.requestCallCount == 0)
        #expect(viewModel.currentStep == .trackingPermission)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func onboardingViewModelPersistsStepOnAdvance() async {
        let defaults = UserDefaults(suiteName: "onboarding.persist.\(UUID().uuidString)")!
        let authRepo = FakeAuthorizationRepository(isAuthorized: false)
        authRepo.requestResultIsAuthorized = true
        let viewModel = OnboardingViewModel(
            authorizeUseCase: AuthorizeUseCase(
                authRepository: authRepo,
                notificationRepository: FakeNotificationRepository()
            ),
            startStep: .screenTimePermission,
            userDefaults: defaults,
            onAuthorized: {}
        )

        await viewModel.requestScreenTime()

        #expect(viewModel.currentStep == .notificationPermission)
        #expect(defaults.string(forKey: OnboardingViewModel.savedStepKey) == "notificationPermission")
    }

    @Test func onboardingViewModelCompleteClearsSavedStep() async {
        let defaults = UserDefaults(suiteName: "onboarding.clear.\(UUID().uuidString)")!
        defaults.set(OnboardingStep.trackingPermission.rawValue, forKey: OnboardingViewModel.savedStepKey)
        let viewModel = OnboardingViewModel(
            authorizeUseCase: AuthorizeUseCase(
                authRepository: FakeAuthorizationRepository(isAuthorized: true),
                notificationRepository: FakeNotificationRepository()
            ),
            startStep: .completion,
            userDefaults: defaults,
            onAuthorized: {}
        )

        viewModel.complete()

        #expect(defaults.string(forKey: OnboardingViewModel.savedStepKey) == nil)
    }

    @Test func contentViewModelRestoresSavedOnboardingStep() async {
        let defaults = UserDefaults(suiteName: "onboarding.restore.\(UUID().uuidString)")!
        defaults.set(OnboardingStep.trackingPermission.rawValue, forKey: OnboardingViewModel.savedStepKey)
        let viewModel = ContentViewModel(
            authorizeUseCase: AuthorizeUseCase(
                authRepository: FakeAuthorizationRepository(isAuthorized: true),
                notificationRepository: FakeNotificationRepository()
            ),
            userDefaults: defaults
        )

        #expect(viewModel.onboardingStartStep == .trackingPermission)
    }

    @Test func contentViewModelOnboardingStepFallsBackWhenNoSavedStep() async {
        let defaults = UserDefaults(suiteName: "onboarding.fallback.\(UUID().uuidString)")!
        let viewModel = ContentViewModel(
            authorizeUseCase: AuthorizeUseCase(
                authRepository: FakeAuthorizationRepository(isAuthorized: false),
                notificationRepository: FakeNotificationRepository()
            ),
            userDefaults: defaults
        )

        #expect(viewModel.onboardingStartStep == .intro)
    }

    @Test func onboardingViewModelCompleteCallsOnAuthorized() async {
        let notifRepo = FakeNotificationRepository()
        notifRepo.requestAuthorizationResult = .authorized
        var didAuthorize = false
        let viewModel = OnboardingViewModel(
            authorizeUseCase: AuthorizeUseCase(
                authRepository: FakeAuthorizationRepository(isAuthorized: true),
                notificationRepository: notifRepo
            ),
            startStep: .notificationPermission,
            onAuthorized: { didAuthorize = true }
        )

        await viewModel.requestNotification()
        viewModel.complete()

        #expect(didAuthorize)
    }

    // MARK: - RewardedAdViewModel

    @Test func rewardedAdViewModelLoadsShieldUnlockPlacement() {
        let adRepo = FakeAdRepository(loadState: .idle)
        let viewModel = RewardedAdViewModel(
            placement: .shieldUnlock,
            adRepository: adRepo,
            onComplete: {},
            onCancel: {}
        )

        viewModel.onAppear()

        #expect(adRepo.loadCallPlacements == [.shieldUnlock])
        #expect(adRepo.presentCallPlacements.isEmpty)
    }

    @Test func rewardedAdViewModelLoadsGroupEditGatePlacement() {
        let adRepo = FakeAdRepository(loadState: .idle)
        let viewModel = RewardedAdViewModel(
            placement: .groupEditGate,
            adRepository: adRepo,
            onComplete: {},
            onCancel: {}
        )

        viewModel.onAppear()

        #expect(adRepo.loadCallPlacements == [.groupEditGate])
        #expect(adRepo.presentCallPlacements.isEmpty)
    }

    @Test func rewardedAdViewModelShowsFallbackWhenLoadFails() {
        let adRepo = FakeAdRepository(loadState: .failed)
        let viewModel = RewardedAdViewModel(
            placement: .groupEditGate,
            adRepository: adRepo,
            onComplete: {},
            onCancel: {}
        )

        viewModel.onAppear()

        #expect(viewModel.showFallback)
        #expect(adRepo.loadCallCount == 0)
    }

    @Test func rewardedAdViewModelCompletesWhenRewardEarned() async throws {
        let adRepo = FakeAdRepository(loadState: .ready)
        var didComplete = false
        var didCancel = false
        let viewModel = RewardedAdViewModel(
            placement: .shieldUnlock,
            adRepository: adRepo,
            onComplete: { didComplete = true },
            onCancel: { didCancel = true }
        )

        viewModel.presentIfReady(from: UIViewController())
        try await Task.sleep(for: .milliseconds(10))

        #expect(adRepo.presentCallCount == 1)
        #expect(adRepo.presentCallPlacements == [.shieldUnlock])
        #expect(didComplete)
        #expect(!didCancel)
    }

    @Test func rewardedAdViewModelPresentsGroupEditGatePlacement() async throws {
        let adRepo = FakeAdRepository(loadState: .ready)
        var didComplete = false
        var didCancel = false
        let viewModel = RewardedAdViewModel(
            placement: .groupEditGate,
            adRepository: adRepo,
            onComplete: { didComplete = true },
            onCancel: { didCancel = true }
        )

        viewModel.presentIfReady(from: UIViewController())
        try await Task.sleep(for: .milliseconds(10))

        #expect(adRepo.presentCallCount == 1)
        #expect(adRepo.presentCallPlacements == [.groupEditGate])
        #expect(didComplete)
        #expect(!didCancel)
    }

    @Test func rewardedAdViewModelLogsStartAndRewardEarned() async throws {
        let adRepo = FakeAdRepository(loadState: .ready)
        adRepo.shouldEarnReward = true
        let analyticsRepo = FakeAnalyticsRepository()
        let viewModel = RewardedAdViewModel(
            placement: .shieldUnlock,
            adRepository: adRepo,
            analyticsRepository: analyticsRepo,
            onComplete: {},
            onCancel: {}
        )

        viewModel.presentIfReady(from: UIViewController())
        try await Task.sleep(for: .milliseconds(10))

        #expect(analyticsRepo.events.map(\.name) == ["ad_started", "ad_reward_earned"])
        #expect(analyticsRepo.parameters(for: "ad_started")?["placement"] as? String == "shield_unlock")
        #expect(analyticsRepo.parameters(for: "ad_reward_earned")?["placement"] as? String == "shield_unlock")
    }

    @Test func rewardedAdViewModelLogsClosedWithoutReward() async throws {
        let adRepo = FakeAdRepository(loadState: .ready)
        adRepo.shouldEarnReward = false
        let analyticsRepo = FakeAnalyticsRepository()
        let viewModel = RewardedAdViewModel(
            placement: .groupEditGate,
            adRepository: adRepo,
            analyticsRepository: analyticsRepo,
            onComplete: {},
            onCancel: {}
        )

        viewModel.presentIfReady(from: UIViewController())
        try await Task.sleep(for: .milliseconds(10))

        #expect(analyticsRepo.events.map(\.name) == ["ad_started", "ad_closed_no_reward"])
        #expect(
            analyticsRepo.parameters(for: "ad_closed_no_reward")?["placement"] as? String == "group_edit_gate"
        )
    }

    @Test func rewardedAdViewModelLogsUnavailableOnceWhenLoadFails() {
        let adRepo = FakeAdRepository(loadState: .failed)
        let analyticsRepo = FakeAnalyticsRepository()
        let viewModel = RewardedAdViewModel(
            placement: .shieldUnlock,
            adRepository: adRepo,
            analyticsRepository: analyticsRepo,
            onComplete: {},
            onCancel: {}
        )

        viewModel.onAppear()
        viewModel.handleLoadStateChange(.failed, viewController: nil)  // 두 번째 실패 경로

        #expect(viewModel.showFallback)
        #expect(analyticsRepo.events.map(\.name) == ["ad_unavailable"])  // 중복 없이 1회
    }

    @Test func rewardedAdViewModelLogsFallbackUsed() {
        let adRepo = FakeAdRepository(loadState: .failed)
        let analyticsRepo = FakeAnalyticsRepository()
        let viewModel = RewardedAdViewModel(
            placement: .shieldUnlock,
            adRepository: adRepo,
            analyticsRepository: analyticsRepo,
            onComplete: {},
            onCancel: {}
        )

        viewModel.completeFallback()

        #expect(analyticsRepo.parameters(for: "ad_fallback_used")?["placement"] as? String == "shield_unlock")
    }

    @Test func onboardingViewModelLogsNotificationPermissionResultAndStep() async {
        let notifRepo = FakeNotificationRepository()
        notifRepo.requestAuthorizationResult = .authorized
        let analyticsRepo = FakeAnalyticsRepository()
        let viewModel = OnboardingViewModel(
            authorizeUseCase: AuthorizeUseCase(
                authRepository: FakeAuthorizationRepository(isAuthorized: true),
                notificationRepository: notifRepo
            ),
            analyticsRepository: analyticsRepo,
            startStep: .notificationPermission,
            onAuthorized: {}
        )

        await viewModel.requestNotification()

        #expect(
            analyticsRepo.parameters(for: "notification_permission_result")?["granted"] as? Bool == true
        )
        #expect(
            analyticsRepo.parameters(for: "onboarding_step_view")?["step"] as? String == "trackingPermission"
        )
    }

    @Test func onboardingViewModelLogsStepViewOnAdvance() {
        let analyticsRepo = FakeAnalyticsRepository()
        let viewModel = OnboardingViewModel(
            authorizeUseCase: AuthorizeUseCase(
                authRepository: FakeAuthorizationRepository(isAuthorized: false),
                notificationRepository: FakeNotificationRepository()
            ),
            analyticsRepository: analyticsRepo,
            startStep: .intro,
            onAuthorized: {}
        )

        viewModel.advance()

        #expect(analyticsRepo.events.map(\.name) == ["onboarding_step_view"])
        #expect(
            analyticsRepo.parameters(for: "onboarding_step_view")?["step"] as? String == "screenTimePermission"
        )
    }

    // MARK: - 요일별 규칙 편집 (ContentViewModel)

    @Test func presentRuleEditorSeedsWeekdayRules() {
        let rules = (0..<7).map { SharedStore.DayRule(kind: .dailyLimit, dailyLimitMinutes: 10 + $0) }
        let weekdayGroup = SharedStore.ScreenTimeGroup(
            id: UUID(), name: "SNS", ruleKind: .dailyLimit, isApplied: true, weekdayRules: rules
        )
        let plainGroup = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임", ruleKind: .dailyLimit, isApplied: true)

        let viewModel = makeApplyViewModel(with: weekdayGroup)
        viewModel.presentRuleEditor(for: weekdayGroup)
        #expect(viewModel.ruleEditorWeekdayRules == rules)

        // 비요일 그룹은 시드도 nil(요일별 OFF).
        viewModel.presentRuleEditor(for: plainGroup)
        #expect(viewModel.ruleEditorWeekdayRules == nil)
    }

    @Test func commitWeekdayRulesSavesAndSyncsWhenValid() {
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(), name: "SNS", dailyLimitMinutes: 30, ruleKind: .dailyLimit, isApplied: true
        )
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(groupRepository: groupRepo, screenTimeRepository: screenTimeRepo),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]

        viewModel.presentRuleEditor(for: group)
        let rules = (0..<7).map { SharedStore.DayRule(kind: .dailyLimit, dailyLimitMinutes: 10 + $0) }
        viewModel.ruleEditorWeekdayRules = rules
        viewModel.performRuleCommit()

        #expect(viewModel.groups.first?.weekdayRules == rules)
        #expect(groupRepo.screenTimeGroups.first?.weekdayRules == rules)
        #expect(screenTimeRepo.syncCallCount == 1)
    }

    @Test func commitWeekdayRulesRejectedWhenAllUnrestricted() {
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(), name: "SNS", dailyLimitMinutes: 30, ruleKind: .dailyLimit, isApplied: true
        )
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(groupRepository: groupRepo, screenTimeRepository: screenTimeRepo),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]

        viewModel.presentRuleEditor(for: group)
        viewModel.ruleEditorWeekdayRules = (0..<7).map { _ in SharedStore.DayRule(kind: .unrestricted) }
        viewModel.performRuleCommit()

        #expect(viewModel.groups.first?.weekdayRules == nil)   // 저장 안 됨
        #expect(screenTimeRepo.syncCallCount == 0)
        #expect(viewModel.alertMessage?.title == "요일 규칙을 확인해주세요")
    }

    @Test func commitBaseRuleClearsWeekdayRulesWhenToggledOff() {
        let rules = (0..<7).map { SharedStore.DayRule(kind: .dailyLimit, dailyLimitMinutes: 10 + $0) }
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(), name: "SNS", dailyLimitMinutes: 30, ruleKind: .dailyLimit, isApplied: true, weekdayRules: rules
        )
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(groupRepository: groupRepo, screenTimeRepository: screenTimeRepo),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]

        viewModel.presentRuleEditor(for: group)
        #expect(viewModel.ruleEditorWeekdayRules == rules)

        // 토글 OFF → base 일일 한도 커밋. 요일 규칙이 정리되고 base 규칙이 다시 매일 적용된다.
        viewModel.ruleEditorWeekdayRules = nil
        viewModel.ruleEditorSelectedKind = .dailyLimit
        viewModel.limitPickerHours = 1
        viewModel.limitPickerMinutes = 0
        viewModel.performRuleCommit()

        #expect(viewModel.groups.first?.weekdayRules == nil)
        #expect(viewModel.groups.first?.ruleKind == .dailyLimit)
        #expect(viewModel.groups.first?.dailyLimitMinutes == 60)
    }

    @Test func weekdayCommitWarnsWhenTodayBudgetBelowUsed() {
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(), name: "SNS", dailyLimitMinutes: 30, ruleKind: .dailyLimit, isApplied: true
        )
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(groupRepository: groupRepo, screenTimeRepository: screenTimeRepo),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]
        viewModel.usedTimeByGroupID = [group.id: 20]

        // 오늘 슬롯만 10분 한도(<=20분 사용) → 즉시 잠금 경고. 다른 요일은 여유 있는 한도라 무관.
        let todayIndex = WeekdayRulePolicy.weekdayIndex(for: Date())
        var rules = (0..<7).map { _ in SharedStore.DayRule(kind: .dailyLimit, dailyLimitMinutes: 120) }
        rules[todayIndex] = SharedStore.DayRule(kind: .dailyLimit, dailyLimitMinutes: 10)

        viewModel.presentRuleEditor(for: group)
        viewModel.ruleEditorWeekdayRules = rules
        viewModel.performRuleCommit()
        viewModel.handleRuleEditorDismiss()

        #expect(viewModel.pendingLimitLockWarning != nil)
        #expect(viewModel.pendingLimitLockWarning?.usedMinutes == 20)
        #expect(viewModel.groups.first?.weekdayRules == nil)   // 아직 미적용
        #expect(screenTimeRepo.syncCallCount == 0)

        // 확정 → 요일 규칙 전체 적용(base 규칙이 아니라).
        let warning = viewModel.pendingLimitLockWarning!
        viewModel.pendingLimitLockWarning = nil
        viewModel.confirmLimitLockChange(warning)
        #expect(viewModel.groups.first?.weekdayRules == rules)
        #expect(screenTimeRepo.syncCallCount == 1)
    }

    @Test func weekdayCommitNoWarnWhenTodayIsTimeWindows() {
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(), name: "SNS", dailyLimitMinutes: 30, ruleKind: .dailyLimit, isApplied: true
        )
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(groupRepository: groupRepo, screenTimeRepository: screenTimeRepo),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]
        viewModel.usedTimeByGroupID = [group.id: 20]

        // 오늘이 시간대 규칙이면 측정창과 무관 → 사용량이 많아도 즉시 잠금 경고 없음.
        let todayIndex = WeekdayRulePolicy.weekdayIndex(for: Date())
        var rules = (0..<7).map { _ in SharedStore.DayRule(kind: .dailyLimit, dailyLimitMinutes: 10) }
        rules[todayIndex] = SharedStore.DayRule(kind: .timeWindows, timeWindows: [
            TimeWindow(startMinuteOfDay: 9 * 60, endMinuteOfDay: 10 * 60)
        ])

        viewModel.presentRuleEditor(for: group)
        viewModel.ruleEditorWeekdayRules = rules
        viewModel.performRuleCommit()

        #expect(viewModel.pendingLimitLockWarning == nil)
        #expect(viewModel.groups.first?.weekdayRules == rules)   // 즉시 적용
        #expect(screenTimeRepo.syncCallCount == 1)
    }

    // MARK: - Rule Commit Ad Gate (완료 시점 광고 게이트)

    @Test func ruleCommitSkipsAdGateForDraftGroup() {
        // draft(미적용)는 변경이 있어도 완료 광고 게이트 없이 즉시 커밋된다.
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(), name: "SNS", dailyLimitMinutes: 30, ruleKind: .dailyLimit, isApplied: false
        )
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(groupRepository: groupRepo, screenTimeRepository: screenTimeRepo),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]

        viewModel.presentRuleEditor(for: group)
        viewModel.ruleEditorSelectedKind = .dailyLimit
        viewModel.limitPickerHours = 1
        viewModel.limitPickerMinutes = 15
        viewModel.commitRuleSelection()

        #expect(!viewModel.isRuleCommitAdGatePresented)
        #expect(viewModel.groups.first?.dailyLimitMinutes == 75)
    }

    @Test func ruleCommitSkipsAdGateWhenNoChange() {
        // 적용된 그룹이라도 변경이 없으면 광고 없이 커밋(집행 영향 없음).
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(), name: "SNS", dailyLimitMinutes: 30, ruleKind: .dailyLimit, isApplied: true
        )
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(groupRepository: groupRepo, screenTimeRepository: screenTimeRepo),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]

        // presentRuleEditor가 그룹 값(30분) 그대로 편집기를 채운다 → 무변경 완료.
        viewModel.presentRuleEditor(for: group)
        viewModel.commitRuleSelection()

        #expect(!viewModel.isRuleCommitAdGatePresented)
        #expect(viewModel.groups.first?.dailyLimitMinutes == 30)
        #expect(screenTimeRepo.syncCallCount == 1)
    }

    @Test func ruleCommitSkipsAdGateForExplicitUnrestrictedPromotionOnly() {
        // 요일 규칙에서 표시 전용 isExplicitlyUnrestricted만 승격된 커밋은 집행 무영향 → 광고 없이 통과.
        var rules = (0..<7).map { SharedStore.DayRule(kind: .dailyLimit, dailyLimitMinutes: 30 + $0) }
        rules[0] = SharedStore.DayRule(kind: .unrestricted)   // 암묵 제한 없음
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(), name: "SNS", ruleKind: .dailyLimit, isApplied: true, weekdayRules: rules
        )
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(groupRepository: groupRepo, screenTimeRepository: screenTimeRepo),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]

        viewModel.presentRuleEditor(for: group)
        var promoted = rules
        promoted[0] = SharedStore.DayRule(kind: .unrestricted, isExplicitlyUnrestricted: true)  // 명시 승격만
        viewModel.ruleEditorWeekdayRules = promoted
        viewModel.commitRuleSelection()

        #expect(!viewModel.isRuleCommitAdGatePresented)
        #expect(viewModel.groups.first?.weekdayRules == promoted)   // 승격 persist
    }

    @Test func ruleCommitOpensAdGateForAppliedParameterChange() {
        // 적용된 그룹의 파라미터 변경(일일 한도 분)은 완료 시 광고 게이트 cover를 띄우고
        // 아직 커밋하지 않는다(안내 → 확인 → 광고 단계 전환은 cover 안 View 소관).
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(), name: "SNS", dailyLimitMinutes: 30, ruleKind: .dailyLimit, isApplied: true
        )
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(groupRepository: groupRepo, screenTimeRepository: screenTimeRepo),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]

        viewModel.presentRuleEditor(for: group)
        viewModel.ruleEditorSelectedKind = .dailyLimit
        viewModel.limitPickerHours = 1
        viewModel.limitPickerMinutes = 15
        viewModel.commitRuleSelection()

        #expect(viewModel.isRuleCommitAdGatePresented)
        #expect(viewModel.groups.first?.dailyLimitMinutes == 30)   // 아직 미커밋
        #expect(screenTimeRepo.syncCallCount == 0)
    }

    @Test func ruleCommitAppliesChangeAfterAdGateCompleted() {
        // 게이트 보상 후 cover dismiss에서 커밋이 반영된다.
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(), name: "SNS", dailyLimitMinutes: 30, ruleKind: .dailyLimit, isApplied: true
        )
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(groupRepository: groupRepo, screenTimeRepository: screenTimeRepo),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]

        viewModel.presentRuleEditor(for: group)
        viewModel.ruleEditorSelectedKind = .dailyLimit
        viewModel.limitPickerHours = 1
        viewModel.limitPickerMinutes = 15
        viewModel.commitRuleSelection()
        #expect(viewModel.isRuleCommitAdGatePresented)

        viewModel.ruleCommitAdGateCompleted()
        #expect(!viewModel.isRuleCommitAdGatePresented)
        viewModel.handleRuleCommitAdGateDismiss()

        #expect(viewModel.groups.first?.dailyLimitMinutes == 75)
        #expect(groupRepo.screenTimeGroups.first?.dailyLimitMinutes == 75)
        #expect(screenTimeRepo.syncCallCount == 1)
    }

    @Test func ruleCommitCancelKeepsEditorSessionAndDoesNotCommit() {
        // 게이트 취소 후 dismiss는 커밋하지 않고 편집 세션(ruleEditorGroupID)을 유지한다.
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(), name: "SNS", dailyLimitMinutes: 30, ruleKind: .dailyLimit, isApplied: true
        )
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(groupRepository: groupRepo, screenTimeRepository: screenTimeRepo),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]

        viewModel.presentRuleEditor(for: group)
        viewModel.ruleEditorSelectedKind = .dailyLimit
        viewModel.limitPickerHours = 1
        viewModel.limitPickerMinutes = 15
        viewModel.commitRuleSelection()
        #expect(viewModel.isRuleCommitAdGatePresented)

        viewModel.ruleCommitAdGateCancelled()
        viewModel.handleRuleCommitAdGateDismiss()

        #expect(!viewModel.isRuleCommitAdGatePresented)
        #expect(viewModel.groups.first?.dailyLimitMinutes == 30)   // 미커밋
        #expect(viewModel.ruleEditorGroupID == group.id)           // 편집 세션 유지
        #expect(screenTimeRepo.syncCallCount == 0)
    }

    @Test func ruleCommitOpensAdGateForModeSwitch() {
        // 단일 → 요일 모드 전환은 파라미터가 유효해도 완료 시 광고 게이트를 띄운다.
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(), name: "SNS", dailyLimitMinutes: 30, ruleKind: .dailyLimit, isApplied: true
        )
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(groupRepository: groupRepo, screenTimeRepository: screenTimeRepo),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]

        viewModel.presentRuleEditor(for: group)
        viewModel.ruleEditorWeekdayRules = (0..<7).map { SharedStore.DayRule(kind: .dailyLimit, dailyLimitMinutes: 10 + $0) }
        viewModel.commitRuleSelection()

        #expect(viewModel.isRuleCommitAdGatePresented)
        #expect(viewModel.groups.first?.weekdayRules == nil)   // 아직 미커밋
        #expect(screenTimeRepo.syncCallCount == 0)
    }

    @Test func ruleCommitOpensAdGateForWeekdayToSingleSwitch() {
        // 요일 → 단일 모드 전환(토글 OFF 완료)도 집행 구조 변경이라 완료 시 광고 게이트를 띄운다.
        let rules = (0..<7).map { SharedStore.DayRule(kind: .dailyLimit, dailyLimitMinutes: 10 + $0) }
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(), name: "SNS", dailyLimitMinutes: 30, ruleKind: .dailyLimit, isApplied: true, weekdayRules: rules
        )
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(groupRepository: groupRepo, screenTimeRepository: screenTimeRepo),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]

        viewModel.presentRuleEditor(for: group)
        viewModel.ruleEditorWeekdayRules = nil   // 요일 토글 OFF → base 규칙(변경 없음)으로 완료
        viewModel.commitRuleSelection()

        #expect(viewModel.isRuleCommitAdGatePresented)
        #expect(viewModel.groups.first?.weekdayRules == rules)   // 아직 미커밋
        #expect(screenTimeRepo.syncCallCount == 0)
    }

    @Test func ruleCommitSkipsAdGateForInvalidWeekdayAndAlerts() {
        // 무효한 요일 상태(전부 제한 없음)는 광고 없이 기존 검증 alert 경로를 탄다(광고 낭비 방지).
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(), name: "SNS", dailyLimitMinutes: 30, ruleKind: .dailyLimit, isApplied: true
        )
        let groupRepo = FakeGroupRepository()
        groupRepo.screenTimeGroups = [group]
        let screenTimeRepo = FakeScreenTimeRepository()
        let viewModel = ContentViewModel(
            manageGroupsUseCase: ManageGroupsUseCase(groupRepository: groupRepo, screenTimeRepository: screenTimeRepo),
            syncProtectionUseCase: makeSyncProtectionUseCase(screenTimeRepo: screenTimeRepo),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            userDefaults: makeUserDefaults()
        )
        viewModel.groups = [group]

        viewModel.presentRuleEditor(for: group)
        viewModel.ruleEditorWeekdayRules = (0..<7).map { _ in SharedStore.DayRule(kind: .unrestricted) }
        viewModel.commitRuleSelection()

        #expect(!viewModel.isRuleCommitAdGatePresented)
        #expect(viewModel.alertMessage?.title == "요일 규칙을 확인해주세요")
        #expect(viewModel.groups.first?.weekdayRules == nil)   // 미커밋
        #expect(screenTimeRepo.syncCallCount == 0)
    }

    // MARK: - 요일별 규칙 표시 (HomeViewModel)

    @Test func homeViewModelUnrestrictedTodayShowsUsableUntilMidnightNotNeedSetup() {
        // 회귀 핵심: 오늘 '제한 없음' 요일 그룹이 "설정 필요"로 오표시되지 않는다.
        // 하루 종일 자유 = "23:59까지 사용 가능" + 초록 가드(사용 가능 상태와 동일 시각 언어).
        let todayIndex = WeekdayRulePolicy.weekdayIndex(for: Date())
        var rules = (0..<7).map { _ in SharedStore.DayRule(kind: .dailyLimit, dailyLimitMinutes: 30) }
        rules[todayIndex] = SharedStore.DayRule(kind: .unrestricted)
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(), name: "SNS", ruleKind: .dailyLimit, isApplied: true, weekdayRules: rules
        )
        let viewModel = HomeViewModel(
            groups: [group],
            todayStats: DailyStats(dateKey: "2026-07-10"),
            isMonitoring: true,
            isShieldActive: false,
            shieldOverrideUntil: nil,
            successMessage: nil,
            errorMessage: nil
        )

        #expect(viewModel.statusTitle(for: group) == "23:59까지 사용 가능")
        #expect(viewModel.statusTitle(for: group) != "설정 필요")
        #expect(viewModel.statusTint(for: group) == .green)
        #expect(viewModel.statusIcon(for: group) == "checkmark.shield.fill")
        #expect(viewModel.lockProgress(for: group) == nil)   // 진행바 숨김
    }

    @Test func homeViewModelWeekdayGroupShowsTodayRuleRow() {
        // 오늘 규칙이 일일 한도인 요일 그룹: 규칙 행 제목 "요일별 규칙", 부제 "오늘: …", 진행바 있음.
        let todayIndex = WeekdayRulePolicy.weekdayIndex(for: Date())
        var rules = (0..<7).map { _ in SharedStore.DayRule(kind: .unrestricted) }
        rules[todayIndex] = SharedStore.DayRule(kind: .dailyLimit, dailyLimitMinutes: 45)
        let group = SharedStore.ScreenTimeGroup(
            id: UUID(), name: "SNS", dailyLimitMinutes: 30, ruleKind: .dailyLimit, isApplied: true, weekdayRules: rules
        )
        let viewModel = HomeViewModel(
            groups: [group],
            todayStats: DailyStats(dateKey: "2026-07-10"),
            isMonitoring: true,
            isShieldActive: false,
            shieldOverrideUntil: nil,
            successMessage: nil,
            errorMessage: nil,
            validGroupIDs: [group.id],
            usedTimeByGroupID: [group.id: 10]
        )

        #expect(viewModel.ruleRowTitle(for: group) == "요일별 규칙")
        #expect(viewModel.ruleRowSubtitle(for: group).hasPrefix("오늘"))
        #expect(viewModel.lockProgress(for: group) != nil)   // 오늘 한도 45분, 10분 사용 → 바 있음
    }

    // MARK: - Helpers

    private func makeUserDefaults(hasCompletedInitialHomeEntry: Bool = false) -> UserDefaults {
        let suiteName = "GoldTimeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(hasCompletedInitialHomeEntry, forKey: "hasCompletedInitialHomeEntry")
        return defaults
    }

    private func makeSyncProtectionUseCase(
        screenTimeRepo: FakeScreenTimeRepository? = nil
    ) -> SyncProtectionUseCase {
        SyncProtectionUseCase(
            groupRepository: FakeGroupRepository(),
            screenTimeRepository: screenTimeRepo ?? FakeScreenTimeRepository()
        )
    }

    private func makeLoadDashboardUseCase(
        screenTimeRepo: FakeScreenTimeRepository? = nil
    ) -> LoadDashboardUseCase {
        LoadDashboardUseCase(
            shieldRepository: FakeShieldRepository(),
            statsRepository: FakeStatsRepository(),
            screenTimeRepository: screenTimeRepo ?? FakeScreenTimeRepository()
        )
    }

    private func makeAuthorizeUseCase(isAuthorized: Bool = false) -> AuthorizeUseCase {
        AuthorizeUseCase(
            authRepository: FakeAuthorizationRepository(isAuthorized: isAuthorized),
            notificationRepository: FakeNotificationRepository()
        )
    }
}

// MARK: - AppLifecycleViewModel

@MainActor
struct AppLifecycleViewModelTests {

    @Test func doesNotShowLockOptionsWhenNoPendingRequest() {
        let shieldRepo = FakeShieldRepository()
        shieldRepo.pendingShieldOpenRequest = false
        shieldRepo.isShieldActive = true
        shieldRepo.lockedGroupsValue = [SharedStore.ScreenTimeGroup(name: "SNS")]
        let viewModel = AppLifecycleViewModel(
            authorizeUseCase: makeAuthorizeUseCase(),
            syncProtectionUseCase: makeSyncProtectionUseCase(),
            shieldRepository: shieldRepo
        )

        viewModel.refreshLockOptionsPresentation()

        #expect(viewModel.showLockOptions == false)
    }

    @Test func showsLockOptionsWhenPendingRequestExists() {
        let shieldRepo = FakeShieldRepository()
        shieldRepo.pendingShieldOpenRequest = true
        let viewModel = AppLifecycleViewModel(
            authorizeUseCase: makeAuthorizeUseCase(),
            syncProtectionUseCase: makeSyncProtectionUseCase(),
            shieldRepository: shieldRepo
        )

        viewModel.refreshLockOptionsPresentation()

        #expect(viewModel.showLockOptions == true)
    }

    @Test func setsCohortUserPropertiesOnActivationWhenAuthorized() {
        SharedStore.screenTimeGroups = [
            SharedStore.ScreenTimeGroup(name: "SNS", ruleKind: .dailyLimit),
            SharedStore.ScreenTimeGroup(name: "게임", ruleKind: .dailyLimit),
            SharedStore.ScreenTimeGroup(name: "유튜브", ruleKind: .cooldown)
        ]
        let analyticsRepo = FakeAnalyticsRepository()
        let viewModel = AppLifecycleViewModel(
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true),
            syncProtectionUseCase: makeSyncProtectionUseCase(),
            shieldRepository: FakeShieldRepository(),
            analyticsRepository: analyticsRepo
        )

        viewModel.appDidBecomeActive()

        #expect(analyticsRepo.userProperties["primary_rule_kind"] == "dailyLimit")
        #expect(analyticsRepo.userProperties["active_group_count"] == "count_2_3")
        #expect(analyticsRepo.userProperties["uses_daily"] == "true")
        #expect(analyticsRepo.userProperties["uses_cooldown"] == "true")
        #expect(analyticsRepo.userProperties["uses_timewindow"] == "false")

        SharedStore.clearGroupStateForTesting()
    }

    @Test func doesNotSetCohortUserPropertiesWhenUnauthorized() {
        let analyticsRepo = FakeAnalyticsRepository()
        let viewModel = AppLifecycleViewModel(
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: false),
            syncProtectionUseCase: makeSyncProtectionUseCase(),
            shieldRepository: FakeShieldRepository(),
            analyticsRepository: analyticsRepo
        )

        viewModel.appDidBecomeActive()

        #expect(analyticsRepo.userProperties.isEmpty)
    }

    @Test func clearsDeliveredNotificationsOnActivation() {
        let notifRepo = FakeNotificationRepository()
        let viewModel = AppLifecycleViewModel(
            authorizeUseCase: makeAuthorizeUseCase(),
            syncProtectionUseCase: makeSyncProtectionUseCase(),
            shieldRepository: FakeShieldRepository(),
            notificationRepository: notifRepo,
            analyticsRepository: FakeAnalyticsRepository()
        )

        viewModel.appDidBecomeActive()

        #expect(notifRepo.clearDeliveredCallCount == 1)
    }

    @Test func logsUnlockOptionsShownOnceWhenPendingRequest() {
        let shieldRepo = FakeShieldRepository()
        shieldRepo.pendingShieldOpenRequest = true
        shieldRepo.lockedGroupsValue = [
            SharedStore.ScreenTimeGroup(name: "SNS"),
            SharedStore.ScreenTimeGroup(name: "게임")
        ]
        let analyticsRepo = FakeAnalyticsRepository()
        let viewModel = AppLifecycleViewModel(
            authorizeUseCase: makeAuthorizeUseCase(),
            syncProtectionUseCase: makeSyncProtectionUseCase(),
            shieldRepository: shieldRepo,
            analyticsRepository: analyticsRepo
        )

        viewModel.refreshLockOptionsPresentation()
        viewModel.refreshLockOptionsPresentation()  // 재호출해도 중복 로깅 없음

        let unlockEvents = analyticsRepo.events.filter { $0.name == "unlock_options_shown" }
        #expect(unlockEvents.count == 1)
        #expect(analyticsRepo.parameters(for: "unlock_options_shown")?["locked_count"] as? Int == 2)
    }

    private func makeSyncProtectionUseCase() -> SyncProtectionUseCase {
        SyncProtectionUseCase(
            groupRepository: FakeGroupRepository(),
            screenTimeRepository: FakeScreenTimeRepository()
        )
    }

    private func makeAuthorizeUseCase(isAuthorized: Bool = false) -> AuthorizeUseCase {
        AuthorizeUseCase(
            authRepository: FakeAuthorizationRepository(isAuthorized: isAuthorized),
            notificationRepository: FakeNotificationRepository()
        )
    }
}

// MARK: - UserCohortProperties

@MainActor
struct UserCohortPropertiesTests {

    private func properties(_ groups: [SharedStore.ScreenTimeGroup]) -> [String: String?] {
        Dictionary(uniqueKeysWithValues: UserCohortProperties(groups: groups).entries.map { ($0.name, $0.value) })
    }

    @Test func emptyGroupsYieldNoneAndFalseFlags() {
        let result = properties([])

        #expect(result["primary_rule_kind"] == "none")
        #expect(result["active_group_count"] == "count_0")
        #expect(result["uses_daily"] == "false")
        #expect(result["uses_timewindow"] == "false")
        #expect(result["uses_cooldown"] == "false")
    }

    @Test func unappliedGroupsAreExcluded() {
        let result = properties([
            SharedStore.ScreenTimeGroup(name: "SNS", ruleKind: .cooldown, isApplied: false)
        ])

        #expect(result["primary_rule_kind"] == "none")
        #expect(result["active_group_count"] == "count_0")
        #expect(result["uses_cooldown"] == "false")
    }

    @Test func picksMostFrequentRuleAsPrimary() {
        let result = properties([
            SharedStore.ScreenTimeGroup(name: "a", ruleKind: .dailyLimit),
            SharedStore.ScreenTimeGroup(name: "b", ruleKind: .dailyLimit),
            SharedStore.ScreenTimeGroup(name: "c", ruleKind: .cooldown)
        ])

        #expect(result["primary_rule_kind"] == "dailyLimit")
        #expect(result["active_group_count"] == "count_2_3")
        #expect(result["uses_daily"] == "true")
        #expect(result["uses_cooldown"] == "true")
        #expect(result["uses_timewindow"] == "false")
    }

    @Test func tiedFrequencyYieldsNonePrimary() {
        let result = properties([
            SharedStore.ScreenTimeGroup(name: "a", ruleKind: .dailyLimit),
            SharedStore.ScreenTimeGroup(name: "b", ruleKind: .cooldown)
        ])

        #expect(result["primary_rule_kind"] == "none")
        #expect(result["active_group_count"] == "count_2_3")
    }

    @Test func weekdayGroupCountsDayKindsAndPrimaryWeekday() {
        // 요일별 그룹: uses* 플래그는 요일 안에서 쓰는 종류까지 포함하고(평일 쿨다운 → usesCooldown),
        // base ruleKind(폴백용 dailyLimit)는 세지 않는다. primary는 그룹당 1표로 "weekday".
        var rules = (0..<7).map { _ in SharedStore.DayRule(kind: .unrestricted) }
        for index in 1...5 {
            rules[index] = SharedStore.DayRule(kind: .cooldown, cooldownUsageMinutes: 10, cooldownDurationMinutes: 180)
        }
        let result = properties([
            SharedStore.ScreenTimeGroup(name: "SNS", ruleKind: .dailyLimit, isApplied: true, weekdayRules: rules)
        ])

        #expect(result["primary_rule_kind"] == "weekday")
        #expect(result["uses_weekday"] == "true")
        #expect(result["uses_cooldown"] == "true")
        #expect(result["uses_daily"] == "false")   // base 폴백은 미집계
        #expect(result["uses_timewindow"] == "false")
    }

    @Test func nonWeekdayGroupsReportUsesWeekdayFalse() {
        let result = properties([
            SharedStore.ScreenTimeGroup(name: "a", ruleKind: .dailyLimit)
        ])
        #expect(result["uses_weekday"] == "false")
        #expect(result["primary_rule_kind"] == "dailyLimit")
    }

    @Test func bucketsLargeGroupCount() {
        let groups = (0..<4).map {
            SharedStore.ScreenTimeGroup(name: "g\($0)", ruleKind: .timeWindows)
        }

        let result = properties(groups)

        #expect(result["active_group_count"] == "count_4_plus")
        #expect(result["primary_rule_kind"] == "timeWindows")
        #expect(result["uses_timewindow"] == "true")
    }
}

/// 요일 묶음 편집 저장 로직(applyingBundle) — 해제 요일이 '제한 없음'이 되는 계약 검증.
@MainActor
struct WeekdayBundleApplyTests {

    private let daily = SharedStore.DayRule(kind: .dailyLimit, dailyLimitMinutes: 30)
    private let cooldown = SharedStore.DayRule(kind: .cooldown, cooldownUsageMinutes: 10, cooldownDurationMinutes: 180)

    @Test func shrinkingDefaultBundleTurnsDeselectedDaysUnrestricted() {
        // 보고된 버그 시나리오: 토글 직후 기본 월~일 단일 묶음에서 토(6)·일(0)을 해제하고 저장.
        // 해제가 무동작이면 아무 변화가 없다 — 해제 요일은 '제한 없음'이 되어야 한다.
        let allDaily = Array(repeating: daily, count: 7)
        let result = RuleEditorSheet.applyingBundle(
            to: allDaily,
            selectedDays: [1, 2, 3, 4, 5],
            initialDays: [0, 1, 2, 3, 4, 5, 6],
            rule: daily
        )
        #expect(result[0].kind == .unrestricted)
        #expect(result[6].kind == .unrestricted)
        for index in 1...5 { #expect(result[index] == daily) }
    }

    @Test func addingDaysStealsFromOtherBundle() {
        // 다른 묶음의 요일을 선택에 추가하면 그 요일이 이 규칙으로 넘어온다(빼앗기).
        var rules = Array(repeating: daily, count: 7)
        rules[0] = SharedStore.DayRule(kind: .unrestricted)
        let result = RuleEditorSheet.applyingBundle(
            to: rules,
            selectedDays: [0, 6],   // 제한 없음이던 일(0) + daily였던 토(6)를 쿨다운으로
            initialDays: [6],
            rule: cooldown
        )
        #expect(result[0] == cooldown)
        #expect(result[6] == cooldown)
        for index in 1...5 { #expect(result[index] == daily) }
    }

    @Test func deselectingAllDeletesBundle() {
        // 기존 묶음의 요일을 전부 해제하고 저장 = 묶음 삭제(해당 요일 전부 제한 없음).
        var rules = Array(repeating: daily, count: 7)
        rules[0] = cooldown
        rules[6] = cooldown
        let result = RuleEditorSheet.applyingBundle(
            to: rules,
            selectedDays: [],
            initialDays: [0, 6],
            rule: cooldown
        )
        #expect(result[0].kind == .unrestricted)
        #expect(result[6].kind == .unrestricted)
        for index in 1...5 { #expect(result[index] == daily) }
    }

    @Test func newBundleOnlyWritesSelectedDays() {
        // 신규 묶음(+ 추가, initialDays 비어 있음)은 선택 요일만 덮어쓰고 나머지는 불변.
        let allDaily = Array(repeating: daily, count: 7)
        let result = RuleEditorSheet.applyingBundle(
            to: allDaily,
            selectedDays: [0, 6],
            initialDays: [],
            rule: cooldown
        )
        #expect(result[0] == cooldown)
        #expect(result[6] == cooldown)
        for index in 1...5 { #expect(result[index] == daily) }
    }

    @Test func applyingExplicitUnrestrictedMarksSelectedExplicitAndDeselectedImplicit() {
        // 편집 화면에서 '제한 없음'(explicit)을 골라 저장: 선택 요일은 explicit, 이 묶음에서 해제된 요일은 implicit 강등.
        let explicitUnrestricted = SharedStore.DayRule(kind: .unrestricted, isExplicitlyUnrestricted: true)
        let allDaily = Array(repeating: daily, count: 7)
        let result = RuleEditorSheet.applyingBundle(
            to: allDaily,
            selectedDays: [0],
            initialDays: [0, 6],
            rule: explicitUnrestricted
        )
        #expect(result[0] == explicitUnrestricted)          // 선택 요일 = explicit(행 생성 대상)
        #expect(result[0].isExplicitlyUnrestricted)
        #expect(result[6].kind == .unrestricted)            // 해제 요일 = implicit(행 미생성)
        #expect(!result[6].isExplicitlyUnrestricted)
        for index in 1...5 { #expect(result[index] == daily) }
    }
}

/// 요일 규칙 편집 시드·표시·탭 분기(seededWeekdayRules/visibleBundles/tapEditTarget) — implicit/explicit '제한 없음' 구분.
@MainActor
struct WeekdayRuleEditorTests {

    private let daily = SharedStore.DayRule(kind: .dailyLimit, dailyLimitMinutes: 30)
    private let cooldown = SharedStore.DayRule(kind: .cooldown, cooldownUsageMinutes: 10, cooldownDurationMinutes: 180)
    private let explicitUnrestricted = SharedStore.DayRule(kind: .unrestricted, isExplicitlyUnrestricted: true)
    private let implicitUnrestricted = SharedStore.DayRule(kind: .unrestricted)

    /// 일요일 시작 표시 순서(0=일 … 6=토).
    private let sundayFirst = [0, 1, 2, 3, 4, 5, 6]

    // MARK: - seededWeekdayRules

    @Test func seedForDraftGroupIsSevenImplicitUnrestricted() {
        // 신규(draft) 그룹(currentKind == nil) → 7일 전부 암묵적 '제한 없음'(행 0개로 시작).
        let seeded = RuleEditorSheet.seededWeekdayRules(currentKind: nil, base: daily)
        #expect(seeded.count == 7)
        #expect(seeded.allSatisfy { $0.kind == .unrestricted && !$0.isExplicitlyUnrestricted })
    }

    @Test func seedForExistingGroupIsSevenBaseCopies() {
        // 기존 규칙 그룹(currentKind non-nil) → base 규칙 × 7(파라미터 보존).
        let seeded = RuleEditorSheet.seededWeekdayRules(currentKind: .dailyLimit, base: daily)
        #expect(seeded.count == 7)
        #expect(seeded.allSatisfy { $0 == daily })
    }

    // MARK: - visibleBundles

    @Test func visibleBundlesSkipImplicitUnrestricted() {
        // 암묵적 '제한 없음'은 행을 만들지 않는다 → 7일 전부 implicit면 행 0개.
        let rules = Array(repeating: implicitUnrestricted, count: 7)
        #expect(RuleEditorSheet.visibleBundles(from: rules, orderedIndices: sundayFirst).isEmpty)
    }

    @Test func visibleBundlesShowExplicitUnrestrictedRow() {
        // explicit '제한 없음'은 행이 된다(유일 값이라 explicit 요일들은 한 행으로 병합).
        var rules = Array(repeating: implicitUnrestricted, count: 7)
        rules[1] = explicitUnrestricted
        rules[3] = explicitUnrestricted
        let bundles = RuleEditorSheet.visibleBundles(from: rules, orderedIndices: sundayFirst)
        #expect(bundles.count == 1)
        #expect(bundles[0].days == [1, 3])
        #expect(bundles[0].rule == explicitUnrestricted)
    }

    @Test func visibleBundlesMixExplicitRestrictedAndSkipImplicit() {
        // 혼합: implicit(0,3,4) skip, daily 1행(1,2), cooldown 1행(5), explicit 1행(6).
        var rules = Array(repeating: implicitUnrestricted, count: 7)
        rules[1] = daily
        rules[2] = daily
        rules[5] = cooldown
        rules[6] = explicitUnrestricted
        let bundles = RuleEditorSheet.visibleBundles(from: rules, orderedIndices: sundayFirst)
        #expect(bundles.count == 3)
        #expect(bundles.contains { $0.rule == daily && $0.days == [1, 2] })
        #expect(bundles.contains { $0.rule == cooldown && $0.days == [5] })
        #expect(bundles.contains { $0.rule == explicitUnrestricted && $0.days == [6] })
    }

    // MARK: - tapEditTarget

    @Test func tapImplicitUnrestrictedSelectsSingleDay() {
        // 암묵적 '제한 없음' 요일 탭 → 그 하루만 선택 + '제한 없음' 규칙으로 편집 진입.
        var rules = Array(repeating: daily, count: 7)
        rules[3] = implicitUnrestricted
        let target = RuleEditorSheet.tapEditTarget(day: 3, in: rules)
        #expect(target?.days == [3])
        #expect(target?.rule.kind == .unrestricted)
    }

    @Test func tapExplicitUnrestrictedSelectsSingleDay() {
        // explicit '제한 없음' 요일 탭도 그 하루만 선택해 진입한다(같은 값의 다른 요일 비포함).
        var rules = Array(repeating: implicitUnrestricted, count: 7)
        rules[1] = explicitUnrestricted
        rules[4] = explicitUnrestricted
        let target = RuleEditorSheet.tapEditTarget(day: 1, in: rules)
        #expect(target?.days == [1])
        #expect(target?.rule == explicitUnrestricted)
    }

    @Test func tapRestrictedDaySelectsSingleDayWithItsRule() {
        // 제한 요일 탭 → 같은 규칙을 공유하는 다른 요일이 있어도 그 하루만 선택 + 현재 규칙 유지
        // (여러 요일 일괄 변경은 요일 그룹 행 진입이 담당).
        var rules = Array(repeating: daily, count: 7)
        rules[0] = cooldown
        rules[6] = cooldown
        let target = RuleEditorSheet.tapEditTarget(day: 6, in: rules)
        #expect(target?.days == [6])
        #expect(target?.rule == cooldown)
    }

    @Test func tapOutOfRangeReturnsNil() {
        let rules = Array(repeating: daily, count: 7)
        #expect(RuleEditorSheet.tapEditTarget(day: 7, in: rules) == nil)
        #expect(RuleEditorSheet.tapEditTarget(day: -1, in: rules) == nil)
    }
}

/// 주간 스트립 — 규칙 종류 아이콘 매핑 검증(요일 탭 진입 분기는 WeekdayRuleEditorTests의 tapEditTarget).
@MainActor
struct WeekdayRuleStripTests {

    @Test func stripIconNamesMatchRuleKinds() {
        // 규칙 3종 아이콘은 규칙 선택 행(ruleRow)과 동일해야 시각 언어가 이어진다.
        #expect(RuleEditorSheet.stripIconName(for: .unrestricted) == "minus")
        #expect(RuleEditorSheet.stripIconName(for: .dailyLimit) == "timer")
        #expect(RuleEditorSheet.stripIconName(for: .timeWindows) == "clock.badge.xmark")
        #expect(RuleEditorSheet.stripIconName(for: .cooldown) == "cup.and.saucer.fill")
    }
}

// MARK: - Fake Repositories

private enum TestAuthorizationError: Error {
    case denied
}

private enum TestScreenTimeError: Error {
    case failed
}

@MainActor
private final class FakeAnalyticsRepository: AnalyticsRepository {
    private(set) var events: [AnalyticsEvent] = []
    private(set) var userProperties: [String: String?] = [:]

    func log(_ event: AnalyticsEvent) {
        events.append(event)
    }

    func setUserProperty(_ value: String?, for name: String) {
        userProperties[name] = value
    }

    func recordError(_ error: Error, context: String) {}

    func parameters(for eventName: String) -> [String: Any]? {
        events.first { $0.name == eventName }?.parameters
    }
}

@MainActor
private final class FakeGroupRepository: GroupRepository {
    var screenTimeGroups: [ScreenTimeGroup] = []
    var isStrictLockEnabled: Bool = false

    func defaultGroupName(for index: Int) -> String {
        "그룹 \(index + 1)"
    }
}

@MainActor
private final class FakeShieldRepository: ShieldRepository {
    var isShieldActive = false
    var currentShieldOverrideUntil: Date?
    var overrideUntilByGroupID: [UUID: Date] = [:]
    var usedTimeByGroupID: [UUID: Int] = [:]
    var overrideBaselineUsedTimeByGroupID: [UUID: Int] = [:]
    var overrideGrantedMinutesByGroupID: [UUID: Int] = [:]
    var cooldownEndByGroupID: [UUID: Date] = [:]
    var oneMinuteRemainingValue = 5
    var oneMinuteRemaining: Int { oneMinuteRemainingValue }
    var lastRequestedUnlockApplicationToken: ApplicationToken?
    var lastRequestedUnlockWebDomainToken: WebDomainToken?
    var lockedGroupsValue: [ScreenTimeGroup] = []
    var groupsInOverrideValue: [ScreenTimeGroup] = []
    var pendingShieldOpenRequest = false
    private(set) var recordWalkAwayCallCount = 0

    func lockedGroups() -> [ScreenTimeGroup] { lockedGroupsValue }
    func lockedGroups(containing token: ApplicationToken) -> [ScreenTimeGroup] { lockedGroupsValue }
    func lockedGroups(containing token: WebDomainToken) -> [ScreenTimeGroup] { lockedGroupsValue }
    func groupsInOverride() -> [ScreenTimeGroup] { groupsInOverrideValue }
    func hasPendingShieldOpenRequest() -> Bool { pendingShieldOpenRequest }
    func clearLastRequestedUnlockTokens() {
        lastRequestedUnlockApplicationToken = nil
        lastRequestedUnlockWebDomainToken = nil
    }
    func clearShieldOpenRequest() { pendingShieldOpenRequest = false }
    func recordWalkAway() { recordWalkAwayCallCount += 1 }
}

@MainActor
private final class FakeStatsRepository: StatsRepository {
    var todayStats = DailyStats(dateKey: "2026-05-18")
    var weeklyStatsValue: [DailyStats] = Array(repeating: DailyStats(dateKey: "2026-05-18"), count: 7)
    var previousWeekStatsValue: [DailyStats] = Array(repeating: DailyStats(dateKey: "2026-05-11"), count: 7)
    var nDayStatsValue: [DailyStats] = []
    var oldestStatDateValue: Date?

    func lastSevenDayStats() -> [DailyStats] { weeklyStatsValue }
    func previousSevenDayStats() -> [DailyStats] { previousWeekStatsValue }
    func lastNDayStats(_ n: Int) -> [DailyStats] { Array(nDayStatsValue.prefix(n)) }
    func statsForCalendarWeek(weekOffset: Int) -> [DailyStats] {
        weekOffset == 0 ? weeklyStatsValue : previousWeekStatsValue
    }
    func statsForCalendarMonth(monthOffset: Int) -> [DailyStats] { nDayStatsValue }
    func calendarWeekRange(weekOffset: Int) -> (start: Date, end: Date)? { nil }
    func calendarMonthRange(monthOffset: Int) -> (start: Date, end: Date)? { nil }
    func allDailyStats() -> [DailyStats] { weeklyStatsValue + previousWeekStatsValue }
    var oldestStatDate: Date? { oldestStatDateValue }
    var trackingStartDateValue: Date?
    var trackingStartDate: Date? {
        [trackingStartDateValue, oldestStatDateValue].compactMap { $0 }.min()
    }
}

@MainActor
private final class FakeScreenTimeRepository: ScreenTimeRepository {
    var isDailyMonitoringEnabled = false
    var syncCallCount = 0
    var extendCallCount = 0
    var lastExtensionSource: ExtensionSource?
    var syncError: Error?
    var extendResult: Result<GroupExtensionResult, ExtensionFailure>?
    var extendResults: [Result<GroupExtensionResult, ExtensionFailure>] = []
    var nearMidnightCutoff = false
    var nearMidnightNoticeWindow = false
    var monitoredIDs: Set<UUID> = []
    var validGroupsOverride: [ScreenTimeGroup]?

    func rolloverCounterIfNeeded() {}

    @discardableResult
    func reapplyShieldIfOverrideExpired() -> Bool { false }

    func syncDailyMonitoring(groups: [ScreenTimeGroup]) throws {
        syncCallCount += 1
        if let syncError { throw syncError }
    }

    func reconnectMonitoring() throws {}

    func monitoredGroupIDs() -> Set<UUID> { monitoredIDs }

    func validDailyMonitoringGroups(from groups: [ScreenTimeGroup]) -> [ScreenTimeGroup] {
        if let validGroupsOverride { return validGroupsOverride }
        return groups.filter { $0.selectionCount > 0 && $0.dailyLimitMinutes >= 0 }
    }

    func extendGroup(
        groupID: UUID,
        duration seconds: Int,
        source: ExtensionSource
    ) -> Result<GroupExtensionResult, ExtensionFailure> {
        extendCallCount += 1
        lastExtensionSource = source
        if !extendResults.isEmpty {
            return extendResults.removeFirst()
        }
        return extendResult ?? .failure(.groupNotFound)
    }

    func isNearMidnightOverrideCutoff(now: Date) -> Bool { nearMidnightCutoff }

    func isWithinNearMidnightNoticeWindow(now: Date) -> Bool {
        nearMidnightCutoff || nearMidnightNoticeWindow
    }
}

@MainActor
private final class FakeAuthorizationRepository: AuthorizationRepository {
    var isAuthorized: Bool
    var requestResultIsAuthorized: Bool
    var requestError: Error?
    private(set) var requestCallCount = 0
    private var authorizationChangeHandlers: [UUID: AuthorizationChangeHandler] = [:]

    init(isAuthorized: Bool) {
        self.isAuthorized = isAuthorized
        requestResultIsAuthorized = isAuthorized
    }

    func refresh() {}

    func request() async throws {
        requestCallCount += 1
        if let requestError {
            throw requestError
        }
        setAuthorized(requestResultIsAuthorized)
    }

    func observeAuthorizationChanges(_ handler: @escaping AuthorizationChangeHandler) -> AuthorizationObservation {
        let id = UUID()
        authorizationChangeHandlers[id] = handler
        handler(isAuthorized)
        return AuthorizationObservation { }
    }

    func setAuthorized(_ isAuthorized: Bool) {
        self.isAuthorized = isAuthorized
        for handler in authorizationChangeHandlers.values {
            handler(isAuthorized)
        }
    }
}

@MainActor
private final class FakeNotificationRepository: NotificationRepository {
    var authorizationStateValue: NotificationPermissionState = .notDetermined
    var requestAuthorizationResult: NotificationPermissionState = .authorized
    private(set) var authorizationStateCallCount = 0
    private(set) var requestCallCount = 0

    func authorizationState() async -> NotificationPermissionState {
        authorizationStateCallCount += 1
        return authorizationStateValue
    }

    func requestAuthorizationIfNeeded() async -> NotificationPermissionState {
        requestCallCount += 1
        authorizationStateValue = requestAuthorizationResult
        return requestAuthorizationResult
    }

    var isDeferredByScheduledSummary = false

    func isNotificationDeferredByScheduledSummary() async -> Bool {
        isDeferredByScheduledSummary
    }

    func scheduleWeeklyStatsNotification(weekStartDay: Int) {}

    func scheduleDailyMorningNotification(extraMinutes: Int) {}

    var isDailyMorningNotificationEnabled = true
    private(set) var setDailyMorningEnabledCalls: [Bool] = []

    func setDailyMorningNotificationEnabled(_ enabled: Bool) {
        isDailyMorningNotificationEnabled = enabled
        setDailyMorningEnabledCalls.append(enabled)
    }

    var isUsageAlertEnabled = true
    private(set) var setUsageAlertEnabledCalls: [Bool] = []

    func setUsageAlertEnabled(_ enabled: Bool) {
        isUsageAlertEnabled = enabled
        setUsageAlertEnabledCalls.append(enabled)
    }

    private(set) var clearDeliveredCallCount = 0

    func clearDeliveredNotifications() {
        clearDeliveredCallCount += 1
    }
}

@MainActor
private final class FakeAdRepository: AdRepository {
    var loadStateValue: AdLoadState
    var shouldEarnReward = true
    private(set) var loadCallPlacements: [RewardedAdPlacement] = []
    private(set) var presentCallPlacements: [RewardedAdPlacement] = []
    var loadCallCount: Int { loadCallPlacements.count }
    var presentCallCount: Int { presentCallPlacements.count }

    init(loadState: AdLoadState) {
        self.loadStateValue = loadState
    }

    func loadState(for placement: RewardedAdPlacement) -> AdLoadState {
        loadStateValue
    }

    func loadAd(for placement: RewardedAdPlacement) {
        loadCallPlacements.append(placement)
    }

    func present(
        from viewController: UIViewController,
        placement: RewardedAdPlacement,
        onDismissed: @escaping (Bool) -> Void
    ) {
        presentCallPlacements.append(placement)
        onDismissed(shouldEarnReward)
    }
}
