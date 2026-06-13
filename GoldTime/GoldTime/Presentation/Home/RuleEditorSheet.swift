//
//  RuleEditorSheet.swift
//  GoldTime
//
//  그룹의 차단 규칙(일일 한도 / 시간대별 차단)을 고르고 편집하는 시트.
//  NavigationStack 2단계: 1단계 규칙 종류 선택 → 2단계 종류별 본문.
//

import SwiftUI

struct RuleEditorSheet: View {
    @Binding var selectedKind: GroupRuleKind
    @Binding var hours: Int
    @Binding var minutes: Int
    @Binding var timeWindows: [TimeWindow]
    @Binding var cooldownUsageMinutes: Int
    @Binding var cooldownDurationMinutes: Int
    let currentKind: GroupRuleKind
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ruleRow(
                        kind: .dailyLimit,
                        systemName: "hourglass",
                        title: "일일 한도",
                        subtitle: "하루에 정한 시간을 넘기면 잠가요"
                    )
                    ruleRow(
                        kind: .timeWindows,
                        systemName: "clock.badge.xmark",
                        title: "시간대별 차단",
                        subtitle: "정한 시간대 동안 사용을 막아요"
                    )
                    ruleRow(
                        kind: .cooldown,
                        systemName: "hourglass.bottomhalf.filled",
                        title: "쿨다운 잠금",
                        subtitle: "정한 만큼 쓰면 한동안 쉬어야 해요"
                    )
                } header: {
                    Text("차단 규칙")
                } footer: {
                    Text("적용된 그룹은 규칙을 바꾸면 바로 반영돼요.")
                }
            }
            .navigationTitle("차단 규칙")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소", action: onCancel)
                }
            }
        }
    }

    @ViewBuilder
    private func ruleRow(
        kind: GroupRuleKind,
        systemName: String,
        title: String,
        subtitle: String
    ) -> some View {
        NavigationLink {
            detail(for: kind)
        } label: {
            HStack(spacing: 14) {
                IconTile(systemName: systemName, tint: Color.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.semibold))
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if currentKind == kind {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Color.accent)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func detail(for kind: GroupRuleKind) -> some View {
        switch kind {
        case .dailyLimit:
            DailyLimitDetailView(
                hours: $hours,
                minutes: $minutes,
                onConfirm: confirm(as: .dailyLimit)
            )
        case .timeWindows:
            TimeWindowsDetailView(
                windows: $timeWindows,
                onConfirm: confirm(as: .timeWindows)
            )
        case .cooldown:
            CooldownDetailView(
                usageMinutes: $cooldownUsageMinutes,
                durationMinutes: $cooldownDurationMinutes,
                onConfirm: confirm(as: .cooldown)
            )
        }
    }

    private func confirm(as kind: GroupRuleKind) -> () -> Void {
        {
            selectedKind = kind
            onConfirm()
        }
    }
}

// MARK: - 일일 한도 본문

private struct DailyLimitDetailView: View {
    @Binding var hours: Int
    @Binding var minutes: Int
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Picker("시간", selection: $hours) {
                    ForEach(0..<6, id: \.self) { h in
                        Text("\(h)시간").tag(h)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)

                Picker("분", selection: $minutes) {
                    ForEach(Array(stride(from: 0, through: 55, by: 5)), id: \.self) { m in
                        Text("\(m)분").tag(m)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
            }
            .frame(height: 216)
            .padding(.top, 24)

            Text("이 시간을 넘기면 그룹이 잠겨요.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 12)

            Spacer()
        }
        .padding(.horizontal, 20)
        .navigationTitle("일일 한도")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("완료", action: onConfirm)
                    .fontWeight(.semibold)
            }
        }
    }
}

// MARK: - 시간대별 차단 본문

private struct TimeWindowsDetailView: View {
    @Binding var windows: [TimeWindow]
    let onConfirm: () -> Void

    private var invalidReason: TimeWindowPolicy.InvalidReason? {
        TimeWindowPolicy.firstInvalidReason(for: windows)
    }

    private var canAddWindow: Bool {
        windows.count < TimeWindowPolicy.maxWindowCount
    }

