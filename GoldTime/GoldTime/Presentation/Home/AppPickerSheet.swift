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

    private var viewModel: AppPickerSheetViewModel {
        AppPickerSheetViewModel(selection: selection)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !viewModel.warnings.isEmpty || !viewModel.notices.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.circle.fill")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.red)
                        }
                        ForEach(viewModel.notices, id: \.self) { notice in
                            Label(notice, systemImage: "info.circle.fill")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)
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
                    Button(role: .cancel) { dismiss() }
                        .tint(.gray100)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .confirm) {
                        onCommit()
                        dismiss()
                    }
                    .disabled(!viewModel.warnings.isEmpty)
                }
            }
            .navigationTitle("항목 선택")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
