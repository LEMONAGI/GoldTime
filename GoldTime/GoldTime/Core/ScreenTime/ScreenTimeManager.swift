//
//  ScreenTimeManager.swift
//  GoldTime
//
//  DeviceActivityCenter 기반 자동 모니터링 동기화, 쉴드 적용/해제, 연장 처리.
//

import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

extension DeviceActivityName {
    static let daily = Self("daily")

    nonisolated static func override(for groupID: UUID) -> Self {
        Self("override.\(groupID.uuidString)")
    }
}

extension DeviceActivityEvent.Name {
    nonisolated static func dailyLimit(for groupID: UUID) -> Self {
        Self("dailyLimit.\(groupID.uuidString)")
    }
}

extension ManagedSettingsStore.Name {
    static let goldtime = Self("goldtime")
}

protocol OverrideMonitorRegistering {
    func stopMonitoring(_ activities: [DeviceActivityName])
    func startMonitoring(
        _ activity: DeviceActivityName,
        during schedule: DeviceActivitySchedule,
        events: [DeviceActivityEvent.Name: DeviceActivityEvent]
    ) throws
}

struct DeviceActivityOverrideMonitorRegistrar: OverrideMonitorRegistering {
    func stopMonitoring(_ activities: [DeviceActivityName]) {
        DeviceActivityCenter().stopMonitoring(activities)
    }

    func startMonitoring(
        _ activity: DeviceActivityName,
        during schedule: DeviceActivitySchedule,
        events: [DeviceActivityEvent.Name: DeviceActivityEvent]
    ) throws {
        try DeviceActivityCenter().startMonitoring(activity, during: schedule, events: events)
    }
}

enum ScreenTimeManager {
    enum ManagerError: LocalizedError {
        case invalidConfiguration(String)

        var errorDescription: String? {
            switch self {
            case .invalidConfiguration(let message):
                return message
            }
        }
    }

    enum ExtensionSource: Equatable {
        case oneMinute
        case adReward
    }

    enum ExtensionFailure: Error, Equatable {
        case groupNotFound
        case oneMinuteLimitReached
        case relockTimerRegistrationFailed
    }

    struct GroupExtensionResult {
        let group: SharedStore.ScreenTimeGroup
        let durationSeconds: Int
        let overrideUntil: Date
        let remainingLockedGroups: [SharedStore.ScreenTimeGroup]
    }

    struct OverrideScheduleWindow {
        let start: Date
        let end: Date
        let startComponents: DateComponents
        let endComponents: DateComponents
        let warningTimeComponents: DateComponents?
    }

    private static var center: DeviceActivityCenter { DeviceActivityCenter() }
    private static var store: ManagedSettingsStore { ManagedSettingsStore(named: .goldtime) }
    static var overrideMonitorRegistrar: any OverrideMonitorRegistering = DeviceActivityOverrideMonitorRegistrar()
    private static let overrideMonitorStartDelay: TimeInterval = 1
    private static let minimumOverrideMonitorDuration: TimeInterval = 15 * 60

    // MARK: - 일일 모니터링 동기화

    static func startDailyMonitoring(groups: [SharedStore.ScreenTimeGroup]) throws {
        let sanitizedGroups = sanitized(groups)

        if let reason = ScreenTimeGroupPolicy.firstInvalidReason(for: sanitizedGroups.policySnapshots) {
            throw ManagerError.invalidConfiguration(reason.userMessage)
        }

        SharedStore.screenTimeGroups = sanitizedGroups
        SharedStore.clearAllShieldState()
        do {
            try registerDailyMonitoring(groups: sanitizedGroups)
            SharedStore.isDailyMonitoringEnabled = true
        } catch {
            SharedStore.isDailyMonitoringEnabled = false
            throw error
        }
    }

    static func syncDailyMonitoring(groups: [SharedStore.ScreenTimeGroup]) throws {
        resetDailyProtectionStateIfNeeded()

        let sanitizedGroups = sanitized(groups)
        let validGroups = validDailyMonitoringGroups(from: sanitizedGroups)
        let validGroupIDs = Set(validGroups.map(\.id))
        let staleOverrideActivities = SharedStore.overrideUntilByGroupID.keys
            .filter { !validGroupIDs.contains($0) }
            .map(DeviceActivityName.override(for:))

        SharedStore.screenTimeGroups = sanitizedGroups
        if !staleOverrideActivities.isEmpty {
            center.stopMonitoring(staleOverrideActivities)
        }
        SharedStore.pruneShieldState(keepingGroupIDs: validGroupIDs)

        guard !validGroups.isEmpty else {
            center.stopMonitoring()
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
            SharedStore.isDailyMonitoringEnabled = false
            SharedStore.clearAllShieldState()
            return
        }

        do {
            try registerDailyMonitoring(groups: validGroups)
            SharedStore.isDailyMonitoringEnabled = true
            applyShield()
        } catch {
            SharedStore.isDailyMonitoringEnabled = false
            throw error
        }
    }

