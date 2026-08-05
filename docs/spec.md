# TrackPinch 제품 및 기술 명세

- 상태: Draft
- 마지막 갱신: 2026-08-05
- 대상 플랫폼: macOS 14 이상(잠정)
- 배포 방식: 서명 및 공증된 직접 배포 우선

## 1. 개요

TrackPinch는 설정한 modifier key를 누른 상태에서 트랙패드의 두 손가락 입력으로 현재 활성 윈도우의 크기를 조절하는 macOS 메뉴 막대 유틸리티다.

첫 번째 버전은 macOS 공개 API로 안정적으로 구현할 수 있는 `modifier + 두 손가락 방향 이동`을 사용한다. 두 손가락 사이의 가로·세로 간격을 직접 측정하는 axis-aware pinch는 공개 API의 전역 입력 제약이 있으므로 별도 기술 실험 후 결정한다.

## 2. 목표

- 마우스로 윈도우 모서리를 찾지 않고도 활성 윈도우의 폭과 높이를 연속적으로 조절한다.
- 수평, 수직, 대각선 입력을 하나의 일관된 제스처로 제공한다.
- 제스처가 시작된 윈도우를 세션이 끝날 때까지 안정적으로 유지한다.
- 제스처 사용 중 원래 앱이 함께 스크롤되지 않도록 입력을 소비한다.
- 공개 macOS API만 사용하는 안정적인 MVP를 먼저 제공한다.

## 3. 비목표

MVP에서는 다음 항목을 지원하지 않는다.

- 윈도우 이동, snap, tiling 또는 레이아웃 preset
- fullscreen 윈도우나 크기 변경이 불가능한 dialog/sheet 조절
- 세 손가락 이상을 사용하는 시스템 gesture 재정의
- private `MultitouchSupport` framework 또는 비공개 API 사용
- Mac App Store 배포 보장
- 트랙패드가 아닌 모든 pointing device의 명시적 지원

## 4. 핵심 사용자 경험

### 4.1 기본 조작

기본 modifier는 `Fn`이며 설정에서 변경할 수 있다.

| 입력 | 결과 |
| --- | --- |
| Fn + 두 손가락을 오른쪽으로 이동 | 윈도우 폭 증가 |
| Fn + 두 손가락을 왼쪽으로 이동 | 윈도우 폭 감소 |
| Fn + 두 손가락을 아래로 이동 | 윈도우 높이 증가 |
| Fn + 두 손가락을 위로 이동 | 윈도우 높이 감소 |
| Fn + 두 손가락을 대각선으로 이동 | 폭과 높이를 동시에 변경 |

입력 방향은 macOS의 자연스러운 스크롤 설정과 무관하게 손가락의 물리적인 이동 방향을 기준으로 한다.

### 4.2 Resize session

1. 사용자가 modifier를 누른 채 두 손가락을 움직인다.
2. 첫 유효 입력에서 현재 frontmost application의 focused window와 시작 frame을 저장한다.
3. 초기 이동량이 dead zone을 넘으면 수평, 수직 또는 대각선 mode를 결정한다.
4. 세션 동안 동일한 mode와 대상 윈도우를 유지한다.
5. modifier를 놓거나 physical gesture가 끝나면 즉시 세션을 종료한다.
6. 손을 뗀 뒤 발생하는 momentum scroll은 크기 변경에 사용하지 않는다.

### 4.3 축 판정

- 초기 누적 이동량 8 pt까지는 dead zone으로 처리한다.
- `abs(x) >= 1.5 * abs(y)`이면 수평 mode로 고정한다.
- `abs(y) >= 1.5 * abs(x)`이면 수직 mode로 고정한다.
- 그 외에는 대각선 mode로 고정한다.
- 수평 mode에서는 Y delta를, 수직 mode에서는 X delta를 무시한다.
- 대각선 mode에서는 X와 Y delta를 각각 폭과 높이에 적용한다.

수치와 비율은 실기기 사용성 테스트 후 조정할 수 있지만, 세션 도중 mode가 바뀌지는 않는다.

### 4.4 Resize anchor

