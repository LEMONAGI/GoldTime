//
//  NotificationSettingsView.swift
//  GoldTime
//
//  알림 권한이 있을 때 어떤 알림을 받을지 고르는 화면.
//

import SwiftUI

struct NotificationSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(spacing: 0) {
                    toggleRow(
                        systemName: "sun.max.fill",
                        tint: Color.accent,
                        title: "하루 요약 알림",
                        subtitle: "매일 아침 9시에 어제 쓴 시간을 정리해 보내드려요.",
                        isOn: Binding(
                            get: { viewModel.isDailyMorningNotificationEnabled },
                            set: { viewModel.setDailyMorningNotificationEnabled($0) }
                        )
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    Divider().padding(.horizontal, 20)

                    toggleRow(
                        systemName: "bell.badge.fill",
                        tint: .green,
                        title: "앱 복귀 알림",
                        subtitle: "한도에 도달하면 GoldTime으로 돌아오게 알려드려요. 꼭 필요해서 끌 수 없어요.",
                        isOn: .constant(true),
                        isLocked: true
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("알림 설정")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggleRow(
        systemName: String,
        tint: Color,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        isLocked: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            IconTile(systemName: systemName, tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Color.accent)
                .disabled(isLocked)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView(viewModel: SettingsViewModel())
    }
}
