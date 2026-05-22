//
//  SettingsView.swift
//  GoldTime
//

import SwiftUI
import UIKit

struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    let onRequestResetProtection: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            permissionsSection
            notificationsSection
            troubleshootingSection
        }
        .navigationTitle("설정")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.loadState()
        }
        .alert(item: $viewModel.alertMessage) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("확인"))
            )
        }
    }

    private var permissionsSection: some View {
        Section("권한") {
            if viewModel.isScreenTimeAuthorized {
                settingsRow(
                    title: "스크린 타임 권한",
                    subtitle: "허용됨",
                    systemName: "checkmark.circle.fill",
                    tint: .green
                )
            } else {
                Button {
                    guard !viewModel.isRequestingScreenTimeAuthorization else { return }
                    Task { await viewModel.requestScreenTimeAuthorization() }
                } label: {
                    settingsRow(
                        title: "스크린 타임 권한",
                        subtitle: "확인이 필요해요",
                        systemName: "exclamationmark.circle.fill",
                        tint: .orange,
                        showsProgress: viewModel.isRequestingScreenTimeAuthorization,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var notificationsSection: some View {
        Section("알림") {
            if viewModel.notificationPermissionState == .notDetermined {
                Button {
                    guard !viewModel.isRequestingNotificationAuthorization else { return }
                    Task { await viewModel.requestNotificationAuthorization() }
                } label: {
                    notificationRow(showsChevron: true)
                }
                .buttonStyle(.plain)
            } else if viewModel.notificationPermissionState == .denied {
                Button {
                    openAppSettings()
                } label: {
                    notificationRow(showsChevron: true)
                }
                .buttonStyle(.plain)
            } else {
                notificationRow()
            }
        }
    }

    private func notificationRow(showsChevron: Bool = false) -> some View {
        settingsRow(
            title: "GoldTime 복귀 알림",
            subtitle: notificationSubtitle,
            systemName: notificationIconName,
            tint: notificationTint,
            showsProgress: viewModel.isRequestingNotificationAuthorization,
            showsChevron: showsChevron
        )
    }

    private var troubleshootingSection: some View {
        Section("문제 해결") {
            Button(role: .destructive) {
                onRequestResetProtection()
            } label: {
                actionRow(
                    title: "전체 보호 초기화",
                    subtitle: "그룹 설정은 유지하고 현재 잠금과 모니터링만 다시 맞춤",
                    systemName: "arrow.clockwise"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func actionRow(title: String, subtitle: String, systemName: String) -> some View {
        HStack(spacing: 12) {
            IconTile(systemName: systemName, tint: Color.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func settingsRow(
        title: String,
        subtitle: String,
        systemName: String,
        tint: Color,
        showsProgress: Bool = false,
        showsChevron: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            IconTile(systemName: systemName, tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if showsProgress {
                ProgressView()
            } else if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var notificationSubtitle: String {
        switch viewModel.notificationPermissionState {
        case .notDetermined:
            "권한 요청 전"
        case .authorized:
            "허용됨"
        case .denied:
            "iOS 설정에서 꺼져 있어요"
        case .provisional:
            "임시 허용됨"
        case .ephemeral:
            "일시 허용됨"
        case .unknown:
            "상태 확인 필요"
        }
    }

    private var notificationIconName: String {
        switch viewModel.notificationPermissionState {
        case .authorized, .provisional, .ephemeral:
            "bell.badge.fill"
        case .denied:
            "bell.slash.fill"
        case .notDetermined, .unknown:
            "bell"
        }
    }

    private var notificationTint: Color {
        switch viewModel.notificationPermissionState {
        case .authorized, .provisional, .ephemeral:
            .green
        case .denied:
            .orange
        case .notDetermined, .unknown:
            Color.accent
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}
