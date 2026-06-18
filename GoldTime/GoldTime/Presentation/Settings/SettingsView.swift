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
    @Environment(\.scenePhase) private var scenePhase

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
        .onChange(of: scenePhase) { _, newPhase in
            // iOS 설정에서 권한을 바꾸고 돌아오면 즉시 행이 최신 상태로 갱신되도록 한다.
            guard newPhase == .active else { return }
            Task { await viewModel.loadState() }
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

                if isNotificationAuthorized && !viewModel.isNotificationDeferredBySummary {
                    NavigationLink {
                        NotificationSettingsView(viewModel: viewModel)
                    } label: {
                        notificationRow(showsChevron: true)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                } else if viewModel.notificationPermissionState == .notDetermined {
                    // 한 번도 권한을 요청한 적이 없으면 iOS 설정에 토글이 없어 켤 수 없으므로,
                    // 설정 이동 대신 시스템 권한 요청을 먼저 띄운다.
                    Button {
                        guard !viewModel.isRequestingNotificationAuthorization else { return }
                        Task { await viewModel.requestNotificationAuthorization() }
                    } label: {
                        notificationRow(showsChevron: true)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                } else {
                    // 거부됐거나, 권한은 있어도 시간 지정 요약에 묶여 알림이 늦는 경우는
                    // iOS 설정에서만 바꿀 수 있으므로 설정으로 이동.
                    Button {
                        openAppSettings()
                    } label: {
                        notificationRow(showsChevron: true)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
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
            title: "알림",
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
        subtitle: String? = nil,
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
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
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

    private var isNotificationAuthorized: Bool {
        switch viewModel.notificationPermissionState {
        case .authorized, .provisional, .ephemeral: true
        case .notDetermined, .denied, .unknown: false
        }
    }

    /// 권한은 허용됐지만 시간 지정 요약에 묶여 알림이 지연되는 상태.
    private var isNotificationDeferredBySummary: Bool {
        isNotificationAuthorized && viewModel.isNotificationDeferredBySummary
    }

    private var notificationSubtitle: String? {
        if isNotificationDeferredBySummary {
            return "시간 지정 요약에 묶여 알림이 늦을 수 있어요"
        }
        switch viewModel.notificationPermissionState {
        case .notDetermined: return "탭하여 알림을 허용해 주세요"
        case .authorized, .provisional, .ephemeral: return nil
        case .denied: return "iOS 설정에서 꺼져 있어요"
        case .unknown: return "iOS 설정에서 켜주세요"
        }
    }

    private var notificationIconName: String {
        if isNotificationDeferredBySummary {
            return "clock.badge.exclamationmark.fill"
        }
        switch viewModel.notificationPermissionState {
        case .authorized, .provisional, .ephemeral: return "bell.badge.fill"
        case .denied, .notDetermined, .unknown: return "bell.slash.fill"
        }
    }

    private var notificationTint: Color {
        if isNotificationDeferredBySummary {
            return .orange
        }
        switch viewModel.notificationPermissionState {
        case .authorized, .provisional, .ephemeral: return Color.accentColor
        case .denied: return .red
        case .notDetermined, .unknown: return .red
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
                    let body = """
                    안녕하세요! 보내주신 의견은 빠짐없이 읽고 있어요.
                    버그는 쏜살같이, 기능 추가는 정확하게!

                    (여기에 의견을 적어주세요)

                    ---
                    앱 버전: \(appVersion) (\(buildNumber))
                    기기: \(device.model)
                    iOS: \(device.systemVersion)
                    """
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