MVP에서는 윈도우의 좌측 상단 위치를 고정하고 우측 하단 모서리를 움직이는 것처럼 크기를 변경한다.

- 오른쪽/아래 입력은 확장이다.
- 왼쪽/위 입력은 축소다.
- 크기 변경 뒤에도 현재 display의 visible frame 안에 최소 조작 가능 영역이 남도록 제한한다.
- 앱이 자체적으로 강제하는 최소·최대 크기 제한을 존중한다.

## 5. 기능 요구사항

### FR-1. 메뉴 막대 앱

- Dock icon 없이 메뉴 막대에서 실행한다.
- 메뉴에서 TrackPinch 활성화 여부, modifier, sensitivity 및 로그인 시 실행 여부를 설정할 수 있다.
- Accessibility 권한 상태와 입력 monitor 상태를 확인할 수 있다.
- 앱 종료 기능을 제공한다.

### FR-2. Modifier 설정

- 기본값은 Fn이다.
- Fn, Control, Option, Command 및 modifier 조합을 설정할 수 있어야 한다.
- Globe/Fn의 시스템 동작과 충돌할 수 있음을 설정 화면에서 안내한다.
- 설정한 modifier가 정확히 눌린 경우에만 resize session을 시작한다.

### FR-3. 전역 트랙패드 입력

- `CGEventTap`으로 정밀 scroll event와 modifier flag를 확인한다.
- TrackPinch가 비활성화돼 있거나 modifier가 일치하지 않으면 event를 수정하지 않는다.
- 설정한 modifier와 일치하는 정밀 scroll event는 첫 event부터 원래 대상 앱으로 전달하지 않는다.
- 대상 window가 지원되지 않더라도 한 gesture 도중 일부 event만 원래 앱으로 전달하지 않는다.
- event tap callback에서는 최소한의 계산만 수행하고 AX 변경은 별도 실행 경로에서 처리한다.
- timeout 또는 user input으로 event tap이 비활성화되면 재활성화를 시도하고 상태를 UI에 반영한다.

### FR-4. 대상 윈도우 선택

- 제스처 시작 시 `NSWorkspace.shared.frontmostApplication`으로 대상 process를 선택한다.
- Accessibility hierarchy에서 `kAXFocusedWindowAttribute`를 우선 사용한다.
- focused window가 없으면 `kAXMainWindowAttribute`를 fallback으로 사용한다.
- TrackPinch 자체 설정 window나 panel은 대상으로 선택하지 않는다.
- 세션 도중 focus가 바뀌어도 처음 선택한 윈도우를 유지한다.

### FR-5. 윈도우 크기 변경

- 시작 시 `kAXPositionAttribute`와 `kAXSizeAttribute`를 읽는다.
- `AXUIElementIsAttributeSettable`로 size 변경 가능 여부를 확인한다.
- 변경 가능한 일반 윈도우에 `AXUIElementSetAttributeValue`로 새 size를 적용한다.
- top-left anchor를 유지하는 MVP에서는 position을 불필요하게 다시 쓰지 않는다.
- 입력 event를 coalesce하고 기본 최대 60 Hz로 AX update를 제한한다.
- 실패한 AX 호출은 crash 없이 세션을 종료하고 진단 가능한 error를 기록한다.

### FR-6. 크기 제한

- TrackPinch의 안전 하한은 폭 160 pt, 높이 120 pt다.
- 대상 앱이 더 큰 최소 크기를 강제하면 앱의 결과를 그대로 수용한다.
- 시작 윈도우가 위치한 display를 기준 display로 사용한다.
- resize 후 최소 80 x 40 pt 영역이 해당 display의 visible frame 안에 남아야 한다.

### FR-7. 설정 저장

다음 설정을 `UserDefaults`에 저장한다.

- TrackPinch 활성화 여부
- modifier 조합
- resize sensitivity
- 수평/수직 방향 반전 여부
- 로그인 시 실행 여부

## 6. 권한과 온보딩

### 6.1 Accessibility

다른 앱의 focused window를 조회하고 크기를 변경하려면 Accessibility 권한이 필요하다.

