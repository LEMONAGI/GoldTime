
import Foundation

final class AnalyticsRepositoryImpl: AnalyticsRepository {
    private let service: AnalyticsService

    init(service: AnalyticsService = .shared) {
        self.service = service
    }

    func log(_ event: AnalyticsEvent) {
        service.logEvent(name: event.name, parameters: event.parameters)
    }

    func setUserProperty(_ value: String?, for name: String) {
        service.setUserProperty(value, for: name)
    }

    func recordError(_ error: Error, context: String) {
        service.recordError(error, context: context)
    }
}
