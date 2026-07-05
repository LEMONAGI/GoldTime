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

- 쿨다운 사용 tick(`cdtick.*`, activity `cooldownUsage.*`)은 `cooldownBaselineByGroupID + tick minute`으로 `raiseUsedTime`해 진행바를 갱신하고, 복원된 사용량이 `cooldownUsageMinutes` 이상일 때만 잠금+휴식 타이머(`cooldownTimer.*`)를 건다. 휴식 종료는 `CooldownMonitor.cooldownEnd`로 오늘 23:59:59를 넘기지 않는다. `cooldownUsage` activity의 `intervalDidEnd`는 daily처럼 무시(23:59:59 자연 종료, 자정 리셋이 재등록).
- `cooldownTimer` `intervalDidEnd`(휴식 종료)는 재충전 전에 **두 가드**로 막는다: (1) `cooldownEnd != nil`(자정 등으로 이미 풀림), (2) `CooldownMonitor.shouldRechargeOnTimerEnd`(종료 예정 시각이 미래면 실제 종료 아님 → 설정 변경 재동기화 등으로 타이머가 일찍 멈춘 경우 휴식 보존). **두 조건을 단일 가드로 합치지 말 것** — `isInCooldown`은 `cooldownEnd == nil`도 false라 합치면 nil(이미 재충전됨)일 때 재충전이 잘못 통과해 이중 재충전된다. 재충전 시 직전 generation의 `cooldownUsage`를 stop한 뒤 새 generation으로 재등록. **재충전 등록이 throw하면 `enqueueScreenTimeError`로 기록 + `SharedStore.clearRegistration(for:)`으로 churn 가드를 무효화**한다 — 안 비우면 `lastRegisteredGroupsByID`에 `last==group`이 남아 메인 앱 `syncDailyMonitoring`의 `guard last != group`이 다음 foreground sync 재등록을 영구 스킵(자동 복구는 다음 자정 하트비트뿐, ~최대 24h 사용량 미추적·재잠금 공백). foreground 자가치유(`ScreenTimeManager.rechargeExpiredCooldowns`)·하트비트("성공 시에만 기록") 경로와 동일 계약.
- 재충전 등록은 `CooldownMonitor`(메인 앱과 공유)를 호출한다. extension에서 직접 DeviceActivity 이름을 문자열로 만들지 말고 이 헬퍼를 쓸 것.
- override 측정창(`releaseShield`)은 date-less(end 23:59:59, 자정을 넘기지 않음)이다. `handleOverrideTick`의 stale-tick 가드(`usageBasedOverride`/`overrideUntil` metadata 없으면 monitor만 멈추고 재잠금 안 함)는 자정 리셋 직후 늦게 도착한 tick에 대한 방어로 그대로 유지한다.
- **자정 자율 재무장 = `dailyHeartbeat`(repeats:true) `intervalDidStart`의 `handleHeartbeat()`**가 주 경로다(daily 측정창은 repeats:false라 자정에 안 울림). 정확성 규약: (1) **generation은 리셋 *전에* 스냅샷** — `resetDailyProtectionStateIfNeeded()`가 `clearAllUsedTime()`으로 `lastRegisteredGenerationByID`를 비우므로, 리셋 후 읽으면 daily generation을 잃는다. (2) 재무장·아침알림은 **`didReset==true`일 때만** — 하트비트는 같은 날 등록 직후에도 발화하므로 가드 없으면 모니터를 불필요하게 갈아끼운다. (3) daily 재등록은 즉시잠금/등록 양쪽 모두 **old activity stop + gen bump를 무조건 먼저** 한 뒤 `used>=limit`(0분 그룹 포함)이면 `markGroupShielded`만(모니터 미등록), 아니면 새 gen으로 `DailyMonitor.startUsageMonitoring`. cooldown도 동일(stop usage+timer → `CooldownMonitor.startUsageMonitoring`). timeWindow는 repeats:true라 재등록 안 하고 `lastRegisteredGroupsByID`만 복원(churn 감소). stop→+1 규약이라 date-less가 혹시 재무장해도 이중 카운트 없음.
- **하트비트 종료(23:59:59) `intervalDidEnd`는 무시**(`activity == .dailyHeartbeat` 가드) — repeats:true라 00:00에 다시 시작한다. 가드 빠뜨리면 override 종료로 오분류된다.
- **하트비트 재무장에서 `registered[group.id] = group` 기록은 모니터 등록 성공 시에만**(`do` 블록 안) 한다. `startUsageMonitoring`이 throw했는데도 catch 밖에서 기록하면, 실패한 그룹이 `lastRegisteredGroupsByID`에 등록됨으로 박제된다 → 메인 앱 `syncDailyMonitoring`의 churn 가드(`guard last != group`)가 **foreground 재등록을 영구 스킵**하고(자동 복구는 다음 자정 하트비트뿐 → 최대 ~24h 보호 공백), `monitoredGroupIDs()`가 미추적 그룹을 정상 모니터링으로 오표시한다. 성공 시에만 기록하면 실패 그룹은 `last==nil`이 되어 다음 포그라운드 sync가 즉시 재등록한다. 메인 앱 `syncDailyMonitoring`(`newRegistered[group.id]=group`을 do 블록 안에 두고 실패는 `firstError` 전파)과 동일 계약. 즉시 잠금(`used>=limit`, 모니터 미등록)·cooldown 예산 0 분기는 등록 자체가 없으니 기록 유지.
- daily 이름/파싱·`tick`/`tickInfo`·`isTrackable`은 `DailyMonitor.swift`(공유)에 있다. extension에서 같은 멤버를 다시 선언하지 말 것(중복 선언). `isTrackable`은 `ScreenTimeGroupPolicy` 재사용이라 정책 3개+`TimeWindow` typealias가 extension 멤버십에 포함된다.
- **이 extension은 자체 `Localizable.xcstrings`(번들 독립)가 필요하다.** `intervalDidStart`가 `NotificationService.scheduleDailyMorningNotificationIfNeeded()`를 호출해 **아침 요약 알림 문구를 이 extension 프로세스에서 생성**한다(`NotificationService.swift`가 membershipException으로 이 타겟에도 포함됨). 메인 앱 카탈로그는 공유되지 않으므로, 알림 문구를 `String(localized:)`로 바꾸면 `notification.morning.*` 키를 이 번들 카탈로그에도 **중복**으로 넣어야 한다 — 안 그러면 알림에 키 문자열(`notification.morning.onTime.title`)이 그대로 뜬다. Policy의 `userMessage`는 이 타겟에도 컴파일되지만 호출처가 메인 앱(Presentation)뿐이라 키가 불필요(`isTrackable`은 enum case만 사용). 호출 경로가 늘면 카탈로그도 따라 늘려야 한다.
- 이 타겟은 공유 Policy의 미사용 `String(localized:)`까지 자동 추출해 카탈로그를 오염시키지 않도록 **Use Compiler to Extract Swift Strings(`SWIFT_EMIT_LOC_STRINGS`)를 NO로 유지**한다. 런타임 로컬라이징과 카탈로그 리소스 컴파일은 그대로 동작하며, extension에서 새 문구를 호출하기 시작하면 자체 카탈로그에 키와 번역을 수동으로 추가한다.
- **사용량 알림은 tick 3경로에서 발송한다**(daily `eventDidReachThreshold`/cooldown `handleCooldownUsageTick`/override `handleOverrideTick`). `emitUsageAlerts(used:limit:override:)`가 `UsageAlertPolicy.ticks`로 50·90% 단계를 정하고 `SharedStore.claimUsageAlert`/`claimOverrideAlert`(compare-and-set)로 단계당 1회만 보낸다. daily는 **override 중이면 스킵**(연장은 override 경로가 담당), cooldown은 휴식·override 가드 뒤·예산소진 가드 **앞**에서 호출(50%는 소진 전이라야 의미). 쿨다운 휴식 종료 재충전(`handleCooldownTimerEnded` 성공, `endCooldownAndRecharge` 직후)에서 `NotificationService.scheduleRechargeAvailable`로 재사용 알림 — **자정 리셋 `handleHeartbeat` 경로는 무음**(새벽 알림 방지). **알림 문구 키(`notification.usage.*`·`notification.recharge.*`)는 이 extension의 `Localizable.xcstrings`에 중복으로 넣었다**(메인 앱 카탈로그 비공유). 시간대 5분 전·종료 알림은 메인 앱이 예약하므로 이 카탈로그엔 없다. 새 알림 문구를 extension에서 호출하면 이 번들 카탈로그도 함께 갱신.
- **`handleOverrideTick` 소진 재잠금은 `CooldownMonitor.shouldReshieldOnOverrideExhaustion`으로 가드**한다(cross-process race 방어). 쿨다운 그룹은 휴식이 진행 중일 때만 재잠금하고, 휴식이 이미 재충전된 뒤 살아남은 연장의 소진은 `markGroupShielded`를 스킵한다 — 그 잠금은 `cooldownUntil`이 없어 자정까지 해제 경로가 없는 좀비 잠금이 되기 때문. 나머지(stopMonitoring/clearOverride/recordOverrideIntervalDidEnd/resync/applyShield)는 무조건 유지. 짝이 되는 `handleCooldownTimerEnded` 재충전은 `.cooldownUsage`뿐 아니라 `.override(for:)`도 stop해 재충전 후 소진 tick 자체가 오지 않게 한다.
