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
            list.append(String(localized: "appPicker.warning.tooMany \(SharedStore.maxAppsPerGroup) \(count) \(SharedStore.maxAppsPerGroup)"))
        }
        return list
    }

    static func notices(for summary: SelectionSummary) -> [String] {
        var list: [String] = []
        if summary.hasWeb {
            list.append(String(localized: "appPicker.notice.web"))
        }
        return list
    }
}
