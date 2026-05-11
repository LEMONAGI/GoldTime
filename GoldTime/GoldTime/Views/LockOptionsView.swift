//
//  LockOptionsView.swift
//  GoldTime
//
//  쉴드가 활성화된 상태에서 앱 진입 시 표시되는 그룹별 연장 화면.
//

import FamilyControls
import Foundation
import ManagedSettings
import SwiftUI

struct LockOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var oneMinuteRemaining: Int = SharedStore.oneMinuteRemaining
    @State private var showAdMock = false
    @State private var infoMessage: String?
    @State private var completionAlert: CompletionAlert?
    @State private var lockedGroups: [SharedStore.ScreenTimeGroup] = []
    @State private var selectedGroupID: UUID?
    @State private var requestedApplicationToken: ApplicationToken?
    @State private var pendingAdRewardGroupID: UUID?
    @State private var isExtending = false

    private let shieldMessages = [
        "오늘 한도를 다 썼어요.",
        "여기서 멈추면 광고는 없습니다.",
        "더 쓰려면 광고가 필요해요.",
        "잠깐 쉬어갈 시간이에요.",
        "멈추거나, 광고를 보거나."
    ]
    @State private var headerMessage: String = ""

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text("💰").font(.system(size: 56))
                Text("시간이 금이다")
                    .font(.title.bold())
                Text(headerMessage)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 32)

            groupContext

            Spacer()

            VStack(spacing: 12) {
                optionButton(
                    title: "1분만 더 쓰기",
                    subtitle: oneMinuteRemaining > 0
                        ? "전체 그룹에서 오늘 \(oneMinuteRemaining)번 남았어요"
                        : "오늘은 더 사용할 수 없어요",
                    background: canExtendOneMinute ? Color.goldPrimary : Color.gray.opacity(0.3),
                    foreground: canExtendOneMinute ? .black : .gray,
                    enabled: canExtendOneMinute,
                    action: tapOneMinute
                )

                optionButton(
                    title: "광고 보고 15분 더 쓰기",
                    subtitle: selectedGroupName.map { "\($0)을 15분 연장해요" } ?? "풀 그룹을 먼저 고르세요",
                    background: canExtendWithAd ? Color.goldPrimary : Color.gray.opacity(0.3),
                    foreground: canExtendWithAd ? .black : .gray,
                    enabled: canExtendWithAd,
                    action: startAdFlow
                )

                optionButton(
                    title: "그만 쓰기",
                    subtitle: "잠금을 유지하고 돌아갑니다",
                    background: Color.gray.opacity(0.2),
                    foreground: .primary,
                    enabled: true,
                    action: { dismiss() }
                )
            }
            .padding(.horizontal, 20)

            if let infoMessage {
                Text(infoMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }

            Spacer()
        }
        .onAppear {
            headerMessage = shieldMessages.randomElement() ?? "오늘 한도를 다 썼어요."
            refreshLockedGroups()
        }
        .fullScreenCover(isPresented: $showAdMock, onDismiss: {
            guard let groupID = pendingAdRewardGroupID else { return }
            pendingAdRewardGroupID = nil
            extendGroup(groupID: groupID, seconds: 15 * 60, source: .adReward)
        }) {
            AdMockView(
                onComplete: {
                    showAdMock = false
                },
                onCancel: {
                    pendingAdRewardGroupID = nil
                    showAdMock = false
                }
            )
        }
        .alert(item: $completionAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("확인")) {
                    dismiss()
                }
            )
        }
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private var groupContext: some View {
        VStack(alignment: .leading, spacing: 12) {
            if lockedGroups.isEmpty {
                Text("잠긴 그룹을 찾지 못했어요.")
                    .font(.headline)
                Text("앱을 다시 열어보거나, GoldTime에서 모니터링 상태를 확인해주세요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if lockedGroups.count == 1, let group = lockedGroups.first {
                Text(group.displayName)
                    .font(.headline)
                Text("이 그룹만 한 번 연장할 수 있어요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("이 앱은 여러 그룹에 잠겨 있어요")
                    .font(.headline)
                Text("한 번에 한 그룹만 연장합니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    ForEach(lockedGroups) { group in
                        Button {
                            selectedGroupID = group.id
                            infoMessage = nil
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.displayName)
                                        .font(.subheadline.weight(.semibold))
                                    Text("앱 \(group.appCount)/\(SharedStore.maxAppsPerGroup) · \(group.dailyLimitMinutes)분 한도")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: selectedGroupID == group.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedGroupID == group.id ? Color.goldPrimary : .secondary)
                            }
                            .padding(12)
                            .background(Color(.tertiarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 20)
    }

    private var selectedGroup: SharedStore.ScreenTimeGroup? {
        guard let selectedGroupID else {
            return nil
        }
        return lockedGroups.first { $0.id == selectedGroupID }
    }

    private var selectedGroupName: String? {
        selectedGroup?.displayName
    }

    private var canExtendOneMinute: Bool {
        selectedGroup != nil && oneMinuteRemaining > 0 && !isExtending
    }

    private var canExtendWithAd: Bool {
        selectedGroup != nil && !isExtending
    }

    private func refreshLockedGroups() {
        ScreenTimeManager.reapplyShieldIfOverrideExpired()
        let token = SharedStore.lastRequestedUnlockApplicationToken
        requestedApplicationToken = token

        if let token {
            lockedGroups = SharedStore.lockedGroups(containing: token)
        }

        if lockedGroups.isEmpty {
            lockedGroups = SharedStore.lockedGroups()
        }

        if lockedGroups.count == 1 {
            selectedGroupID = lockedGroups.first?.id
        } else if let selectedGroupID,
                  !lockedGroups.contains(where: { $0.id == selectedGroupID }) {
            self.selectedGroupID = nil
        }

        oneMinuteRemaining = SharedStore.oneMinuteRemaining
        SharedStore.clearLastRequestedUnlockApplicationToken()
        SharedStore.clearShieldOpenRequest()
    }

    private func tapOneMinute() {
        guard canExtendOneMinute else {
            infoMessage = "풀 그룹을 먼저 고르거나, 광고를 보거나, 잠금을 유지할 수 있어요."
            return
        }
        guard let groupID = selectedGroupID else {
            infoMessage = "풀 그룹을 먼저 골라주세요."
            return
        }
        extendGroup(groupID: groupID, seconds: 60, source: .oneMinute)
    }

    private func startAdFlow() {
        guard let groupID = selectedGroupID else {
            infoMessage = "풀 그룹을 먼저 골라주세요."
            return
        }
        pendingAdRewardGroupID = groupID
        showAdMock = true
    }

    private func extendGroup(
        groupID: UUID,
        seconds: Int,
        source: ScreenTimeManager.ExtensionSource
    ) {
        guard !isExtending else { return }
        isExtending = true
        defer { isExtending = false }

        let outcome = ScreenTimeManager.extendGroup(
            groupID: groupID,
            duration: seconds,
            source: source
        )

        switch outcome {
        case .success(let result):
            oneMinuteRemaining = SharedStore.oneMinuteRemaining
            updateLockedGroupsAfterExtension(result)
            completionAlert = CompletionAlert(
                title: "연장 완료",
                message: completionMessage(for: result)
            )
        case .failure(let failure):
            infoMessage = message(for: failure, source: source)
            oneMinuteRemaining = SharedStore.oneMinuteRemaining
        }
    }

    private func message(
        for failure: ScreenTimeManager.ExtensionFailure,
        source: ScreenTimeManager.ExtensionSource
    ) -> String {
        switch failure {
        case .groupNotFound:
            return "이 그룹을 찾지 못했어요. GoldTime에서 그룹 설정을 확인해주세요."
        case .oneMinuteLimitReached:
            return source == .oneMinute
                ? "오늘 1분 연장은 모두 사용했어요. 광고를 보거나 잠금을 유지할 수 있어요."
                : "광고 연장을 처리하지 못했어요. 잠시 뒤 다시 시도해주세요."
        }
    }

    private func updateLockedGroupsAfterExtension(_ result: ScreenTimeManager.GroupExtensionResult) {
        if let requestedApplicationToken {
            lockedGroups = SharedStore.lockedGroups(containing: requestedApplicationToken)
        } else {
            lockedGroups = result.remainingLockedGroups
        }

        if let selectedGroupID,
           !lockedGroups.contains(where: { $0.id == selectedGroupID }) {
            self.selectedGroupID = lockedGroups.first?.id
        }
    }

    private func completionMessage(for result: ScreenTimeManager.GroupExtensionResult) -> String {
        let duration = result.durationSeconds == 60 ? "1분" : "\(result.durationSeconds / 60)분"
        var message = "\(result.group.displayName)을 \(duration) 연장했어요. 방금 쓰던 앱으로 돌아가세요."

        if let token = requestedApplicationToken {
            let remainingGroups = SharedStore.lockedGroups(containing: token)
            if let remainingGroup = remainingGroups.first {
                message += "\n아직 \(remainingGroup.displayName) 때문에 잠겨 있어요. 하나 더 풀지는 직접 결정하세요."
            }
        } else if let remainingGroup = result.remainingLockedGroups.first {
            message += "\n아직 \(remainingGroup.displayName) 때문에 잠겨 있어요. 하나 더 풀지는 직접 결정하세요."
        }

        return message
    }

    @ViewBuilder
    private func optionButton(
        title: String,
        subtitle: String,
        background: Color,
        foreground: Color,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .opacity(0.8)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .disabled(!enabled)
    }
}

private struct CompletionAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
