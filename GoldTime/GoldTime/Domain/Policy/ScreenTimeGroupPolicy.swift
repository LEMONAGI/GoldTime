//
//  ScreenTimeGroupPolicy.swift
//  GoldTime
//
//  그룹 한도와 Shield 대상 계산을 Apple framework 호출부 밖에서 검증하기 위한 순수 정책.
//

import Foundation

enum ScreenTimeGroupPolicy {
    static let maxGroupCount = 5
    static let maxAppsPerGroup = 9
    static let maxShieldApplicationCount = 49
    static let oneMinuteDailyLimit = 5

    enum InvalidReason: Equatable {
        case tooManyGroups
        case groupHasNoSelection(String)
        case groupHasNoLimit(String)
        case groupHasNoRule(String)
        case groupNotApplied(String)
        case groupHasInvalidTimeWindows(String, TimeWindowPolicy.InvalidReason)
        case groupHasInvalidCooldown(String, CooldownPolicy.InvalidReason)
        case groupHasTooManySelections(String)
        case groupHasNonAppTokens(String)
        case shieldApplicationLimitExceeded(Int)

        var userMessage: String {
            switch self {
            case .tooManyGroups:
                return String(localized: "group.error.tooMany \(ScreenTimeGroupPolicy.maxGroupCount)")
            case .groupHasNoSelection(let name):
                return String(localized: "group.error.noSelection \(name)")
            case .groupHasNoLimit(let name):
                return String(localized: "group.error.noLimit \(name)")
            case .groupHasNoRule(let name):
                return String(localized: "group.error.noRule \(name)")
            case .groupNotApplied(let name):
                return String(localized: "group.error.notApplied \(name)")
            case .groupHasInvalidTimeWindows(let name, let reason):
                return String(localized: "group.error.namedReason \(name) \(reason.userMessage)")
            case .groupHasInvalidCooldown(let name, let reason):
                return String(localized: "group.error.namedReason \(name) \(reason.userMessage)")
            case .groupHasTooManySelections(let name):
                return String(localized: "group.error.tooManySelections \(name) \(ScreenTimeGroupPolicy.maxAppsPerGroup)")
            case .groupHasNonAppTokens(let name):
                return String(localized: "group.error.nonAppTokens \(name)")
            case .shieldApplicationLimitExceeded(let count):
                return String(localized: "group.error.shieldLimitExceeded \(ScreenTimeGroupPolicy.maxShieldApplicationCount) \(count)")
            }
        }
    }

    struct GroupSnapshot<Token: Hashable>: Identifiable {
        var id: UUID
        var name: String
        var appTokens: Set<Token>
        var webDomainTokenCount: Int
        var hasNonAppTokens: Bool
        var dailyLimitMinutes: Int
        var ruleKind: GroupRuleKind?
        var timeWindows: [TimeWindow]
        var isApplied: Bool
        /// 쿨다운 모드: 사용 예산(분). ruleKind == .cooldown 일 때 유효.
        var cooldownUsageMinutes: Int
        /// 쿨다운 모드: 강제 휴식(분). ruleKind == .cooldown 일 때 유효.
        var cooldownDurationMinutes: Int

        init(
            id: UUID = UUID(),
            name: String,
            appTokens: Set<Token>,
            webDomainTokenCount: Int = 0,
            hasNonAppTokens: Bool = false,
            dailyLimitMinutes: Int,
            ruleKind: GroupRuleKind? = .dailyLimit,
            timeWindows: [TimeWindow] = [],
            isApplied: Bool = true,
            cooldownUsageMinutes: Int = 10,
            cooldownDurationMinutes: Int = 300
        ) {
            self.id = id
            self.name = name
            self.appTokens = appTokens
            self.webDomainTokenCount = webDomainTokenCount
            self.hasNonAppTokens = hasNonAppTokens
            self.dailyLimitMinutes = dailyLimitMinutes
            self.ruleKind = ruleKind
            self.timeWindows = timeWindows
            self.isApplied = isApplied
            self.cooldownUsageMinutes = cooldownUsageMinutes
            self.cooldownDurationMinutes = cooldownDurationMinutes
        }

        var selectionCount: Int {
            appTokens.count + webDomainTokenCount
        }
    }

