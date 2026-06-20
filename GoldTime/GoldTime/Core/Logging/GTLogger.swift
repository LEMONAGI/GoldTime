//
//  GTLogger.swift
//  GoldTime
//
//  os.Logger(통합 로깅 시스템) 기반 디버그 로거. 그룹별·잠금 방식별로 사용량 측정 /
//  잠금 적용 / 잠금 해제가 실제로 일어나는지 추적하기 위한 경량 래퍼다.
//
//  ── 왜 print가 아니라 os.Logger인가 ──────────────────────────────────────────
//  print는 Xcode 디버거 콘솔로만 나가서 앱/extension을 강제종료하거나 Xcode 연결이
//  끊기면 사라진다. 특히 측정·잠금 로직이 도는 DeviceActivityMonitorExtension은
//  별도 프로세스라 Xcode에 거의 안 잡힌다. os.Logger는 OS가 관리하는 시스템 로그
//  저장소에 기록되어 강제종료/재부팅 후에도 일정 기간 남는다. Mac에 기기를 연결해
//  Console.app 또는 터미널로 사후 확인한다.
//
//      log stream --predicate 'subsystem == "com.nagi.GoldTime"' --info --debug
//      log show   --last 30m --predicate 'subsystem == "com.nagi.GoldTime"'
//
//  Console.app: 기기 선택 후 검색창에 `subsystem:com.nagi.GoldTime`.
//  카테고리(DailyLimit/Cooldown/TimeWindow/Override/Shield/Activity)로 좁혀 본다.
//
//  ── 프라이버시 ──────────────────────────────────────────────────────────────
//  FamilyActivitySelection·application/webDomain 토큰은 opaque(무의미)하고 민감하므로
//  절대 로깅하지 않는다. 토큰은 "개수"만 찍는다. 그룹 이름·UUID·분 수·임계값은 디버깅에
//  필요하므로 `\(value, privacy: .public)`로 명시한다 — os.Logger 기본은 동적 문자열을
//  <private>로 마스킹하기 때문이다.
//

import os

enum GTLog {
    /// extension에서 `Bundle.main`은 각 extension의 bundle id를 반환하므로,
    /// 메인 앱·extension이 동일 subsystem으로 묶이도록 고정 문자열을 쓴다.
    static let subsystem = "com.nagi.GoldTime"

    /// 일일 한도(dailyLimit) 측정/잠금.
    static let dailyLimit = Logger(subsystem: subsystem, category: "DailyLimit")
    /// 쿨다운(cooldown) 예산 측정/휴식/재충전.
    static let cooldown = Logger(subsystem: subsystem, category: "Cooldown")
    /// 시간대 차단(timeWindows) 진입/종료.
    static let timeWindow = Logger(subsystem: subsystem, category: "TimeWindow")
    /// 광고/1분 연장 해제(override) 등록/소진/재잠금.
    static let override = Logger(subsystem: subsystem, category: "Override")
    /// Shield 적용/해제, 자정 리셋·재무장.
    static let shield = Logger(subsystem: subsystem, category: "Shield")
    /// DeviceActivity 콜백 진입점 raw 추적(tick이 실제로 도착하는지 자체 확인).
    static let activity = Logger(subsystem: subsystem, category: "Activity")
}
