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
        if activity == .daily {
            SharedStore.oneMinuteUsedToday = 0
            SharedStore.oneMinuteCounterDate = Date()
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
            SharedStore.clearAllShieldState()
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        switch activity {
        case .daily:
            SharedStore.oneMinuteUsedToday = 0
            SharedStore.oneMinuteCounterDate = Date()
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
            SharedStore.clearAllShieldState()
        default:
            if let groupID = activity.overrideGroupID {
                SharedStore.clearOverride(for: groupID)
                applyShieldFromGroups()
            }
            break
        }
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

    private func applyShieldFromGroups() {
        let applicationTokens = SharedStore.shieldApplicationTokens()
        guard !applicationTokens.isEmpty else {
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
            SharedStore.isShieldActive = false
            return
        }

        store.shield.applications = applicationTokens
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        SharedStore.isShieldActive = true
    }
}
