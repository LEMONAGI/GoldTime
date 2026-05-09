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

        static var defaults: UserDefaults {
            UserDefaults(suiteName: suiteName) ?? .standard
        }

        static func markStarted() {
            defaults.set(Date(), forKey: startedAtKey)
        }

        static func clear() {
            defaults.removeObject(forKey: startedAtKey)
        }
    }

    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        respond(to: action, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        respond(to: action, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        respond(to: action, completionHandler: completionHandler)
    }

    private func respond(
        to action: ShieldAction,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .primaryButtonPressed:
            // "그만 쓰기" — 쉴드 닫고 홈으로
            OpenRequestStore.clear()
            completionHandler(.close)
        case .secondaryButtonPressed:
            // "GoldTime 가기" — 알림으로 진입 유도 (익스텐션에서 UIApplication.open 불가)
            OpenRequestStore.markStarted()
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
        content.title = "한도에 도달했어요"
        content.body = "GoldTime을 열어 1분 연장 또는 광고 시청을 선택하세요."
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
