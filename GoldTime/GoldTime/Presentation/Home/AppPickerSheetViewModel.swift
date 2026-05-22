//
//  AppPickerSheetViewModel.swift
//  GoldTime
//

import FamilyControls
import Foundation

struct AppPickerSheetViewModel {
    struct SelectionSummary {
        let appCount: Int
        let webDomainCount: Int
        let hasCategory: Bool

        init(appCount: Int, webDomainCount: Int, hasCategory: Bool) {
            self.appCount = appCount
            self.webDomainCount = webDomainCount
            self.hasCategory = hasCategory
        }

        init(selection: FamilyActivitySelection) {
            self.init(
                appCount: selection.applicationTokens.count,
                webDomainCount: selection.webDomainTokens.count,
                hasCategory: !selection.categoryTokens.isEmpty
            )
        }

        var selectionCount: Int {
            appCount + webDomainCount
        }

        var hasWeb: Bool {
            webDomainCount > 0
        }
    }

    let selection: FamilyActivitySelection

    init(selection: FamilyActivitySelection) {
        self.selection = selection
    }

    var warnings: [String] {
        Self.warnings(for: SelectionSummary(selection: selection))
    }

    var notices: [String] {
        Self.notices(for: SelectionSummary(selection: selection))
    }

    static func warnings(for summary: SelectionSummary) -> [String] {
        var list: [String] = []
        let count = summary.selectionCount
        if count > SharedStore.maxAppsPerGroup {
            list.append("앱과 웹 사이트를 합쳐 \(SharedStore.maxAppsPerGroup)개 이하로 선택해주세요 (\(count)/\(SharedStore.maxAppsPerGroup))")
        }
        return list
    }

    static func notices(for summary: SelectionSummary) -> [String] {
        var list: [String] = []
        if summary.hasWeb {
            list.append("웹 사이트는 사파리에서 사용하는 것만 가능해요.")
        }
        return list
    }
}
