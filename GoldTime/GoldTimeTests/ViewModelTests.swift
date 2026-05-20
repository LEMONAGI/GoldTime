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

    @Test func statsViewModelCalculatesWeeklySummary() {
        let weeklyStats = [
            SharedStore.DailyStats(dateKey: "2026-05-12", walkAwayCount: 1),
            SharedStore.DailyStats(dateKey: "2026-05-13", walkAwayCount: 0),
            SharedStore.DailyStats(dateKey: "2026-05-14", walkAwayCount: 3)
        ]
        let viewModel = StatsViewModel(
            groups: [SharedStore.ScreenTimeGroup(name: "SNS", dailyLimitMinutes: 45)],
            todayStats: SharedStore.DailyStats(dateKey: "2026-05-18"),
            weeklyStats: weeklyStats,
            oneMinuteRemaining: 2,
            isMonitoring: true
        )

        #expect(viewModel.groupLimitValue == "45분")
        #expect(viewModel.weeklyWalkAwayCount == 4)
        #expect(viewModel.hasWeeklyWalkAway)
        #expect(viewModel.protectionGroupCaption == "유효 그룹 자동 적용")
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

    @Test func onboardingViewModelRequestsNotificationAfterAuthorization() async {
        let authRepo = FakeAuthorizationRepository(isAuthorized: false)
        authRepo.requestResultIsAuthorized = true
        let notifRepo = FakeNotificationRepository()
        var didAuthorize = false
        let viewModel = OnboardingViewModel(
            authorizeUseCase: AuthorizeUseCase(
                authRepository: authRepo,
                notificationRepository: notifRepo
            ),
            onAuthorized: { didAuthorize = true }
        )

        await viewModel.requestAuthorization()

        #expect(authRepo.requestCallCount == 1)
        #expect(notifRepo.requestCallCount == 1)
        #expect(didAuthorize)
        #expect(viewModel.errorMessage == nil)
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
    var lockedGroupsValue: [ScreenTimeGroup] = []
    var groupsInOverrideValue: [ScreenTimeGroup] = []
    var pendingShieldOpenRequest = false
    private(set) var recordWalkAwayCallCount = 0

    func lockedGroups() -> [ScreenTimeGroup] { lockedGroupsValue }
    func lockedGroups(containing token: ApplicationToken) -> [ScreenTimeGroup] { lockedGroupsValue }
    func groupsInOverride() -> [ScreenTimeGroup] { groupsInOverrideValue }
    func hasPendingShieldOpenRequest() -> Bool { pendingShieldOpenRequest }
    func clearLastRequestedUnlockApplicationToken() { lastRequestedUnlockApplicationToken = nil }
    func clearShieldOpenRequest() { pendingShieldOpenRequest = false }
    func recordWalkAway() { recordWalkAwayCallCount += 1 }
}

@MainActor
private final class FakeStatsRepository: StatsRepository {
    var todayStats = SharedStore.DailyStats(dateKey: "2026-05-18")
    var weeklyStatsValue: [DailyStats] = []

    func lastSevenDayStats() -> [DailyStats] { weeklyStatsValue }
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

    func resetProtectionState() throws {}

    func validDailyMonitoringGroups(from groups: [ScreenTimeGroup]) -> [ScreenTimeGroup] {
        groups.filter { !$0.selection.applicationTokens.isEmpty || $0.dailyLimitMinutes >= 0 }
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
    private(set) var requestCallCount = 0

    func requestAuthorizationIfNeeded() async {
        requestCallCount += 1
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
