
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

enum LockOptionsEntrySource: String {
    case shield
    case homeGroup = "home_group"
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
    private var didLogOptionsViewed = false

    private let extendGroupUseCase: ExtendGroupUseCase
    private let analyticsRepository: any AnalyticsRepository
    private let relockRetryDelays: [UInt64] = [
        300_000_000,
        700_000_000,
        1_200_000_000
    ]

    private let shieldMessages = [
        String(localized: "lock.message.limitDone"),
        String(localized: "lock.message.noAdIfLeave"),
        String(localized: "lock.message.needAd"),
        String(localized: "lock.message.exitWithoutAd"),
        String(localized: "lock.message.stopOrAd")
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
    /// 요일별 그룹은 오늘 투영 규칙 기준으로 판정한다.
    private var isWindowOnlyLock: Bool {
        !lockedGroups.isEmpty && lockedGroups.allSatisfy { ($0.resolved(on: Date()).ruleKind ?? .dailyLimit) == .timeWindows }
    }

    /// 잠긴 그룹이 전부 쿨다운 규칙이면 "한도 초과"가 아니라 "휴식 중" 프레이밍이 맞다.
    /// 요일별 그룹은 오늘 투영 규칙 기준으로 판정한다.
    private var isCooldownOnlyLock: Bool {
        !lockedGroups.isEmpty && lockedGroups.allSatisfy { ($0.resolved(on: Date()).ruleKind ?? .dailyLimit) == .cooldown }
    }

    var headerTitle: String {
        if isWindowOnlyLock { return String(localized: "lock.header.window") }
        if isCooldownOnlyLock { return String(localized: "lock.header.cooldown") }
        return String(localized: "lock.header.limit")
    }

    /// 선택된 그룹이 시간대 차단으로 잠겨 있으면 종료 시각을 알려준다. 요일별 그룹은 오늘 투영 기준.
    var selectedWindowLockCaption: String? {
        guard let group = selectedGroup?.resolved(on: Date()),
              (group.ruleKind ?? .dailyLimit) == .timeWindows else { return nil }
        let minute = TimeWindowPolicy.minuteOfDay(for: Date())
        guard let end = TimeWindowPolicy.activeWindowEnd(minuteOfDay: minute, windows: group.timeWindows) else {
            return nil
        }
        return String(localized: "lock.caption.windowUntil \(goldTimeClockText(minuteOfDay: end))")
    }

    /// 선택된 그룹이 쿨다운으로 잠겨 있으면 휴식 종료 시각을 알려준다. 요일별 그룹은 오늘 투영 기준.
    var selectedCooldownLockCaption: String? {
        guard let group = selectedGroup?.resolved(on: Date()),
              (group.ruleKind ?? .dailyLimit) == .cooldown,
              let end = cooldownEndByGroupID[group.id] else { return nil }
        return String(localized: "lock.caption.cooldownUntil \(goldTimeClockText(date: end))")
    }

    /// 자정까지 < 15분이라 정확한 사용량 추적이 불가능한 시점(23:45부터). 1분 연장을 막는다.
    var isNearMidnightCutoff: Bool {
        extendGroupUseCase.isNearMidnightCutoff()
    }

    /// 선택된 그룹이 연장 불가 기간 중인지. 반드시 원본 selectedGroup으로 판정한다
    /// (resolved 투영은 strict 필드가 스트립되므로 금지).
    var isSelectedGroupStrictLocked: Bool {
        selectedGroup?.isStrictLockActive() == true
    }

    var canExtendOneMinute: Bool {
        selectedGroup != nil && oneMinuteRemaining > 0 && !isExtending && !isNearMidnightCutoff && !isSelectedGroupStrictLocked
    }

    var canExtendWithAd: Bool {
        selectedGroup != nil && !isExtending && !isSelectedGroupStrictLocked
    }

    /// 선택된 그룹이 연장 불가 기간 중이면 연장 대신 만료일을 안내한다.
    var strictLockNotice: String? {
        guard let group = selectedGroup, group.isStrictLockActive(), let until = group.strictUntil else { return nil }
        return String(localized: "lock.strict.notice \(goldTimeStrictLockedUntilText(until))")
    }

    /// 자정 근처는 광고를 봐도 10분이 아니라 "자정까지"만 열리므로 버튼 제목을 정직하게 바꾼다.
    var adButtonTitle: String {
        isNearMidnightCutoff ? String(localized: "lock.ad.untilMidnight") : String(localized: "lock.ad.buy10min")
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
        return String(localized: "lock.nearMidnight.notice")
    }

    var maxAppsPerGroup: Int { SharedStore.maxAppsPerGroup }

    func onAppear(
        initialGroupID: UUID? = nil,
        entrySource: LockOptionsEntrySource = .shield
    ) {
        refreshLockedGroups()
        // 첫 문구("오늘 한도 다 썼어요.")는 한도 초과 전용이라 시간대 차단·쿨다운만 잠긴 경우엔 제외.
        let pool = (isWindowOnlyLock || isCooldownOnlyLock) ? Array(shieldMessages.dropFirst()) : shieldMessages
        headerMessage = pool.randomElement() ?? String(localized: "lock.message.needAd")
        if let id = initialGroupID, lockedGroups.contains(where: { $0.id == id }) {
            selectedGroupID = id
        }
        if !didLogOptionsViewed {
            didLogOptionsViewed = true
            analyticsRepository.log(.shieldExtendOptionsViewed(
                entrySource: entrySource.rawValue,
                lockedGroupCount: lockedGroups.count,
                strictLockedGroupCount: lockedGroups.filter { $0.isStrictLockActive() }.count,
                oneMinuteRemaining: oneMinuteRemaining,
                nearMidnight: isNearMidnightCutoff
            ))
        }
    }

    func selectGroup(_ id: UUID) {
        selectedGroupID = id
        infoMessage = nil
    }

    func tapWalkAway() -> Bool {
        extendGroupUseCase.walkAway(lockedGroups: lockedGroups)
        if !lockedGroups.isEmpty {
            analyticsRepository.log(.shieldExtendStopSelected(lockedGroupCount: lockedGroups.count))
        }
        return true
    }

    func tapOneMinute() {
        guard canExtendOneMinute else {
            infoMessage = String(localized: "lock.info.pickOrAd")
            return
        }
        guard let groupID = selectedGroupID else {
            infoMessage = String(localized: "lock.info.pickGroup")
            return
        }
        analyticsRepository.log(.shieldExtendMethodSelected(method: sourceAnalyticsValue(.oneMinute)))
        extendGroup(groupID: groupID, source: .oneMinute)
    }

    func retryRelockRegistration() {
        guard let pendingRetry else {
            infoMessage = String(localized: "lock.info.noRetry")
            return
        }
        extendGroup(groupID: pendingRetry.groupID, source: pendingRetry.source)
    }

    func startAdFlow() {
        guard let groupID = selectedGroupID else {
            infoMessage = String(localized: "lock.info.pickGroup")
            return
        }
        analyticsRepository.log(.shieldExtendMethodSelected(method: sourceAnalyticsValue(.adReward)))
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
            analyticsRepository.log(.shieldExtendCompleted(
                method: sourceAnalyticsValue(source),
                seconds: result.durationSeconds,
                payload: ShieldExtendAnalyticsPayload(group: result.group)
            ))
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
                title: source == .adReward ? String(localized: "lock.alert.purchased") : String(localized: "lock.alert.extended"),
                message: completionMessage(for: result, source: source)
            )
        case .failure(let failure):
            analyticsRepository.log(.shieldExtendFailed(
                method: sourceAnalyticsValue(source),
                reason: failureAnalyticsValue(failure)
            ))
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
        infoMessage = String(localized: "lock.info.retrying")
        extendGroup(groupID: groupID, source: source)
    }

