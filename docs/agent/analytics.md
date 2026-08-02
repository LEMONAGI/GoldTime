# Firebase Analytics 운영 플레이북

Read when: Firebase/GA4 이벤트를 추가·변경할 때, 대시보드·BigQuery 분석을 설계할 때, 수집값의 의미를 해석할 때.

Skip when: 화면 문구만 바꾸고 분석 계약을 바꾸지 않을 때.

이 문서는 GoldTime이 **앱 코드로 정의해 전송하는 분석 계약**의 단일 출처다. Firebase가 자동으로 수집하는 이벤트·속성은 이 표의 일부가 아니다. 자동 수집 범위는 Firebase 공식 [iOS 이벤트 문서](https://firebase.google.com/docs/analytics/ios/events?platform=ios)에서 확인한다. 코드와 이 문서가 다르면 코드가 진실이며, 같은 변경에서 이 문서를 갱신한다.

## 한눈에 보기

- 앱 정의 이벤트는 21개다. `AnalyticsEvent` 19개와 extension 대기 큐에서 전송하는 `shield_hit`, `screen_time_error` 2개를 합친 수다.
- 사용자 속성은 8개다. 현재 적용된 그룹 구성의 **마지막 알려진 상태**를 나타내는 코호트 축이다.
- 그룹명·UUID·선택 앱/웹사이트 토큰·원시 사용 시간·사용자 식별자는 전송하지 않는다. 범주·버킷·플래그·집계된 그룹 수만 보낸다.
- 주 코드 위치: `Domain/Repository/AnalyticsRepository.swift`(이벤트), `Domain/Model/RuleAnalyticsPayload.swift`(규칙 버킷), `Domain/Model/UserCohortProperties.swift`(코호트), `Core/Persistence/SharedStore.swift`(extension 큐).

## 전송 구조와 한계

| 경로 | 동작 | 해석할 때 기억할 것 |
| --- | --- | --- |
| 메인 앱 | `AnalyticsService`가 Firebase Analytics로 직접 `logEvent`한다. Firebase는 메인 앱 타겟에만 링크된다. | 이벤트는 해당 성공 경로에 도달했다는 뜻이지 이후의 장기 행동까지 뜻하지 않는다. |
| DeviceActivity extension | Firebase를 직접 링크하지 않는다. `SharedStore` App Group 큐에 문자열 이벤트를 넣고, 메인 앱이 다음 foreground 활성화에서 드레인한다. | 큐는 최대 200건이며 초과 시 가장 오래된 항목을 버린다. 저장 시각은 Firebase 파라미터로 보내지 않으므로 GA4 시간은 실제 Shield/오류 시각보다 늦을 수 있다. |
| 사용자 속성 | 권한이 있는 앱 활성화와 그룹 설정 저장·동기화 뒤에 `setUserProperty`한다. | 값이 바뀔 때만 수집되며, 이벤트에 붙은 값은 마지막 갱신값이다. extension 큐 이벤트는 드레인 뒤 속성을 갱신하므로 엄밀한 인과관계로 조인하지 않는다. |
| 광고/추적 동의 | UMP·ATT는 광고 SDK 초기화 흐름이다. Analytics 수집은 기본 활성화 상태이며 현재 코드는 `setCollectionEnabled`를 호출하지 않는다. | ATT 허용/거부를 나타내는 앱 정의 이벤트는 없다. `trackingPermission` 화면 도달을 ATT 허용으로 해석하지 않는다. |
| Crashlytics | `recordError`는 non-fatal Crashlytics 기록이며 GA4 이벤트 표와 별도다. | Crashlytics 오류 수를 `screen_time_error` 수나 Firebase Analytics 이벤트 수와 합치지 않는다. |

### 이벤트 Boolean 파라미터 주의

Firebase iOS SDK가 문서로 보장하는 이벤트 파라미터 타입은 `String`·`Int`·`Double`이다. 현재 `authorization_result.granted`, `notification_permission_result.granted`, `rule_changed.was_locked`, `rule_changed.caused_lock`은 Swift `Bool`을 넘긴다. 이 문서는 이를 논리값 `true`/`false`로 표기하지만, Firebase export에서 실제 저장 타입이 무엇인지는 코드만으로 확정할 수 없다.

새 대시보드나 custom definition을 만들기 전에는 DebugView와 BigQuery에서 해당 key의 `string_value`/`int_value`를 확인한다. 추후 `0`/`1` 또는 문자열로 바꾸려면 기존 보고서·historical data와 호환되는 별도 이벤트 스키마 변경으로 취급한다.

## 이벤트 사전

### 온보딩과 권한

| 이벤트 | 발생 조건 | 파라미터 | 분석 질문 | 해석 주의 |
| --- | --- | --- | --- | --- |
| `onboarding_step_view` | 사용자가 다음 단계로 실제 전환 | `step`: `screenTimePermission`, `notificationPermission`, `trackingPermission`, `completion` | 어느 단계에서 온보딩이 멈추는가? | 초기 `intro`와 복원된 시작 단계는 기록하지 않는다. 화면 노출 수가 아니라 단계 전환 수다. |
| `authorization_result` | Screen Time 권한 요청이 성공 또는 실패/거부로 종료 | `granted`: 논리값 `true` / `false` | 권한 요청 성공률은 얼마인가? | 재승인·앱 활성화 시 상태 확인은 이 이벤트가 아니다. 실제 Firebase 저장 타입은 위 Boolean 주의를 따른다. |
| `notification_permission_result` | 알림 권한 요청이 종료 | `granted`: 논리값 `true` / `false` | 알림 권한 요청 허용률은 얼마인가? | “나중에”로 건너뛴 경우는 기록하지 않는다. 실제 Firebase 저장 타입은 위 Boolean 주의를 따른다. |

### 그룹 설정과 모니터링

| 이벤트 | 발생 조건 | 파라미터 | 분석 질문 | 해석 주의 |
| --- | --- | --- | --- | --- |
| `group_created` | 새 draft 그룹을 만들고 저장한 뒤 | `group_count`: 생성 후 전체 그룹 수 | 사용자가 몇 번째 그룹까지 만드는가? | 적용·모니터링 성공을 뜻하지 않는다. 기존 사용자의 과거 그룹은 이 퍼널에 없다. |
| `group_applied` | 유효한 draft 그룹을 적용한 뒤 | [규칙 공통 파라미터](#규칙-공통-파라미터) | 어떤 규칙·선택 규모가 실제 적용되는가? | 적용 상태로 저장된 사실이다. 유효 모니터 등록은 `rule_monitoring_registered`로 본다. |
| `rule_monitoring_registered` | 사용자의 적용/편집 뒤 sync가 끝나고 해당 그룹이 유효한 모니터 대상일 때 | [규칙 공통 파라미터](#규칙-공통-파라미터) | 어떤 규칙이 실제 집행 대상이 되는가? | foreground/lifecycle 재동기화는 기록하지 않는다. 오늘 요일 규칙이 제한 없음이거나 등록 실패면 없다. |
| `monitoring_synced` | 사용자 변경에 따른 보호 동기화 성공 경로 | `applied_group_count`: 현재 적용 그룹 수 | 설정 변경 뒤 보호 동기화가 얼마나 일어나는가? | 자동 lifecycle sync는 제외한다. 그룹별 등록 성공 수나 Shield 발생 수가 아니다. |
| `rule_changed` | 기존 그룹의 **규칙 종류**가 다른 종류로 바뀔 때 | `from_rule`, `to_rule`: `dailyLimit`, `timeWindows`, `cooldown`, `weekday`<br>`was_locked`: 논리값 `true` / `false`<br>`used_bucket`<br>`caused_lock`: 논리값 `true` / `false` | 어떤 규칙 전환이 즉시 잠금으로 이어지는가? | 같은 규칙 안의 분·시간대 값 변경, 새 그룹의 첫 선택, 규칙 없음 상태는 제외된다. Boolean의 실제 Firebase 저장 타입은 위 주의를 따른다. |

### Shield와 해제 선택

| 이벤트 | 발생 조건 | 파라미터 | 분석 질문 | 해석 주의 |
| --- | --- | --- | --- | --- |
| `shield_hit` | extension이 새 잠금을 만들 때 | `rule_kind`: `dailyLimit`, `timeWindows`, `cooldown` | 실제 집행 규칙별로 사용자가 얼마나 막히는가? | 요일별 그룹도 그날 투영된 집행 규칙으로 기록하므로 `weekday`는 오지 않는다. extension 큐 지연·유실 가능성이 있다. |
| `unlock_options_shown` | Shield 요청으로 해제 시트가 처음 표시될 때 | `locked_count`: 당시 잠긴 그룹 수 | Shield 뒤 몇 개 그룹을 고르는 상황이 생기는가? | 한 번의 활성화에서 중복 표시를 막는다. Shield가 발생했어도 앱을 열지 않으면 없다. |
| `walk_away` | 잠긴 그룹이 하나 이상일 때 “그만 쓰기”를 탭 | `locked_count` | 비용 없이 멈추기를 선택한 비중은 얼마인가? | 탭 행동일 뿐 실제 사용 중단·장기 유지의 증거는 아니다. |
| `one_minute_unlock` | 1분 연장이 실제 성공 | 없음 | 광고 없이 짧은 연장을 얼마나 쓰는가? | 노출·시도·실패는 기록하지 않으며 그룹·규칙 정보도 없다. |
| `ad_unlock` | Shield 해제용 보상 광고 뒤 Screen Time 연장이 실제 성공 | `seconds`<br>[규칙 공통 파라미터](#규칙-공통-파라미터) | 어떤 규칙에서 광고로 얼마나 많은 시간을 구매하는가? | `ad_reward_earned`와 별개다. 보상 후 실제 연장이 실패하면 없다. 편집 게이트 광고에는 발생하지 않는다. |

### 광고 퍼널

`placement` 값은 `shield_unlock`(Shield 해제) 또는 `group_edit_gate`(그룹 변경 적용 완료 게이트)다.

| 이벤트 | 발생 조건 | 파라미터 | 분석 질문 | 해석 주의 |
| --- | --- | --- | --- | --- |
| `ad_started` | 준비된 보상형 광고를 실제 표시하기 직전 | `placement` | 위치별 광고 표시 시도는 얼마인가? | 광고 요청·로딩 시작이 아니다. |
| `ad_reward_earned` | 광고 SDK가 보상 획득 콜백을 줄 때 | `placement` | 위치별 보상 완료율은 얼마인가? | Shield 해제의 실제 연장 성공은 `ad_unlock`으로 따로 확인한다. |
| `ad_closed_no_reward` | 광고가 보상 없이 닫힐 때 | `placement` | 위치별 미완료/이탈은 얼마인가? | 광고가 아예 로드되지 않은 경우는 `ad_unavailable`이다. |
| `ad_unavailable` | 광고 로드 실패로 무료 fallback UI를 처음 보여줄 때 | `placement` | 위치별 광고 공급 실패는 얼마인가? | 두 진입 경로의 중복 기록을 막는다. 광고 수익·노출 수가 아니다. |
| `ad_fallback_used` | 사용자가 fallback 무료 진행을 선택 | `placement` | 광고가 없을 때 무료 대안을 얼마나 쓰는가? | `ad_unavailable` 이후의 선택 이벤트다. 자동 지급량이 아니다. |

### 연장 불가 모드와 운영 오류

| 이벤트 | 발생 조건 | 파라미터 | 분석 질문 | 해석 주의 |
| --- | --- | --- | --- | --- |
| `strict_lock_commit` | 연장 불가 기간의 시작 또는 기간 연장이 저장·동기화된 뒤 | `days`: 이번 적용 기간(1…30)<br>[규칙 공통 파라미터](#규칙-공통-파라미터) | 어떤 규칙에서 사용자가 연장 불가 모드를 선택하는가? | 신규 시작과 기간 연장을 구분하는 파라미터는 없다. 완전한 우회 방지나 실제 지속을 뜻하지 않는다. |
| `strict_revoke_detected` | Screen Time 복구 화면에서 활성 연장 불가 기간과 권한 철회 상태를 감지 | 없음 | 연장 불가 기간 중 권한 복구가 얼마나 필요한가? | 권한 철회 순간의 직접 콜백이 아니라, 사용자가 복구 화면에 도달했을 때의 관측값이다. |
| `screen_time_error` | extension·백그라운드·ScreenTimeManager의 등록/복구 실패를 다음 앱 활성화에 전송 | `context`<br>`message`: 오류 요약 앞 100자 | 어느 등록·복구 경로가 불안정한가? | 큐의 200건 상한과 지연 전송 영향을 받는다. 오류 메시지 원문으로 사용자·그룹을 식별하는 분석을 만들지 않는다. |

`screen_time_error.context`의 현재 값은 다음과 같다.

| 범주 | 값 |
| --- | --- |
| 자정 재무장 | `heartbeatDaily`, `heartbeatCooldown`, `heartbeatTimeWindow` |
| 쿨다운 | `cooldownTimer`, `cooldownTimerRestore`, `cooldownRecharge` |
| 연장·백그라운드 | `overrideMonitor`, `backgroundReconnect` |

## 공통 계약

### 규칙 공통 파라미터

`group_applied`, `rule_monitoring_registered`, `ad_unlock`, `strict_lock_commit`에서 공통으로 전송한다. 규칙별 선택 파라미터는 해당 규칙일 때만 존재한다.

| 파라미터 | 값/버킷 | 의미 |
| --- | --- | --- |
| `rule_kind` | `weekday`, `dailyLimit`, `timeWindows`, `cooldown`, `unknown` | 설정한 top-level 규칙 종류. `shield_hit`의 집행 규칙과 혼동하지 않는다. |
| `rule_config_bucket` | 아래 규칙별 버킷 | 해당 규칙의 대표 구성 버킷. |
| `selection_count_bucket` | `selection_0`, `selection_1`, `selection_2_3`, `selection_4_6`, `selection_7_9`, `selection_10_plus` | 선택한 앱/웹사이트 수의 익명 버킷. |
| `daily_limit_bucket` | `daily_0m`, `daily_1_15m`, `daily_16_30m`, `daily_31_60m`, `daily_61_120m`, `daily_121_240m`, `daily_241m_plus` | 일일 한도 규칙에서만 보낸다. |
| `time_window_count_bucket` | `windows_0`, `windows_1`, `windows_2`, `windows_3`, `windows_4_plus` | 시간대 규칙에서만 보낸다. |
| `time_window_total_bucket` | `total_15_60m`, `total_61_180m`, `total_181_360m`, `total_361m_plus` | 시간대의 총 허용 시간 버킷이다. |
| `cooldown_usage_bucket` | `usage_5_15m`, `usage_16_30m`, `usage_31_60m`, `usage_61_120m` | 쿨다운 사용 예산 버킷이다. |
| `cooldown_duration_bucket` | `rest_30_60m`, `rest_61_120m`, `rest_121_240m`, `rest_241_360m` | 쿨다운 휴식 시간 버킷이다. |
| `weekday_restricted_days` | `days_0`…`days_7` | 요일별 모드의 제한 요일 수다. 정상 적용 규칙은 `days_1`…`days_7`이다. |

`rule_config_bucket`은 `weekday`면 `days_N`, 일일 한도면 `daily_*`, 시간대면 `windows_*_total_*`, 쿨다운이면 `usage_*_rest_*`다. `rule_changed.used_bucket`은 `used_0m`, `used_1_15m`, `used_16_30m`, `used_31_60m`, `used_61_120m`, `used_121m_plus`다.

### 사용자 속성

| 속성 | 값 | 정의와 사용처 |
| --- | --- | --- |
| `primary_rule_kind` | `dailyLimit`, `timeWindows`, `cooldown`, `weekday`, `none` | 적용 그룹을 그룹당 한 표로 센 최빈 규칙. 동률·없음은 `none`이다. |
| `active_group_count` | `count_0`, `count_1`, `count_2_3`, `count_4_plus` | 적용된 그룹 수 버킷. |
| `uses_daily` | 문자열 `true` / `false` | 요일별 그룹 안의 일일 한도까지 포함해 사용 여부를 표시한다. |
| `uses_timewindow` | 문자열 `true` / `false` | 요일별 그룹 안의 시간대까지 포함한다. |
| `uses_cooldown` | 문자열 `true` / `false` | 요일별 그룹 안의 쿨다운까지 포함한다. |
| `uses_weekday` | 문자열 `true` / `false` | 요일별 규칙 그룹이 하나 이상 적용됐는지 표시한다. |
| `active_rule_profile` | `wdN_dlN_twN_cdN` | 적용 그룹의 top-level 그룹 수. 순서는 요일별·일일 한도·시간대·쿨다운이며, 요일별 내부 규칙은 별도 그룹으로 세지 않는다. |
| `strict_rule_profile` | `wdN_dlN_twN_cdN` | 아직 만료되지 않은 연장 불가 기간을 가진 적용 그룹만 같은 방식으로 센다. 없으면 `wd0_dl0_tw0_cd0`이다. |

속성은 사용자 성향의 영구 사실이 아니라 마지막 알려진 설정 스냅샷이다. 기간 비교에서는 이벤트에 붙은 속성과 이벤트 날짜를 함께 보고, 과거 이벤트를 현재 사용자 속성으로 재분류하지 않는다.

## 무엇을 분석할 수 있는가

| 질문 | 권장 분자 / 분모 | 함께 볼 축 | 피해야 할 결론 |
| --- | --- | --- | --- |
| 온보딩은 어디서 멈추는가? | 다음 단계 `onboarding_step_view` 사용자 / 이전 단계 사용자. 시작 분모는 자동 `first_open` 또는 `intro` 진입을 별도로 잡는다. | `authorization_result.granted`, `notification_permission_result.granted` | `onboarding_step_view`만으로 완전한 시작 퍼널을 만들지 않는다. |
| 설정이 실제 집행까지 이어지는가? | `rule_monitoring_registered` 사용자 / `group_applied` 사용자 | 규칙·선택 버킷 | `group_applied`를 모니터 등록 성공으로 간주하지 않는다. |
| 한도 도달 뒤 사용자는 무엇을 선택하는가? | `walk_away`, `one_minute_unlock`, `ad_unlock` 각각 / `unlock_options_shown` | `locked_count`, Shield의 `rule_kind` | `walk_away`는 실제 앱 종료가 아니라 탭이다. `shield_hit`과 시트 표시는 1:1이 아니다. |
| 광고 경험은 어디에서 끊기는가? | `ad_reward_earned` 또는 `ad_closed_no_reward` / `ad_started`; `ad_fallback_used` / `ad_unavailable` | `placement` | `group_edit_gate`는 Shield 해제가 아니며 `ad_unlock`이 뒤따르지 않는다. 실제 광고 매출은 이 데이터에 없다. |
| 어떤 규칙이 마찰과 연장을 만드는가? | `shield_hit`, `ad_unlock`, `rule_changed.caused_lock` | 규칙 공통 버킷, 사용자 속성 | 요일별 그룹의 `shield_hit`은 그날의 daily/timeWindow/cooldown 집행값이다. `weekday`와 같은 축으로 단순 합치지 않는다. |
| 연장 불가 모드는 행동을 어떻게 바꾸는가? | strict 프로필 보유/비보유 코호트의 Shield·해제 선택 비교 | `strict_rule_profile`, `strict_lock_commit.days` | 활성 연장 불가 그룹의 광고·1분 이벤트 0은 의도된 차단일 수 있다. |
| Screen Time 경로가 안정적인가? | `screen_time_error` 사용자/건수 / 관련 `rule_monitoring_registered` 또는 `monitoring_synced` 사용자 | `context`, 앱 버전, 날짜 | 큐 지연·상한 때문에 실시간 오류율·정확한 발생 시각으로 해석하지 않는다. |

## 추이 해석 규칙

- `group_edit_gate`의 광고 노출 의미는 1.2.0부터 “편집 진입”이 아니라 “변경 적용 완료 게이트”다. 이전 버전과 단순 비교해 감소를 이탈로 결론내리지 않는다.
- 연장 불가 기간의 그룹은 광고·1분 연장이 UI에서 차단된다. 이 구간의 해제·광고 이벤트 0은 정상 제품 동작일 수 있다.
- `ad_started`·`ad_reward_earned`는 광고 SDK 퍼널, `ad_unlock`은 Shield 해제 집행 성공이다. 세 이벤트를 하나의 동일 분모로 합치지 않는다.
- `shield_hit`·`screen_time_error`는 extension 큐를 거쳐 늦게 전송되거나 200건 상한에서 유실될 수 있다. 일시별 피크와 실시간 모니터링에는 부적합하다.
- 이 계약은 광고 횟수와 무료 fallback만 기록한다. AdMob paid revenue·eCPM·실제 impression은 포함하지 않는다.

## GA4와 BigQuery 운영

### 콘솔 등록 원칙

저장소만으로 GA4 Console의 Custom definitions 등록 여부는 확인할 수 없다. 새 대시보드를 만들기 전에 **Admin → Custom definitions**에서 아래를 확인·등록하고 이 문서의 “콘솔 상태”를 실제 상태로 갱신한다. 이벤트 파라미터는 이벤트 범위 custom dimension/metric, 사용자 속성은 사용자 범위 custom dimension으로 등록한다. 공식 [GA4 custom dimensions 안내](https://support.google.com/analytics/answer/14240153?hl=en)을 따른다.

| 등록 대상 | 권장 범위·형식 | 현재 콘솔 상태 |
| --- | --- | --- |
| `rule_kind`, `rule_config_bucket`, `selection_count_bucket`, `daily_limit_bucket`, `time_window_count_bucket`, `time_window_total_bucket`, `cooldown_usage_bucket`, `cooldown_duration_bucket`, `weekday_restricted_days`, `from_rule`, `to_rule`, `used_bucket`, `placement`, `step`, `context` | 이벤트 범위 · 텍스트 차원 | 저장소에서 확인 불가 |
| `granted`, `was_locked`, `caused_lock` | **등록 전 DebugView/BigQuery로 실제 저장 타입 확인**. 확인 후 이벤트 범위 텍스트 차원 또는 정수 metric으로 등록 | 저장소에서 확인 불가 |
| `group_count`, `applied_group_count`, `locked_count`, `seconds`, `days` | 이벤트 범위 · 정수 custom metric | 저장소에서 확인 불가 |
| 이 문서의 사용자 속성 8개 | 사용자 범위 · 텍스트 차원 | 저장소에서 확인 불가 |

같은 파라미터를 이벤트별로 중복 등록하지 않는다. GA4 등록은 과거 수집 데이터의 완전한 소급 해결책이 아니며 보고서 반영에는 시간이 걸릴 수 있다. 앱 이벤트의 정수 파라미터는 이벤트 범위 차원보다 custom metric으로 다루는 것이 안전하다.

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
  AND event_name IN ('ad_started', 'ad_reward_earned', 'ad_unlock');
```

숫자 파라미터는 `event_params.value.int_value`, 문자열 버킷은 `string_value`에서 꺼낸다. 쿼리에 새 파라미터를 추가할 때는 먼저 이 이벤트 사전에서 그 파라미터가 해당 이벤트에 실제 존재하는지 확인한다.

## 변경 체크리스트

이벤트·파라미터·사용자 속성을 변경할 때는 같은 변경에서 다음을 한다.

1. `AnalyticsEvent`/대기 큐와 이 문서의 이벤트 수·발생 조건·값 목록을 함께 수정한다.
2. 새 값이 사용자별 식별자·그룹명·선택 앱/웹사이트·원시 사용시간을 보내지 않는지 검토한다.
3. GA4 custom definition 등록 필요 여부와 BigQuery/대시보드 쿼리 영향을 기록한다.
4. extension 이벤트면 큐 지연·200건 상한·foreground 드레인 영향을 이 문서와 검증 시나리오에 반영한다.
