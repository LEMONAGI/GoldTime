import Foundation

/// 앱 활성화 시 Firebase user property로 갱신하는 최신 권한 스냅샷.
/// 이벤트가 아니라 사용자 속성으로 보내 현재 활성 사용자의 허용 비율을 본다.
struct AuthorizationAnalyticsProperties {
    let isScreenTimeAuthorized: Bool
    let isNotificationAuthorized: Bool

    init(screenTimeAuthorized: Bool, notificationState: NotificationPermissionState) {
        isScreenTimeAuthorized = screenTimeAuthorized
        isNotificationAuthorized = [.authorized, .provisional, .ephemeral].contains(notificationState)
    }

    var entries: [(name: String, value: String?)] {
        [
            ("authorized_screen_time", String(isScreenTimeAuthorized)),
            ("authorized_notification", String(isNotificationAuthorized))
        ]
    }
}
