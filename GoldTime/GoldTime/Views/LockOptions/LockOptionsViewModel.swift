//
//  LockOptionsViewModel.swift
//  GoldTime
//

import Foundation
import ManagedSettings

struct LockOptionsCompletionAlert: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String

    static func == (lhs: LockOptionsCompletionAlert, rhs: LockOptionsCompletionAlert) -> Bool {
        lhs.title == rhs.title && lhs.message == rhs.message
    }
}

@MainActor
@Observable
final class LockOptionsViewModel {
    var oneMinuteRemaining: Int
    var isRewardedAdPresented = false
    var infoMessage: String?
    var completionAlert: LockOptionsCompletionAlert?
    var lockedGroups: [SharedStore.ScreenTimeGroup] = []
    var selectedGroupID: UUID?
    var headerMessage = ""

    private var requestedApplicationToken: ApplicationToken?
    private var pendingAdRewardGroupID: UUID?
    private var isExtending = false
    private var store: any GoldTimeStoreProviding
    private let screenTimeManager: any ScreenTimeManaging

    private let shieldMessages = [
        "오늘 한도 다 썼어요.",
        "지금 나가면 광고는 없어요.",
        "더 쓰려면 광고가 필요해요.",
        "광고 없이 나가는 방법도 있어요.",
        "멈추거나, 광고를 보거나."
    ]

    init(
        store: (any GoldTimeStoreProviding)? = nil,
        screenTimeManager: (any ScreenTimeManaging)? = nil
    ) {
        let resolvedStore = store ?? GoldTimeStoreAdapter()
        self.store = resolvedStore
        self.screenTimeManager = screenTimeManager ?? ScreenTimeManagerAdapter()
        oneMinuteRemaining = resolvedStore.oneMinuteRemaining
    }

    var selectedGroup: SharedStore.ScreenTimeGroup? {
        guard let selectedGroupID else {
            return nil
        }
        return lockedGroups.first { $0.id == selectedGroupID }
    }

    var selectedGroupName: String? {
        selectedGroup?.displayName
    }

    var canExtendOneMinute: Bool {
        selectedGroup != nil && oneMinuteRemaining > 0 && !isExtending
    }

    var canExtendWithAd: Bool {
        selectedGroup != nil && !isExtending
    }

    var maxAppsPerGroup: Int {
        SharedStore.maxAppsPerGroup
    }

    func onAppear() {
        headerMessage = shieldMessages.randomElement() ?? "오늘 한도를 다 썼어요."
        refreshLockedGroups()
    }

    func selectGroup(_ id: UUID) {
        selectedGroupID = id
        infoMessage = nil
    }

    func tapWalkAway() -> Bool {
        if !lockedGroups.isEmpty {
            store.recordWalkAway()
        }
        return true
    }

    func tapOneMinute() {
        guard canExtendOneMinute else {
            infoMessage = "풀 그룹을 먼저 고르거나, 광고를 보거나, 잠금을 유지할 수 있어요."
            return
        }
        guard let groupID = selectedGroupID else {
            infoMessage = "풀 그룹을 먼저 골라주세요."
            return
        }
        extendGroup(groupID: groupID, seconds: 60, source: .oneMinute)
    }

    func startAdFlow() {
        guard let groupID = selectedGroupID else {
            infoMessage = "풀 그룹을 먼저 골라주세요."
            return
        }
        pendingAdRewardGroupID = groupID
        isRewardedAdPresented = true
    }

    func rewardedAdDidComplete() {
        isRewardedAdPresented = false
    }

    func rewardedAdDidCancel() {
        pendingAdRewardGroupID = nil
        isRewardedAdPresented = false
    }

    func rewardedAdDismissed() {
        guard let groupID = pendingAdRewardGroupID else { return }
        pendingAdRewardGroupID = nil
        extendGroup(groupID: groupID, seconds: 15 * 60, source: .adReward)
    }

    private func refreshLockedGroups() {
        screenTimeManager.reapplyShieldIfOverrideExpired()
        let token = store.lastRequestedUnlockApplicationToken
        requestedApplicationToken = token

        if let token {
            lockedGroups = store.lockedGroups(containing: token)
        }

        if lockedGroups.isEmpty {
            lockedGroups = store.lockedGroups()
        }

        if lockedGroups.count == 1 {
            selectedGroupID = lockedGroups.first?.id
        } else if let selectedGroupID,
                  !lockedGroups.contains(where: { $0.id == selectedGroupID }) {
            self.selectedGroupID = nil
        }

        oneMinuteRemaining = store.oneMinuteRemaining
        store.clearLastRequestedUnlockApplicationToken()
        store.clearShieldOpenRequest()
    }

    private func extendGroup(
        groupID: UUID,
        seconds: Int,
        source: ScreenTimeManager.ExtensionSource
    ) {
        guard !isExtending else { return }
        isExtending = true
        defer { isExtending = false }

        let outcome = screenTimeManager.extendGroup(
            groupID: groupID,
            duration: seconds,
            source: source
        )

        switch outcome {
        case .success(let result):
            oneMinuteRemaining = store.oneMinuteRemaining
            updateLockedGroupsAfterExtension(result)
            completionAlert = LockOptionsCompletionAlert(
                title: "연장 완료",
                message: completionMessage(for: result)
            )
        case .failure(let failure):
            infoMessage = message(for: failure, source: source)
            oneMinuteRemaining = store.oneMinuteRemaining
        }
    }

    private func message(
        for failure: ScreenTimeManager.ExtensionFailure,
        source: ScreenTimeManager.ExtensionSource
    ) -> String {
        switch failure {
        case .groupNotFound:
            return "이 그룹을 찾지 못했어요. GoldTime에서 그룹 설정을 확인해주세요."
        case .oneMinuteLimitReached:
            return source == .oneMinute
                ? "오늘 1분 연장은 모두 사용했어요. 광고를 보거나 잠금을 유지할 수 있어요."
                : "광고 연장을 처리하지 못했어요. 잠시 뒤 다시 시도해주세요."
        }
    }

    private func updateLockedGroupsAfterExtension(_ result: ScreenTimeManager.GroupExtensionResult) {
        if let requestedApplicationToken {
            lockedGroups = store.lockedGroups(containing: requestedApplicationToken)
        } else {
            lockedGroups = result.remainingLockedGroups
        }

        if let selectedGroupID,
           !lockedGroups.contains(where: { $0.id == selectedGroupID }) {
            self.selectedGroupID = lockedGroups.first?.id
        }
    }

    private func completionMessage(for result: ScreenTimeManager.GroupExtensionResult) -> String {
        let duration = result.durationSeconds == 60 ? "1분" : "\(result.durationSeconds / 60)분"
        var message = "\(result.group.displayName)을 \(duration) 연장했어요. 방금 쓰던 앱으로 돌아가세요."

        if let token = requestedApplicationToken {
            let remainingGroups = store.lockedGroups(containing: token)
            if let remainingGroup = remainingGroups.first {
                message += "\n\(remainingGroup.displayName)는 아직 잠겨 있어요."
            }
        } else if let remainingGroup = result.remainingLockedGroups.first {
            message += "\n\(remainingGroup.displayName)는 아직 잠겨 있어요."
        }

        return message
    }
}