    static func validDailyMonitoringGroups(
        from groups: [SharedStore.ScreenTimeGroup]
    ) -> [SharedStore.ScreenTimeGroup] {
        sanitized(groups).filter { group in
            ScreenTimeGroupPolicy.invalidReason(for: group.policySnapshot) == nil
        }
    }

    static func resetProtectionState() throws {
        center.stopMonitoring()
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        SharedStore.isDailyMonitoringEnabled = false
        SharedStore.clearAllShieldState()
        try syncDailyMonitoring(groups: SharedStore.screenTimeGroups)
    }

    @discardableResult
    private static func resetDailyProtectionStateIfNeeded(now: Date = Date()) -> Bool {
        guard SharedStore.resetDailyProtectionStateIfNeeded(now: now) else {
            return false
        }

        clearShield()
        return true
    }

    private static func sanitized(
        _ groups: [SharedStore.ScreenTimeGroup]
    ) -> [SharedStore.ScreenTimeGroup] {
        Array(groups.prefix(SharedStore.maxGroupCount)).map { group in
            var sanitized = group
            sanitized.selection = group.selection.supportedTokenSelection
            return sanitized
        }
    }

    private static func registerDailyMonitoring(groups: [SharedStore.ScreenTimeGroup]) throws {
        // 자정~자정 일일 스케줄
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )

        let events = Dictionary(
            uniqueKeysWithValues: groups.map { group in
                (
                    DeviceActivityEvent.Name.dailyLimit(for: group.id),
                    DeviceActivityEvent(
                        applications: group.selection.applicationTokens,
                        categories: [],
                        webDomains: group.selection.webDomainTokens,
                        threshold: DateComponents(minute: group.dailyLimitMinutes)
                    )
                )
            }
        )

