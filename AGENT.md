# AGENT.md

This file provides guidance to AI coding agents when working with code in this repository.
Keep this file synchronized with `CLAUDE.md`.

## App Concept

**GoldTime** — "시간이 금이다". 스크린타임을 초과하면 광고를 봐야만 계속 사용할 수 있는 앱.
앱이 노골적으로 "나 너한테 돈 벌고 싶어"라고 말하는 **적대적 조력자** 포지션.

```
앱의 목표: 광고 많이 보여주기 → 돈 벌기
유저의 목표: 광고 최대한 안 보기 → 스크린타임 줄이기
→ 두 목표가 완전히 일치. 유저가 이길수록 건강해짐.
```

- **타겟:** iOS 26.0+
- **Bundle ID:** `com.goldtime.app`
- **컬러:** 골드(#F5C518), 딥블랙(#1A1A1A), 화이트
- **톤앤매너:** 냉소적이지만 결국 유저 편 ("오늘 저한테 ₩0 벌어줬어요 👑")

**Critical constraint:** Family Controls와 Shield는 **실제 기기 전용**. 시뮬레이터에서는 빌드만 가능.

## Build & Run

Open `GoldTime/GoldTime.xcodeproj` in Xcode. Select a real device and run.

- **Build via MCP:** `mcp__xcode__BuildProject`
- **Scheme:** `GoldTime`
- **Tests:** 현재 scaffolding만 존재, 미구현

## Architecture

MVVM + Service layer. 모든 타겟 간 상태는 App Group UserDefaults(`SharedStore`)로 공유.

### Targets (5 total)
1. **GoldTime** — Main app (SwiftUI)
2. **DeviceActivityMonitorExtension** — 스크린타임 임계값 이벤트 수신 → Shield 트리거
3. **ShieldConfigurationExtension** — 잠금 화면 UI 커스텀 (랜덤 헤더 멘트, 버튼 3개)
4. **ShieldActionExtension** — Shield 버튼 탭 처리 → 앱 재진입 알림 발송
5. **GoldTimeTests / GoldTimeUITests** — 미구현 scaffolding

### Shared State: `SharedStore.swift`
App Group(`group.com.goldtime.shared`) 기반. 전 타겟 공유 상태:
- 선택된 앱/카테고리, 일일 한도
- Shield 상태, 오버라이드 시간
- 1분 연장 카운터, 광고 시청 횟수(통계용)

### Services
- `ScreenTimeManager` — DeviceActivityCenter & ManagedSettingsStore 오케스트레이션; 모니터링 생명주기, Shield 적용/해제, 오버라이드 스케줄링
- `AuthorizationService` (@Observable singleton) — FamilyControls 권한 요청
- `NotificationService` — Shield에서 앱으로 복귀시키는 로컬 알림

### Screens
| 화면 | 역할 |
|------|------|
| `OnboardingView` | FamilyControls 권한 요청, 앱 선택, 일일 한도 설정 |
| `HomeView` (대시보드) | 오늘 점수("₩0 벌어줬어요"), 통계 카드, 7일 그래프 |
| `LockOptionsView` | Shield 진입 시 3-버튼 모달 |
| `AdMockView` | 광고 시청 화면 (현재 mock, AdMob으로 교체 예정) |
| 통계 화면 | 사용 전/후 비교, 절약 시간, 광고 헌납 금액 |
| 설정 화면 | 앱/한도/1분 연장 횟수/광고 단가 변경 |

## Shield 잠금 화면 UX

**헤더 멘트 (랜덤):**
```swift
let shieldMessages = [
    "또 왔어요?",
    "오늘 벌써 \(count)번째예요. 알고 있죠?",
    "광고 보고 더 할 거예요? 진심으로요?",
    "시간이 금이라는 거 알죠?",
    "의지력 테스트 중이에요.",
    "저는 기다릴게요. 당신이 결정하세요."
]
```

**버튼 3개:**
| 버튼 | 동작 |
|------|------|
| "딱 1분만요... 진짜로" | 광고 없이 1분 연장 (기본 3회/일 제한) |
| "광고 보고 더 할게요 🥲" | AdMob Rewarded Ad → 15분 연장 |
| "...잘 참았어요" | 잠금 유지 |

## Key Frameworks

| Framework | Use |
|-----------|-----|
| FamilyControls | 권한 획득, 앱/카테고리 선택 |
| DeviceActivity | 사용 시간 모니터링, 임계값 이벤트 |
| ManagedSettings | Shield 적용 |
| ManagedSettingsUI | Shield UI 커스텀 |
| SwiftUI | 전체 UI |
| SwiftData | 로컬 영속성 (현재 minimal) |
| UserNotifications | 익스텐션 → 앱 복귀 알림 |
| Google AdMob | Rewarded Ad (보상형 광고) — 현재 mock, 출시 전 교체 |

**AdMob:** 테스트 Ad Unit ID `ca-app-pub-3940256099942544/1712485313`. 광고 완료 콜백 시 AppGroup UserDefaults에 UUID 토큰 저장.

외부 의존성 없음 (현재). AdMob 통합 시 SPM 또는 CocoaPods 추가 예정.

## Unlock Mechanics

1. **1분 연장** — Shield 해제 1분, 기본 3회/일 제한(`oneMinuteCount`), DeviceActivity로 자동 재잠금
2. **광고 시청** — AdMob Rewarded Ad 완료 → 15분 해제
3. **잘 참았어요** — 잠금 유지

일일 카운터는 자정에 DeviceActivity interval 경계로 리셋.
