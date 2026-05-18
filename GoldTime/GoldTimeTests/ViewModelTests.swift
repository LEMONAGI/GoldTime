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
    @Test func contentViewModelAddsGroupAndPersistsWithoutSync() {
        let store = FakeGoldTimeStore()
        let screenTimeManager = FakeScreenTimeManager()
        let viewModel = ContentViewModel(
            store: store,
            screenTimeManager: screenTimeManager,
            authorization: FakeAuthorization(isAuthorized: true)
        )

        viewModel.addGroup()

        #expect(viewModel.groups.count == 1)
        #expect(store.screenTimeGroups.count == 1)
        #expect(screenTimeManager.syncCallCount == 0)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func contentViewModelBlocksSixthGroup() {
        let store = FakeGoldTimeStore()
        store.screenTimeGroups = (0..<SharedStore.maxGroupCount).map {
            SharedStore.ScreenTimeGroup(name: "그룹 \($0 + 1)")
        }
        let viewModel = ContentViewModel(
            store: store,
            screenTimeManager: FakeScreenTimeManager(),
            authorization: FakeAuthorization(isAuthorized: true)
        )
        viewModel.groups = store.screenTimeGroups

        viewModel.addGroup()

        #expect(viewModel.groups.count == SharedStore.maxGroupCount)
        #expect(viewModel.alertMessage?.title == "그룹 제한")
    }

    @Test func contentViewModelCommitsLimitPickerSelection() {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "SNS", dailyLimitMinutes: 30)
        let store = FakeGoldTimeStore()
        store.screenTimeGroups = [group]
        let screenTimeManager = FakeScreenTimeManager()
        let viewModel = ContentViewModel(
            store: store,
            screenTimeManager: screenTimeManager,
            authorization: FakeAuthorization(isAuthorized: true)
        )
        viewModel.groups = [group]

        viewModel.presentLimitPicker(for: group)
        viewModel.limitPickerHours = 1
        viewModel.limitPickerMinutes = 15
        viewModel.commitLimitPickerSelection()

        #expect(viewModel.groups.first?.dailyLimitMinutes == 75)
        #expect(store.screenTimeGroups.first?.dailyLimitMinutes == 75)
        #expect(screenTimeManager.syncCallCount == 1)
    }

    @Test func homeViewModelDescribesShieldAndOverrideStates() {
        let store = FakeGoldTimeStore()
        store.lockedGroupsValue = [SharedStore.ScreenTimeGroup(name: "게임")]
        let viewModel = HomeViewModel(
            groups: store.lockedGroupsValue,
            todayStats: SharedStore.DailyStats(dateKey: "2026-05-18"),
            isMonitoring: true,
            isShieldActive: true,
            shieldOverrideUntil: nil,
            successMessage: nil,
            errorMessage: nil,
            store: store,
            screenTimeManager: FakeScreenTimeManager()
        )

        #expect(viewModel.shieldStatusValue == "잠금 중")
        #expect(viewModel.shieldStatusCaption == "한도를 넘겼어요")
        #expect(viewModel.protectionStatusTitle == "자동 적용 중")
    }

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

    @Test func lockOptionsViewModelExtendsSelectedGroupWithOneMinute() {
        let group = SharedStore.ScreenTimeGroup(id: UUID(), name: "게임")
        let store = FakeGoldTimeStore()
        store.oneMinuteRemaining = 5
        store.lockedGroupsValue = [group]
        let screenTimeManager = FakeScreenTimeManager()
        screenTimeManager.extendResult = .success(
            ScreenTimeManager.GroupExtensionResult(
                group: group,
                durationSeconds: 60,
                overrideUntil: Date().addingTimeInterval(60),
                remainingLockedGroups: []
            )
        )
        let viewModel = LockOptionsViewModel(store: store, screenTimeManager: screenTimeManager)

        viewModel.onAppear()
        viewModel.tapOneMinute()

        #expect(screenTimeManager.extendCallCount == 1)
        #expect(screenTimeManager.lastExtensionSource == .oneMinute)
        #expect(viewModel.completionAlert?.title == "연장 완료")
        #expect(viewModel.lockedGroups.isEmpty)
    }

    @Test func lockOptionsViewModelRecordsWalkAwayOnlyWhenLockedGroupExists() {
        let store = FakeGoldTimeStore()
        store.lockedGroupsValue = [SharedStore.ScreenTimeGroup(name: "SNS")]
        let viewModel = LockOptionsViewModel(store: store, screenTimeManager: FakeScreenTimeManager())

        viewModel.onAppear()
        _ = viewModel.tapWalkAway()

        #expect(store.recordWalkAwayCallCount == 1)
    }

    @Test func onboardingViewModelRequestsNotificationAfterAuthorization() async {
        let authorization = FakeAuthorization(isAuthorized: false)
        authorization.requestResultIsAuthorized = true
        let notification = FakeNotificationAuthorizer()
        var didAuthorize = false
        let viewModel = OnboardingViewModel(
            authorization: authorization,
            notificationAuthorizer: notification,
            onAuthorized: { didAuthorize = true }
        )

        await viewModel.requestAuthorization()

        #expect(authorization.requestCallCount == 1)
        #expect(notification.requestCallCount == 1)
        #expect(didAuthorize)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func rewardedAdViewModelShowsFallbackWhenLoadFails() {
        let adProvider = FakeRewardedAdProvider(loadState: .failed)
        let viewModel = RewardedAdViewModel(
            adProvider: adProvider,
            onComplete: {},
            onCancel: {}
        )

        viewModel.onAppear()

        #expect(viewModel.showFallback)
        #expect(adProvider.loadCallCount == 0)
    }

    @Test func rewardedAdViewModelCompletesWhenRewardEarned() async throws {
        let adProvider = FakeRewardedAdProvider(loadState: .ready)
        var didComplete = false
        var didCancel = false
        let viewModel = RewardedAdViewModel(
            adProvider: adProvider,
            onComplete: { didComplete = true },
            onCancel: { didCancel = true }
        )

        viewModel.presentIfReady(from: UIViewController())
        try await Task.sleep(for: .milliseconds(10))

        #expect(adProvider.presentCallCount == 1)
        #expect(didComplete)
        #expect(!didCancel)
    }
}

