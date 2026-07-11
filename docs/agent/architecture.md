# Architecture

Read when: 새 파일을 어느 레이어에 둘지 모를 때, 레이어 간 의존성을 건드릴 때, UseCase / Repository / RepositoryImpl을 추가할 때.

Skip when: 수정 대상 파일과 레이어가 이미 명확할 때.

---

## 레이어 구조

GoldTime 메인 앱은 5개 레이어로 구성됩니다. 물리 모듈 분리는 없고, 폴더링으로 레이어를 표현합니다.

```
GoldTime/GoldTime/
│
├── App/            진입점 (GoldTimeApp — 루트 ViewModel 소유)
├── Core/           Apple Framework 래퍼 — ScreenTime, Auth, Notification, Ads, Persistence
├── Domain/         순수 Swift — Model, Repository 프로토콜, UseCase, Policy
├── Data/           Repository 구현체 (Core → Domain 매핑)
└── Presentation/   ViewModel + View (MVVM, @Observable)
```

### 의존 방향

```
Presentation ──→ Domain ←── Data ──→ Core
     App ──→ Presentation (진입점 — 루트 ViewModel 생성·소유)
```

- **Domain**은 아무것도 의존하지 않습니다(파일별 import 예외와 `ScreenTimeGroup` typealias
  유지 결정은 `Domain/CLAUDE.md`).
- **Core**는 Apple Framework만 의존합니다. **집행 비즈니스 로직(잠금·모니터링·리셋)의 실질
  위치는 Core(`SharedStore`/`ScreenTimeManager`)입니다** — extension 타겟과 파일 단위로
  공유해야 해서 static 기반이며, 이는 의도된 구조입니다(`decision-context.md` ADR).
- **Data**는 Domain 프로토콜 + Core 서비스를 의존합니다. RepositoryImpl은 Core로의 얇은
  pass-through가 정상입니다(로직을 여기 늘리지 않습니다).
- **Presentation**은 Domain UseCase / Repository 프로토콜 의존이 기본입니다. Core 직접 참조는
  `Presentation/CLAUDE.md`의 허용 경계(값 읽기·설정 키·UI 부수효과) 안에서만.
- **App**은 루트 ViewModel을 생성·소유만 합니다. 중앙 DI 컨테이너는 없습니다.

---

## 레이어별 규칙

> 각 레이어/타겟 폴더에는 `CLAUDE.md`가 co-locate되어, 그 폴더의 파일을 열면 해당 규칙이
> 자동으로 로드됩니다. 아래 표는 그 규칙들의 **통합 개요**입니다 — 코드가 진실이고, 함정은
> 가장 가까운 nested `CLAUDE.md`에 누적합니다.

### Domain — 가장 엄격

| 항목 | 규칙 |
|---|---|
| import | 기본 `Foundation`만. 파일별 예외 — `ManagedSettings`: `ShieldRepository.swift`·`ExtendGroupUseCase.swift`(Shield 토큰 타입), `FamilyControls`: `ManageGroupsUseCase.swift`(`FamilyActivitySelection`), `UIKit`: `AdRepository.swift`(광고 표시 anchor `UIViewController`). 예외 파일에서도 Apple 타입은 opaque 값으로 시그니처 통과만 — 해석·분기 금지 |
| Core 참조 | `ScreenTimeManager`, `AuthorizationService` 직접 참조 금지 |
| Core 참조 유지 결정 (ADR) | `Domain/Model/ScreenTimeGroup.swift`의 `typealias ScreenTimeGroup = SharedStore.ScreenTimeGroup`은 유지(분리하지 않음 — Codable 하위 호환·extension 파일 공유가 우선). `SharedStore.maxGroupCount` 같은 상수 참조도 허용. 배경: `decision-context.md` |
| 구현체 | Repository 프로토콜만 선언. 구현체(`Impl`)는 Domain에 없음 |
| UseCase 패턴 | `final class UseCase`, Repository를 생성자에서 `any RepositoryProtocol`로 주입 |
| 상태 관리 | `@Observable`, `@Published` 사용 금지. 순수 값 타입 / 참조 타입 |

### Core

