# DeviceActivityMonitorExtension — 위험도 High / 직렬

DeviceActivity interval·threshold 콜백에서 Shield 적용·해제와 일일 상태 정리를 담당한다.
메인 앱 API에 의존하지 않고 `SharedStore`(App Group) + 알림으로만 메인 앱과 이어진다.

## 코드만 봐선 모르는 것

- **Codable/App Group key 하위 호환 필수**. 구조 변경은 설치된 앱 상태에 영향 → 마이그레이션.
- `eventDidReachThreshold`가 해당 그룹 id를 `SharedStore.shieldedGroupIDs`에 추가하고, 잠긴
  그룹들의 앱/웹사이트 token union을 Shield로 적용한다(override 중인 그룹은 union에서 제외).
- **같은 날짜의 foreground 재동기화·`.daily` 재등록은 기존 `shieldedGroupIDs`를 지우면 안 된다.**
  잠금 초기화는 실제 날짜 변경 또는 전체 보호 초기화 명시 실행 때만 허용.
- `intervalDidEnd`가 override(`override.<groupID>`)를 비우고 Shield union을 다시 적용한다.
- **시간대 전용 그룹만 있으면 `daily.*` activity가 없어 자정 콜백이 사라질 수 있다.** window
  `intervalDidStart`의 일일 리셋 점검 + 자정 BGTask(`MonitoringBackgroundTask`) + 앱 active
  동기화로 보완한다. 시간대 잠금은 `SharedStore.resyncTimeWindowLocks(now:)`로 판정.
- 1분 연장 카운터 리셋은 실제 날짜 변경 또는 전체 보호 초기화에서만.

전체 흐름은 `docs/agent/critical-flows.md`. 실기기 검증 필수(시뮬레이터 = 검증 아님).

## 주의사항 (작업 중 발견 시 누적)

- 쿨다운 사용 tick(`cdtick.*`, activity `cooldownUsage.*`)은 `cooldownBaselineByGroupID + tick minute`으로 `raiseUsedTime`해 진행바를 갱신하고, 복원된 사용량이 `cooldownUsageMinutes` 이상일 때만 잠금+휴식 타이머(`cooldownTimer.*`)를 건다. `cooldownUsage` activity의 `intervalDidEnd`는 daily처럼 무시(23:59:59 자연 종료, 자정 리셋이 재등록).
- `cooldownTimer` `intervalDidEnd`(휴식 종료)는 재충전 전에 `cooldownEnd != nil` 가드로 자정 등에 이미 풀린 경우 중복 재충전을 막는다. 재충전 시 직전 generation의 `cooldownUsage`를 stop한 뒤 새 generation으로 재등록.
- 재충전 등록은 `CooldownMonitor`(메인 앱과 공유)를 호출한다. extension에서 직접 DeviceActivity 이름을 문자열로 만들지 말고 이 헬퍼를 쓸 것.
- override 측정창(`releaseShield`)은 date-less(end 23:59:59, 자정을 넘기지 않음)이다. `handleOverrideTick`의 stale-tick 가드(`usageBasedOverride`/`overrideUntil` metadata 없으면 monitor만 멈추고 재잠금 안 함)는 자정 리셋 직후 늦게 도착한 tick에 대한 방어로 그대로 유지한다.
