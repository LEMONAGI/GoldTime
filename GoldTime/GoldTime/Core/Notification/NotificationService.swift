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
    static let dailyMorningIdentifier = "com.goldtime.dailyMorning"

    static func authorizationStatus() async -> UNAuthorizationStatus {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }

    static func requestAuthorizationIfNeeded() async -> UNAuthorizationStatus {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .timeSensitive])
        case .authorized, .provisional:
            if settings.timeSensitiveSetting == .disabled {
                _ = try? await center.requestAuthorization(options: [.timeSensitive])
            }
        default:
            break
        }
        return await authorizationStatus()
    }

    /// 쉴드의 "GoldTime 가기" 버튼 탭 시 발송. 알림 탭 → 앱 진입.
    static func scheduleOpenAppNotification() {
        let content = UNMutableNotificationContent()
        content.title = "한도에 도달했어요"
        content.body = "GoldTime을 열어 1분 연장 또는 광고 시청을 선택하세요."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = openAppCategory

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    /// 자정 배경 작업에서 호출. 어제 추가 사용 분량에 따라 다음 날 오전 9시 알림 예약.
    /// isWeekStart가 true이면 주간 통계 알림 내용으로 대체한다.
    static func scheduleDailyMorningNotification(extraMinutes: Int, isWeekStart: Bool = false) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [dailyMorningIdentifier, weeklyStatsIdentifier])

        let content = UNMutableNotificationContent()
        content.sound = .default

        if isWeekStart {
            content.title = "주간 통계가 도착했어요!"
            content.body = "이번 주 기록을 확인해보세요."
        } else {
            switch extraMinutes {
            case 0:
                content.title = "어제 한도 내 사용."
                content.body = "좋은 하루였어요. 저한텐 아니고요."
            case 1...5:
                content.title = "어제 \(extraMinutes)분 초과."
                content.body = "이 정도면 살짝 눈 감아드릴게요."
            case 6...15:
                content.title = "어제 \(extraMinutes)분 초과."
                content.body = "시간이 금이라는 거 기억하시죠."
            case 16...30:
                content.title = "어제 \(extraMinutes)분 초과."
                content.body = "어제 청구서가 좀 두꺼웠어요."
            default:
                content.title = "어제 \(extraMinutes)분 초과."
                content.body = "이 정도면 저를 위해 노력하신 거죠?"
            }
        }

        var components = DateComponents()
        components.hour = 9
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: dailyMorningIdentifier, content: content, trigger: trigger)
        center.add(request, withCompletionHandler: nil)
    }
}
