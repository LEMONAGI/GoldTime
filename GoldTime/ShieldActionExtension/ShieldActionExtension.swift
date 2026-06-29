//
//  ShieldActionExtension.swift
//  ShieldActionExtension
//

import Foundation
import ManagedSettings
import UserNotifications

class ShieldActionExtension: ShieldActionDelegate {
    private enum OpenRequestStore {
        static let suiteName = "group.com.goldtime.shared"
        static let startedAtKey = "shieldOpenRequestStartedAt"
        static let applicationTokenKey = "lastRequestedUnlockApplicationToken"
        static let webDomainTokenKey = "lastRequestedUnlockWebDomainToken"

        static var defaults: UserDefaults {
            UserDefaults(suiteName: suiteName) ?? .standard
        }

        static func markStarted(
            applicationToken: ApplicationToken?,
            webDomainToken: WebDomainToken?
        ) {
            defaults.set(Date(), forKey: startedAtKey)
            if let applicationToken,
               let data = try? JSONEncoder().encode(applicationToken) {
                defaults.set(data, forKey: applicationTokenKey)
            } else {
                defaults.removeObject(forKey: applicationTokenKey)
            }
            if let webDomainToken,
               let data = try? JSONEncoder().encode(webDomainToken) {
                defaults.set(data, forKey: webDomainTokenKey)
            } else {
                defaults.removeObject(forKey: webDomainTokenKey)
            }
        }

        static func clear() {
            defaults.removeObject(forKey: startedAtKey)
            defaults.removeObject(forKey: applicationTokenKey)
            defaults.removeObject(forKey: webDomainTokenKey)
        }
    }

    private enum DailyStatsStore {
        static let suiteName = "group.com.goldtime.shared"
        static let dailyStatsByDateKey = "dailyStatsByDate"

        static var defaults: UserDefaults {
            UserDefaults(suiteName: suiteName) ?? .standard
        }

        struct DailyStats: Codable {
            var dateKey: String
            var adWatchCount: Int
            var adUnlockedSeconds: Int
            var oneMinuteUsedCount: Int
            var shieldHitCount: Int
            var walkAwayCount: Int

            init(dateKey: String) {
                self.dateKey = dateKey
                adWatchCount = 0
                adUnlockedSeconds = 0
                oneMinuteUsedCount = 0
                shieldHitCount = 0
                walkAwayCount = 0
            }

            private enum CodingKeys: String, CodingKey {
                case dateKey
                case adWatchCount
                case adUnlockedSeconds
                case oneMinuteUsedCount
                case shieldHitCount
                case walkAwayCount
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                dateKey = try container.decode(String.self, forKey: .dateKey)
                adWatchCount = try container.decodeIfPresent(Int.self, forKey: .adWatchCount) ?? 0
                adUnlockedSeconds = try container.decodeIfPresent(Int.self, forKey: .adUnlockedSeconds) ?? 0
                oneMinuteUsedCount = try container.decodeIfPresent(Int.self, forKey: .oneMinuteUsedCount) ?? 0
                shieldHitCount = try container.decodeIfPresent(Int.self, forKey: .shieldHitCount) ?? 0
                walkAwayCount = try container.decodeIfPresent(Int.self, forKey: .walkAwayCount) ?? 0
            }
        }

        static func recordWalkAway() {
            let key = dateKey(for: Date())
            var statsByDate = loadStatsByDate()
            var stats = statsByDate[key] ?? DailyStats(dateKey: key)
            stats.walkAwayCount += 1
            statsByDate[key] = stats
            if let data = try? JSONEncoder().encode(statsByDate) {
                defaults.set(data, forKey: dailyStatsByDateKey)
            }
        }

        private static func loadStatsByDate() -> [String: DailyStats] {
            guard let data = defaults.data(forKey: dailyStatsByDateKey) else {
                return [:]
            }
            return (try? JSONDecoder().decode([String: DailyStats].self, from: data)) ?? [:]
        }

        private static func dateKey(for date: Date) -> String {
            dateKeyFormatter.string(from: date)
        }

        private static let dateKeyFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.calendar = Calendar.current
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter
        }()
    }

    /// extension에서 발생한 분석 이벤트를 App Group 큐에 적재한다. ShieldActionExtension은
    /// `SharedStore`(메인 앱·DeviceActivityMonitor 타겟 전용)를 링크하지 않으므로, 큐 키와
    /// Codable 형태(`SharedStore.PendingAnalyticsEvent`)를 그대로 복제해 메인 앱이
    /// `drainPendingAnalyticsEvents()`로 드레인하게 한다. 형태가 어긋나면 드레인 시 디코딩
    /// 실패로 큐 전체가 소실되니 name/parameters/timestamp 순서·타입을 바꾸지 말 것.
    private enum PendingAnalyticsStore {
        static let suiteName = "group.com.goldtime.shared"
        static let key = "pendingAnalyticsEvents"
        static let cap = 200

        static var defaults: UserDefaults {
            UserDefaults(suiteName: suiteName) ?? .standard
        }

        private struct Event: Codable {
            let name: String
            let parameters: [String: String]
            let timestamp: Date
        }

        static func enqueue(_ name: String) {
            var events = load()
            events.append(Event(name: name, parameters: [:], timestamp: Date()))
            if events.count > cap {
                events = Array(events.suffix(cap))
            }
            if let data = try? JSONEncoder().encode(events) {
                defaults.set(data, forKey: key)
            }
        }

        private static func load() -> [Event] {
            guard let data = defaults.data(forKey: key) else { return [] }
            return (try? JSONDecoder().decode([Event].self, from: data)) ?? []
        }
    }

    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        respond(
            to: action,
            applicationToken: application,
            webDomainToken: nil,
            completionHandler: completionHandler
        )
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        respond(
            to: action,
            applicationToken: nil,
            webDomainToken: webDomain,
            completionHandler: completionHandler
        )
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        respond(
            to: action,
            applicationToken: nil,
            webDomainToken: nil,
            completionHandler: completionHandler
        )
    }

    private func respond(
        to action: ShieldAction,
        applicationToken: ApplicationToken?,
        webDomainToken: WebDomainToken?,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .primaryButtonPressed:
            // "그만 쓰기" — 쉴드 닫고 홈으로 (차단 수용 분기)
            DailyStatsStore.recordWalkAway()
            PendingAnalyticsStore.enqueue("shield_dismissed")
            OpenRequestStore.clear()
            completionHandler(.close)
        case .secondaryButtonPressed:
            // "GoldTime 가기" — 알림으로 진입 유도 (익스텐션에서 UIApplication.open 불가)
            // 연장/광고로 이어지는 입구 분기.
            OpenRequestStore.markStarted(
                applicationToken: applicationToken,
                webDomainToken: webDomainToken
            )
            PendingAnalyticsStore.enqueue("shield_open_requested")
            scheduleOpenAppNotification {
                completionHandler(.defer)
            }
        case .firstSecondarySubmenuItemPressed,
             .secondSecondarySubmenuItemPressed,
             .thirdSecondarySubmenuItemPressed:
            completionHandler(.none)
        @unknown default:
            completionHandler(.none)
        }
    }

    private func scheduleOpenAppNotification(completion: @escaping () -> Void) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "notification.openApp.title")
        content.body = String(localized: "notification.openApp.body")
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(
            identifier: "goldtime.open-app",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { _ in
            completion()
        }
    }
}
