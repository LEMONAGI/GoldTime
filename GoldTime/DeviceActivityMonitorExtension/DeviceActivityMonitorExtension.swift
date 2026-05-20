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

    var overrideGroupID: UUID? {
        let prefix = "override."
        guard rawValue.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(rawValue.dropFirst(prefix.count)))
    }
}

extension DeviceActivityEvent.Name {
    var dailyLimitGroupID: UUID? {
        let prefix = "dailyLimit."
        guard rawValue.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(rawValue.dropFirst(prefix.count)))
    }
}

extension ManagedSettingsStore.Name {
    static let goldtime = Self("goldtime")
}

class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private var store: ManagedSettingsStore { ManagedSettingsStore(named: .goldtime) }

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        if activity == .daily, SharedStore.resetDailyProtectionStateIfNeeded() {
            clearSystemShield()
        } else if activity.overrideGroupID != nil {
            SharedStore.recordOverrideIntervalDidStart(activityName: activity.rawValue)
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        switch activity {
        case .daily:
            break
        default:
            let result = SharedStore.clearOverrideAfterActivityEnd(activityName: activity.rawValue)
            SharedStore.recordOverrideIntervalDidEnd(
                activityName: activity.rawValue,
                parsedGroupID: result.parsedGroupID,
                didClearOverride: result.didClearOverride
            )
            applyShieldFromGroups()
            break
        }
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
        if activity == .daily, let groupID = event.dailyLimitGroupID {
            SharedStore.recordShieldHit()
            SharedStore.markGroupShielded(groupID)
            applyShieldFromGroups()
        }
    }

    @discardableResult
    private func applyShieldFromGroups() -> Int {
        let applicationTokens = SharedStore.shieldApplicationTokens()
        guard !applicationTokens.isEmpty else {
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

        store.shield.applications = applicationTokens
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        SharedStore.isShieldActive = true
        SharedStore.recordOverrideReapply(
            tokenCount: applicationTokens.count,
            message: "applied shield from locked groups"
        )
        return applicationTokens.count
    }

    private func clearSystemShield() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
    }
}
