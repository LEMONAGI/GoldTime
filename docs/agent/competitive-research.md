# Competitive Research

Read when: 기획이 모호하거나, 경쟁/유사 스크린타임 앱 참고가 필요하거나, 결정이 GoldTime다운지 판단해야 할 때.

Skip when: 코드 위치만 찾거나, 이미 정해진 작은 구현을 수행하거나, 순수 테스트/설정 변경만 할 때.

이 문서는 경쟁 앱을 따라 하기 위한 데이터베이스가 아니라, GoldTime다운 결정을 빠르게 내리기 위한 해석 문서입니다.

## GoldTime다운 판단 기준

모호한 기획은 아래 질문에 "예"라고 답할 수 있는 방향으로 결정합니다.

- 무의식적 사용을 의식적 선택으로 바꾸는가.
- 한도 초과 뒤 계속 쓰는 행동의 비용이 선명해지는가.
- 광고가 보상이 아니라 더 쓰기 위해 치르는 비용으로 느껴지는가.
- Shield 순간의 선택이 짧고 명확해지는가.
- 사용자를 수치심 주지 않고 선택 앞에 세우는가.
- 웃기지만 오글거리거나 밈에 기대지 않는가.
- iOS 기본 흐름과 HIG를 해치지 않는가.

GoldTime은 "앱 사용을 잘 분석해주는 앱"보다 "멈춘 자리에서 계산하게 만드는 앱"에 가깝습니다.

## 반복적으로 관찰되는 시장 패턴

### 생산성/포커스 운영체제

Opal, Jomo 계열은 스케줄, 세션, 리포트, 딥포커스, 루틴을 전면에 둡니다. 사용자는 생산성 관리 도구를 켜고, 앱은 장기적인 집중 상태를 관리합니다.

GoldTime 적용:

- 빌릴 것: 차단 대상 그룹화, 세션/한도 상태의 명료한 표시, 사용자가 직접 선택했다는 감각.
- 피할 것: 랭킹, 과한 리포트, 생산성 코칭, "더 나은 나"를 강조하는 웰니스 문법.
- 비틀 것: 장기 생산성보다 "지금 더 쓰려면 비용을 치른다"는 짧은 결제대 경험으로 바꿉니다.

### 사용 직전 마찰

one sec, ScreenZen 계열은 앱을 열기 직전에 호흡, 대기, 카운트다운, 짧은 질문으로 자동 행동을 끊습니다.

GoldTime 적용:

- 빌릴 것: 짧은 대기, 한 번 더 생각하게 만드는 문장, 지금 선택한다는 느낌.
- 피할 것: 긴 명상 흐름, 너무 다정한 코칭, 매번 같은 마찰로 지루해지는 구조.
- 비틀 것: "진정하세요"보다 "한도 끝났고, 더 쓰려면 계산하세요"에 가깝게 표현합니다.

### 가벼운 차단/단순 설정

ClearSpace 계열은 복잡한 분석보다 단순한 차단, 쉬운 설정, 적은 화면 수를 강조합니다.

GoldTime 적용:

- 빌릴 것: 설정 진입 장벽 낮추기, 대상 선택과 한도 설정의 간결함.
- 피할 것: 기능을 너무 줄여 GoldTime의 광고 비용 장치가 흐려지는 것.
- 비틀 것: 설정은 단순하게, 한도 초과 순간의 선택지는 GoldTime답게 선명하게 만듭니다.

### 규칙 자동 적용

Opal, Jomo, ScreenZen, Roots 계열은 사용자가 앱 그룹, 한도, 스케줄 같은 규칙을 저장하면 별도의 "모니터링 시작" 단계를 요구하기보다 규칙이 활성 상태가 되는 모델을 씁니다. 수동 액션은 보통 즉시 차단, 임시 break, strict mode, 문제 해결처럼 예외적인 동작에 가깝습니다.

GoldTime 적용:

- 빌릴 것: 유효한 그룹 설정이 곧 보호 규칙이라는 단순한 모델, 저장 즉시 적용되는 피드백, 문제 있는 그룹만 설정 필요로 남기는 방식.
- 피할 것: 시작/중지 버튼을 핵심 CTA처럼 두어 사용자가 보호를 켜야 한다는 부담을 만드는 것.
- 비틀 것: 일반적인 pause/break를 만들지 않고, Shield 순간의 1분/광고/그만쓰기 선택을 우선합니다. 전체 보호 해제는 사용자용 휴식 기능이 아니라 복구/개발용 초기화로 숨깁니다.

### 의도적 사용 점수화

Roots 계열은 사용 시간의 양뿐 아니라 질, 의도성, 좋은/나쁜 사용의 구분을 강조합니다.

GoldTime 적용:

- 빌릴 것: 사용자가 "참고 나간 선택"을 성과로 볼 수 있게 하는 피드백.
- 피할 것: 앱별 삶의 질 점수, 복잡한 분석, 사용자를 평가하는 듯한 언어.
- 비틀 것: 품질 점수보다 광고 회피, 참기 선택, 추가 사용 비용 같은 행동 결과를 보여줍니다.

