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
            // "그만 쓰기" — 쉴드 닫고 홈으로
            DailyStatsStore.recordWalkAway()
            OpenRequestStore.clear()
            completionHandler(.close)
        case .secondaryButtonPressed:
            // "GoldTime 가기" — 알림으로 진입 유도 (익스텐션에서 UIApplication.open 불가)
            OpenRequestStore.markStarted(
                applicationToken: applicationToken,
                webDomainToken: webDomainToken
            )
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
        content.title = "한도 끝났어요"
        content.body = "더 쓰려면 GoldTime에서 선택하세요. 지금 나가면 광고 없이 끝납니다."
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