| 항목 | 규칙 |
|---|---|
| import | Apple Framework 직접 import 허용 (`FamilyControls`, `DeviceActivity`, `ManagedSettings`, `UserNotifications`, `GoogleMobileAds`) |
| 의존 | 다른 레이어에 의존하지 않음 |
| 싱글톤 | `shared` 패턴 허용 (`AuthorizationService.shared`, `RewardedAdService.shared`) |
| @Observable | Data와 달리 Core 서비스는 `@Observable` 허용. `AuthorizationService`, `RewardedAdService`가 `@Observable`로 선언되어 Data/Presentation에서 바인딩 가능 |
| SharedStore | App Group UserDefaults 직접 읽기/쓰기 담당 |

### Data

| 항목 | 규칙 |
|---|---|
| 구현 | Domain Repository 프로토콜을 `final class XxxRepositoryImpl: XxxRepository`로 구현 |
| Core 의존 | Core 서비스를 생성자에서 주입받거나 싱글톤으로 사용 |
| 타입 매핑 | Core 타입 → Domain 타입 변환이 이 레이어의 책임. extension 또는 private 함수로 처리 |
| 상태 관리 | `@Observable` 사용 금지 |

타입 매핑 예시:
```swift
// ScreenTimeRepositoryImpl.swift 내부
private extension ScreenTimeManager.ExtensionSource {
    var domainType: ExtensionSource { ... }
}
```

### Presentation

| 항목 | 규칙 |
|---|---|
| ViewModel import | `Foundation`만. `import FamilyControls`는 `AppPickerSheet` 등 FamilyActivityPicker 직접 사용 화면에서만 예외. `import ManagedSettings`는 `LockOptionsViewModel`에서 그룹 토큰 타입 참조를 위해 예외 허용 |
| ViewModel 패턴 | `@MainActor @Observable final class XxxViewModel` |
| DI | UseCase를 생성자에서 `XxxUseCase? = nil`로 받음. nil이면 내부에서 `RepositoryImpl`을 생성하고 UseCase에 주입하여 기본 구현 생성 |
| Core 참조 금지 | `ScreenTimeManager`, `AuthorizationService` 직접 접근 금지 |
| Core 직접 참조 허용 경계 (ADR) | 집행 로직(`ScreenTimeManager`, 잠금/모니터링 상태 변경)은 UseCase로만. 값 읽기·사용자 설정 키·UI 부수효과는 직접 참조 허용 — `weekStartDay`(Settings/AppLifecycle), `suiteName`(`ContentView` `@AppStorage`), `max*` 상수(AppPicker/LockOptions), `drainPendingAnalyticsEvents()`(AppLifecycle), `ConsentService.shared`(Onboarding/Settings). 허용 목록은 `Presentation/CLAUDE.md`가 단일 출처 |
| View 패턴 | `@Bindable var viewModel: XxxViewModel` (소유는 GoldTimeApp 또는 상위 View) |
| 순수 struct VM | `HomeViewModel`, `StatsViewModel`처럼 계산만 하는 VM은 struct 허용 |

### App

| 항목 | 규칙 |
|---|---|
| DI | 중앙 컨테이너 없음 — ViewModel 생성자 기본값 주입(`? = nil` → 내부 기본 조립)이 공식 패턴. 과거 `AppDIContainer`는 실사용 없는 dead code라 2026-07 삭제(재도입 금지, `decision-context.md` ADR) |
| GoldTimeApp | 루트 ViewModel(AppLifecycle/Content/Settings)을 `@State`로 소유. `ContentView`에 `@Bindable` 또는 `let`으로 전달. 화면 지역 ViewModel은 해당 View가 `@State`로 직접 생성 |
| 로직 | 진입점 배선(Firebase configure, BGTask 등록) 외 비즈니스 로직 없음 |

---

## 새 파일을 어느 레이어에 둘지

