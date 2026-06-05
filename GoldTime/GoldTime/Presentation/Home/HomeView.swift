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
    let onPresentLimitPicker: (ScreenTimeGroup) -> Void
    let onUnlockGroup: (UUID) -> Void
    
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
        overrideUntilByGroupID: [UUID: Date] = [:],
        usedTimeByGroupID: [UUID: Int] = [:],
        overrideBaselineUsedTimeByGroupID: [UUID: Int] = [:],
        overrideGrantedMinutesByGroupID: [UUID: Int] = [:],
        oneMinuteRemaining: Int = 0,
        oneMinuteDailyLimit: Int = ScreenTimeGroupPolicy.oneMinuteDailyLimit,
        onAddGroup: @escaping () -> Void,
        onDeleteGroup: @escaping (UUID) -> Void,
        onUpdateGroupName: @escaping (UUID, String) -> Void,
        onPresentPicker: @escaping (ScreenTimeGroup) -> Void,
        onPresentLimitPicker: @escaping (ScreenTimeGroup) -> Void,
        onUnlockGroup: @escaping (UUID) -> Void = { _ in }
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
            overrideUntilByGroupID: overrideUntilByGroupID,
            usedTimeByGroupID: usedTimeByGroupID,
            overrideBaselineUsedTimeByGroupID: overrideBaselineUsedTimeByGroupID,
            overrideGrantedMinutesByGroupID: overrideGrantedMinutesByGroupID,
            oneMinuteRemaining: oneMinuteRemaining,
            oneMinuteDailyLimit: oneMinuteDailyLimit
        )
        self.onAddGroup = onAddGroup
        self.onDeleteGroup = onDeleteGroup
        self.onUpdateGroupName = onUpdateGroupName
        self.onPresentPicker = onPresentPicker
        self.onPresentLimitPicker = onPresentLimitPicker
        self.onUnlockGroup = onUnlockGroup
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
        .navigationTitle("홈")
        .navigationBarTitleDisplayMode(.large)
    }
    
    private var timeBillHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Label("오늘의 시간 청구서", systemImage: "receipt")
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
                
                Text("총 초과 사용 시간")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .frame(maxWidth: .infinity)
            
            Spacer().frame(height: 20)
            dashedDivider
            Spacer().frame(height: 18)
            
            VStack(spacing: 10) {
                billRow("광고", "\(viewModel.todayStats.adWatchCount)개", accent: true)
                billRow(
                    "남은 1분 연장",
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
    
    private func billRow(_ label: String, _ value: String, accent: Bool = false) -> some View {
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
                SectionHeader(title: "그룹 목록")
                Spacer()
                Text("그룹 \(viewModel.groups.count)/\(viewModel.maxGroupCount)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(viewModel.isAtGroupLimit ? .orange : .secondary)
            }
            
            monitoringControls
            
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
                            onPresentLimitPicker: onPresentLimitPicker,
                            onUnlockGroup: onUnlockGroup
                        )
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(Color.accent)
                    Text("그룹당 \(viewModel.maxAppsPerGroup)개 항목까지 · 같은 항목을 여러 그룹에 포함시킬 수 있어요. 그룹 이름을 탭하면 바로 바꿀 수 있어요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .opacity(viewModel.isAtGroupLimit ? 0.45 : 1)

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
            Text("그룹을 만들고 항목을 선택하면, 그룹별로 다른 일일 한도를 걸 수 있어요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .cardContainer(padding: 20)
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
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
}
