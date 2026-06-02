//
//  SettingsView.swift
//  GoldTime
//

import SwiftUI
import UIKit

struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    let isReconnecting: Bool
    let onRequestReconnect: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                generalCard
                troubleshootingCard
                feedbackCard
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
        .background(Color(.systemGroupedBackground))
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

    private var generalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "일반")
            VStack(spacing: 0) {
                if viewModel.isScreenTimeAuthorized {
                    settingsRow(
                        title: "스크린 타임 권한",
                        subtitle: "허용됨",
                        systemName: "checkmark.circle.fill",
                        tint: .green
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                } else {
                    Button {
                        guard !viewModel.isRequestingScreenTimeAuthorization else { return }
                        Task { await viewModel.requestScreenTimeAuthorization() }
                    } label: {
                        settingsRow(
                            title: "스크린 타임 권한",
                            subtitle: "확인이 필요해요",
                            systemName: "exclamationmark.circle.fill",
                            tint: .red,
                            showsProgress: viewModel.isRequestingScreenTimeAuthorization,
                            showsChevron: true
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }

                Divider().padding(.horizontal, 20)

                if viewModel.notificationPermissionState == .notDetermined {
                    Button {
                        guard !viewModel.isRequestingNotificationAuthorization else { return }
                        Task { await viewModel.requestNotificationAuthorization() }
                    } label: {
                        notificationRow(showsChevron: true)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                } else if viewModel.notificationPermissionState == .denied {
                    Button {
                        openAppSettings()
                    } label: {
                        notificationRow(showsChevron: true)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                } else {
                    notificationRow()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }

                Divider().padding(.horizontal, 20)

                weekStartDayRow
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    private var troubleshootingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "문제 해결")
            Button {
                onRequestReconnect()
            } label: {
                actionRow(
                    title: "스크린 타임 재연결",
                    subtitle: "모니터링 연결이 끊겼을 때 다시 연결합니다",
                    systemName: "arrow.clockwise",
                    showsProgress: isReconnecting
                )
            }
            .buttonStyle(.plain)
            .disabled(isReconnecting)
            .cardContainer()
        }
    }

    private var weekStartDayRow: some View {
        HStack(spacing: 12) {
            IconTile(systemName: "calendar", tint: Color.accent)
            Text("주 시작 요일")
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            Picker("", selection: $viewModel.weekStartDay) {
                Text("월요일").tag(2)
                Text("일요일").tag(1)
            }
            .pickerStyle(.menu)
            .tint(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
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

    private func actionRow(title: String, subtitle: String, systemName: String, showsProgress: Bool = false) -> some View {
        HStack(spacing: 12) {
            IconTile(systemName: systemName, tint: Color.red)
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
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
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
        .contentShape(Rectangle())
    }

    private var notificationSubtitle: String {
        switch viewModel.notificationPermissionState {
        case .notDetermined: "권한 요청 전"
        case .authorized: "허용됨"
        case .denied: "iOS 설정에서 꺼져 있어요"
        case .provisional: "임시 허용됨"
        case .ephemeral: "일시 허용됨"
        case .unknown: "상태 확인 필요"
        }
    }

    private var notificationIconName: String {
        switch viewModel.notificationPermissionState {
        case .authorized, .provisional, .ephemeral: "bell.badge.fill"
        case .denied: "bell.slash.fill"
        case .notDetermined, .unknown: "bell"
        }
    }

    private var notificationTint: Color {
        switch viewModel.notificationPermissionState {
        case .authorized, .provisional, .ephemeral: .green
        case .denied: .red
        case .notDetermined, .unknown: .red
        }
    }

    private let appStoreID = "6772543300"

    private var feedbackCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "피드백")
            VStack(spacing: 0) {
                Button {
                    var components = URLComponents()
                    components.scheme = "mailto"
                    components.path = "nagi.appstudio@gmail.com"
                    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
                    let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
                    let device = UIDevice.current
                    let body = "\n\n---\n앱 버전: \(appVersion) (\(buildNumber))\n기기: \(device.model)\niOS: \(device.systemVersion)"
                    components.queryItems = [
                        URLQueryItem(name: "subject", value: "GoldTime 피드백"),
                        URLQueryItem(name: "body", value: body)
                    ]
                    if let url = components.url { openURL(url) }
                } label: {
                    settingsRow(
                        title: "이메일로 피드백 보내기",
                        subtitle: "앱 개선에 도움이 됩니다",
                        systemName: "envelope.fill",
                        tint: Color.accent,
                        showsChevron: true
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                Divider().padding(.horizontal, 20)

                Button {
                    guard !appStoreID.isEmpty,
                          let url = URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")
                    else { return }
                    openURL(url)
                } label: {
                    settingsRow(
                        title: "리뷰 작성하기",
                        subtitle: "앱스토어에서 별점과 리뷰를 남겨주세요",
                        systemName: "star.fill",
                        tint: Color.accent,
                        showsChevron: true
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                Divider().padding(.horizontal, 20)

                ShareLink(
                    item: URL(string: "https://apps.apple.com/app/id\(appStoreID)") ?? URL(string: "https://apps.apple.com")!
                ) {
                    settingsRow(
                        title: "친구에게 공유하기",
                        subtitle: "주변에 GoldTime을 알려주세요",
                        systemName: "square.and.arrow.up",
                        tint: Color.accent,
                        showsChevron: true
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}
