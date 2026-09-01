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
    let onPresentPicker: (ScreenTimeGroup) -> Void
    let onPresentRuleEditor: (ScreenTimeGroup) -> Void
    let onUnlockGroup: (UUID) -> Void
    let onApplyGroup: (UUID) -> Void
    let onPresentStrictLock: (ScreenTimeGroup) -> Void
    let isStrictLockFeatureEnabled: Bool
    /// 홈 상단 연장 불가 베타 배너의 금빛 발광 여부(첫 탭 전까지 true).
    let isStrictLockBetaBannerGlowing: Bool
    /// 배너 탭 — 상위(ContentView)가 발광을 끄고 안내 시트를 띄운다.
    let onTapStrictLockBetaBanner: () -> Void

    init(
        groups: [ScreenTimeGroup],
        todayStats: DailyStats,
        isMonitoring: Bool,
        isShieldActive: Bool,
        shieldOverrideUntil: Date?,
        successMessage: String?,
        errorMessage: String?,
        lockedGroupIDs: Set<UUID> = [],
        overrideGroupIDs: Set<UUID> = [],
        validGroupIDs: Set<UUID> = [],
        untrackedGroupIDs: Set<UUID> = [],
        overrideUntilByGroupID: [UUID: Date] = [:],
        usedTimeByGroupID: [UUID: Int] = [:],
        overrideBaselineUsedTimeByGroupID: [UUID: Int] = [:],
        overrideGrantedMinutesByGroupID: [UUID: Int] = [:],
        cooldownEndByGroupID: [UUID: Date] = [:],
        oneMinuteRemaining: Int = 0,
        oneMinuteDailyLimit: Int = ScreenTimeGroupPolicy.oneMinuteDailyLimit,
        onAddGroup: @escaping () -> Void,
        onDeleteGroup: @escaping (UUID) -> Void,
        onUpdateGroupName: @escaping (UUID, String) -> Void,
        onPresentPicker: @escaping (ScreenTimeGroup) -> Void,
        onPresentRuleEditor: @escaping (ScreenTimeGroup) -> Void,
        onUnlockGroup: @escaping (UUID) -> Void = { _ in },
        onApplyGroup: @escaping (UUID) -> Void = { _ in },
        onPresentStrictLock: @escaping (ScreenTimeGroup) -> Void = { _ in },
        isStrictLockFeatureEnabled: Bool = false,
        isStrictLockBetaBannerGlowing: Bool = false,
        onTapStrictLockBetaBanner: @escaping () -> Void = {}
    ) {
        self.viewModel = HomeViewModel(
            groups: groups,
            todayStats: todayStats,
            isMonitoring: isMonitoring,
            isShieldActive: isShieldActive,
            shieldOverrideUntil: shieldOverrideUntil,
            successMessage: successMessage,
            errorMessage: errorMessage,
            lockedGroupIDs: lockedGroupIDs,
            overrideGroupIDs: overrideGroupIDs,
            validGroupIDs: validGroupIDs,
            untrackedGroupIDs: untrackedGroupIDs,
            overrideUntilByGroupID: overrideUntilByGroupID,
            usedTimeByGroupID: usedTimeByGroupID,
            overrideBaselineUsedTimeByGroupID: overrideBaselineUsedTimeByGroupID,
            overrideGrantedMinutesByGroupID: overrideGrantedMinutesByGroupID,
            cooldownEndByGroupID: cooldownEndByGroupID,
            oneMinuteRemaining: oneMinuteRemaining,
            oneMinuteDailyLimit: oneMinuteDailyLimit
        )
        self.onAddGroup = onAddGroup
        self.onDeleteGroup = onDeleteGroup
        self.onUpdateGroupName = onUpdateGroupName
        self.onPresentPicker = onPresentPicker
        self.onPresentRuleEditor = onPresentRuleEditor
        self.onUnlockGroup = onUnlockGroup
        self.onApplyGroup = onApplyGroup
        self.onPresentStrictLock = onPresentStrictLock
        self.isStrictLockFeatureEnabled = isStrictLockFeatureEnabled
        self.isStrictLockBetaBannerGlowing = isStrictLockBetaBannerGlowing
        self.onTapStrictLockBetaBanner = onTapStrictLockBetaBanner
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 베타 기간에만 노출되는 신기능 안내 배너. 게이트가 유료 판정으로 바뀌는 정식
                // 출시 때는 이 배너 자체를 재검토/제거한다(베타 안내라 베타 기간 한정).
                if isStrictLockFeatureEnabled {
                    StrictLockBetaBanner(
                        isGlowing: isStrictLockBetaBannerGlowing,
                        onTap: onTapStrictLockBetaBanner
                    )
                }

                timeBillHero
                    .padding(.bottom, 20)
                
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
        .scrollIndicators(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("home.title")
        .navigationBarTitleDisplayMode(.large)
    }
    
    private var timeBillHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Label("home.bill.heroTitle", systemImage: "receipt")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.accent)
                
                Text(viewModel.billComment)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer().frame(height: 24)
            
            VStack(alignment: .center, spacing: 4) {
                CountUpDurationText(seconds: viewModel.todayStats.totalUnlockedSeconds)
                    .font(.system(size: 70, weight: .heavy))
                    .foregroundStyle(Color.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                
                Text("home.totalExtra")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .frame(maxWidth: .infinity)
            
            Spacer().frame(height: 20)
            dashedDivider
            Spacer().frame(height: 18)
            
            VStack(spacing: 10) {
                billRow("home.bill.adCount", String(localized: "common.countItems \(viewModel.todayStats.adWatchCount)"), accent: true)
                billRow(
                    "home.bill.oneMinute",
                    "\(viewModel.oneMinuteRemaining)/\(viewModel.oneMinuteDailyLimit)"
                )
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color("gray100"))
        .background(Color.accent.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.accent.opacity(0.5), lineWidth: 1.5)
        }
        .accessibilityElement(children: .combine)
    }

    private var dashedDivider: some View {
        GeometryReader { geometry in
            Path { path in
                path.move(to: .zero)
                path.addLine(to: CGPoint(x: geometry.size.width, y: 0))
            }
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .foregroundStyle(.white.opacity(0.2))
        }
        .frame(height: 1)
    }
    
    private func billRow(_ label: LocalizedStringKey, _ value: String, accent: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
            
            Spacer(minLength: 12)
            
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(accent ? Color.accent : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
    
    private var managementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "home.groupList")
                Spacer()
                Text("home.groupCount \(viewModel.groups.count) \(viewModel.maxGroupCount)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(viewModel.isAtGroupLimit ? .orange : .secondary)
            }

            if viewModel.groups.isEmpty {
                emptyGroupState
            } else {
                VStack(spacing: 12) {
                    ForEach(viewModel.groups) { group in
                        GroupCardView(
                            group: group,
                            viewModel: viewModel,
                            onDeleteGroup: onDeleteGroup,
                            onUpdateGroupName: onUpdateGroupName,
                            onPresentPicker: onPresentPicker,
                            onPresentRuleEditor: onPresentRuleEditor,
                            onUnlockGroup: onUnlockGroup,
                            onApplyGroup: onApplyGroup,
                            onPresentStrictLock: onPresentStrictLock,
                            isStrictLockFeatureEnabled: isStrictLockFeatureEnabled
                        )
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(Color.accent)
                    Text("home.groupHint \(viewModel.maxAppsPerGroup)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .opacity(viewModel.isAtGroupLimit ? 0.45 : 1)

                Button {
                    onAddGroup()
                } label: {
                    Label("home.addGroup", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GoldTimeButtonStyle(background: Color.accent, foreground: .black))
                .disabled(viewModel.isAtGroupLimit)
                .opacity(viewModel.isAtGroupLimit ? 0.45 : 1)
                
                if viewModel.isAtGroupLimit {
                    Text("group.error.tooMany \(viewModel.maxGroupCount)")
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
            Text("home.empty.title")
                .font(.headline)
            Text("home.empty.subtitle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth:  .infinity)
        .cardContainer(padding: 20)
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
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
}