        center.stopMonitoring([.daily])
        try center.startMonitoring(.daily, during: schedule, events: events)
    }

    static func stopAllMonitoring() {
        center.stopMonitoring()
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        SharedStore.isDailyMonitoringEnabled = false
        SharedStore.clearAllShieldState()
    }

    // MARK: - 쉴드 제어

    static func applyShield() {
        let applicationTokens = SharedStore.shieldApplicationTokens()
        let webDomainTokens = SharedStore.shieldWebDomainTokens()
        guard !applicationTokens.isEmpty || !webDomainTokens.isEmpty else {
            clearShield()
            return
        }

        store.shield.applications = applicationTokens.isEmpty ? nil : applicationTokens
        store.shield.applicationCategories = nil
        store.shield.webDomains = webDomainTokens.isEmpty ? nil : webDomainTokens
        SharedStore.isShieldActive = true
    }

    static func clearShield() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        SharedStore.isShieldActive = false
    }

    static func overrideScheduleWindow(
        now: Date,
        overrideUntil: Date,
        calendar: Calendar = .current
    ) -> OverrideScheduleWindow {
        let start = roundedUpToWholeSecond(
            now.addingTimeInterval(overrideMonitorStartDelay),
            calendar: calendar
        )
        let minimumEnd = max(
            overrideUntil,
            start.addingTimeInterval(minimumOverrideMonitorDuration)
        )
        let end = roundedUpToWholeSecond(minimumEnd, calendar: calendar)
        let warningTimeComponents = warningTimeComponents(
            from: end,
            warningAt: overrideUntil
        )

        return OverrideScheduleWindow(
            start: start,
            end: end,
            startComponents: calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: start
            ),
            endComponents: calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: end
            ),
            warningTimeComponents: warningTimeComponents
        )
    }

    private static func warningTimeComponents(
        from intervalEnd: Date,
        warningAt: Date
    ) -> DateComponents? {
        let secondsBeforeEnd = Int(ceil(intervalEnd.timeIntervalSince(warningAt)))
        guard secondsBeforeEnd > 0 else { return nil }

        return DateComponents(
            minute: secondsBeforeEnd / 60,
            second: secondsBeforeEnd % 60
        )
    }

    private static func roundedUpToWholeSecond(
        _ date: Date,
        calendar: Calendar
    ) -> Date {
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond],
            from: date
        )
        var roundedComponents = DateComponents()
        roundedComponents.year = components.year
        roundedComponents.month = components.month
        roundedComponents.day = components.day
        roundedComponents.hour = components.hour
        roundedComponents.minute = components.minute
        roundedComponents.second = components.second
        let base = calendar.date(from: roundedComponents) ?? date

        if (components.nanosecond ?? 0) == 0 {
            return base
        }
        return calendar.date(byAdding: .second, value: 1, to: base) ?? date
    }

    /// 특정 그룹만 일정 시간 동안 쉴드 해제. 다른 잠긴 그룹은 계속 Shield union에 남긴다.
    @discardableResult
    static func releaseShield(
        forSeconds seconds: TimeInterval,
        groupID: UUID,
        now: Date = Date()
    ) -> Result<Date, ExtensionFailure> {
        let end = now.addingTimeInterval(seconds)
        let window = overrideScheduleWindow(now: now, overrideUntil: end)

        let schedule = DeviceActivitySchedule(
            intervalStart: window.startComponents,
            intervalEnd: window.endComponents,
            repeats: false,
            warningTime: window.warningTimeComponents
        )

        let activity = DeviceActivityName.override(for: groupID)
        overrideMonitorRegistrar.stopMonitoring([activity])
        do {
            try overrideMonitorRegistrar.startMonitoring(activity, during: schedule, events: [:])
            SharedStore.setOverride(until: end, for: groupID)
            applyShield()
            SharedStore.recordOverrideRegistration(
                activityName: activity.rawValue,
                groupID: groupID,
                overrideUntil: end,
                registeredAt: now,
                message: "registered override monitor"
            )
        } catch {
            SharedStore.recordOverrideRegistration(
                activityName: activity.rawValue,
                groupID: groupID,
                overrideUntil: end,
                registeredAt: now,
                message: "failed to register override monitor: \(error.localizedDescription)"
            )
            print("Failed to start override monitoring: \(error.localizedDescription)")
            return .failure(.relockTimerRegistrationFailed)
        }

        return .success(end)
    }

    @discardableResult
    static func extendGroup(
        groupID: UUID,
        duration seconds: Int,
        source: ExtensionSource,
        now: Date = Date()
    ) -> Result<GroupExtensionResult, ExtensionFailure> {
        guard let group = SharedStore.group(id: groupID) else {
            return .failure(.groupNotFound)
        }

        if source == .oneMinute {
            rolloverCounterIfNeeded(now: now)
            guard SharedStore.oneMinuteUsedToday < SharedStore.oneMinuteDailyLimit else {
                return .failure(.oneMinuteLimitReached)
            }
        }

        let releaseResult = releaseShield(
            forSeconds: TimeInterval(seconds),
            groupID: groupID,
            now: now
        )

        let overrideUntil: Date
        switch releaseResult {
        case .success(let end):
            overrideUntil = end
        case .failure(let failure):
            return .failure(failure)
        }

        switch source {
        case .oneMinute:
            SharedStore.oneMinuteUsedToday += 1
            SharedStore.recordOneMinuteUnlock(seconds: seconds)
        case .adReward:
            SharedStore.recordAdUnlock(seconds: seconds)
        }

        return .success(
            GroupExtensionResult(
                group: group,
                durationSeconds: seconds,
                overrideUntil: overrideUntil,
                remainingLockedGroups: SharedStore.lockedGroups(now: now)
            )
        )
    }

    @discardableResult
    static func consumeAdReward(for groupID: UUID) -> Bool {
        if case .success = extendGroup(
            groupID: groupID,
            duration: 15 * 60,
            source: .adReward
        ) {
            return true
        }
        return false
    }

    @discardableResult
    static func reapplyShieldIfOverrideExpired(now: Date = Date()) -> Bool {
        guard SharedStore.clearExpiredOverrides(now: now) else {
            return false
        }

        applyShield()
        return SharedStore.isShieldActive
    }

    // MARK: - 1분 카운터

    /// 카운터를 사용하고 1분 연장. 한도 초과 시 false 반환.
    @discardableResult
    static func consumeOneMinute(for groupID: UUID) -> Bool {
        if case .success = extendGroup(
            groupID: groupID,
            duration: 60,
            source: .oneMinute
        ) {
            return true
        }
        return false
    }

    static func rolloverCounterIfNeeded(now: Date = Date()) {
        let calendar = Calendar.current
        if !calendar.isDate(SharedStore.oneMinuteCounterDate, inSameDayAs: now) {
            SharedStore.oneMinuteUsedToday = 0
            SharedStore.oneMinuteCounterDate = now
        }
    }
}

extension Array where Element == SharedStore.ScreenTimeGroup {
    var policySnapshots: [ScreenTimeGroupPolicy.GroupSnapshot<ApplicationToken>] {
        map(\.policySnapshot)
    }
}

extension SharedStore.ScreenTimeGroup {
    var policySnapshot: ScreenTimeGroupPolicy.GroupSnapshot<ApplicationToken> {
        ScreenTimeGroupPolicy.GroupSnapshot(
            id: id,
            name: displayName,
            appTokens: selection.applicationTokens,
            webDomainTokenCount: selection.webDomainTokens.count,
            hasNonAppTokens: hasNonAppTokens,
            dailyLimitMinutes: dailyLimitMinutes
        )
    }
}
