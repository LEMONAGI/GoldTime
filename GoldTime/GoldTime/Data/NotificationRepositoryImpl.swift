
import Foundation
import UserNotifications

struct NotificationRepositoryImpl: NotificationRepository {
    func authorizationState() async -> NotificationPermissionState {
        await NotificationService.authorizationStatus().permissionState
    }

    func requestAuthorizationIfNeeded() async -> NotificationPermissionState {
        await NotificationService.requestAuthorizationIfNeeded().permissionState
    }

    func isNotificationDeferredByScheduledSummary() async -> Bool {
        await NotificationService.isDeferredByScheduledSummary()
    }

    func scheduleDailyMorningNotification(extraMinutes: Int) {
        NotificationService.scheduleDailyMorningNotification(extraMinutes: extraMinutes)
    }

    var isDailyMorningNotificationEnabled: Bool {
        SharedStore.isDailyMorningNotificationEnabled
    }

    func setDailyMorningNotificationEnabled(_ enabled: Bool) {
        SharedStore.isDailyMorningNotificationEnabled = enabled
        if enabled {
            NotificationService.scheduleDailyMorningNotificationUsingYesterdayUsage()
        } else {
            NotificationService.cancelDailyMorningNotification()
        }
    }

    var isUsageAlertEnabled: Bool {
        SharedStore.isUsageAlertEnabled
    }

    func setUsageAlertEnabled(_ enabled: Bool) {
        SharedStore.isUsageAlertEnabled = enabled
        if enabled {
            // 켜는 즉시 현재 시간대 그룹 구성으로 5분 전·종료 알림을 미리 건다.
            NotificationService.rescheduleTimeWindowAlerts(groups: SharedStore.screenTimeGroups)
        } else {
            // 끄면 예약된 시간대 알림을 모두 취소(한도 임박·재사용 알림은 발송 시점 토글 가드로 막힘).
            NotificationService.cancelTimeWindowAlerts()
        }
    }
}

private extension UNAuthorizationStatus {
    var permissionState: NotificationPermissionState {
        switch self {
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .authorized:
            .authorized
        case .provisional:
            .provisional
        case .ephemeral:
            .ephemeral
        @unknown default:
            .unknown
        }
    }
}
