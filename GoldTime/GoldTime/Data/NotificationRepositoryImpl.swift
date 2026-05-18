
import Foundation

struct NotificationRepositoryImpl: NotificationRepository {
    func requestAuthorizationIfNeeded() async {
        await NotificationService.requestAuthorizationIfNeeded()
    }
}
