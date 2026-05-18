//
//  SettingsView.swift
//  GoldTime
//

import SwiftUI

struct SettingsView: View {
    let auth: AuthorizationService
    let onRequestResetProtection: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                permissionsSection
                notificationAndLanguageSection
                troubleshootingSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("설정")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "권한", systemName: "checkmark.shield")

            VStack(spacing: 10) {
                settingsRow(
                    title: "스크린 타임 권한",
                    subtitle: auth.isAuthorized ? "허용됨" : "확인이 필요해요",
                    systemName: auth.isAuthorized ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                    tint: auth.isAuthorized ? .green : .orange
                )
            }
            .cardContainer()
        }
    }

    private var notificationAndLanguageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "알림과 언어", systemName: "bell.badge")

            VStack(spacing: 10) {
                settingsRow(
                    title: "알림",
                    subtitle: "Shield에서 GoldTime으로 돌아올 때 사용",
                    systemName: "bell",
                    tint: Color.accent
                )
                settingsRow(
                    title: "언어",
                    subtitle: "현재는 시스템 언어를 사용",
                    systemName: "globe",
                    tint: .blue
                )
            }
            .cardContainer()
        }
    }

    private var troubleshootingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "문제 해결", systemName: "wrench.and.screwdriver")

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
            .cardContainer()
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
        .rowContainer()
    }

    private func settingsRow(title: String, subtitle: String, systemName: String, tint: Color) -> some View {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rowContainer()
    }
}
