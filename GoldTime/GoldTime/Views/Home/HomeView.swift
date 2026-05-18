//
//  HomeView.swift
//  GoldTime
//
//  홈 대시보드, 그룹별 앱 한도 설정, 자동 보호 적용, 현재 상태 표시.
//

import FamilyControls
import SwiftUI

struct HomeView: View {
    let groups: [SharedStore.ScreenTimeGroup]
    let todayStats: SharedStore.DailyStats
    let isMonitoring: Bool
    let isShieldActive: Bool
    let shieldOverrideUntil: Date?
    let successMessage: String?
    let errorMessage: String?
    let onAddGroup: () -> Void
    let onDeleteGroup: (UUID) -> Void
    let onUpdateGroupName: (UUID, String) -> Void
    let onPresentPicker: (SharedStore.ScreenTimeGroup) -> Void
    let onPresentLimitPicker: (SharedStore.ScreenTimeGroup) -> Void
    let onRequestResetProtection: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                timeBillHero
                currentStatusSection
                managementSection

                if let successMessage {
                    statusSection(successMessage, tint: .green, systemName: "checkmark.circle.fill")
                }

                if let errorMessage {
                    statusSection(errorMessage, tint: .red, systemName: "exclamationmark.triangle.fill")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("GoldTime")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var timeBillHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("오늘의 시간 청구서")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                    Text(billSummaryLine)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(billComment)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                StatusBadge(
                    title: shieldStatusValue,
                    systemName: isShieldActive ? "lock.fill" : "lock.open.fill",
                    tint: isShieldActive ? .red : .green
                )
            }

            HStack(spacing: 10) {
                BillPill(title: "광고", value: "\(todayStats.adWatchCount)개")
                BillPill(title: "추가 사용", value: goldTimeDurationText(seconds: todayStats.adUnlockedSeconds))
            }

            HStack(spacing: 10) {
                BillPill(title: "1분 연장", value: "\(todayStats.oneMinuteUsedCount)회")
                BillPill(title: "시간을 아낀 선택", value: "\(todayStats.walkAwayCount)회")
            }

            Text("한도 넘긴 뒤의 선택만 기록합니다.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.68))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color("gray100"))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var currentStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "현재 상태", systemName: "shield")

            HStack(spacing: 12) {
                IconTile(
                    systemName: isShieldActive ? "lock.fill" : "lock.open.fill",
                    tint: isShieldActive ? .red : protectionStatusTint
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(shieldStatusValue)
                        .font(.headline)
                    Text(shieldStatusCaption)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                GroupStatusBadge(title: protectionStatusTitle, tint: protectionStatusTint)
            }
            .cardContainer()
        }
    }