| 추가할 것 | 레이어 | 경로 예시 |
|---|---|---|
| Apple framework 서비스 래퍼 (신규) | Core | `Core/{영역}/XxxService.swift` |
| 비즈니스 개체 타입 (struct/typealias) | Domain/Model | `Domain/Model/Xxx.swift` |
| 데이터 접근 계약 (protocol) | Domain/Repository | `Domain/Repository/XxxRepository.swift` |
| 비즈니스 로직 흐름 | Domain/UseCase | `Domain/UseCase/XxxUseCase.swift` |
| 비즈니스 규칙 (순수 판단 함수) | Domain/Policy | `Domain/Policy/XxxPolicy.swift` |
| Repository 구현체 | Data | `Data/XxxRepositoryImpl.swift` |
| 화면 상태 + 인터랙션 | Presentation | `Presentation/{화면}/XxxViewModel.swift` |
| SwiftUI 화면 | Presentation | `Presentation/{화면}/XxxView.swift` |
| 새 UseCase 배선 | Presentation | ViewModel 생성자에 `? = nil` 파라미터 추가 |

---

## 레이어 경계 위반 — 하지 말 것

```swift
// ❌ Presentation에서 Core 서비스 직접 접근
class SomeViewModel {
    func foo() { ScreenTimeManager.shared.syncDailyMonitoring(...) }
}

// ❌ Domain UseCase에서 @Observable 사용
@Observable
final class LoadDashboardUseCase { ... }

// ❌ Data에서 Presentation 패턴 혼용
@Observable
final class GroupRepositoryImpl { ... }

// ❌ Presentation에서 FamilyControls 직접 import (AppPickerSheet·LockOptionsViewModel 제외)
import FamilyControls  // in SomeOtherViewModel.swift

// ❌ Domain UseCase에서 Core 서비스 메서드 직접 호출
final class ManageGroupsUseCase {
    func foo() { ScreenTimeManager.shared.xxx() }  // Core 서비스 직접 참조
}
```

---

## Extension 타겟 구조

GoldTime은 메인 앱 외에 세 개의 Screen Time Extension 타겟을 포함합니다.

| 타겟 폴더 | 역할 |
|---|---|
| `DeviceActivityMonitorExtension/` | DeviceActivity interval/threshold callback에서 Shield 적용·해제, 일일 상태 정리 담당 |
| `ShieldConfigurationExtension/` | 시스템 Shield 화면에 표시할 문구와 버튼 구성 담당 |
| `ShieldActionExtension/` | Shield 화면 버튼 액션 처리 및 앱 복귀 요청 기록 담당 |

Extension은 메인 앱 API에 직접 의존하지 않습니다. `SharedStore` (App Group UserDefaults)를 통해 메인 앱과 상태를 공유하고, 알림으로 이벤트를 전달합니다. Extension 코드를 수정할 때는 App Group key와 Codable 저장 구조의 하위 호환을 반드시 유지합니다.

---

## UseCase / Repository 추가 패턴

새 기능이 필요할 때 순서:

1. **Domain/Repository**에 protocol 추가
2. **Domain/UseCase**에 UseCase class 추가 (Repository를 생성자 주입)
3. **Data**에 RepositoryImpl 추가 (Core 서비스 호출 + 타입 매핑)
4. **Presentation** ViewModel 생성자에 `XxxUseCase? = nil` 파라미터 추가 — nil이면 내부에서
   `XxxRepositoryImpl()`로 기본 조립(기존 no-arg 호출부·테스트가 안 깨진다), 테스트는 Fake 주입

---

## DI 흐름 요약

```
GoldTimeApp                              ← 루트 ViewModel @State 소유
  └─ ContentViewModel()                  ← no-arg 생성 (프로덕션 경로)
       └─ init(manageGroupsUseCase: ManageGroupsUseCase? = nil, ...)
            └─ nil이면 내부에서 기본 조립:
                 ManageGroupsUseCase(
                   groupRepository: GroupRepositoryImpl(),        ← Core/SharedStore 참조
                   screenTimeRepository: ScreenTimeRepositoryImpl() ← Core/ScreenTimeManager 참조
                 )

GoldTimeTests                            ← 테스트 경로
  └─ ContentViewModel(manageGroupsUseCase: ManageGroupsUseCase(
       groupRepository: FakeGroupRepository(), ...))              ← Fake 명시 주입
```

중앙 DI 컨테이너는 없습니다. ViewModel 생성자의 `? = nil` 기본값이 프로덕션 조립이고,
테스트만 명시 주입합니다. ViewModel이 UseCase 참조를, UseCase가 Repository 참조를 ARC로
유지합니다.
