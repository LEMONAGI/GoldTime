//
//  MonitoringBackgroundTask.swift
//  GoldTime
//
//  기기 재시작 등으로 DeviceActivity 등록이 초기화됐을 때
//  앱 실행 없이 백그라운드에서 모니터링을 복구한다.
//

import BackgroundTasks
import Foundation

enum MonitoringBackgroundTask {
    static let identifier = "com.goldtime.monitoring-reconnect"

    static func handle(_ task: BGAppRefreshTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        // 폴백 경로. 주 경로는 자정 `DeviceActivityMonitor.intervalDidStart`이며,
        // 같은 가드를 공유하므로 그날 이미 예약됐으면 여기선 건너뛴다.
        NotificationService.scheduleDailyMorningNotificationIfNeeded()

        // 동기화 실패를 try?로 삼키면 fallback 복구 경로의 상태를 관측할 수 없다. 실패를 분석 큐에
        // 기록(다음 active 때 Firebase로 드레인)하고 task 완료 상태에도 반영한다.
        var syncFailed = false
        if SharedStore.isDailyMonitoringEnabled {
            do {
                try ScreenTimeManager.syncDailyMonitoring(groups: SharedStore.screenTimeGroups)
            } catch {
                SharedStore.enqueueScreenTimeError(
                    context: "backgroundReconnect",
                    message: error.localizedDescription
                )
                syncFailed = true
            }
        }

        scheduleNext()
        task.setTaskCompleted(success: !syncFailed)
    }

    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = nextMidnight()
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func nextMidnight() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.startOfDay(for: tomorrow)
    }
}
