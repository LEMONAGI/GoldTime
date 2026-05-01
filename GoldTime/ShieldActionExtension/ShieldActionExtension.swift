//
//  ShieldActionExtension.swift
//  ShieldActionExtension
//

import Foundation
import ManagedSettings
import UserNotifications

class ShieldActionExtension: ShieldActionDelegate {
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
            // "잘 참았어요" — 쉴드 닫고 홈으로
            completionHandler(.close)
        case .secondaryButtonPressed:
            // "GoldTime 가기" — 알림으로 진입 유도 (익스텐션에서 UIApplication.open 불가)
            scheduleOpenAppNotification()
            completionHandler(.defer)
        @unknown default:
            completionHandler(.none)
        }
    }

    private func scheduleOpenAppNotification() {
        let content = UNMutableNotificationContent()
        content.title = "시간이 금이다 ⏳"
        content.body = "GoldTime을 열어 1분 연장 또는 광고 시청을 선택하세요."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
