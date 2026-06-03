//
//  ViewModelTests.swift
//  GoldTimeTests
//

import Foundation
import FamilyControls
import ManagedSettings
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

    @Test func contentViewModelRequestsScreenTimeOnHomeLoadForStartedUser() async throws {
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

        #expect(authRepo.requestCallCount == 1)
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

    @Test func adGateSkippedForUnlockedGroup() {
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

        #expect(!viewModel.isAdGatePresented)
        #expect(viewModel.isPickerPresented)
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

    @Test func adGateOpenedForOverrideGroupLimitChange() {
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

        viewModel.requestLimitPickerPresentation(for: group)

        #expect(viewModel.isAdGatePresented)
        #expect(viewModel.adGateFallbackLabel == "그래도 변경하기")
        #expect(!viewModel.isLimitPickerPresented)
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
        viewModel.overrideGroupIDs = [group.id]

        viewModel.requestDeleteGroup(group.id)

        #expect(viewModel.isAdGatePresented)
        #expect(viewModel.adGateFallbackLabel == "그래도 삭제하기")
    }

    @Test func regularGroupDeleteShowsCompletionAlertWithName() async {
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

    @Test func contentViewModelCommitsLimitPickerSelection() {
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

        viewModel.presentLimitPicker(for: group)
        viewModel.limitPickerHours = 1
        viewModel.limitPickerMinutes = 15
        viewModel.commitLimitPickerSelection()

        #expect(viewModel.groups.first?.dailyLimitMinutes == 75)
        #expect(groupRepo.screenTimeGroups.first?.dailyLimitMinutes == 75)
        #expect(screenTimeRepo.syncCallCount == 1)
    }

    @Test func limitPickerWarnsAndDefersWhenNewLimitBelowUsedTime() {
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
        viewModel.presentLimitPicker(for: group)
        viewModel.limitPickerHours = 0
        viewModel.limitPickerMinutes = 10
        viewModel.commitLimitPickerSelection()
        viewModel.handleLimitPickerDismiss()

        #expect(viewModel.pendingLimitLockWarning != nil)
        #expect(viewModel.pendingLimitLockWarning?.minutes == 10)
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

    @Test func limitPickerCancelKeepsOriginalLimit() {
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

        viewModel.presentLimitPicker(for: group)
        viewModel.limitPickerHours = 0
        viewModel.limitPickerMinutes = 10
        viewModel.commitLimitPickerSelection()
        viewModel.handleLimitPickerDismiss()
        viewModel.cancelLimitLockChange()

        #expect(viewModel.pendingLimitLockWarning == nil)
        #expect(viewModel.groups.first?.dailyLimitMinutes == 30)   // 그대로
        #expect(screenTimeRepo.syncCallCount == 0)
    }

    @Test func limitPickerAppliesWithoutWarningWhenAboveUsedTime() {
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
        viewModel.presentLimitPicker(for: group)
        viewModel.limitPickerHours = 0
        viewModel.limitPickerMinutes = 20
        viewModel.commitLimitPickerSelection()

        #expect(viewModel.pendingLimitLockWarning == nil)
        #expect(viewModel.groups.first?.dailyLimitMinutes == 20)
        #expect(screenTimeRepo.syncCallCount == 1)
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

        #expect(viewModel.shieldStatusValue == "잠금 중")
        #expect(viewModel.shieldStatusCaption == "한도를 넘겼어요")
        #expect(viewModel.protectionStatusTitle == "자동 적용 중")
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
                oldestStatDate: nil
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
                oldestStatDate: nil
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
                oldestStatDate: nil
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
            oldestStatDate: nil
        )

        #expect(report.yesterdayUnlockedSeconds == 2700)
        #expect(report.todayDelta == 60 - 2700)
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
                oldestStatDate: nil
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

    @Test func statsViewModelWeeklyDeltaCaptionNoPrevData() {
        let viewModel = StatsViewModel(
            groups: [],
            statsReport: StatsReport(
                todayStats: DailyStats(dateKey: "2026-05-20"),
                weeklyStats: makeWeeklyStats(),
                previousWeekStats: Array(repeating: DailyStats(dateKey: ""), count: 7),
                monthlyStats: Array(repeating: DailyStats(dateKey: ""), count: 30),
                oldestStatDate: nil
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
                oldestStatDate: nil
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
        let vm = makeComparisonVM(repo: repo)
        let today = Calendar.current.date(from: DateComponents(year: 2025, month: 6, day: 1))!

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
        let vm = makeComparisonVM(repo: repo)
        let today = Calendar.current.date(from: DateComponents(year: 2025, month: 6, day: 1))!

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
                oldestStatDate: oldest
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

    @Test func onboardingViewModelNotificationDenialStaysOnSameStep() async {
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

        #expect(viewModel.currentStep == .notificationPermission)
        #expect(viewModel.errorMessage != nil)
        #expect(!didAuthorize)
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

    @Test func rewardedAdViewModelShowsFallbackWhenLoadFails() {
        let adRepo = FakeAdRepository(loadState: .failed)
        let viewModel = RewardedAdViewModel(
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
            adRepository: adRepo,
            onComplete: { didComplete = true },
            onCancel: { didCancel = true }
        )

        viewModel.presentIfReady(from: UIViewController())
        try await Task.sleep(for: .milliseconds(10))

        #expect(adRepo.presentCallCount == 1)
        #expect(didComplete)
        #expect(!didCancel)
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

    private func makeLoadDashboardUseCase() -> LoadDashboardUseCase {
        LoadDashboardUseCase(
            shieldRepository: FakeShieldRepository(),
            statsRepository: FakeStatsRepository(),
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

    private func makeSyncProtectionUseCase() -> SyncProtectionUseCase {
        SyncProtectionUseCase(
            groupRepository: FakeGroupRepository(),
            screenTimeRepository: FakeScreenTimeRepository()
        )
    }

    private func makeAuthorizeUseCase() -> AuthorizeUseCase {
        AuthorizeUseCase(
            authRepository: FakeAuthorizationRepository(isAuthorized: false),
            notificationRepository: FakeNotificationRepository()
        )
    }
}

// MARK: - Fake Repositories

private enum TestAuthorizationError: Error {
    case denied
}

@MainActor
private final class FakeGroupRepository: GroupRepository {
    var screenTimeGroups: [ScreenTimeGroup] = []

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

    func rolloverCounterIfNeeded() {}

    @discardableResult
    func reapplyShieldIfOverrideExpired() -> Bool { false }

    func syncDailyMonitoring(groups: [ScreenTimeGroup]) throws {
        syncCallCount += 1
        if let syncError { throw syncError }
    }

    func reconnectMonitoring() throws {}

    func validDailyMonitoringGroups(from groups: [ScreenTimeGroup]) -> [ScreenTimeGroup] {
        groups.filter { $0.selectionCount > 0 && $0.dailyLimitMinutes >= 0 }
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

    func scheduleWeeklyStatsNotification(weekStartDay: Int) {}

    func scheduleDailyMorningNotification(extraMinutes: Int) {}

    var isDailyMorningNotificationEnabled = true
    private(set) var setDailyMorningEnabledCalls: [Bool] = []

    func setDailyMorningNotificationEnabled(_ enabled: Bool) {
        isDailyMorningNotificationEnabled = enabled
        setDailyMorningEnabledCalls.append(enabled)
    }
}

@MainActor
private final class FakeAdRepository: AdRepository {
    var loadState: AdLoadState
    var shouldEarnReward = true
    private(set) var loadCallCount = 0
    private(set) var presentCallCount = 0

    init(loadState: AdLoadState) {
        self.loadState = loadState
    }

    func loadAd() { loadCallCount += 1 }

    func present(
        from viewController: UIViewController,
        onDismissed: @escaping (Bool) -> Void
    ) {
        presentCallCount += 1
        onDismissed(shouldEarnReward)
    }
}
