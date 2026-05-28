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

    var body: some View {
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
                        GroupStatusBadge(
                            title: viewModel.statusTitle(for: group),
                            tint: viewModel.statusTint(for: group)
                        )
                        if viewModel.overrideGroupIDs.contains(group.id) {
                            TimelineView(.periodic(from: .now, by: 60)) { _ in
                                if let remainingLabel = viewModel.overrideRemainingLabel(for: group) {
                                    GroupStatusBadge(title: remainingLabel, tint: .blue)
                                }
                            }
                        }
                        if let lockLabel = viewModel.remainingBeforeLockLabel(for: group) {
                            GroupStatusBadge(title: lockLabel, tint: .green)
                        }
                        GroupStatusBadge(
                            title: "항목 \(group.appCount)/\(viewModel.maxAppsPerGroup)",
                            tint: group.appCount >= 8 ? .orange : .secondary
                        )
                    }
                }

                Spacer(minLength: 8)

                Button(role: .destructive) {
                    if isLocked {
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
                .confirmationDialog("잠긴 그룹", isPresented: $isShowingDeleteConfirm) {
                    Button("광고 보고 삭제하기", role: .destructive) {
                        onDeleteGroup(group.id)
                    }
                    Button("취소", role: .cancel) {}
                } message: {
                    Text("우회 방지를 위해,\n잠겨 있는 그룹은 광고를 본 뒤 편집하거나 삭제할 수 있어요.")
                }
            }

            Divider()

            Button {
                if isLocked { isShowingLimitConfirm = true } else { onPresentLimitPicker(group) }
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
            .confirmationDialog("잠긴 그룹", isPresented: $isShowingLimitConfirm) {
                Button("광고 보고 변경하기") {
                    onPresentLimitPicker(group)
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("우회 방지를 위해,\n잠겨 있는 그룹은 광고를 본 뒤 편집하거나 삭제할 수 있어요.")
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
                .confirmationDialog("잠긴 그룹", isPresented: $isShowingEditConfirm) {
                    Button("광고 보고 편집하기") {
                        onPresentPicker(group)
                    }
                    Button("취소", role: .cancel) {}
                } message: {
                    Text("우회 방지를 위해,\n잠겨 있는 그룹은 광고를 본 뒤 편집하거나 삭제할 수 있어요.")
                }
        }
        .cardContainer()
    }

    @ViewBuilder
    private var editTokenList: some View {
        if group.selectionCount == 0 {
            Button {
                if isLocked { isShowingEditConfirm = true } else { onPresentPicker(group) }
            } label: {
                Label("제한 항목 선택", systemImage: "square.grid.2x2")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GoldTimeButtonStyle(background: Color(.tertiarySystemGroupedBackground), foreground: .primary))
        } else {
            Button {
                if isLocked { isShowingEditConfirm = true } else { onPresentPicker(group) }
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("제한 항목")
                            .font(.subheadline.weight(.semibold))
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
