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

    /// `daily.<UUID>.<generation>` 형식. 재시작 시 generation을 +1 해서 시스템 카운터를 분리한다.
    nonisolated static func dailyGroup(for groupID: UUID, generation: Int) -> Self {
        Self("daily.\(groupID.uuidString).\(generation)")
    }

    /// 옛 형식(`daily.<UUID>`)과 새 형식(`daily.<UUID>.<gen>`) 모두 인식.
    var dailyGroupID: UUID? {
        let prefix = "daily."
        guard rawValue.hasPrefix(prefix), rawValue != "daily" else { return nil }
        let body = String(rawValue.dropFirst(prefix.count))
        let firstSegment = body.split(separator: ".").first.map(String.init) ?? body
        return UUID(uuidString: firstSegment)
    }

    nonisolated static func override(for groupID: UUID) -> Self {
        Self("override.\(groupID.uuidString)")
    }
}

extension DeviceActivityEvent.Name {
    nonisolated static func tick(for groupID: UUID) -> Self {
        Self("tick.\(groupID.uuidString)")
    }

    var tickGroupID: UUID? {
        let prefix = "tick."
        guard rawValue.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(rawValue.dropFirst(prefix.count)))
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

    private static var dailySchedule: DeviceActivitySchedule {
        DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
    }

    static func startDailyMonitoring(groups: [SharedStore.ScreenTimeGroup]) throws {
        let sanitizedGroups = sanitized(groups)

        if let reason = ScreenTimeGroupPolicy.firstInvalidReason(for: sanitizedGroups.policySnapshots) {
            throw ManagerError.invalidConfiguration(reason.userMessage)
        }

        SharedStore.screenTimeGroups = sanitizedGroups
        SharedStore.clearAllShieldState()
        SharedStore.clearAllUsedTime()
        center.stopMonitoring()
        do {
            try registerAllGroups(sanitizedGroups)
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
        let registeredGroupIDs: Set<UUID> = SharedStore.lastRegisteredGroupsByID
            .map { Set($0.keys) } ?? []
        var generationByID = SharedStore.lastRegisteredGenerationByID
        let staleGroupActivities = registeredGroupIDs
            .subtracting(validGroupIDs)
            .map { groupID -> DeviceActivityName in
                .dailyGroup(for: groupID, generation: generationByID[groupID] ?? 0)
            }

        SharedStore.screenTimeGroups = sanitizedGroups
        let activitiesToStop = staleOverrideActivities + staleGroupActivities
        if !activitiesToStop.isEmpty {
            center.stopMonitoring(activitiesToStop)
        }
        for staleID in registeredGroupIDs.subtracting(validGroupIDs) {
            generationByID.removeValue(forKey: staleID)
        }
        SharedStore.pruneShieldState(keepingGroupIDs: validGroupIDs)

        guard !validGroups.isEmpty else {
            center.stopMonitoring()
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
            SharedStore.isDailyMonitoringEnabled = false
            SharedStore.clearAllShieldState()
            SharedStore.lastRegisteredGenerationByID = [:]
            return
        }

        // 그룹별 변경 감지: 변경된 그룹만 재시작 (usedTime은 SharedStore에 보존)
        let lastRegistered = SharedStore.lastRegisteredGroupsByID ?? [:]
        var newRegistered = lastRegistered.filter { validGroupIDs.contains($0.key) }
        var firstError: Error?

        for group in validGroups {
            let last = lastRegistered[group.id]
            guard last != group else { continue }

            let currentGen = generationByID[group.id] ?? 0
            let usedMinutes = SharedStore.usedTimeByGroupID[group.id] ?? 0
            let wasLocked = SharedStore.shieldedGroupIDs.contains(group.id)
            let needsMonitoringRestart = last == nil || last!.selection != group.selection || wasLocked

            if usedMinutes >= group.dailyLimitMinutes {
                center.stopMonitoring([.dailyGroup(for: group.id, generation: currentGen)])
                SharedStore.markGroupShielded(group.id)
                newRegistered[group.id] = group
            } else if needsMonitoringRestart {
                // 같은 activity name으로 재시작하면 DeviceActivity의 schedule-interval 누적 카운터가
                // 그대로 유지되어 1분 만에 잠기는 버그가 발생한다. 새 generation으로 등록해 시스템
                // 카운터를 분리한다.
                center.stopMonitoring([.dailyGroup(for: group.id, generation: currentGen)])
                SharedStore.unmarkGroupShielded(group.id)
                let nextGen = (last == nil) ? currentGen : currentGen + 1
                do {
                    try registerGroup(group, generation: nextGen)
                    generationByID[group.id] = nextGen
                    newRegistered[group.id] = group
                } catch {
                    firstError = firstError ?? error
                }
            } else {
                // 이름·한도만 변경: DeviceActivity 재시작 없이 등록 정보만 갱신
                // extension이 SharedStore.group(id:)를 동적으로 읽으므로 변경된 한도가 반영됨
                SharedStore.unmarkGroupShielded(group.id)
                newRegistered[group.id] = group
            }
        }

        SharedStore.lastRegisteredGroupsByID = newRegistered
        SharedStore.lastRegisteredGenerationByID = generationByID
        SharedStore.isDailyMonitoringEnabled = true
        applyShield()

        if let error = firstError { throw error }
    }

    static func validDailyMonitoringGroups(
        from groups: [SharedStore.ScreenTimeGroup]
    ) -> [SharedStore.ScreenTimeGroup] {
        sanitized(groups).filter { group in
            ScreenTimeGroupPolicy.invalidReason(for: group.policySnapshot) == nil
        }
    }

    static func reconnectMonitoring() throws {
        center.stopMonitoring()
        SharedStore.lastRegisteredGroupsByID = nil
        SharedStore.lastRegisteredGenerationByID = [:]
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

    // 그룹당 독립 daily.<groupID>.<generation> 활동으로 1분 tick 이벤트 등록
    private static func registerGroup(
        _ group: SharedStore.ScreenTimeGroup,
        generation: Int
    ) throws {
        let event = DeviceActivityEvent(
            applications: group.selection.applicationTokens,
            categories: [],
            webDomains: group.selection.webDomainTokens,
            threshold: DateComponents(minute: 1)
        )
        try center.startMonitoring(
            .dailyGroup(for: group.id, generation: generation),
            during: dailySchedule,
            events: [.tick(for: group.id): event]
        )
    }

    private static func registerAllGroups(_ groups: [SharedStore.ScreenTimeGroup]) throws {
        var newRegistered: [UUID: SharedStore.ScreenTimeGroup] = [:]
        var generationByID: [UUID: Int] = [:]
        for group in groups {
            try registerGroup(group, generation: 0)
            newRegistered[group.id] = group
            generationByID[group.id] = 0
        }
        SharedStore.lastRegisteredGroupsByID = newRegistered
        SharedStore.lastRegisteredGenerationByID = generationByID
    }

    static func stopAllMonitoring() {
        center.stopMonitoring()
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        SharedStore.isDailyMonitoringEnabled = false
        SharedStore.clearAllShieldState()
        SharedStore.lastRegisteredGroupsByID = nil
        SharedStore.lastRegisteredGenerationByID = [:]
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
