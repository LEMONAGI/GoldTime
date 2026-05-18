//
//  AppPickerSheetViewModel.swift
//  GoldTime
//

import FamilyControls
import Foundation

struct AppPickerSheetViewModel {
    let selection: FamilyActivitySelection

    var warnings: [String] {
        var list: [String] = []
        let hasCategory = !selection.categoryTokens.isEmpty
        let hasWeb = !selection.webDomainTokens.isEmpty
        if hasCategory && hasWeb {
            list.append("카테고리와 웹사이트는 아직 지원하지 않아요. 앱만 선택해주세요.")
        } else if hasCategory {
            list.append("카테고리는 아직 지원하지 않아요. 앱만 선택해주세요.")
        } else if hasWeb {
            list.append("웹사이트는 아직 지원하지 않아요. 앱만 선택해주세요.")
        }
        let count = selection.applicationTokens.count
        if count > SharedStore.maxAppsPerGroup {
            list.append("앱을 \(SharedStore.maxAppsPerGroup)개 이하로 선택해주세요 (\(count)/\(SharedStore.maxAppsPerGroup))")
        }
        return list
    }
}