### 강한 물리적 잠금

Brick 계열은 물리적 장치나 강한 잠금 절차로 우회를 어렵게 만듭니다.

GoldTime 적용:

- 빌릴 것: 차단이 실제로 무게감 있게 느껴져야 한다는 점.
- 피할 것: 하드웨어 의존, 완전 통제, 부모 통제처럼 느껴지는 흐름.
- 비틀 것: 우회 방지보다 "우회하려면 광고라는 비용을 치른다"는 심리적 장치를 강화합니다.

## 빌릴 것

- 앱 그룹, 한도, 차단 상태를 사용자가 즉시 이해하게 하는 단순한 구조.
- 유효한 규칙은 저장 즉시 자동 적용되는 모델.
- 자동 행동을 끊는 짧은 마찰.
- 지금 멈춘 선택을 성과로 기록하는 피드백.
- 사용자가 직접 설정했다는 감각.
- 반복 사용해도 피곤하지 않은 기본 iOS 패턴.

## 피할 것

- 경쟁 앱의 리포트, 랭킹, 챌린지, 코칭을 GoldTime의 핵심처럼 가져오는 것.
- 시작/중지 토글을 핵심 흐름으로 두어 보호를 쉽게 꺼도 되는 기능처럼 보이게 하는 것.
- 사용자를 중독자처럼 부르거나 수치심을 주는 문구.
- 광고 시청을 보상처럼 미화하는 흐름.
- 기획이 모호하다는 이유로 기능을 많이 붙이는 결정.
- HIG에서 벗어난 낯선 UI를 차별화처럼 포장하는 결정.

## GoldTime식으로 비틀 것

- "집중 세션"은 "한도 초과 뒤 비용을 치를지 말지 고르는 순간"으로 바꿉니다.
- "사용 리포트"는 "광고를 피한 횟수, 참고 나간 횟수, 광고로 산 추가 시간"으로 바꿉니다.
- "동기부여 문구"는 "사실 1개 + 짧은 찌름 + 선택지"로 바꿉니다.
- "차단 강도"는 "선택 비용의 선명함"으로 바꿉니다.
- "웰니스 코칭"은 "건조하고 직설적인 결제대 톤"으로 바꿉니다.
- "규칙 시작 버튼"은 "유효한 그룹 저장 즉시 적용"으로 바꿉니다.

## 모호한 결정 체크리스트

기획이 명확하지 않으면 아래 순서로 결정합니다.

1. 이 결정이 한도 초과 뒤의 선택 순간과 관련 있는지 확인합니다.
2. 관련 있으면 이 문서의 시장 패턴에서 가장 가까운 범주를 찾습니다.
3. 경쟁 앱이 해결한 사용자 심리를 적습니다.
4. 그 심리를 GoldTime의 비용감, 광고 비용, Shield 선택 경험으로 바꿉니다.
5. 결정이 너무 코칭/리포트/랭킹/감시 쪽으로 가면 범위를 줄입니다.
6. 문구나 화면 판단이 필요하면 `product-context.md`도 확인합니다.
7. UI 구현, 기본 컴포넌트, HIG 판단이 필요하면 `ui-design-system.md`도 확인합니다.
8. 제품 범위나 MVP 포함 여부가 필요하면 `decision-context.md`도 확인합니다.

경쟁 앱에서 관찰한 UI를 그대로 복제하지 않습니다. iOS 시스템 컴포넌트 위에서 GoldTime의 비용감과 선택 경험에 맞게 해석합니다.

## 최신 리서치 업데이트 규칙

- 먼저 이 문서로 판단합니다.
- 이 문서로 부족하거나 최신 정보가 중요한 경우에만 경쟁/유사 앱을 다시 조사합니다.
- 공식 웹사이트, App Store, Apple 공식 문서, 공개 도움말을 우선 출처로 봅니다.
- 새 리서치에서 재사용 가치가 있는 관찰을 얻으면 이 문서에 추가합니다.
- 추가할 때는 앱별 기능 목록보다 "관찰 -> GoldTime 적용점"을 우선합니다.
- 오래된 정보와 충돌하면 날짜와 출처를 남기고 판단을 갱신합니다.

재사용 가치가 있는 정보:

- 여러 앱에서 반복되는 UX 패턴.
- GoldTime의 기능/문구/대시보드 결정에 직접 도움이 되는 패턴.
- 기존 판단을 바꾸거나 더 선명하게 만드는 정보.
- Apple 정책, App Store 표현, Screen Time 관련 UX처럼 실무 리스크를 줄이는 정보.

## 리서치 업데이트 로그

### 2026-06-02

출처:

- Opal FAQ (Streaks / Focus Hours): https://opalapp.com/help/what-are-streaks-and-focus-hours
- Opal FAQ (Screen Time 리포트): https://opalapp.com/help/how-when-and-where-does-opal-report-your-screen-time
- Swift Charts RuleMark: https://developer.apple.com/documentation/charts/rulemark
- 차트 plan vs actual 점선 컨벤션: https://nastengraph.substack.com/p/how-to-visualize-plan-vs-actual

