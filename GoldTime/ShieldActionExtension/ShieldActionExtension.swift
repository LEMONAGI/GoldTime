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

        static var defaults: UserDefaults {
            UserDefaults(suiteName: suiteName) ?? .standard
        }

        static func markStarted(applicationToken: ApplicationToken?) {
            defaults.set(Date(), forKey: startedAtKey)
            if let applicationToken,
               let data = try? JSONEncoder().encode(applicationToken) {
                defaults.set(data, forKey: applicationTokenKey)
            } else {
                defaults.removeObject(forKey: applicationTokenKey)
            }
        }

        static func clear() {
            defaults.removeObject(forKey: startedAtKey)
            defaults.removeObject(forKey: applicationTokenKey)
        }
    }

    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        respond(to: action, applicationToken: application, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        respond(to: action, applicationToken: nil, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        respond(to: action, applicationToken: nil, completionHandler: completionHandler)
    }

    private func respond(
        to action: ShieldAction,
        applicationToken: ApplicationToken?,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .primaryButtonPressed:
            // "그만 쓰기" — 쉴드 닫고 홈으로
            OpenRequestStore.clear()
            completionHandler(.close)
        case .secondaryButtonPressed:
            // "GoldTime 가기" — 알림으로 진입 유도 (익스텐션에서 UIApplication.open 불가)
            OpenRequestStore.markStarted(applicationToken: applicationToken)
            scheduleOpenAppNotification()
            completionHandler(.defer)
        case .firstSecondarySubmenuItemPressed,
             .secondSecondarySubmenuItemPressed,
             .thirdSecondarySubmenuItemPressed:
            completionHandler(.none)
        @unknown default:
            completionHandler(.none)
        }
    }

    private func scheduleOpenAppNotification() {
        let content = UNMutableNotificationContent()
        content.title = "한도 끝났어요"
        content.body = "더 쓰려면 GoldTime에서 선택하세요. 지금 나가면 광고 없이 끝납니다."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "goldtime.open-app",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
