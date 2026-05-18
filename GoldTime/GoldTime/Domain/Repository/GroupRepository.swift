
import Foundation

protocol GroupRepository {
    var screenTimeGroups: [ScreenTimeGroup] { get set }
    func defaultGroupName(for index: Int) -> String
}
