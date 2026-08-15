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
                privacyCard
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("settings.title")
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
                dismissButton: .default(Text("common.confirm"))
            )
        }
    }

    private var generalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "settings.section.general")
            VStack(spacing: 0) {
                if viewModel.isScreenTimeAuthorized {
                    settingsRow(
                        title: "settings.screenTime.title",
                        subtitle: String(localized: "settings.screenTime.allowed"),
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
                            title: "settings.screenTime.title",
                            subtitle: String(localized: "settings.screenTime.needCheck"),
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
            SectionHeader(title: "settings.section.troubleshooting")
            Button {
                onRequestReconnect()
            } label: {
                actionRow(
                    title: "settings.reconnect.title",
                    subtitle: "settings.reconnect.subtitle",
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
            Text("settings.weekStart")
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            Picker("settings.weekStart", selection: $viewModel.weekStartDay) {
                Text("settings.weekday.monday").tag(2)
                Text("settings.weekday.sunday").tag(1)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func notificationRow(showsChevron: Bool = false) -> some View {
        settingsRow(
            title: "settings.notification.title",
            subtitle: notificationSubtitle,
            systemName: notificationIconName,
            tint: notificationTint,
            showsProgress: viewModel.isRequestingNotificationAuthorization,
            showsChevron: showsChevron
        )
    }

    private func actionRow(title: LocalizedStringKey, subtitle: LocalizedStringKey, systemName: String, showsProgress: Bool = false) -> some View {
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
        title: LocalizedStringKey,
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
            return String(localized: "settings.notif.deferred")
        }
        switch viewModel.notificationPermissionState {
        case .notDetermined: return String(localized: "settings.notif.notDetermined")
        case .authorized, .provisional, .ephemeral: return nil
        case .denied: return String(localized: "settings.notif.denied")
        case .unknown: return String(localized: "settings.notif.unknown")
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
            SectionHeader(title: "settings.section.feedback")
            VStack(spacing: 0) {
                Button {
                    var components = URLComponents()
                    components.scheme = "mailto"
                    components.path = "nagi.appstudio@gmail.com"
                    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
                    let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
                    let device = UIDevice.current
                    let body = String(localized: "settings.feedback.email.body \(appVersion) \(buildNumber) \(device.model) \(device.systemVersion)")
                    components.queryItems = [
                        URLQueryItem(name: "subject", value: String(localized: "settings.feedback.email.subject")),
                        URLQueryItem(name: "body", value: body)
                    ]
                    if let url = components.url { openURL(url) }
                } label: {
                    settingsRow(
                        title: "settings.feedback.email",
                        subtitle: String(localized: "settings.feedback.email.subtitle"),
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
                        title: "settings.feedback.review",
                        subtitle: String(localized: "settings.feedback.review.subtitle"),
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
                        title: "settings.feedback.share",
                        subtitle: String(localized: "settings.feedback.share.subtitle"),
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

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "settings.section.privacy")
            VStack(spacing: 0) {
                Button {
                    guard let url = viewModel.privacyPolicyURL else { return }
                    openURL(url)
                } label: {
                    settingsRow(
                        title: "settings.privacy.policy",
                        subtitle: String(localized: "settings.privacy.policy.subtitle"),
                        systemName: "hand.raised.fill",
                        tint: Color.accent,
                        showsChevron: true
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                // 광고 개인화 동의 변경은 EEA/UK 등 동의가 필요한 지역에서만 노출한다.
                if viewModel.isPrivacyOptionsAvailable {
                    Divider().padding(.horizontal, 20)

                    Button {
                        Task { await viewModel.presentPrivacyOptions() }
                    } label: {
                        settingsRow(
                            title: "settings.privacy.adChoices",
                            subtitle: String(localized: "settings.privacy.adChoices.subtitle"),
                            systemName: "checkmark.shield.fill",
                            tint: Color.accent,
                            showsChevron: true
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
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

#if DEBUG
#Preview("설정") {
    NavigationStack {
        SettingsView(
            viewModel: SettingsViewModel(),
            isReconnecting: false,
            onRequestReconnect: {}
        )
    }
}
#endif
