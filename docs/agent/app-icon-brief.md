# App Icon Brief

Read when: 앱 아이콘을 새로 그리거나, 이미지 생성 프롬프트를 만들거나, AppIcon light/dark/tinted 변형의 방향을 정할 때.

Skip when: 앱 내부 UI, Screen Time 런타임, 광고 로딩, project config만 바꿀 때.

이 문서는 GoldTime의 현재 제품 컨셉에 맞는 앱 아이콘을 그리기 위한 기준입니다. 실제 AppIcon 파일은 `GoldTime/GoldTime/Assets.xcassets/AppIcon.appiconset/`에 둡니다.

## 핵심 아이디어

GoldTime 아이콘은 "시간이 금이다"를 말 그대로 보여주되, 웰니스 앱처럼 착하거나 코인 앱처럼 탐욕스럽게 보이면 안 됩니다.

한 문장 브리프:

```text
어두운 화면 위에 놓인 금색 시간 토큰. 더 쓰려면 계산해야 한다는 느낌.
```

아이콘이 전달해야 하는 감정:

- 금색이지만 고급스러운 보상보다 "비용"에 가깝습니다.
- 시간 관리 앱이지만 명상, 휴식, 자기계발처럼 보이지 않습니다.
- 광고 앱처럼 보이지 않습니다. 광고는 제품의 농담과 비용 장치이지, 아이콘의 주인공이 아닙니다.
- 적대적 조력자 톤이 느껴지되, 협박이나 처벌처럼 보이지 않습니다.

## 추천 방향

### 1안: Gold Time Token

가장 추천하는 방향입니다.

구성:

- 배경: 거의 검정에 가까운 따뜻한 charcoal.
- 중심 오브젝트: 두꺼운 금색 원형 토큰.
- 토큰 내부: 시계 눈금 2-4개와 짧은 시침/분침.
- 하단 또는 우하단: 아주 작은 잠금/Shield 암시. 자물쇠를 직접 크게 넣기보다 토큰 일부가 막힌 듯한 형태가 좋습니다.

의미:

- 금색 토큰은 "더 쓰기 위해 치르는 비용"입니다.
- 시계는 앱의 시간 제한 맥락을 즉시 말합니다.
- 어두운 배경은 Shield에 걸린 순간의 정지감을 줍니다.

그릴 때:

- 토큰은 정중앙보다 아주 살짝 위에 둡니다.
- 시침은 10시 10분 같은 광고 시계 느낌보다 11시 55분, 12시 직전처럼 한도에 닿은 느낌이 좋습니다.
- 원형 토큰 외곽은 너무 얇지 않게, 작은 크기에서도 한 덩어리로 보여야 합니다.

### 2안: Paid Minute

대안 방향입니다. 1분 연장 기능을 더 강하게 보여주고 싶을 때 사용합니다.

구성:

- 배경: charcoal 또는 아주 어두운 gold-brown.
- 중심 오브젝트: 금색 원형 타이머.
- 내부 형태: 숫자 `1`처럼 보일 수 있는 세로 막대와 작은 시계 핸드의 결합.
- 주변: 토큰 테두리에 짧은 결제 게이트 같은 홈 2-3개.

주의:

- 실제 숫자 텍스트를 넣지 않습니다. 작은 앱 아이콘에서는 글자가 깨지고, 특정 기능 하나로 앱이 좁아 보입니다.
- "1분 무료"처럼 보이면 안 됩니다. 무료 보상보다 제한된 비용 선택에 가깝게 그립니다.

### 3안: Toll Shield

Shield 경험을 더 강조해야 할 때의 보조 방향입니다.

구성:

- 배경: 어두운 charcoal.
- 중심 오브젝트: 금색 Shield 실루엣.
- Shield 내부: 단순한 시계 핸드 또는 토큰 원.
- 하단: 얇은 차단선 또는 문턱 형태.

주의:

- 보안 앱, VPN, 백신 앱처럼 보이기 쉽습니다.
- Shield는 Apple Screen Time 맥락의 결과이지 제품의 전부가 아니므로, 1안보다 우선하지 않습니다.

## 시각 스타일

권장 스타일:

- 단순한 3D 느낌의 금속 토큰.
- 부드러운 bevel과 명확한 하이라이트.
- 아이콘 전체를 채우는 큰 실루엣.
- 작은 크기에서도 구분되는 2-3개의 주요 형태.
- iOS 기본 앱 아이콘과 나란히 있어도 과하게 튀지 않는 정돈된 표면.

피할 스타일:

