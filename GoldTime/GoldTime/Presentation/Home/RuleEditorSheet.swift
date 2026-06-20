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
    /// 그룹에 이미 커밋된 규칙. 아직 규칙을 고르지 않은(새) 그룹은 nil이라 체크표시가 없다.
    let currentKind: GroupRuleKind?
    /// 자정 근처(23:30+) 편집 안내. nil이면 미노출. 일일 한도·쿨다운 상세 본문에서만 띄운다
    /// (시간대별 차단은 모니터 영향이 없어 전달하지 않는다).
    let nearMidnightNotice: String?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ruleRow(
                        kind: .dailyLimit,
                        systemName: "hourglass",
                        title: "rule.dailyLimit.title",
                        subtitle: "rule.dailyLimit.subtitle"
                    )
                    ruleRow(
                        kind: .timeWindows,
                        systemName: "clock.badge.xmark",
                        title: "rule.timeWindows.title",
                        subtitle: "rule.timeWindows.subtitle"
                    )
                    ruleRow(
                        kind: .cooldown,
                        systemName: "hourglass.bottomhalf.filled",
                        title: "rule.cooldown.title",
                        subtitle: "rule.cooldown.subtitle"
                    )
                } footer: {
                    Text("rule.footer")
                }
            }
            .navigationTitle("rule.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel", action: onCancel)
                }
            }
        }
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private func ruleRow(
        kind: GroupRuleKind,
        systemName: String,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey
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
                nearMidnightNotice: nearMidnightNotice,
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
                nearMidnightNotice: nearMidnightNotice,
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
    let nearMidnightNotice: String?
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Picker("rule.picker.hour", selection: $hours) {
                    ForEach(0..<6, id: \.self) { h in
                        Text("common.hours \(h)").tag(h)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)

                Picker("rule.picker.minute", selection: $minutes) {
                    ForEach(Array(stride(from: 0, through: 55, by: 5)), id: \.self) { m in
                        Text("common.minutes \(m)").tag(m)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
            }
            .frame(height: 216)
            .padding(.top, 24)

            Text("rule.dailyLimit.hint")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 12)

            if let nearMidnightNotice {
                NearMidnightNoticeBanner(text: nearMidnightNotice)
                    .padding(.top, 16)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .navigationTitle("rule.dailyLimit.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("common.done", action: onConfirm)
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

                if canAddWindow {
                    Button {
                        addWindow()
                    } label: {
                        Label("rule.timeWindows.add", systemImage: "plus")
                    }
                }
            } footer: {
                if let invalidReason {
                    Text(invalidReason.userMessage)
                        .foregroundStyle(.red)
                } else {
                    Text("rule.timeWindows.hint \(TimeWindowPolicy.maxWindowCount)")
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .navigationTitle("rule.timeWindows.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("common.done", action: onConfirm)
                    .fontWeight(.semibold)
                    .disabled(invalidReason != nil)
            }
        }
    }

    @ViewBuilder
    private func windowRow(_ window: Binding<TimeWindow>) -> some View {
        VStack(spacing: 8) {
            DatePicker(
                "rule.timeWindow.start",
                selection: dateBinding(for: window.startMinuteOfDay),
                displayedComponents: .hourAndMinute
            )
            DatePicker(
                "rule.timeWindow.end",
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
        // endMinuteOfDay는 inclusive라 직전 종료 분 +1에서 시작해야 겹치지 않는다.
        // 비면 08:00~08:59. 직전이 12:00–12:59면 새 시간대는 13:00–13:59.
        let start: Int
        if let lastEnd = windows.map(\.endMinuteOfDay).max() {
            start = min(lastEnd + 1, 23 * 60)
        } else {
            start = 8 * 60
        }
        let end = min(start + 59, 24 * 60 - 1)
        windows.append(TimeWindow(startMinuteOfDay: start, endMinuteOfDay: end))
    }
}

// MARK: - 쿨다운 잠금 본문

private struct CooldownDetailView: View {
    @Binding var usageMinutes: Int
    @Binding var durationMinutes: Int
    let nearMidnightNotice: String?
    let onConfirm: () -> Void

    // 사용 시간 5분 단위(5분~2시간), 휴식 간격 15분 단위(30분~6시간).
    private let usagePresets = Array(stride(from: 5, through: 120, by: 5))
    private let durationPresets = Array(stride(from: 30, through: 360, by: 15))

    private var invalidReason: CooldownPolicy.InvalidReason? {
        CooldownPolicy.firstInvalidReason(usageMinutes: usageMinutes, cooldownMinutes: durationMinutes)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 4) {
                    Text("rule.cooldown.usage")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("rule.cooldown.usage", selection: $usageMinutes) {
                        ForEach(usagePresets, id: \.self) { m in
                            Text(Self.label(forMinutes: m)).tag(m)
                        }
                    }
                    .pickerStyle(.wheel)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Text("rule.cooldown.rest")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("rule.cooldown.rest", selection: $durationMinutes) {
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
                    Text("rule.cooldown.hint")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .font(.footnote)
            .multilineTextAlignment(.center)
            .padding(.top, 12)
            .padding(.horizontal, 8)

            if let nearMidnightNotice {
                NearMidnightNoticeBanner(text: nearMidnightNotice)
                    .padding(.top, 16)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .navigationTitle("rule.cooldown.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("common.done", action: onConfirm)
                    .fontWeight(.semibold)
                    .disabled(invalidReason != nil)
            }
        }
    }

    /// 분을 "N분 / N시간 / N시간 M분"으로 표기.
    static func label(forMinutes minutes: Int) -> String {
        if minutes < 60 { return String(localized: "common.minutes \(minutes)") }
        let hours = minutes / 60
        let mins = minutes % 60
        return mins == 0 ? String(localized: "common.hours \(hours)") : String(localized: "common.hourMinute \(hours) \(mins)")
    }
}

// MARK: - 자정 근처 편집 안내 배너

/// 일일 한도·쿨다운 상세에서 자정 근처(23:30+) 편집임을 알리는 배너.
private struct NearMidnightNoticeBanner: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "moon.stars")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
