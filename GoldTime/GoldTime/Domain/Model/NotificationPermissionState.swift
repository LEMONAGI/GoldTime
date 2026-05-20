import Foundation

enum NotificationPermissionState: Equatable {
    case notDetermined
    case authorized
    case denied
    case provisional
    case ephemeral
    case unknown
}
