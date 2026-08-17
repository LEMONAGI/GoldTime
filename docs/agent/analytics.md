# Firebase Analytics 운영 플레이북

Read when: Firebase/GA4 이벤트를 추가·변경할 때, 대시보드·BigQuery 분석을 설계할 때, 수집값의 의미를 해석할 때.

Skip when: 화면 문구만 바꾸고 분석 계약을 바꾸지 않을 때.

이 문서는 GoldTime이 **앱 코드로 정의해 전송하는 분석 계약**의 단일 출처다. Firebase가 자동으로 수집하는 이벤트·속성은 이 표의 일부가 아니다. 자동 수집 범위는 Firebase 공식 [iOS 이벤트 문서](https://firebase.google.com/docs/analytics/ios/events?platform=ios)에서 확인한다. 코드와 이 문서가 다르면 코드가 진실이며, 같은 변경에서 이 문서를 갱신한다.

## 한눈에 보기

- 앱 정의 이벤트는 27개다. `AnalyticsEvent`가 만드는 고정/동적 이름 23개와 extension 대기 큐에서 전송하는
  `shield_lock_started`, `shield_action_stop_selected`, `shield_action_extend_selected`,
  `screen_time_error` 4개를 합친 수다.
- 사용자 속성은 9개다. 현재 권한·적용 그룹 구성의 **마지막 알려진 상태**를 나타내는
  코호트 축이다.
- 그룹명·UUID·선택 앱/웹사이트 토큰·원시 사용 시간·사용자 식별자는 전송하지 않는다. 범주·버킷·플래그·집계된 그룹 수만 보낸다.
- 주 코드 위치: `Domain/Repository/AnalyticsRepository.swift`(이벤트), `Domain/Model/RuleAnalyticsPayload.swift`(규칙 버킷),
  `Domain/Model/UserCohortProperties.swift`(그룹 코호트), `Domain/Model/AuthorizationAnalyticsProperties.swift`(권한),
  `Core/Persistence/SharedStore.swift`(extension 큐).

## 전송 구조와 한계

| 경로 | 동작 | 해석할 때 기억할 것 |
| --- | --- | --- |
| 메인 앱 | `AnalyticsService`가 Firebase Analytics로 직접 `logEvent`한다. Firebase는 메인 앱 타겟에만 링크된다. | 이벤트는 해당 성공 경로에 도달했다는 뜻이지 이후의 장기 행동까지 뜻하지 않는다. |
| Screen Time extension | Firebase를 직접 링크하지 않는다. DeviceActivity는 `SharedStore`, ShieldAction은 동일 Codable 형태의 자체 store로 App Group 큐에 문자열 이벤트를 넣고, 메인 앱이 다음 foreground 활성화에서 드레인한다. | 큐는 최대 200건이며 초과 시 가장 오래된 항목을 버린다. 저장 시각은 Firebase 파라미터로 보내지 않으므로 GA4 시간은 실제 Shield/오류 시각보다 늦을 수 있다. |
| 사용자 속성 | 권한 속성은 모든 앱 활성화, 그룹 속성은 Screen Time 권한이 있는 앱 활성화와 그룹 설정 저장·동기화 뒤에 `setUserProperty`한다. | 이벤트에 붙은 값은 마지막 갱신 스냅샷이다. 권한 철회 시 `false`로 덮어쓰지만 사용자가 앱을 다시 열지 않으면 서버의 마지막 값은 즉시 바뀌지 않는다. extension 큐 이벤트는 드레인 뒤 속성을 갱신하므로 엄밀한 인과관계로 조인하지 않는다. |
| 광고/추적 동의 | UMP·ATT는 광고 SDK 초기화 흐름이다. Analytics 수집은 기본 활성화 상태이며 현재 코드는 `setCollectionEnabled`를 호출하지 않는다. | ATT 허용/거부를 나타내는 앱 정의 이벤트는 없다. `trackingPermission` 화면 도달을 ATT 허용으로 해석하지 않는다. |
| Crashlytics | `recordError`는 non-fatal Crashlytics 기록이며 GA4 이벤트 표와 별도다. | Crashlytics 오류 수를 `screen_time_error` 수나 Firebase Analytics 이벤트 수와 합치지 않는다. |

## 이벤트 사전

### 온보딩과 권한

| 이벤트 | 발생 조건 | 파라미터 | 분석 질문 | 해석 주의 |
| --- | --- | --- | --- | --- |
| `onboarding_entered` | 온보딩 화면이 실제로 첫 표시될 때 | 없음 | 신규 사용자 중 온보딩을 시작한 비중은 얼마인가? | SwiftUI 재생성·중간 단계 복원으로 중복되지 않게 설치당 1회만 기록한다. 신규 설치 분모는 Firebase 자동 수집 `first_open`을 쓴다. |
| `onboarding_completed` | 마지막 완료 버튼을 눌러 홈으로 넘어가기 직전 | 없음 | 온보딩 완료율은 얼마인가? | 설치당 1회만 기록하며 권한별 허용·거부는 보내지 않는다. |

### 그룹 설정과 모니터링

| 이벤트 | 발생 조건 | 파라미터 | 분석 질문 | 해석 주의 |
| --- | --- | --- | --- | --- |
| `group_snapshot` | Screen Time 권한이 있는 매 앱 활성화 | `applied_group_count`: 정수 `0`…`5`<br>`snapshot_id`: 해당 활성화의 일회성 배치 ID | 활성 사용자가 실제로 몇 개의 그룹을 적용해 쓰는가? | 0개도 반드시 보낸다. 최대 그룹 수가 5개라 버킷 없이 정수를 보내며 GA4 custom metric으로 등록해 평균 그룹 수를 바로 본다. 같은 활성화의 모든 규칙 스냅샷이 동일한 `snapshot_id`를 공유한다. 앱을 자주 열면 이벤트 수가 늘므로 총 사용자 수를 본다. |
| `group_applied` | 유효한 draft 그룹을 적용 상태로 저장한 뒤 | `rule_mode`: `uniform_daily`, `uniform_time_window`, `uniform_cooldown`, `weekday`<br>`selection_count_bucket` | 어떤 규칙 모드·선택 규모의 그룹이 새로 적용되는가? | 모니터 등록 성공을 뜻하지는 않는다. 실패는 `screen_time_error`로 별도 관찰한다. |
| `group_deleted` | 그룹 삭제가 저장된 뒤 | `was_applied`: 문자열 `true` / `false` | 실제 사용 중인 그룹과 draft 중 무엇이 삭제되는가? | 연장 불가 기간 중 차단된 삭제 시도는 기록하지 않는다. |
| `rule_uniform_daily` | 앱 활성화 시 적용된 균일 일일 한도 그룹마다 | `snapshot_id`<br>`rule_mode=uniform_daily`<br>`uniform_daily_limit_bucket`<br>`selection_count_bucket`<br>`strict_lock_active` | 활성 사용자 중 일일 한도 그룹을 쓰는 사람은 얼마나 되는가? | 앱을 자주 여는 사용자가 이벤트 수를 늘리므로 이벤트 수가 아닌 총 사용자 수로 채택률을 본다. BigQuery 현재 상태 분포는 사용자별 최신 `snapshot_id` 전체를 고른다. |
| `rule_uniform_time_window` | 앱 활성화 시 적용된 균일 시간대 그룹마다 | `snapshot_id`<br>`rule_mode=uniform_time_window`<br>`uniform_time_window_count_bucket`<br>`uniform_time_window_total_bucket`<br>`selection_count_bucket`<br>`strict_lock_active` | 활성 사용자 중 시간대 그룹을 쓰는 사람은 얼마나 되는가? | 같은 사용자가 여러 시간대 그룹을 가져도 총 사용자 수는 한 명이다. 그룹 수 분석은 BigQuery 최신 스냅샷을 쓴다. |
| `rule_uniform_cooldown` | 앱 활성화 시 적용된 균일 쿨다운 그룹마다 | `snapshot_id`<br>`rule_mode=uniform_cooldown`<br>`uniform_cooldown_usage_bucket`<br>`uniform_cooldown_duration_bucket`<br>`selection_count_bucket`<br>`strict_lock_active` | 활성 사용자 중 쿨다운 그룹을 쓰는 사람은 얼마나 되는가? | `strict_lock_active`는 쿨다운과 배타적인 규칙 종류가 아니라 이 그룹의 독립 상태다. |
| `rule_weekday_snapshot` | 앱 활성화 시 적용된 요일별 그룹마다 | `snapshot_id`<br>`rule_mode=weekday`<br>`weekday_uses_daily`<br>`weekday_uses_time_window`<br>`weekday_uses_cooldown`<br>`weekday_daily_days`<br>`weekday_time_window_days`<br>`weekday_cooldown_days`<br>`weekday_unrestricted_days`<br>`selection_count_bucket`<br>`strict_lock_active` | 요일별 그룹 내부에서 실제 규칙을 며칠씩 조합하는가? | 사용 여부 세 값은 해당 days가 1 이상이면 `true`다. 네 요일 수의 합은 정상 데이터에서 7이다. `weekday`를 daily/time-window/cooldown과 동급 규칙으로 합산하지 않는다. |

### Shield와 해제 선택

| 이벤트 | 발생 조건 | 파라미터 | 분석 질문 | 해석 주의 |
| --- | --- | --- | --- | --- |
| `shield_lock_started` | extension이 새 차단을 만들 때 | `rule_mode`: `uniform_daily`, `uniform_time_window`, `uniform_cooldown`, `weekday`, `unknown`<br>`enforcement_rule`: `daily`, `time_window`, `cooldown` | 어떤 저장 방식의 어떤 실제 규칙에서 사용자가 막히는가? | Shield UI 노출 횟수가 아니라 새 차단 상태 시작이다. `rule_mode=weekday`는 요일별 저장 방식, `enforcement_rule`은 그날 투영된 실제 규칙이다. |
| `shield_action_stop_selected` | 시스템 Shield의 “그만 쓰기”를 탭 | 없음 | Shield에서 차단을 수용한 비중은 얼마인가? | 앱을 다시 열지 않으면 큐가 드레인되지 않아 구조적으로 과소집계될 수 있다. |
| `shield_action_extend_selected` | 시스템 Shield의 “GoldTime 가기”를 탭 | 없음 | Shield에서 연장 진입을 선택한 비중은 얼마인가? | 앱이 실제로 열렸거나 연장이 성공했다는 뜻은 아니다. |
| `shield_extend_options_viewed` | 연장 선택 시트가 실제 표시될 때 | `entry_source`: `shield`, `home_group`<br>`locked_group_count`<br>`strict_locked_group_count`<br>`one_minute_remaining`: `0`…`5`<br>`near_midnight`: 문자열 `true`/`false` | Shield 복귀와 홈 그룹 카드 중 어디에서, 몇 개 그룹·어떤 제약 상태로 연장을 고르는가? | ViewModel 생명주기당 1회만 기록한다. Shield 액션 퍼널은 `entry_source=shield`만 분모로 쓴다. |
| `shield_extend_stop_selected` | 연장 시트에서 “그만 쓰기”를 탭 | `locked_group_count` | 연장 화면까지 왔지만 멈춘 비중은 얼마인가? | 탭 행동일 뿐 실제 장기 사용 중단의 증거는 아니다. |
| `shield_extend_method_selected` | 유효한 그룹에 1분 또는 광고 연장을 선택 | `extend_method`: `one_minute`, `ad` | 어떤 연장 방식을 선호하는가? | `ad`는 광고 경로 선택이며, 실제 보상 획득·fallback은 `ad_*` 퍼널로 분리한다. |
| `shield_extend_completed` | 선택한 그룹의 Screen Time 연장이 실제 성공 | `extend_method`<br>`extend_seconds`<br>`rule_mode`<br>`enforcement_rule`<br>규칙 snapshot 파라미터 | 어떤 그룹 설정·실제 차단 규칙에서 연장이 성공하는가? | `extend_method=ad`는 광고 보상 또는 무료 fallback 후 실제 집행 성공을 합친다. |
| `shield_extend_failed` | 실제 Screen Time 연장 시도가 실패 | `extend_method`<br>`failure_reason`: `group_not_found`, `one_minute_limit_reached`, `relock_timer_registration_failed`, `strict_lock_active` | 선택 후 어떤 이유로 연장이 완료되지 않는가? | 자동 재시도도 실제 시도라 실패 건수에 포함될 수 있다. |

### 광고 퍼널

`placement` 값은 `shield_unlock`(Shield 해제) 또는 `group_edit_gate`(그룹 변경 적용 완료 게이트)다.

| 이벤트 | 발생 조건 | 파라미터 | 분석 질문 | 해석 주의 |
| --- | --- | --- | --- | --- |
| `ad_started` | 준비된 보상형 광고를 실제 표시하기 직전 | `placement` | 위치별 광고 표시 시도는 얼마인가? | 광고 요청·로딩 시작이 아니다. |
| `ad_reward_earned` | 광고 SDK가 보상 획득 콜백을 줄 때 | `placement` | 위치별 보상 완료율은 얼마인가? | Shield 해제의 실제 연장 성공은 `shield_extend_completed`(‘extend_method=ad’)로 따로 확인한다. |
| `ad_closed_no_reward` | 광고가 보상 없이 닫힐 때 | `placement` | 위치별 미완료/이탈은 얼마인가? | 광고가 아예 로드되지 않은 경우는 `ad_unavailable`이다. |
| `ad_unavailable` | 광고 로드 실패로 무료 fallback UI를 처음 보여줄 때 | `placement` | 위치별 광고 공급 실패는 얼마인가? | 두 진입 경로의 중복 기록을 막는다. 광고 수익·노출 수가 아니다. |
| `ad_fallback_used` | 사용자가 fallback 무료 진행을 선택 | `placement` | 광고가 없을 때 무료 대안을 얼마나 쓰는가? | `ad_unavailable` 이후의 선택 이벤트다. 자동 지급량이 아니다. |

### 연장 불가 모드와 운영 오류

| 이벤트 | 발생 조건 | 파라미터 | 분석 질문 | 해석 주의 |
| --- | --- | --- | --- | --- |
| `strict_lock_started` | 연장 불가 기간의 최초 시작이 저장·동기화된 뒤 | `strict_lock_days`: 선택한 기간(1…30)<br>해당 그룹의 `rule_mode`·규칙별 snapshot 파라미터 | 어떤 그룹 구성에서 며칠짜리 연장 불가를 시작하는가? | 실제 완주를 뜻하지 않는다. |
| `strict_lock_extended` | 이미 활성인 연장 불가 기간의 연장이 저장·동기화된 뒤 | `strict_lock_days`: 이번에 선택한 기간(1…30)<br>해당 그룹의 `rule_mode`·규칙별 snapshot 파라미터 | 어떤 사용자가 기간을 다시 연장하는가? | 최초 시작과 분리했으며, 최종 남은 일수가 아니라 이번 선택 일수다. |
| `strict_lock_completed` | 시작·연장 때 기록한 만료 시각을 권한 유지 상태로 지난 뒤 첫 앱 활성화 | `strict_lock_total_days`: 최초 시작일에서 최종 만료일까지의 총 일수 | 연장 불가 기간을 정상적으로 끝까지 유지한 비중은 얼마인가? | 1.3.0부터 시작한 약정만 대상이며 그룹별 1회다. 앱이 다시 열려야 전송되고, 복구 화면에서 권한 철회가 감지된 약정은 완주로 세지 않는다. 미승인 상태의 활성화는 전송을 **미룰 뿐 약정을 버리지 않으므로**, 권한이 정상으로 읽힌 다음 활성화에서 전송된다(그만큼 GA4 시각이 실제 만료보다 늦을 수 있다). 총 기간이라 시작·연장의 `strict_lock_days`(이번 선택분)와 **이름을 분리했다** — 두 값을 한 지표로 평균 내지 않는다. |
| `strict_lock_revoke_detected` | Screen Time 복구 화면에서 활성 연장 불가 기간과 권한 철회 상태를 감지 | 없음 | 연장 불가 기간 중 권한 철회가 복구 화면에서 얼마나 관측되는가? | 권한 철회 순간의 직접 콜백이 아니라, 사용자가 복구 화면에 도달했을 때의 관측값이다. 1.2.0 이름은 `strict_revoke_detected`다. |
| `screen_time_error` | extension·백그라운드·ScreenTimeManager의 등록/복구 실패를 다음 앱 활성화에 전송 | `context`<br>`message`: 오류 요약 앞 100자 | 어느 등록·복구 경로가 불안정한가? | 큐의 200건 상한과 지연 전송 영향을 받는다. 오류 메시지 원문으로 사용자·그룹을 식별하는 분석을 만들지 않는다. |

`screen_time_error.context`의 현재 값은 다음과 같다.

| 범주 | 값 |
| --- | --- |
| 자정 재무장 | `heartbeatDaily`, `heartbeatCooldown`, `heartbeatTimeWindow` |
| 쿨다운 | `cooldownTimer`, `cooldownTimerRestore`, `cooldownRecharge` |
| 연장·백그라운드 | `overrideMonitor`, `backgroundReconnect` |

## 공통 계약

### 규칙 공통 파라미터

`shield_extend_completed`와 `strict_lock_started`/`strict_lock_extended`에서 규칙 snapshot을 재사용한다.
`group_applied`는 중복 상세값을 제외하고 `rule_mode`와
`selection_count_bucket`만 보낸다. 규칙별 파라미터는 해당 규칙일 때만 존재한다.

| 파라미터 | 값/버킷 | 의미 |
| --- | --- | --- |
| `rule_mode` | `uniform_daily`, `uniform_time_window`, `uniform_cooldown`, `weekday` | 그룹에 저장된 top-level 설정 방식. |
| `enforcement_rule` | `daily`, `time_window`, `cooldown`, `unknown` | `shield_extend_completed`에서 오늘 실제 차단·연장된 규칙. |
| `selection_count_bucket` | `selection_0`, `selection_1`, `selection_2_3`, `selection_4_6`, `selection_7_9`, `selection_10_plus` | 선택한 앱/웹사이트 수의 익명 버킷. |
| `uniform_daily_limit_bucket` | `daily_0m`, `daily_1_15m`, `daily_16_30m`, `daily_31_60m`, `daily_61_120m`, `daily_121_240m`, `daily_241m_plus` | 균일 일일 한도에서만 보낸다. |
| `uniform_time_window_count_bucket`, `uniform_time_window_total_bucket` | `windows_*`, `total_*` | 균일 시간대에서만 보낸다. |
| `uniform_cooldown_usage_bucket`, `uniform_cooldown_duration_bucket` | `usage_*`, `rest_*` | 균일 쿨다운에서만 보낸다. |
| `weekday_uses_*`, `weekday_*_days` | 사용 여부와 `0`…`7` | 요일별 그룹 내부의 규칙·제한 없음 구성. |
| `strict_lock_active` | 문자열 `true`/`false` | 규칙과 독립적인 해당 그룹의 연장 불가 상태. |
| `snapshot_id` | 활성화마다 새 UUID 문자열 | `group_snapshot`과 같은 활성화의 `rule_*` 이벤트를 묶는 익명 배치 ID. 사용자·그룹 식별자가 아니며 BigQuery 조인 전용이라 GA4 custom dimension으로 등록하지 않는다. |

### 사용자 속성

| 속성 | 값 | 정의와 사용처 |
| --- | --- | --- |
| `authorized_screen_time` | 문자열 `true` / `false` | 앱이 활성화될 때 새로 조회한 Screen Time 권한. 철회 후 다음 앱 진입에서 `false`로 갱신한다. |
| `authorized_notification` | 문자열 `true` / `false` | 앱 활성화마다 조회한 알림 권한. `authorized`·`provisional`·`ephemeral`은 `true`, 나머지는 `false`다. |
| `primary_rule_kind` | `dailyLimit`, `timeWindows`, `cooldown`, `weekday`, `none` | 적용 그룹을 그룹당 한 표로 센 최빈 규칙. 동률·없음은 `none`이다. |
| `uses_daily` | 문자열 `true` / `false` | 요일별 그룹 안의 일일 한도까지 포함해 사용 여부를 표시한다. |
| `uses_timewindow` | 문자열 `true` / `false` | 요일별 그룹 안의 시간대까지 포함한다. |
| `uses_cooldown` | 문자열 `true` / `false` | 요일별 그룹 안의 쿨다운까지 포함한다. |
| `uses_weekday` | 문자열 `true` / `false` | 요일별 규칙 그룹이 하나 이상 적용됐는지 표시한다. |
| `active_rule_profile` | `wdN_dlN_twN_cdN` | 적용 그룹의 top-level 그룹 수. 순서는 요일별·일일 한도·시간대·쿨다운이며, 요일별 내부 규칙은 별도 그룹으로 세지 않는다. |
| `strict_rule_profile` | `wdN_dlN_twN_cdN` | 아직 만료되지 않은 연장 불가 기간을 가진 적용 그룹만 같은 방식으로 센다. 없으면 `wd0_dl0_tw0_cd0`이다. |

속성은 사용자 성향의 영구 사실이 아니라 마지막 알려진 권한·설정 스냅샷이다. 기간 비교에서는
이벤트에 붙은 속성과 이벤트 날짜를 함께 보고, 과거 이벤트를 현재 사용자 속성으로 재분류하지 않는다.

## 무엇을 분석할 수 있는가

| 질문 | 권장 분자 / 분모 | 함께 볼 축 | 피해야 할 결론 |
| --- | --- | --- | --- |
| 온보딩을 시작·완료하는가? | `onboarding_entered` / 자동 `first_open`, `onboarding_completed` / `onboarding_entered` | 앱 버전, 날짜 | `onboarding_completed`는 두 권한의 현재 허용을 뜻하지 않으므로 권한 속성을 별도로 본다. |
| 활성 사용자가 권한을 유지하는가? | `authorized_screen_time = true` 사용자 / 활성 사용자, `authorized_notification = true` 사용자 / 활성 사용자 | 앱 버전, 날짜 | 속성은 마지막 앱 활성화 스냅샷이므로 앱을 다시 열지 않은 사용자의 OS 설정 변경을 실시간으로 알 수는 없다. |
| 활성 사용자는 몇 개의 그룹을 쓰는가? | `group_snapshot` 총 사용자 수 | `applied_group_count`, 권한 속성 | 이벤트 수를 그룹 수로 해석하지 않는다. |
| 그룹을 새로 적용하거나 포기하는가? | `group_applied`, `group_deleted` 사용자/건수 | `rule_mode`, `was_applied` | 두 이벤트는 동일 그룹을 연결할 ID를 보내지 않으므로 그룹별 수명 분석은 할 수 없다. |
| 한도 도달 뒤 사용자는 무엇을 선택하는가? | `shield_extend_stop_selected`, `shield_extend_method_selected`, `shield_extend_completed` / `shield_extend_options_viewed` | `extend_method`, `locked_group_count`, `strict_locked_group_count` | 멈추기는 탭이지 실제 앱 종료·장기 중단의 증거가 아니다. |
| 광고 경험은 어디에서 끊기는가? | `ad_reward_earned` 또는 `ad_closed_no_reward` / `ad_started`; `ad_fallback_used` / `ad_unavailable` | `placement` | `group_edit_gate`는 Shield 해제가 아니다. Shield의 실제 연장 성공은 `shield_extend_completed`를 따로 본다. |
| 어떤 규칙이 마찰과 연장을 만드는가? | `shield_lock_started`, `shield_extend_completed` | `rule_mode`, `enforcement_rule`, 규칙 snapshot 버킷 | `weekday`는 설정 방식, `daily`/`time_window`/`cooldown`은 그날 실제 집행 규칙이므로 같은 축으로 합치지 않는다. |
| 어떤 규칙을 현재 사용하는가? | `rule_uniform_*`, `rule_weekday_snapshot` 이벤트의 총 사용자 수 | `rule_mode`, `weekday_*_days`, `strict_lock_active` | 앱 활성화마다 그룹별로 보내므로 이벤트 수를 그룹 채택률로 쓰지 않는다. |
| 연장 불가 모드는 행동을 어떻게 바꾸는가? | `strict_lock_completed` / `strict_lock_started`, strict 프로필 보유/비보유 코호트의 Shield·해제 선택 비교 | `strict_rule_profile`, `strict_lock_days`(시작·연장), `strict_lock_total_days`(완료), `strict_lock_extended`, `strict_lock_revoke_detected` | 완료는 1.3.0부터 앱이 추적한 약정만 포함하고, 활성 연장 불가 그룹의 광고·1분 이벤트 0은 의도된 차단일 수 있다. |
| Screen Time 경로가 안정적인가? | `screen_time_error` 사용자/건수 / Screen Time 권한 활성 사용자 | `context`, 앱 버전, 날짜 | 큐 지연·상한 때문에 실시간 오류율·정확한 발생 시각으로 해석하지 않는다. |

## 추이 해석 규칙

- `group_edit_gate`의 광고 노출 의미는 1.2.0부터 “편집 진입”이 아니라 “변경 적용 완료 게이트”다. 이전 버전과 단순 비교해 감소를 이탈로 결론내리지 않는다.
- 연장 불가 기간의 그룹은 광고·1분 연장이 UI에서 차단된다. 이 구간의 해제·광고 이벤트 0은 정상 제품 동작일 수 있다.
- `ad_started`·`ad_reward_earned`는 광고 SDK 퍼널, `shield_extend_completed`는 Screen Time 연장 집행 성공이다. 같은 분모로 합치지 않는다.
- `shield_lock_started`·`shield_action_*`·`screen_time_error`는 extension 큐를 거쳐 늦게 전송되거나 200건 상한에서 유실될 수 있다. 일시별 피크와 실시간 모니터링에는 부적합하다.
- 이 계약은 광고 횟수와 무료 fallback만 기록한다. AdMob paid revenue·eCPM·실제 impression은 포함하지 않는다.

## GA4와 BigQuery 운영

### 콘솔 등록 원칙

저장소만으로 GA4 Console의 Custom definitions 등록 여부는 확인할 수 없다. 새 대시보드를 만들기 전에 **Admin → Custom definitions**에서 아래를 확인·등록하고 이 문서의 “콘솔 상태”를 실제 상태로 갱신한다. 이벤트 파라미터는 이벤트 범위 custom dimension/metric, 사용자 속성은 사용자 범위 custom dimension으로 등록한다. 공식 [GA4 custom dimensions 안내](https://support.google.com/analytics/answer/14240153?hl=en)을 따른다.

**2026-08-18 콘솔 전수 확인 — 반드시 등록해야 하는 것은 0건이다.** 등록 현황 전부(측정기준
**18개**, 측정항목 **11개**)를 코드의 전송 파라미터와 대조했고 **1.3.0이 요구하는 등록은 전부
완료됐다.**

아래 표의 ⬜ 행은 **전부 선택이며 출시를 막지 않는다.** 미등록이라는 사실을 "등록해야 한다"로
번역하지 말 것 — GA4 등록의 유일한 효과는 **웹 UI에서 그 축을 고를 수 있다**는 것이고,
등록하지 않아도 이벤트는 정상 수집되며 goldtime-dashboard(BigQuery 직접 조회)도 영향받지 않는다.

**보고할 때의 규칙**: 필수 등록과 선택 등록을 같은 목록·같은 문단에 넣지 않는다. 필수가 0건이면
**"등록할 것 없음"으로 끝내고**, 선택지는 사용자가 GA4 UI에서 볼 축을 물었을 때만 꺼낸다.
"소급되지 않으니 미리 넣는 게 좋다"는 조언을 필수처럼 붙이면, 다 끝난 작업이 남은 할 일로
읽혀 보고가 앞뒤로 뒤집힌다(2026-08-18 실제로 그렇게 보고해 사용자를 혼란시킨 사고가 있었다).

아래 분류에서 "이번 개편이 새로 만든 것"과 "1.2.x부터 계속 미등록이던 것"을 **반드시 구분**한다 —
이 문서의 권장 목록만 보고 전부 미등록으로 세면 이번 변경의 할 일이 3배로 부풀어 보인다(실제로
그렇게 잘못 센 사고가 있었다). 미등록 여부는 **코드의 실제 전송 파라미터와 대조**해서 판단할 것.

| 등록 대상 | 범위·형식 | 상태 |
| --- | --- | --- |
| `rule_mode`, `enforcement_rule`, `entry_source`, `extend_method`, `failure_reason`, `near_midnight`, `strict_lock_active`, `was_applied`, `weekday_uses_daily`, `weekday_uses_time_window`, `weekday_uses_cooldown` | 이벤트 · 텍스트 차원 | ✅ 등록 |
| `uniform_daily_limit_bucket`, `uniform_time_window_count_bucket`, `uniform_time_window_total_bucket`, `uniform_cooldown_usage_bucket`, `uniform_cooldown_duration_bucket` | 이벤트 · 텍스트 차원 | ✅ 등록(2026-08-18 — 1.3.0이 새로 요구한 5개) |
| `applied_group_count`, `locked_group_count`, `strict_locked_group_count`, `one_minute_remaining`, `extend_seconds`, `strict_lock_days`, `strict_lock_total_days`, `weekday_daily_days`, `weekday_time_window_days`, `weekday_cooldown_days`, `weekday_unrestricted_days` | 이벤트 · 정수 metric | ✅ 등록(`extend_seconds`만 단위 `초`, 나머지 `일반`) |
| `authorized_screen_time`, `authorized_notification` | 사용자 · 텍스트 차원 | ✅ 등록 |
| `placement`, `selection_count_bucket`, `context` | 이벤트 · 텍스트 차원 | ⬜ 1.2.x부터 미등록 — **이번 개편과 무관**한 기존 선택 |
| `primary_rule_kind`, `uses_daily`, `uses_timewindow`, `uses_cooldown`, `uses_weekday`, `active_rule_profile`, `strict_rule_profile` | 사용자 · 텍스트 차원 | ⬜ 1.2.x부터 미등록 — **이번 개편과 무관** |
| `snapshot_id` | — | ⛔ **등록 금지** — BigQuery 배치 복원 전용 ID다 |
| `screen_time_error.message` | — | ⛔ **등록 금지** — 오류 원문 100자라 카디널리티가 폭발한다. 원인 분류는 `context`로만 본다 |

구 `applied_group_count_bucket`(표시 이름 `적용 그룹 수`) 차원은 2026-08-18 아카이브 완료 —
출시된 적 없는 이름이라 과거 데이터가 0건이었다.

한도는 넉넉하다(표준 속성: 이벤트 범위 차원 50 · 사용자 범위 차원 25 · custom metric 50).
미등록분은 **대시보드에 영향이 없다** — goldtime-dashboard는 BigQuery를 직접 조회하므로 등록 여부와
무관하다. 영향은 GA4 UI(탐색 분석·보고서)에서 그 축을 고를 수 없다는 것 하나뿐이다. 다만 **등록은
소급되지 않으므로**, GA4 UI에서 볼 생각이 있으면 그 데이터가 흐르기 **전에** 등록해야 한다.

`uniform_*` 5개가 "새로 만든 것"인 이유: 이들이 대체한 구 버킷(`daily_limit_bucket` 등)도 미등록이라
현상 유지로 보이지만, **붙는 자리가 바뀌었다**. 구 버킷은 `group_applied`(적용하는 순간의 행위)에
실렸고 신 버킷은 스냅샷 이벤트(현재 설정 상태)에 실린다 — "지금 사람들이 하루 몇 분으로 맞춰
쓰는가"를 GA4 UI에서 보려면 이 5개가 필요하다.

같은 파라미터를 이벤트별로 중복 등록하지 않는다. GA4 등록은 과거 수집 데이터의 완전한 소급 해결책이 아니며 보고서 반영에는 시간이 걸릴 수 있다. 앱 이벤트의 정수 파라미터는 이벤트 범위 차원보다 custom metric으로 다루는 것이 안전하다.

2026-08-16 콘솔 캡처로 Shield·연장 신규 텍스트 차원 5개
(`enforcement_rule`, `entry_source`, `extend_method`, `failure_reason`, `near_midnight`)와 정수 커스텀
메트릭 4개(`locked_group_count`, `strict_locked_group_count`, `one_minute_remaining`,
`extend_seconds`)의 이벤트 범위 등록을 확인했다. `extend_seconds`의 측정 단위는 `초`,
나머지 세 메트릭은 `일반`이다.

2026-08-17 콘솔 캡처로 `applied_group_count`(표시 이름 `현재 적용 그룹 수`)와
`strict_lock_total_days`(표시 이름 `연장 불가 총 유지 일수`)가 이벤트 범위 custom metric,
측정 단위 `일반`으로 등록된 것을 확인했다.

**아카이브 대상 — 구 custom dimension `applied_group_count_bucket`**(표시 이름 `적용 그룹 수`,
이벤트 범위 텍스트). 이 이름은 **출시된 적이 없다**: `group_snapshot` 자체가 1.3.0 신규
이벤트이고, 출시 전에 파라미터를 `applied_group_count`(정수)로 바꿨다. 따라서 뒤에 쌓인 과거
데이터가 **0건**이며 아카이브해도 잃을 것이 없고, 앞으로도 영구히 데이터가 들어오지 않는다.
남겨두면 보고서 선택기에 `적용 그룹 수`(죽은 차원)와 `현재 적용 그룹 수`(살아 있는 metric)가
나란히 떠서 혼동을 만든다. "과거 데이터용으로 보존"이라고 적지 말 것 — 보존할 과거가 없다.

### BigQuery에서 보는 법

BigQuery export가 연결돼 있다면 `events_YYYYMMDD`의 반복 레코드인 `event_params`와 `user_properties`를 `UNNEST`한다. 속성은 이벤트 레코드에 붙은 스냅샷으로 읽고, `user_pseudo_id`와 현재 속성만으로 과거 행동을 다시 분류하지 않는다. 스키마는 공식 [GA4 BigQuery export schema](https://support.google.com/analytics/answer/7029846?hl=en)에서 확인한다.

```sql
SELECT
  event_date,
  event_name,
  user_pseudo_id,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'placement') AS placement,
  (SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'active_rule_profile') AS active_rule_profile
FROM `project.analytics_PROPERTY_ID.events_*`
WHERE _TABLE_SUFFIX BETWEEN 'YYYYMMDD' AND 'YYYYMMDD'
  AND event_name IN ('ad_started', 'ad_reward_earned', 'shield_extend_completed');
```

숫자 파라미터는 `event_params.value.int_value`, 문자열 버킷은 `string_value`에서 꺼낸다. 쿼리에 새 파라미터를 추가할 때는 먼저 이 이벤트 사전에서 그 파라미터가 해당 이벤트에 실제 존재하는지 확인한다.

## 변경 체크리스트

이벤트·파라미터·사용자 속성을 변경할 때는 같은 변경에서 다음을 한다.

1. `AnalyticsEvent`/대기 큐와 이 문서의 이벤트 수·발생 조건·값 목록을 함께 수정한다.
2. 새 값이 사용자별 식별자·그룹명·선택 앱/웹사이트·원시 사용시간을 보내지 않는지 검토한다.
3. GA4 custom definition 등록 필요 여부와 BigQuery/대시보드 쿼리 영향을 기록한다.
4. extension 이벤트면 큐 지연·200건 상한·foreground 드레인 영향을 이 문서와 검증 시나리오에 반영한다.
