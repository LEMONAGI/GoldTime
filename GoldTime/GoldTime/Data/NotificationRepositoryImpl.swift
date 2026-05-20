
import Foundation
import UserNotifications

struct NotificationRepositoryImpl: NotificationRepository {
    func authorizationState() async -> NotificationPermissionState {
        await NotificationService.authorizationStatus().permissionState
    }

    func requestAuthorizationIfNeeded() async -> NotificationPermissionState {
        await NotificationService.requestAuthorizationIfNeeded().permissionState
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
