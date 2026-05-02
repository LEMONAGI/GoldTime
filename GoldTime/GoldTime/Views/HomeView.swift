//
//  HomeView.swift
//  GoldTime
//
//  한도 설정, 차단 대상 선택, 모니터링 시작/중지, 현재 상태 표시.
//

import FamilyControls
import SwiftUI
internal import Combine

struct HomeView: View {
    @Binding var showLockOptions: Bool

    @State private var auth = AuthorizationService.shared
    @State private var selection = FamilyActivitySelection()
    @State private var limitMinutes: Int = 30
    @State private var isPickerPresented = false
    @State private var isMonitoring = false
    @State private var errorMessage: String?

    @State private var isShieldActive = SharedStore.isShieldActive
    @State private var oneMinuteRemaining = SharedStore.oneMinuteRemaining
    @State private var shieldOverrideUntil: Date? = SharedStore.shieldOverrideUntil

    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        if !auth.isAuthorized {
            OnboardingView(onAuthorized: { auth.refresh() })
        } else {
            content
                .onAppear(perform: loadState)
        }
    }

    private var content: some View {
        NavigationStack {
            Form {
                Section("일일 스크린타임 한도") {
                    Stepper(value: $limitMinutes, in: 1...600, step: 5) {
                        Text("\(limitMinutes)분")
                    }
                }

                Section("차단할 앱 / 카테고리") {
                    Button {
                        isPickerPresented = true
                    } label: {
                        HStack {
                            Text("앱 선택하기")
                            Spacer()
                            Text("\(selectionSummary)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("오늘의 상태") {
                    HStack {
                        Text("쉴드 활성")
                        Spacer()
                        Text(isShieldActive ? "잠금 중" : "사용 가능")
                            .foregroundStyle(isShieldActive ? .red : .green)
                    }
                    HStack {
                        Text("\"딱 1분만요\" 남은 횟수")
                        Spacer()
                        Text("\(oneMinuteRemaining) / \(SharedStore.oneMinuteDailyLimit)")
                            .foregroundStyle(.secondary)
                    }
                    if let until = shieldOverrideUntil, until > Date() {
                        HStack {
                            Text("연장 종료")
                            Spacer()
                            Text(until, style: .relative)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    if isMonitoring {
                        Button("모니터링 중지", role: .destructive) {
                            ScreenTimeManager.stopAllMonitoring()
                            isMonitoring = false
                        }
                    } else {
                        Button {
                            startMonitoring()
                        } label: {
                            Text("모니터링 시작")
                                .frame(maxWidth: .infinity)
                                .fontWeight(.bold)
                        }
                        .disabled(!canStart)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("GoldTime")
            .familyActivityPicker(isPresented: $isPickerPresented, selection: $selection)
            .onChange(of: selection) { _, newValue in
                SharedStore.selectedApps = newValue
            }
            .onChange(of: showLockOptions) { _, newValue in
                if !newValue { refreshShieldState() }
            }
            .onReceive(refreshTimer) { _ in
                refreshShieldState()
            }
        }
    }

    private var canStart: Bool {
        !(selection.applicationTokens.isEmpty
          && selection.categoryTokens.isEmpty
          && selection.webDomainTokens.isEmpty)
        && limitMinutes > 0
    }

    private var selectionSummary: String {
        let apps = selection.applicationTokens.count
        let cats = selection.categoryTokens.count
        let webs = selection.webDomainTokens.count
        let total = apps + cats + webs
        return total == 0 ? "선택 없음" : "앱 \(apps) · 카테고리 \(cats) · 웹 \(webs)"
    }

    private func loadState() {
        ScreenTimeManager.rolloverCounterIfNeeded()
        selection = SharedStore.selectedApps
        if SharedStore.dailyLimitMinutes > 0 {
            limitMinutes = SharedStore.dailyLimitMinutes
            isMonitoring = true
        }
        refreshShieldState()
    }

    private func refreshShieldState() {
        isShieldActive = SharedStore.isShieldActive
        oneMinuteRemaining = SharedStore.oneMinuteRemaining
        shieldOverrideUntil = SharedStore.shieldOverrideUntil
    }

    private func startMonitoring() {
        do {
            try ScreenTimeManager.startDailyMonitoring(
                limitMinutes: limitMinutes,
                selection: selection
            )
            isMonitoring = true
            errorMessage = nil
        } catch {
            errorMessage = "모니터링 시작 실패: \(error.localizedDescription)"
        }
    }
}
