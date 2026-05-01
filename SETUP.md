# GoldTime — Xcode 설정 가이드

소스 파일은 모두 디스크에 작성됐지만, **Xcode 프로젝트에 타겟·Capability·App Group을 추가하는 작업은 Xcode UI에서 직접 해야 합니다** (pbxproj 수동 편집은 손상 위험이 큼).

아래 순서대로 진행해주세요. (Xcode 16 기준)

---

## 0. 사전 준비

- 실기기 + Apple Developer 계정 (개인 무료 계정도 OK).
- **Family Controls 는 시뮬레이터에서 동작하지 않음**. 실기기 배포 필수.

---

## 1. 메인 앱 타겟 설정

### 1-1. 신규 폴더/파일을 프로젝트에 추가
Project Navigator(왼쪽 사이드바)에서 **GoldTime 그룹** 우클릭 → **Add Files to "GoldTime"...** 로 다음을 추가:

- `GoldTime/Models/` (폴더 그대로 — "Create groups" 선택)
- `GoldTime/Services/`
- `GoldTime/Views/`

타겟은 **GoldTime** 만 체크.

### 1-2. Capabilities 추가
Project 선택 → **GoldTime 타겟** → **Signing & Capabilities** 탭:

1. **+ Capability** → **Family Controls** 추가
2. **+ Capability** → **App Groups** 추가
   - **+** 클릭하여 신규 그룹 생성: `group.com.goldtime.shared`
   - 체크박스 활성화
3. **+ Capability** → **Background Modes** 추가 (선택, 알림 처리 안정성용)
   - "Background fetch" 체크

### 1-3. Info.plist 키 추가
**Info** 탭 (또는 Info.plist):

| Key | Value |
|---|---|
| `NSFamilyControlsUsageDescription` | 스크린타임 한도 초과 시 선택한 앱을 잠그고, 시간 연장을 관리하기 위해 사용됩니다. |

알림 권한은 코드에서 `requestAuthorization(options:)` 으로 요청하므로 별도 plist 키 불필요 (단, iOS 사용자가 거절하면 알림 못 보냄).

---

## 2. DeviceActivityMonitorExtension 타겟 추가

1. **File → New → Target...**
2. **Device Activity Monitor Extension** 선택 → Next
3. **Product Name**: `DeviceActivityMonitorExtension`
4. **Embed in Application**: GoldTime
5. Activate scheme 다이얼로그 → **Cancel** (메인 앱 스킴 유지)
6. 자동으로 생성된 템플릿 파일(`DeviceActivityMonitorExtension.swift`)은 **삭제** (Move to Trash) — 우리가 작성한 파일을 사용.
7. Project Navigator → 새 익스텐션 그룹 우클릭 → **Add Files to ...** → 디스크의 `GoldTime/DeviceActivityMonitorExtension/DeviceActivityMonitorExtension.swift` 추가 (타겟: DeviceActivityMonitorExtension만 체크).
8. **공유 파일 추가**: `Models/SharedStore.swift` 를 익스텐션 타겟의 멤버십에 추가:
   - `SharedStore.swift` 클릭 → File Inspector → **Target Membership** → **DeviceActivityMonitorExtension** 체크.

### 2-1. 익스텐션 Capabilities
Target → DeviceActivityMonitorExtension → Signing & Capabilities:
- **+ Capability** → **Family Controls**
- **+ Capability** → **App Groups** → `group.com.goldtime.shared` 체크

---

## 3. ShieldConfigurationExtension 타겟 추가

1. **File → New → Target...** → **Shield Configuration Extension**
2. Product Name: `ShieldConfigurationExtension`
3. Embed in Application: GoldTime
4. 템플릿 swift 파일 삭제 → 디스크의 `GoldTime/ShieldConfigurationExtension/ShieldConfigurationExtension.swift` 추가 (타겟: ShieldConfigurationExtension).
5. Capabilities: **Family Controls**, **App Groups** (동일 그룹).

이 익스텐션은 `SharedStore` 를 사용하지 않으므로 추가 멤버십 불필요.

---

## 4. ShieldActionExtension 타겟 추가

1. **File → New → Target...** → **Shield Action Extension**
2. Product Name: `/ㄴ`
3. Embed in Application: GoldTime
4. 템플릿 swift 파일 삭제 → 디스크의 `GoldTime/ShieldActionExtension/ShieldActionExtension.swift` 추가.
5. Capabilities: **Family Controls**, **App Groups**.

---

## 5. ContentView.swift 정리 (선택)

`GoldTime/ContentView.swift` 는 Xcode 템플릿 잔존물입니다. `GoldTimeApp` 이 이제 `HomeView` 를 사용하므로 미사용 상태입니다. 그대로 두어도 되고, 삭제해도 됩니다 (`#Preview` 가 있는 채로 남겨두면 추후 참고용).

---

## 6. 빌드 & 실기기 테스트

1. iOS 실기기를 Mac 에 연결.
2. 실기기 선택 → **Run (⌘R)**.
3. 앱 실행 → "스크린타임 권한 허용하기" 탭 → 시스템 다이얼로그 → 허용.
4. **차단할 앱 / 카테고리** → "앱 선택하기" 탭 → 가급적 SNS 앱(인스타 등) 1–2개 + Social Networking 카테고리 선택.
5. 한도를 **1분**으로 설정 (테스트 편의) → "모니터링 시작".
6. 선택한 앱 1분간 사용 → 시스템 쉴드(GoldTime 커스텀 디자인) 자동 표시 확인.
7. 쉴드의 "GoldTime 가기" 탭 → 알림 도착 → 알림 탭 → GoldTime 진입 → **3-옵션 시트** 자동 표시 확인.
8. 각 옵션 동작 확인:
   - **딱 1분만요**: 60초 후 자동 재쉴드 + 카운터 1/5 → 5/5 → 6회째 비활성화.
   - **광고보고 더 할게요**: 10초 ProgressView → 15분 사용 가능 → 종료 시 재쉴드.
   - **잘 참았어요**: 시트 닫고 쉴드 유지.

---

## 7. 자주 발생하는 문제

### "권한 요청이 즉시 거절됨"
- Apple Developer 계정의 **Family Controls** capability 가 자동 부여되었는지 확인. 첫 시도 시 Xcode 가 자동으로 요청. 안 되면 Apple Developer 포털에서 App ID 의 Capabilities 확인.

### 쉴드가 안 뜸
- 한도(분)에 도달하기까지는 실제 그 시간만큼 선택 앱을 **포그라운드에서** 사용해야 함. 백그라운드 시간은 보통 카운트되지 않음.
- 시뮬레이터에서는 안 됨. 실기기 필수.

### 쉴드에서 커스텀 문구가 안 보이고 기본 문구가 뜸
- ShieldConfigurationExtension 타겟에 **Family Controls** capability가 빠졌거나, Embed in Application 단계에서 누락됨.
- 메인 앱 재설치 (오래된 익스텐션 캐시 정리).

### App Group UserDefaults 가 메인 앱에 안 보임
- 모든 타겟(메인 + 3개 익스텐션) 이 **동일한 App Group** (`group.com.goldtime.shared`) 에 속해있는지 확인.
- `SharedStore.swift` 가 모든 타겟의 Target Membership 에 포함됐는지 확인.

---

## 8. 추후 작업 (이번 범위 밖)

- AdMob 통합: `AdMockView` 자리에 `GADRewardedAd` 교체.
- 사용량 통계 화면 (`Item` SwiftData 재활용).
- 위젯 / 라이브 액티비티 (남은 시간 표시).
- App Store 배포 시 Family Controls Distribution entitlement 신청.
