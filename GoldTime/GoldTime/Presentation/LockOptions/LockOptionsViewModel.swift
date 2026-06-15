
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
    var canRetryRelockRegistration: Bool {
        pendingRetry != nil && !isExtending
    }

    private var requestedApplicationToken: ApplicationToken?
    private var requestedWebDomainToken: WebDomainToken?
    private var cooldownEndByGroupID: [UUID: Date] = [:]
    private var pendingAdRewardGroupID: UUID?
    private var pendingRetry: (groupID: UUID, source: ExtensionSource)?
    private var retryTask: Task<Void, Never>?
    private var isExtending = false

    private let extendGroupUseCase: ExtendGroupUseCase
    private let analyticsRepository: any AnalyticsRepository
    private let relockRetryDelays: [UInt64] = [
        300_000_000,
        700_000_000,
        1_200_000_000
    ]

    private let shieldMessages = [
        "오늘 한도 다 썼어요.",
        "지금 나가면 광고는 없어요.",
        "더 쓰려면 광고가 필요해요.",
        "광고 없이 나가는 방법도 있어요.",
        "멈추거나, 광고를 보거나."
    ]

    init(
        extendGroupUseCase: ExtendGroupUseCase? = nil,
        analyticsRepository: (any AnalyticsRepository)? = nil
    ) {
        self.extendGroupUseCase = extendGroupUseCase ?? ExtendGroupUseCase(
            shieldRepository: ShieldRepositoryImpl(),
            screenTimeRepository: ScreenTimeRepositoryImpl()
        )
        self.analyticsRepository = analyticsRepository ?? AnalyticsRepositoryImpl()
    }

    var selectedGroup: ScreenTimeGroup? {
        guard let selectedGroupID else { return nil }
        return lockedGroups.first { $0.id == selectedGroupID }
    }

    var selectedGroupName: String? { selectedGroup?.displayName }

    /// 잠긴 그룹이 전부 시간대 차단 규칙이면 "한도 초과" 프레이밍이 사실과 다르다.
    private var isWindowOnlyLock: Bool {
        !lockedGroups.isEmpty && lockedGroups.allSatisfy { ($0.ruleKind ?? .dailyLimit) == .timeWindows }
    }

    /// 잠긴 그룹이 전부 쿨다운 규칙이면 "한도 초과"가 아니라 "휴식 중" 프레이밍이 맞다.
    private var isCooldownOnlyLock: Bool {
        !lockedGroups.isEmpty && lockedGroups.allSatisfy { ($0.ruleKind ?? .dailyLimit) == .cooldown }
    }

    var headerTitle: String {
        if isWindowOnlyLock { return "차단 시간대예요" }
        if isCooldownOnlyLock { return "쉬는 시간이에요" }
        return "한도 끝났어요"
    }

    /// 선택된 그룹이 시간대 차단으로 잠겨 있으면 종료 시각을 알려준다.
    var selectedWindowLockCaption: String? {
        guard let group = selectedGroup,
              (group.ruleKind ?? .dailyLimit) == .timeWindows else { return nil }
        let minute = TimeWindowPolicy.minuteOfDay(for: Date())
        guard let end = TimeWindowPolicy.activeWindowEnd(minuteOfDay: minute, windows: group.timeWindows) else {
            return nil
        }
        return "\(goldTimeClockText(minuteOfDay: end))까지 잠겨 있어요"
    }

    /// 선택된 그룹이 쿨다운으로 잠겨 있으면 휴식 종료 시각을 알려준다.
    var selectedCooldownLockCaption: String? {
        guard let group = selectedGroup,
              (group.ruleKind ?? .dailyLimit) == .cooldown,
              let end = cooldownEndByGroupID[group.id] else { return nil }
        return "\(goldTimeClockText(date: end))까지 쉬어요"
    }

    /// 자정까지 < 15분이라 정확한 사용량 추적이 불가능한 시점(23:45부터). 1분 연장을 막는다.
    var isNearMidnightCutoff: Bool {
        extendGroupUseCase.isNearMidnightCutoff()
    }

    var canExtendOneMinute: Bool {
        selectedGroup != nil && oneMinuteRemaining > 0 && !isExtending && !isNearMidnightCutoff
    }

    var canExtendWithAd: Bool {
        selectedGroup != nil && !isExtending
    }

    /// 자정 근처는 광고를 봐도 10분이 아니라 "자정까지"만 열리므로 버튼 제목을 정직하게 바꾼다.
    var adButtonTitle: String {
        isNearMidnightCutoff ? "광고 보고 자정까지 열기" : "광고 보고 10분 구매하기"
    }

    /// 자정 근처 안내를 보여줄 구간(23:30부터). 행동 변화(23:45)보다 일찍 알려, 23:44에 연장 시작 후
    /// 광고를 보는 동안 23:45를 넘겨 갑자기 자정까지 열리는 상황에 당황하지 않게 한다.
    var showsNearMidnightNotice: Bool {
        extendGroupUseCase.isNearMidnightNoticeWindow()
    }

    /// 자정 근처 상황을 설명하는 안내 문구. 문구가 "23:45부터는…"이라 23:30~23:45 사이에 떠도
    /// 미리 알림으로 정확하다.
    var nearMidnightNotice: String? {
        guard showsNearMidnightNotice else { return nil }
        return "23:45부터는 사용량 추적이 어려워요. 광고를 보면 23:59까지 잠금이 해제되며, 00:00부터 규칙이 다시 적용됩니다."
    }

    var maxAppsPerGroup: Int { SharedStore.maxAppsPerGroup }

    func onAppear(initialGroupID: UUID? = nil) {
        refreshLockedGroups()
        // 첫 문구("오늘 한도 다 썼어요.")는 한도 초과 전용이라 시간대 차단·쿨다운만 잠긴 경우엔 제외.
        let pool = (isWindowOnlyLock || isCooldownOnlyLock) ? Array(shieldMessages.dropFirst()) : shieldMessages
        headerMessage = pool.randomElement() ?? "더 쓰려면 광고가 필요해요."
        if let id = initialGroupID, lockedGroups.contains(where: { $0.id == id }) {
            selectedGroupID = id
        }
    }

    func selectGroup(_ id: UUID) {
        selectedGroupID = id
        infoMessage = nil
    }

    func tapWalkAway() -> Bool {
        extendGroupUseCase.walkAway(lockedGroups: lockedGroups)
        if !lockedGroups.isEmpty {
            analyticsRepository.log(.walkAway(lockedCount: lockedGroups.count))
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
        extendGroup(groupID: groupID, source: .oneMinute)
    }

    func retryRelockRegistration() {
        guard let pendingRetry else {
            infoMessage = "다시 시도할 연장 요청이 없어요."
            return
        }
        extendGroup(groupID: pendingRetry.groupID, source: pendingRetry.source)
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
        requestedWebDomainToken = state.requestedWebDomainToken
        cooldownEndByGroupID = state.cooldownEndByGroupID
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
            switch source {
            case .adReward:
                analyticsRepository.log(.adUnlock(seconds: result.durationSeconds))
            case .oneMinute:
                analyticsRepository.log(.oneMinuteUnlock)
            }
            pendingRetry = nil
            retryTask?.cancel()
            retryTask = nil
            oneMinuteRemaining = extendGroupUseCase.currentOneMinuteRemaining()
            lockedGroups = extendGroupUseCase.lockedGroupsAfterExtension(
                result: result,
                requestedToken: requestedApplicationToken,
                requestedWebDomainToken: requestedWebDomainToken
            )
            if let selectedGroupID,
               !lockedGroups.contains(where: { $0.id == selectedGroupID }) {
                self.selectedGroupID = lockedGroups.first?.id
            }
            // 광고 = 시간 구매. 완료 알럿이 뜨는 순간 결제감 피드백(차임 + 햅틱)을 준다.
            if source == .adReward {
                PurchaseFeedback.play()
            }
            completionAlert = LockOptionsCompletionAlert(
                title: source == .adReward ? "구매 완료" : "연장 완료",
                message: completionMessage(for: result, source: source)
            )
        case .failure(let failure):
            infoMessage = message(for: failure, source: source)
            oneMinuteRemaining = extendGroupUseCase.currentOneMinuteRemaining()
            if failure == .relockTimerRegistrationFailed {
                pendingRetry = (groupID, source)
                scheduleRelockRegistrationRetry(groupID: groupID, source: source)
            }
        }
    }

    private func scheduleRelockRegistrationRetry(groupID: UUID, source: ExtensionSource) {
        retryTask?.cancel()
        let delays = relockRetryDelays
        retryTask = Task { [weak self] in
            for delay in delays {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                await self?.retryIfStillPending(groupID: groupID, source: source)
                guard await self?.isRetryPending(groupID: groupID, source: source) == true else {
                    return
                }
            }
        }
    }

    private func retryIfStillPending(groupID: UUID, source: ExtensionSource) {
        guard pendingRetry?.groupID == groupID,
              pendingRetry?.source == source,
              !isExtending
        else {
            return
        }
        infoMessage = "재잠금 타이머 등록을 다시 시도하고 있어요."
        extendGroup(groupID: groupID, source: source)
    }

    private func isRetryPending(groupID: UUID, source: ExtensionSource) -> Bool {
        pendingRetry?.groupID == groupID && pendingRetry?.source == source
    }

    private func message(for failure: ExtensionFailure, source: ExtensionSource) -> String {
        switch failure {
        case .groupNotFound:
            return "이 그룹을 찾지 못했어요. GoldTime에서 그룹 설정을 확인해주세요."
        case .oneMinuteLimitReached:
            return source == .oneMinute
                ? "오늘 1분 연장은 모두 사용했어요. 광고를 보거나 잠금을 유지할 수 있어요."
                : "광고 연장을 처리하지 못했어요. 잠시 뒤 다시 시도해주세요."
        case .relockTimerRegistrationFailed:
            return "재잠금 타이머 등록 실패로 잠금을 유지했어요. 자동으로 다시 시도하고 있어요."
        }
    }

    private func completionMessage(for result: GroupExtensionResult, source: ExtensionSource) -> String {
        var message: String
        if isNearMidnightCutoff {
            // 자정 근처는 사용량이 아니라 "자정까지" 시간 기반으로 열린다.
            let endText = goldTimeClockText(date: result.overrideUntil)
            message = "\(result.group.displayName) 잠금을 풀었어요. \(endText)까지 사용할 수 있어요. 자정에는 새로 시작돼요."
        } else {
            let duration = result.durationSeconds == 60 ? "1분" : "\(result.durationSeconds / 60)분"
            message = source == .adReward
                ? "\(result.group.displayName) \(duration)을 구매했어요. \(duration) 더 쓰면 다시 잠겨요."
                : "\(result.group.displayName)을 \(duration) 연장했어요. \(duration) 더 쓰면 다시 잠겨요."
        }

        if let token = requestedApplicationToken {
            let remaining = extendGroupUseCase.lockedGroupsAfterExtension(
                result: result,
                requestedToken: token,
                requestedWebDomainToken: nil
            )
            if let remainingGroup = remaining.first {
                message += " 다른 그룹은 아직 잠겨 있어요."
            }
        } else if let requestedWebDomainToken {
            let remaining = extendGroupUseCase.lockedGroupsAfterExtension(
                result: result,
                requestedToken: nil,
                requestedWebDomainToken: requestedWebDomainToken
            )
            if let remainingGroup = remaining.first {
                message += " 다른 그룹은 아직 잠겨 있어요."
            }
        } else if let remainingGroup = result.remainingLockedGroups.first {
            message += " 다른 그룹은 아직 잠겨 있어요."
        }

        return message
    }
}