    private func isRetryPending(groupID: UUID, source: ExtensionSource) -> Bool {
        pendingRetry?.groupID == groupID && pendingRetry?.source == source
    }

    private func message(for failure: ExtensionFailure, source: ExtensionSource) -> String {
        switch failure {
        case .groupNotFound:
            return String(localized: "lock.error.groupNotFound")
        case .oneMinuteLimitReached:
            return source == .oneMinute
                ? String(localized: "lock.error.oneMinuteExhausted")
                : String(localized: "lock.error.adFailed")
        case .relockTimerRegistrationFailed:
            return String(localized: "lock.error.relockFailed")
        case .strictLockActive:
            return String(localized: "lock.error.strictLockActive")
        }
    }

    private func sourceAnalyticsValue(_ source: ExtensionSource) -> String {
        switch source {
        case .oneMinute: return "one_minute"
        case .adReward: return "ad"
        }
    }

    private func failureAnalyticsValue(_ failure: ExtensionFailure) -> String {
        switch failure {
        case .groupNotFound: return "group_not_found"
        case .oneMinuteLimitReached: return "one_minute_limit_reached"
        case .relockTimerRegistrationFailed: return "relock_timer_registration_failed"
        case .strictLockActive: return "strict_lock_active"
        }
    }

    private func completionMessage(for result: GroupExtensionResult, source: ExtensionSource) -> String {
        var message: String
        if isNearMidnightCutoff {
            // 자정 근처는 사용량이 아니라 "자정까지" 시간 기반으로 열린다.
            let endText = goldTimeClockText(date: result.overrideUntil)
            message = String(localized: "lock.complete.nearMidnight \(result.group.displayName) \(endText)")
        } else {
            let duration = String(localized: "common.minutes \(result.durationSeconds / 60)")
            message = source == .adReward
                ? String(localized: "lock.complete.purchased \(result.group.displayName) \(duration) \(duration)")
                : String(localized: "lock.complete.extended \(result.group.displayName) \(duration) \(duration)")
        }

        if let token = requestedApplicationToken {
            let remaining = extendGroupUseCase.lockedGroupsAfterExtension(
                result: result,
                requestedToken: token,
                requestedWebDomainToken: nil
            )
            if let remainingGroup = remaining.first {
                message += String(localized: "lock.complete.othersLocked")
            }
        } else if let requestedWebDomainToken {
            let remaining = extendGroupUseCase.lockedGroupsAfterExtension(
                result: result,
                requestedToken: nil,
                requestedWebDomainToken: requestedWebDomainToken
            )
            if let remainingGroup = remaining.first {
                message += String(localized: "lock.complete.othersLocked")
            }
        } else if let remainingGroup = result.remainingLockedGroups.first {
            message += String(localized: "lock.complete.othersLocked")
        }

        return message
    }
}
