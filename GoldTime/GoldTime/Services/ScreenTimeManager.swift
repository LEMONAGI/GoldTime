//
//  ScreenTimeManager.swift
//  GoldTime
//
//  DeviceActivityCenter 기반 모니터링 시작/중지, 쉴드 적용/해제, 연장 처리.
//

import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

extension DeviceActivityName {
    static let daily = Self("daily")

    static func override(for groupID: UUID) -> Self {
        Self("override.\(groupID.uuidString)")
    }
}

extension DeviceActivityEvent.Name {
    static func dailyLimit(for groupID: UUID) -> Self {
        Self("dailyLimit.\(groupID.uuidString)")
    }
}

extension ManagedSettingsStore.Name {
    static let goldtime = Self("goldtime")
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

    enum ExtensionSource {
        case oneMinute
        case adReward
    }

    enum ExtensionFailure: Error, Equatable {
        case groupNotFound
        case oneMinuteLimitReached
    }

    struct GroupExtensionResult {
        let group: SharedStore.ScreenTimeGroup
        let durationSeconds: Int
        let overrideUntil: Date
        let remainingLockedGroups: [SharedStore.ScreenTimeGroup]
    }

    private static var center: DeviceActivityCenter { DeviceActivityCenter() }
    private static var store: ManagedSettingsStore { ManagedSettingsStore(named: .goldtime) }

    // MARK: - 일일 모니터링 시작

    static func startDailyMonitoring(groups: [SharedStore.ScreenTimeGroup]) throws {
        let sanitizedGroups = groups.map { group in
            var sanitized = group
            sanitized.selection = group.selection.appOnly
            return sanitized
        }

        if let reason = ScreenTimeGroupPolicy.firstInvalidReason(for: sanitizedGroups.policySnapshots) {
            throw ManagerError.invalidConfiguration(reason.userMessage)
        }

        SharedStore.screenTimeGroups = sanitizedGroups
        SharedStore.isDailyMonitoringEnabled = true
        SharedStore.clearAllShieldState()

        // 자정~자정 일일 스케줄
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )

        let events = Dictionary(
            uniqueKeysWithValues: sanitizedGroups.map { group in
                (
                    DeviceActivityEvent.Name.dailyLimit(for: group.id),
                    DeviceActivityEvent(
                        applications: group.selection.applicationTokens,
                        categories: [],
                        webDomains: [],
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
        guard !applicationTokens.isEmpty else {
            clearShield()
            return
        }

        store.shield.applications = applicationTokens
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        SharedStore.isShieldActive = true
    }

    static func clearShield() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        SharedStore.isShieldActive = false
    }

    /// 특정 그룹만 일정 시간 동안 쉴드 해제. 다른 잠긴 그룹은 계속 Shield union에 남긴다.
    @discardableResult
    static func releaseShield(
        forSeconds seconds: TimeInterval,
        groupID: UUID,
        now: Date = Date()
    ) -> Date {
        let end = now.addingTimeInterval(seconds)
        SharedStore.setOverride(until: end, for: groupID)
        applyShield()

        let calendar = Calendar.current
        let startComps = calendar.dateComponents([.hour, .minute, .second], from: now)
        let endComps = calendar.dateComponents([.hour, .minute, .second], from: end)

        let schedule = DeviceActivitySchedule(
            intervalStart: startComps,
            intervalEnd: endComps,
            repeats: false
        )

        let activity = DeviceActivityName.override(for: groupID)
        center.stopMonitoring([activity])
        do {
            try center.startMonitoring(activity, during: schedule, events: [:])
        } catch {
            print("Failed to start override monitoring: \(error.localizedDescription)")
        }

        return end
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

        switch source {
        case .oneMinute:
            rolloverCounterIfNeeded(now: now)
            guard SharedStore.oneMinuteUsedToday < SharedStore.oneMinuteDailyLimit else {
                return .failure(.oneMinuteLimitReached)
            }
            SharedStore.oneMinuteUsedToday += 1
            SharedStore.recordOneMinuteUnlock(seconds: seconds)
        case .adReward:
            SharedStore.recordAdUnlock(seconds: seconds)
        }

        let overrideUntil = releaseShield(
            forSeconds: TimeInterval(seconds),
            groupID: groupID,
            now: now
        )
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
        map { group in
            ScreenTimeGroupPolicy.GroupSnapshot(
                id: group.id,
                name: group.displayName,
                appTokens: group.selection.applicationTokens,
                hasNonAppTokens: group.hasNonAppTokens,
                dailyLimitMinutes: group.dailyLimitMinutes
            )
        }
    }
}
