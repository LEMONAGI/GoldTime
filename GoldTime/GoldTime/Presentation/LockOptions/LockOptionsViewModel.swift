
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
    var oneMinuteRemaining: Int = 0
    var isRewardedAdPresented = false
    var infoMessage: String?
    var completionAlert: LockOptionsCompletionAlert?
    var lockedGroups: [ScreenTimeGroup] = []
    var selectedGroupID: UUID?
    var headerMessage = ""

    private var requestedApplicationToken: ApplicationToken?
    private var pendingAdRewardGroupID: UUID?
    private var isExtending = false

    private let extendGroupUseCase: ExtendGroupUseCase

    private let shieldMessages = [
        "오늘 한도 다 썼어요.",
        "지금 나가면 광고는 없어요.",
        "더 쓰려면 광고가 필요해요.",
        "광고 없이 나가는 방법도 있어요.",
        "멈추거나, 광고를 보거나."
    ]

    init(extendGroupUseCase: ExtendGroupUseCase? = nil) {
        self.extendGroupUseCase = extendGroupUseCase ?? ExtendGroupUseCase(
            shieldRepository: ShieldRepositoryImpl(),
            screenTimeRepository: ScreenTimeRepositoryImpl()
        )
    }

    var selectedGroup: ScreenTimeGroup? {
        guard let selectedGroupID else { return nil }
        return lockedGroups.first { $0.id == selectedGroupID }
    }

    var selectedGroupName: String? { selectedGroup?.displayName }

    var canExtendOneMinute: Bool {
        selectedGroup != nil && oneMinuteRemaining > 0 && !isExtending
    }

    var canExtendWithAd: Bool {
        selectedGroup != nil && !isExtending
    }

    var maxAppsPerGroup: Int { SharedStore.maxAppsPerGroup }

    func onAppear() {
        headerMessage = shieldMessages.randomElement() ?? "오늘 한도를 다 썼어요."
        refreshLockedGroups()
    }

    func selectGroup(_ id: UUID) {
        selectedGroupID = id
        infoMessage = nil
    }

    func tapWalkAway() -> Bool {
        extendGroupUseCase.walkAway(lockedGroups: lockedGroups)
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
        extendGroup(groupID: groupID, source: .oneMinute)
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
        extendGroup(groupID: groupID, source: .adReward)
    }

    private func refreshLockedGroups() {
        let state = extendGroupUseCase.refreshState()
        requestedApplicationToken = state.requestedToken
        lockedGroups = state.lockedGroups

        if lockedGroups.count == 1 {
            selectedGroupID = lockedGroups.first?.id
        } else if let selectedGroupID,
                  !lockedGroups.contains(where: { $0.id == selectedGroupID }) {
            self.selectedGroupID = nil
        }

        oneMinuteRemaining = state.oneMinuteRemaining
    }

    private func extendGroup(groupID: UUID, source: ExtensionSource) {
        guard !isExtending else { return }
        isExtending = true
        defer { isExtending = false }

        let outcome: Result<GroupExtensionResult, ExtensionFailure>
        switch source {
        case .oneMinute:
            outcome = extendGroupUseCase.extendOneMinute(groupID: groupID)
        case .adReward:
            outcome = extendGroupUseCase.extendWithAd(groupID: groupID)
        }

        switch outcome {
        case .success(let result):
            oneMinuteRemaining = extendGroupUseCase.currentOneMinuteRemaining()
            lockedGroups = extendGroupUseCase.lockedGroupsAfterExtension(
                result: result,
                requestedToken: requestedApplicationToken
            )
            if let selectedGroupID,
               !lockedGroups.contains(where: { $0.id == selectedGroupID }) {
                self.selectedGroupID = lockedGroups.first?.id
            }
            completionAlert = LockOptionsCompletionAlert(
                title: "연장 완료",
                message: completionMessage(for: result)
            )
        case .failure(let failure):
            infoMessage = message(for: failure, source: source)
            oneMinuteRemaining = extendGroupUseCase.currentOneMinuteRemaining()
        }
    }

    private func message(for failure: ExtensionFailure, source: ExtensionSource) -> String {
        switch failure {
        case .groupNotFound:
            return "이 그룹을 찾지 못했어요. GoldTime에서 그룹 설정을 확인해주세요."
        case .oneMinuteLimitReached:
            return source == .oneMinute
                ? "오늘 1분 연장은 모두 사용했어요. 광고를 보거나 잠금을 유지할 수 있어요."
                : "광고 연장을 처리하지 못했어요. 잠시 뒤 다시 시도해주세요."
        }
    }

    private func completionMessage(for result: GroupExtensionResult) -> String {
        let duration = result.durationSeconds == 60 ? "1분" : "\(result.durationSeconds / 60)분"
        var message = "\(result.group.displayName)을 \(duration) 연장했어요. 방금 쓰던 앱으로 돌아가세요."

        if let token = requestedApplicationToken {
            let remaining = extendGroupUseCase.lockedGroupsAfterExtension(
                result: result,
                requestedToken: token
            )
            if let remainingGroup = remaining.first {
                message += "\n\(remainingGroup.displayName)는 아직 잠겨 있어요."
            }
        } else if let remainingGroup = result.remainingLockedGroups.first {
            message += "\n\(remainingGroup.displayName)는 아직 잠겨 있어요."
        }

        return message
    }
}
