//
//  DeviceActivityMonitorExtension.swift
//  DeviceActivityMonitorExtension
//

import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

extension DeviceActivityName {
    static let daily = Self("daily")

    var dailyGroupID: UUID? {
        let prefix = "daily."
        guard rawValue.hasPrefix(prefix), rawValue != "daily" else { return nil }
        return UUID(uuidString: String(rawValue.dropFirst(prefix.count)))
    }

    var overrideGroupID: UUID? {
        let prefix = "override."
        guard rawValue.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(rawValue.dropFirst(prefix.count)))
    }
}

extension DeviceActivityEvent.Name {
    var tickGroupID: UUID? {
        let prefix = "tick."
        guard rawValue.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(rawValue.dropFirst(prefix.count)))
    }
}

extension ManagedSettingsStore.Name {
    static let goldtime = Self("goldtime")
}

class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private var store: ManagedSettingsStore { ManagedSettingsStore(named: .goldtime) }

    private var dailySchedule: DeviceActivitySchedule {
        DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
    }

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        if activity.dailyGroupID != nil {
            if SharedStore.resetDailyProtectionStateIfNeeded() {
                clearSystemShield()
            }
        } else if activity.overrideGroupID != nil {
            SharedStore.recordOverrideIntervalDidStart(activityName: activity.rawValue)
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        if activity == .daily || activity.dailyGroupID != nil {
            // daily 계열은 릴레이에서 처리하므로 무시
            return
        }
        let result = SharedStore.clearOverrideAfterActivityEnd(activityName: activity.rawValue)
        SharedStore.recordOverrideIntervalDidEnd(
            activityName: activity.rawValue,
            parsedGroupID: result.parsedGroupID,
            didClearOverride: result.didClearOverride
        )
        applyShieldFromGroups()
    }

    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)
        guard activity.overrideGroupID != nil else { return }

        let result = SharedStore.clearOverrideAfterActivityEnd(activityName: activity.rawValue)
        SharedStore.recordOverrideIntervalWillEndWarning(
            activityName: activity.rawValue,
            parsedGroupID: result.parsedGroupID,
            didClearOverride: result.didClearOverride
        )
        applyShieldFromGroups()
    }

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)

        guard let groupID = event.tickGroupID,
              activity.dailyGroupID == groupID,
              let group = SharedStore.group(id: groupID) else { return }

        let usedTime = SharedStore.incrementAndGetUsedTime(for: groupID)

        if usedTime >= group.dailyLimitMinutes {
            SharedStore.recordShieldHit()
            SharedStore.markGroupShielded(groupID)
            applyShieldFromGroups()
        } else {
            // 릴레이: stop + start (최신 selection 반영)
            let nextEvent = DeviceActivityEvent(
                applications: group.selection.applicationTokens,
                categories: [],
                webDomains: group.selection.webDomainTokens,
                threshold: DateComponents(minute: 1)
            )
            let center = DeviceActivityCenter()
            center.stopMonitoring([activity])
            try? center.startMonitoring(
                activity,
                during: dailySchedule,
                events: [event: nextEvent]
            )
        }
    }

    @discardableResult
    private func applyShieldFromGroups() -> Int {
        let applicationTokens = SharedStore.shieldApplicationTokens()
        let webDomainTokens = SharedStore.shieldWebDomainTokens()
        let tokenCount = applicationTokens.count + webDomainTokens.count
        guard tokenCount > 0 else {
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
            SharedStore.isShieldActive = false
            SharedStore.recordOverrideReapply(
                tokenCount: 0,
                message: "cleared shield because token union is empty"
            )
            return 0
        }

        store.shield.applications = applicationTokens.isEmpty ? nil : applicationTokens
        store.shield.applicationCategories = nil
        store.shield.webDomains = webDomainTokens.isEmpty ? nil : webDomainTokens
        SharedStore.isShieldActive = true
        SharedStore.recordOverrideReapply(
            tokenCount: tokenCount,
            message: "applied shield from locked groups"
        )
        return tokenCount
    }

    private func clearSystemShield() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
    }
}