    private var managementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "보호 그룹", systemName: "rectangle.3.group")
                Spacer()
                Text("그룹 \(groups.count)/\(SharedStore.maxGroupCount)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(groups.count >= SharedStore.maxGroupCount ? .red : .secondary)
            }

            monitoringControls

            if groups.isEmpty {
                emptyGroupState
            } else {
                VStack(spacing: 12) {
                    ForEach(groups) { group in
                        groupCard(group)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(Color.accent)
                    Text("그룹당 앱 \(SharedStore.maxAppsPerGroup)개까지 · 카테고리와 웹은 아직 제외 · 같은 앱은 여러 그룹에 넣을 수 있어요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button {
                    onAddGroup()
                } label: {
                    Label("그룹 추가", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GoldTimeButtonStyle(background: Color.accent, foreground: .black))
                .disabled(groups.count >= SharedStore.maxGroupCount)
                .opacity(groups.count >= SharedStore.maxGroupCount ? 0.45 : 1)

                if groups.count >= SharedStore.maxGroupCount {
                    Text("그룹은 5개까지예요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .cardContainer()
        }
    }

    private var emptyGroupState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.accent)
            Text("아직 그룹이 없어요.")
                .font(.headline)
            Text("그룹을 만들고 앱을 담으면, 그룹별로 다른 일일 한도를 걸 수 있어요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .cardContainer(padding: 20)
        .frame(maxWidth: .infinity)
    }

    private func groupCard(_ group: SharedStore.ScreenTimeGroup) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                IconTile(systemName: "app.badge", tint: Color.accent)

                VStack(alignment: .leading, spacing: 8) {
                    TextField("그룹명", text: Binding(
                        get: { group.name },
                        set: { onUpdateGroupName(group.id, $0) }
                    ))
                    .font(.headline)

                    HStack(spacing: 8) {
                        GroupStatusBadge(title: statusTitle(for: group), tint: statusTint(for: group))
                        GroupStatusBadge(
                            title: "앱 \(group.appCount)/\(SharedStore.maxAppsPerGroup)",
                            tint: group.appCount >= 8 ? .orange : .secondary
                        )
                        if groupHasDuplicateApps(group) {
                            GroupStatusBadge(title: "중복 포함 앱 있음", tint: .blue)
                        }
                    }
                }

                Spacer(minLength: 8)

                Button(role: .destructive) {
                    onDeleteGroup(group.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.plain)
            }

            Button {
                onPresentLimitPicker(group)
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("일일 한도")
                            .font(.subheadline.weight(.semibold))
                        Text(limitLabel(group.dailyLimitMinutes))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button {
                        onPresentPicker(group)
                    } label: {
                        Label("앱 선택", systemImage: "square.grid.2x2")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GoldTimeButtonStyle(background: Color(.tertiarySystemGroupedBackground), foreground: .primary))
                }

                Text("카테고리와 웹은 아직 제외")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                appTokenList(for: group)
            }
        }
        .cardContainer()
    }

    @ViewBuilder
    private func appTokenList(for group: SharedStore.ScreenTimeGroup) -> some View {
        if group.selection.applicationTokens.isEmpty {
            Text("선택된 앱 없음")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .rowContainer()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(group.selection.applicationTokens), id: \.self) { token in
                    Label(token)
                        .font(.subheadline)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .rowContainer()
        }
    }

    private var monitoringControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                IconTile(
                    systemName: protectionStatusIcon,
                    tint: protectionStatusTint
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(protectionStatusTitle)
                        .font(.body.weight(.semibold))
                    Text(protectionStatusCaption)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Menu {
                    Button(role: .destructive) {
                        onRequestResetProtection()
                    } label: {
                        Label("전체 보호 초기화", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            if let setupMessage = protectionSetupMessage {
                Text(setupMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .cardContainer()
    }

    private func statusSection(_ message: String, tint: Color, systemName: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemName)
                .foregroundStyle(tint)
            Text(message)
                .font(.footnote)
                .foregroundStyle(tint)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var validMonitoringGroups: [SharedStore.ScreenTimeGroup] {
        ScreenTimeManager.validDailyMonitoringGroups(from: groups)
    }

    private var invalidMonitoringGroups: [SharedStore.ScreenTimeGroup] {
        groups.filter { group in
            ScreenTimeGroupPolicy.invalidReason(for: group.policySnapshot) != nil
        }
    }

    private var protectionStatusTitle: String {
        if isMonitoring {
            return "자동 적용 중"
        }
        if groups.isEmpty {
            return "설정 필요"
        }
        if validMonitoringGroups.isEmpty {
            return "설정 필요"
        }
        return "자동 적용 대기"
    }

    private var protectionStatusCaption: String {
        if isMonitoring {
            let count = validMonitoringGroups.count
            return count > 1 ? "\(count)개 유효 그룹에 한도를 적용 중이에요" : "유효한 그룹에 한도를 적용 중이에요"
        }
        if groups.isEmpty {
            return "그룹을 만들고 앱을 담으면 바로 적용돼요"
        }
        if validMonitoringGroups.isEmpty {
            return "앱과 한도가 설정된 그룹이 필요해요"
        }
        return "자동 적용을 준비하고 있어요"
    }

    private var protectionStatusIcon: String {
        isMonitoring ? "checkmark.shield.fill" : "shield"
    }

    private var protectionStatusTint: Color {
        if isMonitoring {
            return .green
        }
        return validMonitoringGroups.isEmpty ? .secondary : Color.accent
    }

    private var protectionSetupMessage: String? {
        guard !groups.isEmpty else {
            return nil
        }

        let invalidCount = invalidMonitoringGroups.count
        guard invalidCount > 0 else {
            return nil
        }

        if validMonitoringGroups.isEmpty {
            return "아직 적용할 수 있는 그룹이 없어요. 앱을 하나 이상 담고 한도를 정해주세요."
        }

        return "\(invalidCount)개 그룹은 설정이 덜 끝나서 자동 적용에서 제외됐어요."
    }

    private var billSummaryLine: String {
        "광고 \(todayStats.adWatchCount)개. 추가 사용 \(goldTimeDurationText(seconds: todayStats.adUnlockedSeconds))."
    }

    private var billComment: String {
        if !hasBillCost, todayStats.walkAwayCount > 0 {
            return "광고 안 보면 당신 승리예요. 저는 손해고요."
        }
        if !hasBillCost {
            return "좋은 날입니다. 저한텐 아니고요."
        }
        return "시간이 금이면, 오늘 좀 썼네요."
    }

    private var hasBillCost: Bool {
        todayStats.adWatchCount > 0
            || todayStats.adUnlockedSeconds > 0
            || todayStats.oneMinuteUsedCount > 0
    }

    private var shieldStatusValue: String {
        if isShieldActive {
            return "잠금 중"
        }
        if let shieldOverrideUntil, shieldOverrideUntil.timeIntervalSinceNow > 0.5 {
            return "연장 중"
        }
        return isMonitoring ? "사용 가능" : "대기 중"
    }

    private var shieldStatusCaption: String {
        if isShieldActive {
            let count = SharedStore.lockedGroups().count
            return count > 1 ? "\(count)개 그룹이 한도에 닿았어요" : "한도를 넘겼어요"
        }
        if let shieldOverrideUntil, shieldOverrideUntil.timeIntervalSinceNow > 0.5 {
            let seconds = max(1, Int(shieldOverrideUntil.timeIntervalSinceNow.rounded(.up)))
            return "\(goldTimeDurationText(seconds: seconds)) 뒤 재잠금"
        }
        return isMonitoring ? "아직 한도 안쪽" : "설정 필요"
    }

    private func statusTitle(for group: SharedStore.ScreenTimeGroup) -> String {
        if SharedStore.lockedGroups().contains(where: { $0.id == group.id }) {
            return "잠금 중"
        }
        if SharedStore.groupsInOverride().contains(where: { $0.id == group.id }) {
            return "연장 중"
        }
        if ScreenTimeGroupPolicy.invalidReason(for: group.policySnapshot) != nil {
            return "설정 필요"
        }
        return isMonitoring ? "적용 중" : "대기 중"
    }

    private func statusTint(for group: SharedStore.ScreenTimeGroup) -> Color {
        switch statusTitle(for: group) {
        case "잠금 중":
            return .red
        case "연장 중":
            return .blue
        case "적용 중", "대기 중":
            return .green
        case "설정 필요":
            return .orange
        default:
            return .secondary
        }
    }

    private func groupHasDuplicateApps(_ group: SharedStore.ScreenTimeGroup) -> Bool {
        groups.contains { other in
            other.id != group.id
                && !other.selection.applicationTokens.isDisjoint(with: group.selection.applicationTokens)
        }
    }

    private func limitLabel(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 {
            return "\(h)시간 \(m)분 넘기면 이 그룹만 잠겨요"
        } else {
            return "\(m)분 넘기면 이 그룹만 잠겨요"
        }
    }
}
