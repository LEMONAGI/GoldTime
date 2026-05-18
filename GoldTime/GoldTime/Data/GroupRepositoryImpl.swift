
import Foundation

struct GroupRepositoryImpl: GroupRepository {
    var screenTimeGroups: [ScreenTimeGroup] {
        get { SharedStore.screenTimeGroups }
        set { SharedStore.screenTimeGroups = newValue }
    }

    func defaultGroupName(for index: Int) -> String {
        SharedStore.defaultGroupName(for: index)
    }
}
