//
//  NotificationService.swift
//  GoldTime
//
//  Local Notification 발송. ShieldAction 익스텐션에서 GoldTime 진입 유도용.
//

import Foundation
import UserNotifications

enum NotificationService {
    static let openAppCategory = "GOLDTIME_OPEN"

    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    /// 쉴드의 "GoldTime 가기" 버튼 탭 시 발송. 알림 탭 → 앱 진입.
    static func scheduleOpenAppNotification() {
        let content = UNMutableNotificationContent()
        content.title = "시간이 금이다 ⏳"
        content.body = "GoldTime을 열어 1분 연장 또는 광고 시청을 선택하세요."
        content.sound = .default
        content.categoryIdentifier = openAppCategory

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
