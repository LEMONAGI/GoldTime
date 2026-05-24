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
    static let weeklyStatsIdentifier = "com.goldtime.weeklyStats"

    static func authorizationStatus() async -> UNAuthorizationStatus {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }

    static func requestAuthorizationIfNeeded() async -> UNAuthorizationStatus {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else {
            return settings.authorizationStatus
        }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        return await authorizationStatus()
    }

    /// 쉴드의 "GoldTime 가기" 버튼 탭 시 발송. 알림 탭 → 앱 진입.
    static func scheduleOpenAppNotification() {
        let content = UNMutableNotificationContent()
        content.title = "한도에 도달했어요"
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

    /// 주 마지막 날 저녁(20:00)에 주간 통계 알림 예약. 매주 반복, 중복 방지를 위해 기존 요청 먼저 제거.
    static func scheduleWeeklyStatsNotification(weekStartDay: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [weeklyStatsIdentifier])

        let lastWeekday = weekStartDay == 1 ? 7 : weekStartDay - 1

        let content = UNMutableNotificationContent()
        content.title = "주간 통계가 도착했어요!"
        content.body = "이번 주 기록을 확인해보세요."
        content.sound = .default

        var components = DateComponents()
        components.weekday = lastWeekday
        components.hour = 20
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: weeklyStatsIdentifier, content: content, trigger: trigger)
        center.add(request, withCompletionHandler: nil)
    }
}
