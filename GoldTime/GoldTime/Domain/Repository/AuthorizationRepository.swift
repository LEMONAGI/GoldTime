
import Foundation

protocol AuthorizationRepository {
    var isAuthorized: Bool { get }
    func refresh()
    func request() async throws
}