- 최초 실행 시 기능이 필요한 이유를 먼저 설명한다.
- `AXIsProcessTrustedWithOptions`로 권한 상태를 확인하고 시스템 prompt를 요청한다.
- 권한이 없을 때 resize 기능을 시작하지 않는다.
- 사용자가 System Settings에서 권한을 변경한 뒤 앱 재시작 없이 상태를 다시 확인할 수 있어야 한다.

### 6.2 Input monitoring

입력 event tap 생성 가능 여부를 별도로 확인한다. 직접 배포 MVP에서는 Accessibility 권한이 입력 listening에도 사용될 수 있지만, 서명된 실제 build에서 TCC 동작을 검증하고 필요한 경우 Input Monitoring 안내를 추가한다.

### 6.3 불필요한 권한

- Screen Recording 권한은 요청하지 않는다.
- 키 입력 내용이나 사용자 gesture 기록을 저장하거나 외부로 전송하지 않는다.

## 7. 기술 구조

SwiftUI는 설정과 상태 표현을 담당하고, AppKit/Core Graphics/Application Services는 전역 입력과 윈도우 제어만 담당한다.

```text
CGEventTap
  -> InputMonitor
  -> GestureClassifier
  -> ResizeSession
  -> WindowController (AXUIElement)
  -> focused window size

MenuBarExtra / Settings
  -> SettingsStore
  -> PermissionManager
  -> InputMonitor configuration
```

### 7.1 주요 component

#### `InputMonitor`

- event tap 생성, run loop 연결 및 lifecycle 관리
- scroll delta, gesture phase, momentum phase, modifier 추출
- 활성 세션에서 원래 scroll event 소비

#### `GestureClassifier`

- dead zone 적용
- 수평, 수직, 대각선 mode 판정
- 자연스러운 스크롤 설정을 보정한 물리적 손가락 방향 생성

#### `ResizeSession`

- 대상 window와 시작 frame snapshot
- 누적 delta를 새 size로 변환
- sensitivity, 방향 반전, clamp 적용
- session begin/update/end 상태 관리

#### `WindowController`

- frontmost application 및 focused window 조회
- AX attribute 읽기, 쓰기 가능 여부 확인 및 size 변경
- 지원하지 않는 window와 AX error 처리

#### `PermissionManager`

- Accessibility 및 event listening 상태 확인
- 온보딩과 설정 화면에 현재 상태 제공

#### `SettingsStore`

- 사용자 설정의 단일 source of truth
- SwiftUI UI와 입력 subsystem 사이의 명시적 설정 전달

## 8. 성능 및 안정성 요구사항

- gesture 시작 후 첫 크기 변화까지 체감 가능한 지연이 없어야 한다.
- AX update는 기본적으로 최대 60 Hz로 coalesce한다.
- event tap callback을 block하거나 그 안에서 AX messaging을 수행하지 않는다.
- `tapDisabledByTimeout`과 `tapDisabledByUserInput`을 처리한다.
- modifier release 또는 gesture cancel 시 남은 update를 폐기한다.
- momentum event 때문에 윈도우가 계속 변하지 않아야 한다.
- 대상 앱이 응답하지 않더라도 TrackPinch 메뉴와 입력 monitor가 함께 멈추지 않아야 한다.

## 9. 오류 처리

| 상황 | 동작 |
| --- | --- |
| Accessibility 권한 없음 | 세션 시작 안 함, 메뉴에서 권한 안내 |
| focused/main window 없음 | 해당 gesture를 소비하고 세션 생성 안 함 |
| size attribute가 settable하지 않음 | 해당 gesture를 소비하고 세션 종료 |
| AX API timeout/error | 세션 종료, error log 기록 |
| event tap 비활성화 | 재활성화 시도, 실패 시 기능 상태 표시 |
| modifier를 도중에 놓음 | 즉시 세션 종료, 이후 scroll 통과 |
| 대상 window가 사라짐 | 세션 종료, 참조 폐기 |

## 10. MVP 완료 조건

