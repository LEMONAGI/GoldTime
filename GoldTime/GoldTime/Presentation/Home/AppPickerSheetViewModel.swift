//
//  AppPickerSheetViewModel.swift
//  GoldTime
//

import FamilyControls
import Foundation

struct AppPickerSheetViewModel {
    struct SelectionSummary {
        let appCount: Int
        let hasCategory: Bool
        let hasWeb: Bool

        init(appCount: Int, hasCategory: Bool, hasWeb: Bool) {
            self.appCount = appCount
            self.hasCategory = hasCategory
            self.hasWeb = hasWeb
        }

        init(selection: FamilyActivitySelection) {
            self.init(
                appCount: selection.applicationTokens.count,
                hasCategory: !selection.categoryTokens.isEmpty,
                hasWeb: !selection.webDomainTokens.isEmpty
            )
        }
    }

    let selection: FamilyActivitySelection

    init(selection: FamilyActivitySelection) {
        self.selection = selection
    }

    var warnings: [String] {
        Self.warnings(for: SelectionSummary(selection: selection))
    }

    static func warnings(for summary: SelectionSummary) -> [String] {
        var list: [String] = []
        if summary.hasWeb {
            list.append("웹사이트는 아직 지원하지 않아요. 앱만 선택해주세요.")
        }
        let count = summary.appCount
        if count > SharedStore.maxAppsPerGroup {
            list.append("카테고리에 포함된 앱도 앱 개수에 포함돼요. \(SharedStore.maxAppsPerGroup)개 이하로 선택해주세요 (\(count)/\(SharedStore.maxAppsPerGroup))")
        }
        return list
    }
}