- 텍스트, 앱 이름, `GT`, `GoldTime` 로고타입.
- 지폐, 달러 기호, 동전 더미, 보석, 왕관.
- 모래시계, 잎, 산, 명상, 불꽃, 번개.
- 광고 재생 버튼, 티켓, 쿠폰, 선물 상자.
- 과한 캐릭터, 표정, 밈 스타일.
- 너무 얇은 선, 복잡한 숫자 눈금, 작은 문구.
- 순수 노란색 배경 하나만 쓰는 단색 아이콘.

## 색상 기준

기본 팔레트:

- Background: warm charcoal, 거의 검정.
- Main gold: 현재 `AccentColor` 계열의 밝은 금색.
- Deep gold: main gold의 그림자/테두리용 진한 금색.
- Highlight: 거의 흰색에 가까운 따뜻한 금색.

현재 에셋 기준:

- `AccentColor`는 밝은 gold 계열입니다.
- `gray100`은 어두운 배경 계열입니다.
- 새 색을 앱 UI에 재사용해야 하면 `ui-design-system.md`의 Asset Color 규칙을 따릅니다.
- 아이콘 이미지 안에서만 쓰는 색은 렌더링된 PNG 내부 색상으로 관리해도 됩니다.

대비:

- 작은 홈 화면 크기에서도 금색 중심 오브젝트가 배경과 분리되어야 합니다.
- dark variant는 배경을 더 어둡게 하고 하이라이트를 줄입니다.
- tinted variant는 형태가 단색 마스크로 읽혀야 하므로, 내부 디테일 없이도 토큰/시계 실루엣이 남아야 합니다.

## iOS AppIcon 변형

현재 AppIcon 세트는 1024x1024 universal 이미지 3개를 받습니다.

- Default/light: 주 아이콘. charcoal 배경 + gold token.
- Dark: 더 어두운 배경 + 낮은 반사광. gold는 유지하되 번쩍임을 줄입니다.
- Tinted: iOS 틴트 적용을 견디는 단순 실루엣. 배경과 중심 형태가 명확히 분리되는 마스크처럼 설계합니다.

파일명은 실제 추가 시 명확하게 둡니다.

```text
AppIcon-Default.png
AppIcon-Dark.png
AppIcon-Tinted.png
```

## 이미지 생성 프롬프트 초안

영문 프롬프트:

```text
iOS app icon, warm charcoal rounded-square background, centered gold coin shaped like a time token, subtle clock hands inside the coin showing almost midnight, thick simple silhouette, soft metallic bevel, restrained premium gold highlights, small hint of a lock gate integrated into the lower edge of the coin, no text, no letters, no dollar sign, no character, no advertisement symbol, clean Apple-style app icon, readable at small size, 1024x1024
```

한국어 프롬프트:

```text
iOS 앱 아이콘, 따뜻한 차콜색 배경, 중앙에 금색 시간 토큰 모양의 원형 코인, 코인 내부에는 자정 직전처럼 보이는 단순한 시계 바늘, 두껍고 단순한 실루엣, 절제된 금속 bevel과 하이라이트, 코인 아래쪽에 아주 작게 잠금 게이트 느낌을 통합, 텍스트 없음, 글자 없음, 달러 기호 없음, 캐릭터 없음, 광고 상징 없음, 작은 크기에서도 읽히는 Apple 스타일 앱 아이콘, 1024x1024
```

네거티브 프롬프트:

```text
text, letters, logo type, dollar sign, coin pile, gift box, play button, coupon, hourglass, leaf, meditation, mascot, face, meme, complex tick marks, thin lines, busy background, pure yellow flat background
```

## 검토 체크리스트

시안 검토 시 다음을 확인합니다.

- 홈 화면 60pt 안에서도 "금색 시간 토큰"으로 보이는가.
- GoldTime의 비용감이 느껴지고, 보상/투자/쿠폰 앱처럼 보이지 않는가.
- 광고 상징이 아이콘의 주인공이 되지 않았는가.
- 텍스트 없이 앱 컨셉이 전달되는가.
- light/dark/tinted에서 같은 실루엣으로 인식되는가.
- App Store에서 과장된 수익 앱, 카지노 앱, 보안 앱처럼 오해되지 않는가.
- iOS 기본 앱 아이콘들 사이에서 너무 장난스럽거나 너무 무겁지 않은가.

## 완료 기준

아이콘 작업은 다음 상태면 완료로 봅니다.

- 1024x1024 PNG 3종이 AppIcon 세트에 연결되어 있습니다.
- Xcode asset catalog에서 누락 경고가 없습니다.
- 홈 화면 작은 크기와 App Store 큰 크기 양쪽에서 식별 가능합니다.
- tinted 상태에서도 중심 실루엣이 무너지지 않습니다.
- 최종 시안이 이 문서의 추천 방향 중 하나에 명확히 속합니다.