- Safari, Finder, Terminal, Notes, Xcode 및 Chromium 기반 앱의 일반 window에서 동작한다.
- modifier를 누르지 않은 일반 scroll은 기존과 동일하게 동작한다.
- modifier를 누르고 수평으로 움직이면 폭만 변경된다.
- modifier를 누르고 수직으로 움직이면 높이만 변경된다.
- 대각선으로 움직이면 폭과 높이가 동시에 변경된다.
- resize 중 대상 앱의 content가 함께 scroll되지 않는다.
- 손을 떼거나 modifier를 놓은 뒤 momentum으로 크기가 더 변하지 않는다.
- 다중 display 환경에서 대상 window를 다른 display로 순간 이동시키지 않는다.
- 크기 변경 불가능한 window와 fullscreen window에서 crash하지 않는다.
- 권한 거부, 권한 회수 및 event tap 재활성화 흐름을 처리한다.

## 11. QA matrix

### Window 종류

- 일반 document window
- 최소 크기가 지정된 window
- 복수 window를 가진 앱
- dialog, sheet, panel
- fullscreen 및 macOS tiled window
- minimized 또는 닫히는 중인 window

### 입력 환경

- 내장 MacBook trackpad
- Magic Trackpad
- 자연스러운 스크롤 on/off
- 빠른 flick와 느린 이동
- gesture 중 modifier release
- gesture 중 대상 앱 종료

### 화면 환경

- 단일 display
- 좌우 및 상하로 배치한 복수 display
- 서로 다른 display scale
- menu bar와 Dock 위치 변경

## 12. Axis-aware pinch 기술 실험

두 손가락을 같은 방향으로 이동하는 대신 실제 손가락 사이의 X/Y 간격으로 폭과 높이를 변경하는 기능은 MVP 이후 검토한다.

### 실험안

1. modifier down 시 대상 focused window를 먼저 snapshot한다.
2. cursor가 있는 display 위에 투명한 non-activating `NSPanel`을 표시한다.
3. panel의 custom `NSView`에서 touch event를 허용한다.
4. 두 `NSTouch`의 identity와 `normalizedPosition`을 추적한다.
5. X 간격 변화는 폭, Y 간격 변화는 높이에 적용한다.
6. modifier up 시 panel을 제거하고 원래 앱의 focus가 유지됐는지 확인한다.

### 통과 조건

- 원래 앱의 focus와 menu bar가 바뀌지 않는다.
- 두 손가락 touch sequence를 시작부터 끝까지 안정적으로 받는다.
- 원래 앱의 zoom, scroll 또는 gesture가 동시에 실행되지 않는다.
- 복수 display와 Space에서 보이지 않는 입력 차단 영역을 만들지 않는다.
- private framework 없이 서명 및 공증이 가능하다.

하나라도 충족하지 못하면 v1에서는 axis-aware pinch를 제공하지 않는다. private multitouch API는 유지보수성과 배포 위험 때문에 채택하지 않는다.

## 13. 후속 후보

- 실제 axis-aware pinch
- cursor 아래 window를 대상으로 선택하는 mode
- 중앙 기준 대칭 resize 또는 cursor 위치 기반 anchor
- resize 중 현재 크기를 표시하는 작은 HUD
- window 이동 및 snap gesture
- 앱별 sensitivity와 제외 목록
- 키보드 shortcut을 이용한 정확한 크기 입력

## 14. 참고 자료

- [Apple - Handling Trackpad Events](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/HandlingTouchEvents/HandlingTouchEvents.html)
- [Apple - NSEvent global monitor](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents%28matching%3Ahandler%3A%29)
- [Apple - NSEvent magnification](https://developer.apple.com/documentation/appkit/nsevent/magnification)
- [Apple - CGEventTapCreate](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate%28tap%3Aplace%3Aoptions%3Aeventsofinterest%3Acallback%3Auserinfo%3A%29)
- [Apple - AXUIElement](https://developer.apple.com/documentation/applicationservices/axuielement_h)
- [Apple - Fn event flag](https://developer.apple.com/documentation/coregraphics/cgeventflags/masksecondaryfn)
- [Apple - App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