    var body: some View {
        List {
            Section {
                ForEach($windows) { $window in
                    windowRow($window)
                }
                .onDelete { offsets in
                    windows.remove(atOffsets: offsets)
                }

                Button {
                    addWindow()
                } label: {
                    Label("시간대 추가", systemImage: "plus")
                }
                .disabled(!canAddWindow)
            } footer: {
                if let invalidReason {
                    Text(invalidReason.userMessage)
                        .foregroundStyle(.red)
                } else {
                    Text("정한 시간대 동안에는 그룹이 잠겨요. 최대 \(TimeWindowPolicy.maxWindowCount)개까지 추가할 수 있어요.")
                }
            }
        }
        .navigationTitle("시간대별 차단")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("완료", action: onConfirm)
                    .fontWeight(.semibold)
                    .disabled(invalidReason != nil)
            }
        }
    }

    @ViewBuilder
    private func windowRow(_ window: Binding<TimeWindow>) -> some View {
        VStack(spacing: 8) {
            DatePicker(
                "시작",
                selection: dateBinding(for: window.startMinuteOfDay),
                displayedComponents: .hourAndMinute
            )
            DatePicker(
                "종료",
                selection: dateBinding(for: window.endMinuteOfDay),
                displayedComponents: .hourAndMinute
            )
        }
        .datePickerStyle(.compact)
    }

    private func dateBinding(for minute: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { Self.date(fromMinuteOfDay: minute.wrappedValue) },
            set: { minute.wrappedValue = Self.minuteOfDay(from: $0) }
        )
    }

    private func addWindow() {
        guard canAddWindow else { return }
        // 마지막 시간대 종료 이후에서 시작하도록 기본값을 잡고, 비면 21:00~22:00.
        let lastEnd = windows.map(\.endMinuteOfDay).max() ?? (21 * 60)
        let start = min(lastEnd, 23 * 60)
        let end = min(start + 60, 24 * 60 - 1)
        windows.append(TimeWindow(startMinuteOfDay: start, endMinuteOfDay: end))
    }
}

// MARK: - 쿨다운 잠금 본문

private struct CooldownDetailView: View {
    @Binding var usageMinutes: Int
    @Binding var durationMinutes: Int
    let onConfirm: () -> Void

    // 사용 시간 5분 단위(5분~2시간), 휴식 간격 10분 단위(30분~6시간).
    private let usagePresets = Array(stride(from: 5, through: 120, by: 5))
    private let durationPresets = Array(stride(from: 30, through: 360, by: 10))

    private var invalidReason: CooldownPolicy.InvalidReason? {
        CooldownPolicy.firstInvalidReason(usageMinutes: usageMinutes, cooldownMinutes: durationMinutes)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 4) {
                    Text("사용 시간")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("사용 시간", selection: $usageMinutes) {
                        ForEach(usagePresets, id: \.self) { m in
                            Text(Self.label(forMinutes: m)).tag(m)
                        }
                    }
                    .pickerStyle(.wheel)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Text("휴식 간격")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("휴식 간격", selection: $durationMinutes) {
                        ForEach(durationPresets, id: \.self) { m in
                            Text(Self.label(forMinutes: m)).tag(m)
                        }
                    }
                    .pickerStyle(.wheel)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: 216)
            .padding(.top, 24)

            Group {
                if let invalidReason {
                    Text(invalidReason.userMessage)
                        .foregroundStyle(.red)
                } else {
                    Text("이만큼 쓰면 잠기고, 휴식이 끝나면 다시 충전돼요. 매일 자정에도 새로 시작해요.")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.footnote)
            .multilineTextAlignment(.center)
            .padding(.top, 12)
            .padding(.horizontal, 8)

            Spacer()
        }
        .padding(.horizontal, 20)
        .navigationTitle("쿨다운 잠금")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("완료", action: onConfirm)
                    .fontWeight(.semibold)
                    .disabled(invalidReason != nil)
            }
        }
    }

    /// 분을 "N분 / N시간 / N시간 M분"으로 표기.
    static func label(forMinutes minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)분" }
        let hours = minutes / 60
        let mins = minutes % 60
        return mins == 0 ? "\(hours)시간" : "\(hours)시간 \(mins)분"
    }
}

// MARK: - Date ↔ minuteOfDay 변환

private extension TimeWindowsDetailView {
    /// 자정 기준 분을 오늘 날짜의 Date로 환산. DatePicker 바인딩에만 쓰며 날짜 성분은 무시한다.
    static func date(fromMinuteOfDay minute: Int) -> Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .minute, value: minute, to: start) ?? start
    }

    static func minuteOfDay(from date: Date) -> Int {
        TimeWindowPolicy.minuteOfDay(for: date)
    }
}
