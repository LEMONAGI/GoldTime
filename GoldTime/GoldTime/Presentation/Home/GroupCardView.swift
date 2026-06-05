//
//  GroupCardView.swift
//  GoldTime
//

import FamilyControls
import SwiftUI

struct GroupCardView: View {
    let group: ScreenTimeGroup
    let viewModel: HomeViewModel
    let onDeleteGroup: (UUID) -> Void
    let onUpdateGroupName: (UUID, String) -> Void
    let onPresentPicker: (ScreenTimeGroup) -> Void
    let onPresentLimitPicker: (ScreenTimeGroup) -> Void
    let onUnlockGroup: (UUID) -> Void

    @State private var isShowingEditConfirm = false
    @State private var isShowingLimitConfirm = false
    @State private var isShowingDeleteConfirm = false
    @State private var isShowingDeleteRegularConfirm = false

    private var isLocked: Bool {
        viewModel.lockedGroupIDs.contains(group.id)
    }

    private var isOverrideActive: Bool {
        viewModel.overrideGroupIDs.contains(group.id)
    }

    /// 잠금 또는 연장 중인 그룹은 우회 방지를 위해 편집/한도/삭제 전에 광고 게이트를 거친다.
    private var isEditRestricted: Bool {
        isLocked || isOverrideActive
    }

    private var restrictedDialogTitle: String {
        isLocked ? "잠긴 그룹" : "연장 중 그룹"
    }

    private var restrictedDialogMessage: String {
        let state = isLocked ? "잠겨 있는" : "연장 중인"
        return "우회 방지를 위해,\n\(state) 그룹은 광고를 본 뒤 편집하거나 삭제할 수 있어요."
    }

    private var selectionCountText: String {
        "\(group.selectionCount)/\(viewModel.maxAppsPerGroup)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 0) {
                IconTile(systemName: "app.badge", tint: Color.accent)
                    .padding(.trailing, 12)

                VStack(alignment: .leading, spacing: 8) {
                    TextField("그룹명", text: Binding(
                        get: { group.name },
                        set: { onUpdateGroupName(group.id, $0) }
                    ))
                    .font(.headline)

                    GroupStatusBadge(
                        title: viewModel.statusTitle(for: group),
                        tint: viewModel.statusTint(for: group)
                    )

                    TimelineView(.periodic(from: .now, by: 60)) { _ in
                        if let progress = viewModel.overrideProgress(for: group) {
                            SegmentedProgressBar(
                                remaining: progress.remaining,
                                total: progress.total,
                                tint: .blue,
                                accessibilityText: progress.accessibilityLabel
                            )
                        } else if let progress = viewModel.lockProgress(for: group) {
                            SegmentedProgressBar(
                                remaining: progress.remaining,
                                total: progress.total,
                                tint: .green,
                                accessibilityText: progress.accessibilityLabel
                            )
                        }
                    }
                }

                Spacer()

                Button(role: .destructive) {
                    if isEditRestricted {
                        isShowingDeleteConfirm = true
                    } else {
                        isShowingDeleteRegularConfirm = true
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.plain)
                .confirmationDialog("그룹 삭제", isPresented: $isShowingDeleteRegularConfirm) {
                    Button("삭제", role: .destructive) {
                        onDeleteGroup(group.id)
                    }
                    Button("취소", role: .cancel) {}
                } message: {
                    Text("그룹을 삭제하면 되돌릴 수 없어요.")
                }
                .confirmationDialog(restrictedDialogTitle, isPresented: $isShowingDeleteConfirm) {
                    Button("광고 보고 삭제하기", role: .destructive) {
                        onDeleteGroup(group.id)
                    }
                    Button("취소", role: .cancel) {}
                } message: {
                    Text(restrictedDialogMessage)
                }
            }

            Divider()

            Button {
                if isEditRestricted { isShowingLimitConfirm = true } else { onPresentLimitPicker(group) }
            } label: {
                HStack(alignment: .center, spacing: 0) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("일일 한도")
                            .font(.subheadline.weight(.semibold))
                        Text(viewModel.limitLabel(group.dailyLimitMinutes))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 18)
                        .padding(.vertical, 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .confirmationDialog(restrictedDialogTitle, isPresented: $isShowingLimitConfirm) {
                Button("광고 보고 변경하기") {
                    onPresentLimitPicker(group)
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text(restrictedDialogMessage)
            }

            if isLocked {
                Button {
                    onUnlockGroup(group.id)
                } label: {
                    Label("잠금 해제", systemImage: "lock.open")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GoldTimeButtonStyle(background: Color.red.opacity(0.12), foreground: .red))
            }

            editTokenList
                .confirmationDialog(restrictedDialogTitle, isPresented: $isShowingEditConfirm) {
                    Button("광고 보고 편집하기") {
                        onPresentPicker(group)
                    }
                    Button("취소", role: .cancel) {}
                } message: {
                    Text(restrictedDialogMessage)
                }
        }
        .cardContainer()
    }

    @ViewBuilder
    private var editTokenList: some View {
        if group.selectionCount == 0 {
            Button {
                if isEditRestricted { isShowingEditConfirm = true } else { onPresentPicker(group) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.grid.2x2")
                    Text("제한 항목 선택")
                    Text(selectionCountText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(GoldTimeButtonStyle(background: Color(.tertiarySystemGroupedBackground), foreground: .primary))
        } else {
            Button {
                if isEditRestricted { isShowingEditConfirm = true } else { onPresentPicker(group) }
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        HStack(spacing: 6) {
                            Text("제한 항목")
                                .font(.subheadline.weight(.semibold))
                            Text(selectionCountText)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        Spacer()
                        Image(systemName: "square.grid.2x2")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(
                                group.selection.applicationTokens.sorted {
                                    ((try? JSONEncoder().encode($0)) ?? Data())
                                        .lexicographicallyPrecedes((try? JSONEncoder().encode($1)) ?? Data())
                                },
                                id: \.self
                            ) { token in
                                Label(token)
                                    .labelStyle(.iconOnly)
                                    .scaleEffect(1.3)
                                    .frame(width: 28, height: 28)
                                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                            ForEach(
                                group.selection.webDomainTokens.sorted {
                                    ((try? JSONEncoder().encode($0)) ?? Data())
                                        .lexicographicallyPrecedes((try? JSONEncoder().encode($1)) ?? Data())
                                },
                                id: \.self
                            ) { token in
                                Label(token)
                                    .labelStyle(.iconOnly)
                                    .scaleEffect(1.3)
                                    .frame(width: 28, height: 28)
                                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .rowContainer()
        }
    }
}
