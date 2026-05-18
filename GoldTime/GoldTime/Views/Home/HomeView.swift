//
//  HomeView.swift
//  GoldTime
//
//  홈 대시보드, 그룹별 앱 한도 설정, 자동 보호 적용, 현재 상태 표시.
//

import FamilyControls
import SwiftUI

struct HomeView: View {
    let viewModel: HomeViewModel
    let onAddGroup: () -> Void
    let onDeleteGroup: (UUID) -> Void
    let onUpdateGroupName: (UUID, String) -> Void
    let onPresentPicker: (SharedStore.ScreenTimeGroup) -> Void
    let onPresentLimitPicker: (SharedStore.ScreenTimeGroup) -> Void
    let onRequestResetProtection: () -> Void

    init(
        groups: [SharedStore.ScreenTimeGroup],
        todayStats: SharedStore.DailyStats,
        isMonitoring: Bool,
        isShieldActive: Bool,
        shieldOverrideUntil: Date?,
        successMessage: String?,
        errorMessage: String?,
        onAddGroup: @escaping () -> Void,
        onDeleteGroup: @escaping (UUID) -> Void,
        onUpdateGroupName: @escaping (UUID, String) -> Void,
        onPresentPicker: @escaping (SharedStore.ScreenTimeGroup) -> Void,
        onPresentLimitPicker: @escaping (SharedStore.ScreenTimeGroup) -> Void,
        onRequestResetProtection: @escaping () -> Void
    ) {
        self.viewModel = HomeViewModel(
            groups: groups,
            todayStats: todayStats,
            isMonitoring: isMonitoring,
            isShieldActive: isShieldActive,
            shieldOverrideUntil: shieldOverrideUntil,
            successMessage: successMessage,
            errorMessage: errorMessage
        )
        self.onAddGroup = onAddGroup
        self.onDeleteGroup = onDeleteGroup
        self.onUpdateGroupName = onUpdateGroupName
        self.onPresentPicker = onPresentPicker
        self.onPresentLimitPicker = onPresentLimitPicker
        self.onRequestResetProtection = onRequestResetProtection
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                timeBillHero
                currentStatusSection
                managementSection

                if let successMessage = viewModel.successMessage {
                    statusSection(successMessage, tint: .green, systemName: "checkmark.circle.fill")
                }

                if let errorMessage = viewModel.errorMessage {
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
                    Text(viewModel.billSummaryLine)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(viewModel.billComment)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                StatusBadge(
                    title: viewModel.shieldStatusValue,
                    systemName: viewModel.isShieldActive ? "lock.fill" : "lock.open.fill",
                    tint: viewModel.isShieldActive ? .red : .green
                )
            }

            HStack(spacing: 10) {
                BillPill(title: "광고", value: "\(viewModel.todayStats.adWatchCount)개")
                BillPill(title: "추가 사용", value: goldTimeDurationText(seconds: viewModel.todayStats.adUnlockedSeconds))
            }

            HStack(spacing: 10) {
                BillPill(title: "1분 연장", value: "\(viewModel.todayStats.oneMinuteUsedCount)회")
                BillPill(title: "시간을 아낀 선택", value: "\(viewModel.todayStats.walkAwayCount)회")
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
                    systemName: viewModel.isShieldActive ? "lock.fill" : "lock.open.fill",
                    tint: viewModel.isShieldActive ? .red : viewModel.protectionStatusTint
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.shieldStatusValue)
                        .font(.headline)
                    Text(viewModel.shieldStatusCaption)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                GroupStatusBadge(title: viewModel.protectionStatusTitle, tint: viewModel.protectionStatusTint)
            }
            .cardContainer()
        }
    }

    private var managementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "보호 그룹", systemName: "rectangle.3.group")
                Spacer()
                Text("그룹 \(viewModel.groups.count)/\(viewModel.maxGroupCount)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(viewModel.isAtGroupLimit ? .red : .secondary)
            }

            monitoringControls

            if viewModel.groups.isEmpty {
                emptyGroupState
            } else {
                VStack(spacing: 12) {
                    ForEach(viewModel.groups) { group in
                        groupCard(group)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(Color.accent)
                    Text("그룹당 앱 \(viewModel.maxAppsPerGroup)개까지 · 카테고리와 웹은 아직 제외 · 같은 앱은 여러 그룹에 넣을 수 있어요.")
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
                .disabled(viewModel.isAtGroupLimit)
                .opacity(viewModel.isAtGroupLimit ? 0.45 : 1)

                if viewModel.isAtGroupLimit {
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
                        GroupStatusBadge(title: viewModel.statusTitle(for: group), tint: viewModel.statusTint(for: group))
                        GroupStatusBadge(
                            title: "앱 \(group.appCount)/\(viewModel.maxAppsPerGroup)",
                            tint: group.appCount >= 8 ? .orange : .secondary
                        )
                        if viewModel.groupHasDuplicateApps(group) {
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
                        Text(viewModel.limitLabel(group.dailyLimitMinutes))
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
                    systemName: viewModel.protectionStatusIcon,
                    tint: viewModel.protectionStatusTint
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.protectionStatusTitle)
                        .font(.body.weight(.semibold))
                    Text(viewModel.protectionStatusCaption)
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

            if let setupMessage = viewModel.protectionSetupMessage {
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

}