@MainActor
private final class FakeGoldTimeStore: GoldTimeStoreProviding {
    var screenTimeGroups: [SharedStore.ScreenTimeGroup] = []
    var isDailyMonitoringEnabled = false
    var isShieldActive = false
    var oneMinuteRemaining = 5
    var currentShieldOverrideUntil: Date?
    var todayStats = SharedStore.DailyStats(dateKey: "2026-05-18")
    var weeklyStats: [SharedStore.DailyStats] = []
    var lastRequestedUnlockApplicationToken: ApplicationToken?
    var lockedGroupsValue: [SharedStore.ScreenTimeGroup] = []
    var groupsInOverrideValue: [SharedStore.ScreenTimeGroup] = []
    var pendingShieldOpenRequest = false
    private(set) var recordWalkAwayCallCount = 0

    func lastSevenDayStats() -> [SharedStore.DailyStats] {
        weeklyStats
    }

    func lockedGroups() -> [SharedStore.ScreenTimeGroup] {
        lockedGroupsValue
    }

    func lockedGroups(containing token: ApplicationToken) -> [SharedStore.ScreenTimeGroup] {
        lockedGroupsValue
    }

    func groupsInOverride() -> [SharedStore.ScreenTimeGroup] {
        groupsInOverrideValue
    }

    func hasPendingShieldOpenRequest() -> Bool {
        pendingShieldOpenRequest
    }

    func clearLastRequestedUnlockApplicationToken() {
        lastRequestedUnlockApplicationToken = nil
    }

    func clearShieldOpenRequest() {
        pendingShieldOpenRequest = false
    }

    func recordWalkAway() {
        recordWalkAwayCallCount += 1
    }

    func defaultGroupName(for index: Int) -> String {
        "그룹 \(index + 1)"
    }
}

@MainActor
private final class FakeScreenTimeManager: ScreenTimeManaging {
    var syncCallCount = 0
    var resetCallCount = 0
    var extendCallCount = 0
    var reapplyCallCount = 0
    var lastExtensionSource: ScreenTimeManager.ExtensionSource?
    var syncError: Error?
    var resetError: Error?
    var extendResult: Result<ScreenTimeManager.GroupExtensionResult, ScreenTimeManager.ExtensionFailure>?

    func rolloverCounterIfNeeded() {}

    func reapplyShieldIfOverrideExpired() -> Bool {
        reapplyCallCount += 1
        return false
    }

    func syncDailyMonitoring(groups: [SharedStore.ScreenTimeGroup]) throws {
        syncCallCount += 1
        if let syncError {
            throw syncError
        }
    }

    func resetProtectionState() throws {
        resetCallCount += 1
        if let resetError {
            throw resetError
        }
    }

    func validDailyMonitoringGroups(
        from groups: [SharedStore.ScreenTimeGroup]
    ) -> [SharedStore.ScreenTimeGroup] {
        groups.filter { !$0.selection.applicationTokens.isEmpty || $0.dailyLimitMinutes >= 0 }
    }

    func extendGroup(
        groupID: UUID,
        duration seconds: Int,
        source: ScreenTimeManager.ExtensionSource
    ) -> Result<ScreenTimeManager.GroupExtensionResult, ScreenTimeManager.ExtensionFailure> {
        extendCallCount += 1
        lastExtensionSource = source
        if let extendResult {
            return extendResult
        }
        return .failure(.groupNotFound)
    }
}

@MainActor
private final class FakeAuthorization: AuthorizationProviding {
    var isAuthorized: Bool
    var requestResultIsAuthorized: Bool
    private(set) var refreshCallCount = 0
    private(set) var requestCallCount = 0

    init(isAuthorized: Bool) {
        self.isAuthorized = isAuthorized
        requestResultIsAuthorized = isAuthorized
    }

    func refresh() {
        refreshCallCount += 1
    }

    func request() async throws {
        requestCallCount += 1
        isAuthorized = requestResultIsAuthorized
    }
}

@MainActor
private final class FakeNotificationAuthorizer: NotificationAuthorizing {
    private(set) var requestCallCount = 0

    func requestAuthorizationIfNeeded() async {
        requestCallCount += 1
    }
}

@MainActor
private final class FakeRewardedAdProvider: RewardedAdProviding {
    var loadState: RewardedAdService.LoadState
    var shouldEarnReward = true
    private(set) var loadCallCount = 0
    private(set) var presentCallCount = 0

    init(loadState: RewardedAdService.LoadState) {
        self.loadState = loadState
    }

    func loadAd() {
        loadCallCount += 1
    }

    func present(
        from viewController: UIViewController,
        onDismissed: @escaping (_ didEarnReward: Bool) -> Void
    ) {
        presentCallCount += 1
        onDismissed(shouldEarnReward)
    }
}
