
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
