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

        if SharedStore.isDailyMonitoringEnabled {
            try? ScreenTimeManager.syncDailyMonitoring(groups: SharedStore.screenTimeGroups)
        }

        scheduleNext()
        task.setTaskCompleted(success: true)
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