    /// 그룹이 선택한 규칙 자체의 유효성. 규칙 미선택(draft 중)도 invalid로 취급해
    /// 모니터링 대상에서 자연스럽게 제외된다.
    static func ruleInvalidReason<Token>(for group: GroupSnapshot<Token>) -> InvalidReason? {
        switch group.ruleKind {
        case .none:
            return .groupHasNoRule(group.name)
        case .dailyLimit:
            return group.dailyLimitMinutes < 0 ? .groupHasNoLimit(group.name) : nil
        case .timeWindows:
            if let reason = TimeWindowPolicy.firstInvalidReason(for: group.timeWindows) {
                return .groupHasInvalidTimeWindows(group.name, reason)
            }
            return nil
        case .cooldown:
            if let reason = CooldownPolicy.firstInvalidReason(
                usageMinutes: group.cooldownUsageMinutes,
                cooldownMinutes: group.cooldownDurationMinutes
            ) {
                return .groupHasInvalidCooldown(group.name, reason)
            }
            return nil
        }
    }

    static func firstInvalidReason<Token>(
        for groups: [GroupSnapshot<Token>],
        maxGroups: Int = ScreenTimeGroupPolicy.maxGroupCount,
        maxAppsPerGroup: Int = ScreenTimeGroupPolicy.maxAppsPerGroup,
        maxShieldApplications: Int = ScreenTimeGroupPolicy.maxShieldApplicationCount
    ) -> InvalidReason? {
        if groups.count > maxGroups {
            return .tooManyGroups
        }

        for group in groups where group.selectionCount == 0 {
            return .groupHasNoSelection(group.name)
        }

        for group in groups {
            if let reason = ruleInvalidReason(for: group) {
                return reason
            }
        }

        for group in groups where group.selectionCount > maxAppsPerGroup {
            return .groupHasTooManySelections(group.name)
        }

        for group in groups where group.hasNonAppTokens {
            return .groupHasNonAppTokens(group.name)
        }

        let count = unionAppTokens(for: groups).count
        if count > maxShieldApplications {
            return .shieldApplicationLimitExceeded(count)
        }

        return nil
    }

    /// 개별 그룹의 모니터링 자격. draft(미적용) 그룹은 보호가 시작되지 않으므로 자격 없음으로 본다.
    /// 이 분기는 per-group 경로에만 두고, 저장 전체 검증인 `firstInvalidReason(for groups:)`에는
    /// 넣지 않는다 — draft 존재가 저장 자체를 막는 에러가 되면 안 되기 때문.
    static func invalidReason<Token>(
        for group: GroupSnapshot<Token>,
        maxAppsPerGroup: Int = ScreenTimeGroupPolicy.maxAppsPerGroup
    ) -> InvalidReason? {
        if !group.isApplied {
            return .groupNotApplied(group.name)
        }

        if group.selectionCount == 0 {
            return .groupHasNoSelection(group.name)
        }

        if let reason = ruleInvalidReason(for: group) {
            return reason
        }

        if group.selectionCount > maxAppsPerGroup {
            return .groupHasTooManySelections(group.name)
        }

        if group.hasNonAppTokens {
            return .groupHasNonAppTokens(group.name)
        }

        return nil
    }

    static func monitoringEligibleGroups<Token>(
        from groups: [GroupSnapshot<Token>],
        maxAppsPerGroup: Int = ScreenTimeGroupPolicy.maxAppsPerGroup
    ) -> [GroupSnapshot<Token>] {
        groups.filter { group in
            invalidReason(for: group, maxAppsPerGroup: maxAppsPerGroup) == nil
        }
    }

    static func unionAppTokens<Token>(for groups: [GroupSnapshot<Token>]) -> Set<Token> {
        groups.reduce(into: Set<Token>()) { result, group in
            result.formUnion(group.appTokens)
        }
    }

    static func groupsContaining<Token>(
        _ token: Token,
        in groups: [GroupSnapshot<Token>]
    ) -> [GroupSnapshot<Token>] {
        groups.filter { $0.appTokens.contains(token) }
    }

    static func hasDuplicateApps<Token>(in groups: [GroupSnapshot<Token>]) -> Bool {
        let totalSelections = groups.reduce(0) { $0 + $1.appTokens.count }
        return totalSelections > unionAppTokens(for: groups).count
    }
}