관찰:

- Opal은 연속 일수(Streak)와 "이번 주 일 평균 vs 지난주 일 평균" 벤치마크를 통계 전면에 둡니다. 절대 총량보다 추세/비교가 통계 UX의 핵심입니다.
- 차트에서 점선(dashed)은 "측정값"이 아니라 "기준/목표"를 뜻하는 관례입니다. 막대=실측, 점선=벤치마크로 분리하면 의미가 즉시 읽힙니다.
- 기존 스크린타임 앱의 흔한 약점은 "평균보다 N분 적음"이 *무엇 대비*인지(그날/그주/앱 전체) 라벨이 없어 모호하다는 점입니다.

GoldTime 적용점:

- 통계의 트렌드는 총 스크린타임이 아니라 "추가 사용"(한도 초과로 광고/1분으로 더 쓴 시간)에 대해 계산합니다. "N일/N주째 감소 중"은 웰니스 코칭이 아니라 비용이 줄고 있다는 행동 결과라서 GoldTime답습니다. 문구는 칭찬 없이 건조하게 둡니다(`product-context.md` Stats 톤).
- 추세는 엄격 연속 기준으로 계산합니다(직전 기간 대비 감소/증가, 같으면 끊김). 핵심 로직은 `UsageTrend.fromOrderedTotals`에 두고 단위 테스트로 고정합니다. 주간 추세는 합계가 아니라 주별 "하루 평균"으로 비교해, 일수가 덜 찬 진행 중인 주가 불리하게 잡히지 않게 합니다.
- 차트 평균 비교는 텍스트뿐 아니라 점선 `RuleMark`로 표기하고, 점선에 비교 기준 라벨(이번 달 평균/올해 평균)을 붙여 무엇 대비인지 모호하지 않게 합니다.
- 주간/월간은 별도 섹션 대신 segmented `Picker`로 한 카드에 묶어 화면을 단순하게 유지합니다(기본 iOS 패턴).
- 그룹별 사용량 분해는 `DailyStats`에 그룹 차원이 없어 데이터 모델/extension 변경이 필요하므로 통계 트렌드 작업과 분리합니다.

### 2026-05-17

출처:

- Opal: https://www.opal.so/
- Jomo: https://jomo.so/
- Jomo Help Center: https://help.jomo.so/en/article/what-is-a-rule-on-jomo-mseknq/
- one sec: https://one-sec.app/
- one sec Delayed Interventions: https://tutorials.one-sec.app/en/articles/3973762
- ScreenZen: https://www.screenzen.co/
- ScreenZen App Store: https://apps.apple.com/us/app/screenzen-screen-time-control/id1541027222
- ClearSpace: https://www.getclearspace.com/
- ClearSpace App Store: https://apps.apple.com/us/app/clearspace-reduce-screen-time/id1572515807
- Roots: https://www.getroots.com/
- Roots App Store: https://apps.apple.com/us/app/roots-screen-time-control/id6446800962
- Brick: https://getbrick.app/
- Apple Human Interface Guidelines: https://developer.apple.com/design/human-interface-guidelines/
- SwiftUI Documentation: https://developer.apple.com/documentation/swiftui/
- DeviceActivityCenter startMonitoring: https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/startmonitoring%28_%3Aduring%3Aevents%3A%29
- FamilyActivityPicker: https://developer.apple.com/documentation/familycontrols/familyactivitypicker

관찰:

- 시장은 생산성 운영체제, 사용 직전 마찰, 가벼운 차단, 의도적 사용 점수화, 강한 물리적 잠금으로 나뉩니다.
- GoldTime은 그중 "사용 직전 마찰"과 가장 가깝지만, 광고를 비용으로 쓰는 점이 차별점입니다.
- 경쟁 앱의 장기 리포트나 코칭보다 Shield 순간의 짧은 선택 경험이 GoldTime의 핵심에 더 맞습니다.
- 최신 유사 앱들은 앱 그룹/규칙 저장 후 별도 시작 버튼보다 자동 적용, 즉시 차단, 스케줄, break/pause, strict mode를 조합합니다.
- Apple Screen Time API는 앱이 `DeviceActivityCenter.startMonitoring`으로 activity와 event를 등록하는 구조이므로, GoldTime 내부에서는 그룹 저장 시 이 등록을 동기화하는 모델이 자연스럽습니다.

GoldTime 적용점:

- 대시보드는 총 사용 시간보다 광고 회피, 참고 나간 횟수, 광고로 산 추가 시간을 우선합니다.
- Shield와 Lock Options는 코칭보다 결제대 같은 선택 구조를 우선합니다.
- 경쟁 앱을 참고하더라도 기능을 늘리는 방향보다 선택 비용을 더 선명하게 만드는 방향을 택합니다.
- 모니터링 시작/중지는 사용자 핵심 흐름에서 제거하고, 유효한 그룹 설정을 자동 적용합니다.
- 일반 pause 기능은 두지 않습니다. 전체 보호 해제는 Screen Time 상태 꼬임을 풀기 위한 숨은 복구/개발용 초기화로만 둡니다.
