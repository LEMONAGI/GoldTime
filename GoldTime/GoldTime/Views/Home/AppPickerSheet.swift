//
//  AppPickerSheet.swift
//  GoldTime
//

import FamilyControls
import SwiftUI

struct AppPickerSheet: View {
    @Binding var selection: FamilyActivitySelection
    @Environment(\.dismiss) private var dismiss
    let onCommit: () -> Void

    private var warnings: [String] {
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.circle.fill")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.red)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.systemBackground))
                    Divider()
                }
                FamilyActivityPicker(selection: $selection)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") {
                        onCommit()
                        dismiss()
                    }
                    .disabled(!warnings.isEmpty)
                }
            }
            .navigationTitle("앱 선택")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
