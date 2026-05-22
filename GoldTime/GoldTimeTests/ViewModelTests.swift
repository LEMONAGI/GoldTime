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
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true)
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
            )
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
            )
        )
        try await Task.sleep(for: .milliseconds(10))

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
            )
        )
        try await Task.sleep(for: .milliseconds(10))

        #expect(viewModel.isAuthorized)
        #expect(viewModel.isNotificationAuthorized)
        #expect(viewModel.isFullyAuthorized)
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
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true)
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
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true)
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
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true)
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
            authorizeUseCase: makeAuthorizeUseCase(isAuthorized: true)
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
        #expect(notices == ["웹 사이트는 사파리에서 사용하는 것만 가능해요."])
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
        #expect(warnings[0].contains("앱과 웹 사이트를 합쳐"))
        #expect(warnings[0].contains("10/9"))
    }

    @Test func homeViewModelDescribesShieldAndOverrideStates() {
        let lockedGroup = SharedStore.ScreenTimeGroup(name: "게임")
        let viewModel = HomeViewModel(
            groups: [lockedGroup],
            todayStats: SharedStore.DailyStats(dateKey: "2026-05-18"),
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

    // MARK: - StatsViewModel

    private func makeWeeklyStats(
        adUnlockedSecondsPerDay: [Int] = Array(repeating: 0, count: 7)
    ) -> [SharedStore.DailyStats] {
        let baseDate = Calendar.current.date(
            byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date())
        )!
        return (0..<7).map { offset in
            let date = Calendar.current.date(byAdding: .day, value: offset, to: baseDate)!
            let key = SharedStore.dateKey(for: date)
            return SharedStore.DailyStats(
                dateKey: key,
                adUnlockedSeconds: adUnlockedSecondsPerDay[offset]
            )
        }
    }

    @Test func statsViewModelTodayDeltaCaptionLess() {
        let weekly = makeWeeklyStats(adUnlockedSecondsPerDay: [0, 0, 0, 0, 0, 600, 0])
        let viewModel = StatsViewModel(
            groups: [],
            todayStats: SharedStore.DailyStats(dateKey: weekly[6].dateKey, adUnlockedSeconds: 300),
            weeklyStats: weekly,
            previousWeekStats: Array(repeating: SharedStore.DailyStats(dateKey: ""), count: 7),
            oneMinuteRemaining: 3,
            isMonitoring: true,
            adFreeStreakDays: 0
        )

        #expect(viewModel.yesterdayAdUnlockedSeconds == 600)
        #expect(viewModel.todayDeltaCaption == "어제보다 5분 적어요")
    }

    @Test func statsViewModelTodayDeltaCaptionMore() {
        let weekly = makeWeeklyStats(adUnlockedSecondsPerDay: [0, 0, 0, 0, 0, 300, 0])
        let viewModel = StatsViewModel(
            groups: [],
            todayStats: SharedStore.DailyStats(dateKey: weekly[6].dateKey, adUnlockedSeconds: 600),
            weeklyStats: weekly,
            previousWeekStats: Array(repeating: SharedStore.DailyStats(dateKey: ""), count: 7),
            oneMinuteRemaining: 3,
            isMonitoring: true,
            adFreeStreakDays: 0
        )

        #expect(viewModel.todayDeltaCaption == "어제보다 5분 많아요")
    }

    @Test func statsViewModelTodayDeltaCaptionNoneYesterday() {
        let weekly = makeWeeklyStats(adUnlockedSecondsPerDay: [0, 0, 0, 0, 0, 0, 0])
        let viewModel = StatsViewModel(
            groups: [],
            todayStats: SharedStore.DailyStats(dateKey: weekly[6].dateKey, adUnlockedSeconds: 0),
            weeklyStats: weekly,
            previousWeekStats: Array(repeating: SharedStore.DailyStats(dateKey: ""), count: 7),
            oneMinuteRemaining: 5,
            isMonitoring: false,
            adFreeStreakDays: 0
        )

        #expect(viewModel.todayDeltaCaption == "어제도 오늘도 없어요")
    }

    @Test func statsViewModelWeeklyDeltaCaptionLess() {
        let thisWeek = makeWeeklyStats(adUnlockedSecondsPerDay: [0, 0, 0, 600, 600, 0, 0])
        let prevWeek = makeWeeklyStats(adUnlockedSecondsPerDay: [600, 600, 600, 600, 600, 600, 0])
        let viewModel = StatsViewModel(
            groups: [],
            todayStats: SharedStore.DailyStats(dateKey: thisWeek[6].dateKey),
            weeklyStats: thisWeek,
            previousWeekStats: prevWeek,
            oneMinuteRemaining: 5,
            isMonitoring: true,
            adFreeStreakDays: 0
        )

        // thisWeek total = 1200s, prevWeek total = 3600s → delta = -2400s = -40분
        #expect(viewModel.weeklyAdUnlockedSeconds == 1200)
        #expect(viewModel.previousWeekAdUnlockedSeconds == 3600)
        #expect(viewModel.weeklyDeltaCaption == "지난 주보다 40분 적어요")
    }

    @Test func statsViewModelWeeklyDeltaCaptionNoPrevData() {
        let viewModel = StatsViewModel(
            groups: [],
            todayStats: SharedStore.DailyStats(dateKey: "2026-05-20"),
            weeklyStats: makeWeeklyStats(),
            previousWeekStats: Array(repeating: SharedStore.DailyStats(dateKey: ""), count: 7),
            oneMinuteRemaining: 5,
            isMonitoring: true,
            adFreeStreakDays: 0
        )

        #expect(viewModel.weeklyDeltaCaption == "지난 주 기록 없음")
    }

    // MARK: - LoadDashboardUseCase streak

    @Test func adFreeStreakIsZeroWhenOldestStatDateNil() {
        let statsRepo = FakeStatsRepository()
        statsRepo.oldestStatDateValue = nil
        let useCase = LoadDashboardUseCase(
            shieldRepository: FakeShieldRepository(),
            statsRepository: statsRepo,
            screenTimeRepository: FakeScreenTimeRepository()
        )

        #expect(useCase.calculateAdFreeStreak() == 0)
    }

    @Test func adFreeStreakIsZeroWhenTodayHasAd() {
        let statsRepo = FakeStatsRepository()
        let today = Calendar.current.startOfDay(for: Date())
        statsRepo.oldestStatDateValue = today
        statsRepo.nDayStatsValue = [
            SharedStore.DailyStats(dateKey: SharedStore.dateKey(for: today), adWatchCount: 1)
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
            SharedStore.DailyStats(dateKey: SharedStore.dateKey(for: threeDaysAgo), adWatchCount: 2),
            SharedStore.DailyStats(dateKey: SharedStore.dateKey(for: calendar.date(byAdding: .day, value: -2, to: today)!), adWatchCount: 0),
            SharedStore.DailyStats(dateKey: SharedStore.dateKey(for: calendar.date(byAdding: .day, value: -1, to: today)!), adWatchCount: 0),
            SharedStore.DailyStats(dateKey: SharedStore.dateKey(for: today), adWatchCount: 0)
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
            SharedStore.DailyStats(dateKey: SharedStore.dateKey(for: fourDaysAgo), adWatchCount: 0),
            SharedStore.DailyStats(dateKey: SharedStore.dateKey(for: calendar.date(byAdding: .day, value: -3, to: today)!), adWatchCount: 0),
            SharedStore.DailyStats(dateKey: SharedStore.dateKey(for: twoDaysAgo), adWatchCount: 0),
            SharedStore.DailyStats(dateKey: SharedStore.dateKey(for: calendar.date(byAdding: .day, value: -1, to: today)!), adWatchCount: 0),
            SharedStore.DailyStats(dateKey: SharedStore.dateKey(for: today), adWatchCount: 0)
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

    @Test func onboardingViewModelNotificationApprovalMovesToCompletionStep() async {
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
        #expect(viewModel.currentStep == .completion)
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
    var todayStats = SharedStore.DailyStats(dateKey: "2026-05-18")
    var weeklyStatsValue: [DailyStats] = Array(repeating: SharedStore.DailyStats(dateKey: "2026-05-18"), count: 7)
    var previousWeekStatsValue: [DailyStats] = Array(repeating: SharedStore.DailyStats(dateKey: "2026-05-11"), count: 7)
    var nDayStatsValue: [DailyStats] = []
    var oldestStatDateValue: Date?

    func lastSevenDayStats() -> [DailyStats] { weeklyStatsValue }
    func previousSevenDayStats() -> [DailyStats] { previousWeekStatsValue }
    func lastNDayStats(_ n: Int) -> [DailyStats] { Array(nDayStatsValue.prefix(n)) }
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
    private(set) var requestCallCount = 0
    private var authorizationChangeHandlers: [UUID: AuthorizationChangeHandler] = [:]

    init(isAuthorized: Bool) {
        self.isAuthorized = isAuthorized
        requestResultIsAuthorized = isAuthorized
    }

    func refresh() {}

    func request() async throws {
        requestCallCount += 1
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
