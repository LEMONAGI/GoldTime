//
//  ScreenTimeGroupPolicy.swift
//  GoldTime
//
//  그룹 한도와 Shield 대상 계산을 Apple framework 호출부 밖에서 검증하기 위한 순수 정책.
//

import Foundation

enum ScreenTimeGroupPolicy {
    enum InvalidReason: Equatable {
        case tooManyGroups
        case groupHasNoApps(String)
        case groupHasNoLimit(String)
        case groupHasTooManyApps(String)
        case groupHasNonAppTokens(String)
        case shieldApplicationLimitExceeded(Int)

        var userMessage: String {
            switch self {
            case .tooManyGroups:
                return "그룹은 5개까지예요."
            case .groupHasNoApps(let name):
                return "\(name)에 앱이 없어요."
            case .groupHasNoLimit(let name):
                return "\(name)의 한도 설정이 올바르지 않아요."
            case .groupHasTooManyApps(let name):
                return "\(name)은 앱 9개까지만 담을 수 있어요."
            case .groupHasNonAppTokens(let name):
                return "\(name)에 앱 외 항목이 있어요. 이번 버전은 앱만 골라주세요."
            case .shieldApplicationLimitExceeded(let count):
                return "iOS Shield 제한 때문에 전체 앱은 49개 이하로 묶어야 해요. 현재 \(count)개예요."
            }
        }
    }

    struct GroupSnapshot<Token: Hashable>: Identifiable {
        var id: UUID
        var name: String
        var appTokens: Set<Token>
        var hasNonAppTokens: Bool
        var dailyLimitMinutes: Int

        init(
            id: UUID = UUID(),
            name: String,
            appTokens: Set<Token>,
            hasNonAppTokens: Bool = false,
            dailyLimitMinutes: Int
        ) {
            self.id = id
            self.name = name
            self.appTokens = appTokens
            self.hasNonAppTokens = hasNonAppTokens
            self.dailyLimitMinutes = dailyLimitMinutes
        }
    }

    static func firstInvalidReason<Token>(
        for groups: [GroupSnapshot<Token>],
        maxGroups: Int = SharedStore.maxGroupCount,
        maxAppsPerGroup: Int = SharedStore.maxAppsPerGroup,
        maxShieldApplications: Int = SharedStore.maxShieldApplicationCount
    ) -> InvalidReason? {
        if groups.count > maxGroups {
            return .tooManyGroups
        }

        for group in groups where group.appTokens.isEmpty {
            return .groupHasNoApps(group.name)
        }

        for group in groups where group.dailyLimitMinutes < 0 {
            return .groupHasNoLimit(group.name)
        }

        for group in groups where group.appTokens.count > maxAppsPerGroup {
            return .groupHasTooManyApps(group.name)
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

    static func invalidReason<Token>(
        for group: GroupSnapshot<Token>,
        maxAppsPerGroup: Int = SharedStore.maxAppsPerGroup
    ) -> InvalidReason? {
        if group.appTokens.isEmpty {
            return .groupHasNoApps(group.name)
        }

        if group.dailyLimitMinutes < 0 {
            return .groupHasNoLimit(group.name)
        }

        if group.appTokens.count > maxAppsPerGroup {
            return .groupHasTooManyApps(group.name)
        }

        if group.hasNonAppTokens {
            return .groupHasNonAppTokens(group.name)
        }

        return nil
    }

    static func monitoringEligibleGroups<Token>(
        from groups: [GroupSnapshot<Token>],
        maxAppsPerGroup: Int = SharedStore.maxAppsPerGroup
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
