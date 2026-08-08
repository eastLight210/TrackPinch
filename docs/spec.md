# TrackPinch 제품 및 기술 명세

- 상태: `v0.1.0-alpha.1` experimental prerelease, signed manual QA 진행 중
- 마지막 갱신: 2026-08-08
- 최소 배포 대상: macOS 14.0
- 제품 bundle identifier: `dev.badgerworks.trackpinch`
- 배포 방식: Developer ID로 서명하고 공증한 직접 배포
- App Sandbox: 사용하지 않음

`v0.1.0-alpha.1` DMG는 사용성 검증을 위한 예외적인 ad hoc signed,
unnotarized preview다. 정식 release gate와 배포 방식은 아래 Developer ID,
notarization, stapling 요구사항을 그대로 따른다.

## 1. 개요

TrackPinch는 설정한 modifier key를 누른 상태에서 트랙패드의 두 손가락 입력으로 현재 활성 윈도우의 크기를 조절하는 macOS 메뉴 막대 유틸리티다.

MVP는 공개 API가 제공하는 precision scroll event를 사용한다. 내장 트랙패드와 Magic Trackpad가 주 대상이지만, 공개 event만으로 입력 장치를 확실하게 구별할 수 없으므로 Magic Mouse 같은 다른 precision scrolling device에서도 동작할 수 있다.

두 손가락 사이의 실제 X/Y 간격을 측정하는 axis-aware pinch는 MVP 범위가 아니다. 관련 가설과 실험 조건은 [Axis-aware pinch spike](./spikes/axis-aware-pinch.md)에서 별도로 관리한다.

## 2. 결정 사항

MVP 구현자는 다음 결정을 변경하지 않는다. 변경이 필요하면 이 문서를 먼저 개정한다.

- 입력은 `modifier + phased precision scroll`이다.
- 기본 modifier는 Control+Option+Command이며 사용자가 변경할 수 있다.
- 첫 event를 소비한 gesture는 physical phase와 연결된 momentum이 끝날 때까지 TrackPinch가 소유한다.
- 윈도우 크기만 변경하고 `kAXPositionAttribute`는 쓰지 않는다.
- 비공개 multitouch API를 사용하지 않는다.
- MVP는 unsandboxed Developer ID build로 직접 배포한다.
- macOS 14.0 이상을 지원한다.
- full implementation 전에 서명된 capability probe로 TCC와 event suppression을 검증한다.

## 3. 목표

- 마우스로 윈도우 모서리를 찾지 않고 활성 윈도우의 폭과 높이를 연속적으로 조절한다.
- 수평, 수직, 대각선 입력을 하나의 일관된 gesture로 제공한다.
- gesture가 시작된 윈도우를 capture가 끝날 때까지 유지한다.
- TrackPinch가 소유한 gesture의 일부 event가 원래 앱으로 새지 않도록 한다.
- 느리거나 응답하지 않는 대상 앱이 입력 tap이나 메뉴 UI를 block하지 않도록 한다.
- 권한과 event tap 상태를 사용자가 구분해서 확인할 수 있게 한다.

## 4. 비목표

MVP에서는 다음 항목을 지원하지 않는다.

- 윈도우 이동, snap, tiling 또는 layout preset
- fullscreen, tiled, sheet, panel의 크기 변경 보장
- raw `NSTouch` 기반 axis-aware pinch
- 특정 hardware가 트랙패드인지 판별하는 private API
- Mac App Store 배포
- 윈도우를 화면 안으로 옮기거나 position을 교정하는 기능
- scroll phase가 없는 legacy mouse wheel로 resize session 시작

## 5. Phase 0 capability gate

프로덕션 구조를 구현하기 전에 최소 기능의 서명된 probe app을 만든다. 이 gate가 통과하지 않으면 Phase 1 이후 구현을 시작하지 않고 입력 또는 배포 결정을 다시 검토한다.

### 5.1 Build profile

- stable bundle identifier `dev.badgerworks.trackpinch`를 사용한다.
- App Sandbox entitlement를 포함하지 않는다.
- Hardened Runtime을 활성화한다.
- Developer ID Application 인증서로 서명한다.
- 배포 artifact는 notarization과 stapling을 완료한다.
- 개발 build와 배포 build에서 bundle identity가 달라 TCC 승인이 초기화되지 않도록 scheme을 관리한다.

### 5.2 검증할 capability

| Capability | 확인 API/동작 | 실패 시 제품 동작 |
| --- | --- | --- |
| AX trust | `AXIsProcessTrustedWithOptions` | TrackPinch disabled, 모든 입력 통과 |
| Event listening | `CGPreflightListenEventAccess`, `CGRequestListenEventAccess` | TrackPinch disabled, 모든 입력 통과 |
| Active event tap | 실제 `.defaultTap` 생성 | degraded 상태, 모든 입력 통과 |
| Scroll suppression | callback에서 matching scroll에 `nil` 반환 | gate 실패 |
| Modifier chord | `.flagsChanged`, scroll event flags와 session flags 비교 | 해당 chord를 기본값으로 확정하지 않음 |
| AX resize | focused standard window의 size set/readback | gate 실패 또는 지원 범위 축소 |

AX prompt와 listen-access prompt는 비동기다. prompt 요청의 return value를 승인 결과로 취급하지 않으며, 앱 활성화 notification과 명시적 `Check Again` 동작에서 상태를 다시 읽는다.

### 5.3 TCC test matrix

다음 시나리오를 macOS 14, 15, 26에서 검증한다. 지원 대상 OS를 실제로 검증할 수 없다면 출시 전에 최소 배포 대상을 좁힌다. 개발 중인 차기 macOS beta는 정보성 smoke test이며 GA 전까지 release gate가 아니다.

| 시나리오 | AX read/write | Event listen | Event suppress | 기대 UI |
| --- | --- | --- | --- | --- |
| Clean install | 거부 | 거부 | 불가 | 두 권한을 구분해 안내 |
| Prompt 거부 | 거부 | 거부 | 불가 | disabled, Retry 제공 |
| Listen만 허용 | 거부 | 허용 | probe 결과 기록 | disabled |
| AX만 허용 | 허용 여부 기록 | probe 결과 기록 | probe 결과 기록 | capability별 상태 표시 |
| 필요한 권한 모두 허용 | 성공 | 성공 | 성공 | enabled 가능 |
| 실행 중 권한 회수 | 이후 호출 실패 | tap disable/failure | 불가 | capture 취소 후 degraded |
| 앱 update/relaunch | 승인 유지 여부 기록 | 승인 유지 여부 기록 | 성공 | 재승인 필요 여부 표시 |

clean user account를 우선 사용한다. TCC reset을 사용하는 경우에는 대상 bundle identifier와 변경되는 권한 범위를 QA 절차에 명시한다.

## 6. 사용자 interaction

### 6.1 기본 조작

기본 modifier는 Control+Option+Command다. Fn/Globe는 지원되는 keyboard에서 선택 가능한 modifier로 유지한다.

| 물리적 손가락 이동 | 결과 |
| --- | --- |
| 오른쪽 | 폭 증가 |
| 왼쪽 | 폭 감소 |
| 아래 | 높이 증가 |
| 위 | 높이 감소 |
| 대각선 | 폭과 높이를 동시에 변경 |

입력 방향은 macOS의 `Natural scrolling` 설정과 무관하게 동일해야 한다.

### 6.2 Resize anchor

TrackPinch는 대상 window의 size만 쓴다. 따라서 대상 앱이 position을 자체 변경하지 않는 일반적인 경우 좌측 상단이 고정되고 우측 하단 모서리를 움직이는 것처럼 보인다.

- TrackPinch는 position을 원래 값으로 되돌리거나 화면 안으로 이동시키지 않는다.
- 대상 앱이 resize에 반응해 position을 변경하면 그 결과를 존중한다.
- 크기 하한은 폭 160 pt, 높이 120 pt다.
- 구현 안전 상한은 각 축 16,384 pt다.
- display visible frame을 기준으로 한 최대 크기 제한은 MVP에 두지 않는다.

## 7. Modifier contract

### 7.1 설정 가능한 modifier

- Function
- Control
- Option
- Command
- Shift
- 위 modifier들의 조합

### 7.2 Normalization

입력 비교 전에 event flags를 다음 집합으로 제한한다.

```text
Function | Control | Option | Command | Shift
```

- Caps Lock, Numeric Pad, Help, device-dependent 및 non-coalesced bit는 비교에서 제외한다.
- 정규화한 현재 집합이 설정 집합과 정확히 같을 때만 match다.
- 설정하지 않은 지원 modifier가 추가로 눌리면 match가 아니다.
- Fn/Globe는 내장 keyboard와 외장 Apple keyboard에서 Phase 0으로 검증한다.
- 외장 keyboard에 Function flag가 없다면 Fn 설정은 해당 keyboard에서 지원하지 않는 것으로 안내한다.

`.flagsChanged` event는 modifier 상태를 갱신하지만 항상 원래대로 통과시킨다.

## 8. Event tap contract

### 8.1 고정 구성

```text
location:  .cgSessionEventTap
placement: .headInsertEventTap
options:   .defaultTap
mask:      scrollWheel | flagsChanged
thread:    dedicated event-tap thread with CFRunLoop
```

- root 권한이 필요한 HID event tap을 사용하지 않는다.
- callback은 dedicated thread에서 직렬로 실행한다.
- consume/pass 결정과 capture state 전이는 이 thread에서 동기적으로 끝낸다.
- callback에서 AX API, `NSWorkspace` query, disk I/O 또는 main-thread sync dispatch를 수행하지 않는다.
- callback의 scroll 반환값은 consume이면 `nil`, pass이면 원래 `CGEvent`다.

### 8.2 Event decoding

scroll callback에서 `NSEvent(cgEvent:)`를 생성하고 다음 규칙을 적용한다.

- idle 상태에서 새 capture를 시작하려면 `hasPreciseScrollingDeltas == true`여야 한다.
- delta source는 `scrollingDeltaX`와 `scrollingDeltaY`다.
- `scrollingDeltaX/Y`는 content-scroll 방향이므로 finger movement로 변환할 때 두 delta의 부호를 반전한다.
- `isDirectionInvertedFromDevice`가 true인 event에는 위 반전을 상쇄해 Natural Scrolling on/off에서 동일한 `fingerDelta`를 만든다.
- decoder output은 `fingerDelta`로 명명하며, 양의 X는 손가락 오른쪽, 양의 Y는 손가락 아래쪽이라는 contract를 갖는다.
- Phase 0 hardware QA에서 양축 sign mapping을 확정했으며 code constant와 fixture에 기록한다.
- `momentumPhase`가 빈 집합이 아니면 size delta로 사용하지 않는다.
- `phase == .none`인 event는 idle에서 capture를 시작하지 않는다.
- `.stationary`는 delta 0의 physical event로 취급한다.

Phase 0 이후에는 sign mapping을 runtime heuristic이나 사용자 scroll 설정에 따라 바꾸지 않는다.

### 8.3 Device scope

MVP가 요구하는 입력은 `phased precision scroll`이다.

- 내장 MacBook trackpad와 Magic Trackpad를 필수 QA 대상으로 한다.
- Magic Mouse가 동일한 phased precision event를 만들면 TrackPinch가 동작하는 것을 허용한다.
- precise event를 만드는 제3자 mouse도 동작할 수 있으며 device별 보장은 하지 않는다.
- idle에서 `.none` phase만 만드는 legacy wheel은 통과시킨다.

## 9. Capture state machine

scroll event의 소유권과 resize 가능 여부를 하나의 `CaptureStateMachine`이 결정한다. `InputMonitor`와 `ResizeSession`이 별도로 소유권을 판단하지 않는다.

### 9.1 State

| State | 의미 |
| --- | --- |
| `idle` | TrackPinch가 소유한 gesture 없음 |
| `resolvingTarget` | gesture를 소유했고 AX 대상 검증 중 |
| `classifying` | 대상은 유효하며 dead zone과 축을 판정 중 |
| `resizing` | 대상 window에 size update 적용 중 |
| `swallowing` | resize는 중단했지만 남은 physical event를 소비 중 |
| `drainingMomentum` | physical sequence가 끝나 연결된 momentum을 배출 중 |

event tap health는 capture state와 분리된 `healthy | degraded` 상태다. `degraded`에서는 새 capture를 시작하지 않는다.

### 9.2 Idle에서 소유권 획득

다음 조건을 모두 만족하는 `.mayBegin` 또는 `.began` scroll에서만 새 capture를 시작한다.

- TrackPinch enabled
- event tap healthy
- 필요한 permission state 충족
- normalized modifier가 설정과 정확히 일치
- precise scrolling delta
- `momentumPhase`가 비어 있음
- cached frontmost PID가 TrackPinch 자신이 아님

조건이 맞으면 generation token을 만들고 cached frontmost PID를 snapshot한 뒤 `resolvingTarget`으로 전이한다. 이 첫 event부터 소비한다.

idle에서 받은 `.changed`, `.ended`, `.cancelled`, `.stationary`, `.none` 또는 momentum event로는 capture를 중간부터 시작하지 않고 통과시킨다.

### 9.3 Target resolution

`FrontmostAppTracker`는 `NSWorkspace` activation notification을 main thread에서 받아 최신 PID를 atomic snapshot으로 유지한다. event-tap callback은 이 cached PID만 읽는다.

AX executor가 generation token과 PID를 받아 대상 window를 검증한다.

- eligible이면 `classifying`으로 전이한다.
- window가 없거나 eligible하지 않으면 `swallowing`으로 전이한다.
- capture가 이미 끝났거나 generation이 바뀌었으면 결과를 폐기한다.

target resolution 중 들어온 physical scroll은 모두 소비하되 resize delta는 적용하지 않는다.

### 9.4 Modifier release와 오류

active capture 중 `.flagsChanged`로 configured modifier match가 깨지면 즉시 다음을 수행한다.

- 새 AX update 생성 중단
- pending AX update 폐기
- generation invalidation
- `swallowing` 전이

modifier release는 resize만 끝낸다. 이미 소유한 scroll sequence의 event를 원래 앱으로 다시 보내지 않는다.

unsupported target, AX timeout, AX invalid element 및 permission revocation도 같은 `swallowing` 경로를 사용한다.

### 9.5 Physical end와 momentum drain

- owning state에서 physical `.ended` 또는 `.cancelled`를 받으면 event를 소비하고 `drainingMomentum`으로 전이한다.
- `drainingMomentum`에서 연결된 momentum `.began`, `.changed`, `.ended`, `.cancelled`를 모두 소비한다.
- momentum delta는 window size에 적용하지 않는다.
- momentum `.ended` 또는 `.cancelled`에서 `idle`로 전이한다.
- physical end 후 300 ms 안에 momentum이 시작하지 않으면 `idle`로 전이한다.
- drain 대기 중 새로운 matching physical `.mayBegin` 또는 `.began`이 오면 새 generation으로 즉시 capture를 시작하고 event를 소비한다.
- drain 대기 중 새로운 nonmatching physical `.mayBegin` 또는 `.began`이 오면 이전 capture를 종료하고 새 event는 통과시킨다.
- `resizing` 또는 `swallowing`에서 종료 event가 손실된 경우를 위한 recovery timeout은 마지막 소유 event로부터 5초다. timeout 시 pending work를 취소하고 `idle`로 fail-open한 뒤, 현재 event를 새 입력으로 다시 판정한다.

### 9.6 Consume/pass decision table

| 현재 상태 | Event | 결정 |
| --- | --- | --- |
| `idle` | 조건이 맞는 precise physical `.mayBegin/.began` | consume, 새 capture |
| `idle` | nonmatching modifier 또는 non-precise event | pass |
| `idle` | `.changed/.ended/.cancelled/.none` | pass |
| `idle` | momentum event | pass |
| `resolvingTarget/classifying/resizing/swallowing` | 모든 scroll event | consume |
| `drainingMomentum` | momentum 또는 이전 sequence의 tail | consume |
| `drainingMomentum` | matching physical `.mayBegin/.began` | consume, 새 capture |
| `drainingMomentum` | nonmatching physical `.mayBegin/.began` | pass, 이전 capture 종료 |
| owning state | `flagsChanged` | pass, modifier 상태만 반영 |
| `degraded` | 모든 일반 event | pass |

한 sequence에서 event 일부를 소비한 뒤 나머지를 pass하는 구현은 허용하지 않는다. 예외는 5초 recovery timeout처럼 event stream 자체가 손실된 경우뿐이다.

## 10. Gesture classification과 resize 계산

### 10.1 Dead zone과 mode lock

- `.began`과 `.changed`의 `fingerDelta`만 누적한다.
- 초기 누적 이동 거리 8 pt까지는 size를 변경하지 않는다.
- `abs(x) >= 1.5 * abs(y)`이면 horizontal mode다.
- `abs(y) >= 1.5 * abs(x)`이면 vertical mode다.
- 그 외에는 diagonal mode다.
- mode를 정하면 dead-zone 누적 delta를 버리고 계산 baseline을 0으로 reset한다.
- 한 capture generation 안에서는 mode를 바꾸지 않는다.

### 10.2 Delta mapping

```text
horizontal: width  += fingerDelta.x * sensitivity
vertical:   height += fingerDelta.y * sensitivity
diagonal:   width  += fingerDelta.x * sensitivity
            height += fingerDelta.y * sensitivity
```

- sensitivity 기본값은 1.0이다.
- 설정 범위는 0.5에서 3.0이다.
- MVP에서는 가로와 세로에 하나의 공통 sensitivity를 적용한다.
- 계산 단위는 macOS point다.
- 결과는 160 x 120 pt와 16,384 x 16,384 pt 사이로 clamp한다.

## 11. 대상 윈도우 contract

### 11.1 선택 순서

1. capture 시작 시 snapshot한 PID로 application AX element를 만든다.
2. `kAXFocusedWindowAttribute`를 조회한다.
3. 없으면 `kAXMainWindowAttribute`를 fallback으로 조회한다.
4. 둘 다 없으면 unsupported다.

### 11.2 Eligibility algorithm

다음 조건을 순서대로 모두 만족해야 한다.

1. PID가 TrackPinch 자신이 아니다.
2. element role이 `kAXWindowRole`이다.
3. subrole이 `kAXStandardWindowSubrole`이다.
4. `kAXMinimizedAttribute`가 true가 아니다.
5. `kAXPositionAttribute`와 `kAXSizeAttribute`를 읽을 수 있다.
6. `kAXSizeAttribute`가 settable이다.
7. 시작 width와 height가 finite이고 0보다 크다.

dialog, sheet, panel 또는 subrole이 없거나 다른 window는 MVP에서 unsupported로 처리한다.

공개 SDK에 없는 fullscreen attribute를 사용하지 않는다. fullscreen/tiled window가 위 조건을 통과하더라도 앱이 size request를 무시하거나 다른 값으로 clamp할 수 있다. 이 경우 actual-size readback 규칙으로 처리하며 보편적인 fullscreen 판정을 보장하지 않는다.

### 11.3 Requested size와 actual size

- 각 update는 마지막으로 확인한 actual size에 incremental delta를 적용한다.
- `AXUIElementSetAttributeValue` 성공 후 `kAXSizeAttribute`를 다시 읽는다.
- actual size가 requested size와 0.5 pt 이상 다르면 actual size를 새 baseline으로 사용한다.
- 앱이 적용하지 않은 overshoot는 버리고 다음 반대 방향 입력에 이월하지 않는다.
- readback이 실패하면 해당 capture의 resize를 중단하고 `swallowing`으로 전이한다.
- target element가 invalid해지면 retry하지 않고 capture를 종료한다.

이 규칙은 앱의 최소·최대 크기 clamp에서 발생하는 hysteresis를 방지한다.

## 12. AX execution contract

AX 작업은 event-tap thread와 main thread에서 분리된 전용 serial executor가 담당한다.

- logical AX update는 동시에 최대 하나만 in-flight다.
- in-flight 동안 새 delta가 오면 request queue에 append하지 않고 하나의 `pendingDelta` vector에 누적한다.
- in-flight update가 끝나면 actual-size baseline에 `pendingDelta`를 적용해 다음 latest desired size 하나를 만든다.
- completed request가 앱에 의해 clamp됐을 때는 그 request의 unapplied overshoot만 버리고, 완료 이후 도착한 `pendingDelta`는 보존한다.
- 모든 request와 response에 capture generation token을 포함한다.
- call 전후에 token을 확인해 stale update를 폐기한다.
- application AX element의 messaging timeout 기본값은 0.25초다.
- timeout은 해당 capture에서 retry하지 않고 `swallowing`으로 전이한다.
- set과 readback을 하나의 logical update로 취급한다.
- logical update 발행 빈도는 최대 60 Hz다.
- callback, AX executor 및 main UI 사이에 synchronous cross-thread wait를 두지 않는다.

0.25초 timeout이 지원 앱에서 반복적으로 false failure를 만들면 Phase 0/QA 측정 결과와 함께 이 문서를 개정한다.

## 13. 권한과 runtime health

### 13.1 Permission state

`PermissionManager`는 하나의 generic Boolean 대신 다음 상태를 각각 제공한다.

- `axTrusted`
- `listenAccess`
- `eventTapCreation`
- `eventTapHealth`
- `loginItemStatus`

새 capture는 AX trust, listen access, active tap creation 및 healthy tap을 모두 만족할 때만 가능하다.

사용자가 저장한 enabled 설정과 실제 입력 소유 가능 상태는 분리한다. 권한 또는 tap health가 준비되지 않은 동안에는 enabled 설정을 보존하되 새 gesture를 소비하지 않는다. 이미 소유한 gesture 도중 조건이 사라지면 AX update만 취소하고 남은 physical sequence와 연결된 momentum을 drain한다.

### 13.2 Event tap recovery

`tapDisabledByTimeout`을 받으면 다음과 같이 처리한다.

1. 첫 timeout에서는 pending AX work만 취소하고 capture를 `swallowing`으로 전이해 이미 소유한 gesture의 tail이 원래 앱으로 새지 않게 한다.
2. 한 번 즉시 `CGEvent.tapEnable`을 시도하고 `CGEvent.tapIsEnabled`가 true일 때만 health를 `running`으로 복구한다.
3. tap이 없거나 실제 enable에 실패하면 capture를 해제하고 `degraded`로 전이한다.
4. 10초 안에 timeout disable이 두 번 발생하면 capture를 해제하고 `degraded`로 전이한다.
5. degraded에서는 자동 retry하지 않고 메뉴의 `Retry Input Monitor`를 기다린다.

`tapDisabledByUserInput`을 받으면 즉시 degraded로 전이하며 자동 enable loop를 만들지 않는다.

사용자 retry는 기존 event-tap thread의 실제 teardown 완료를 기다린 뒤 새 thread를 시작한다. 고정 지연으로 종료를 추정하지 않는다. 새 tap 설치도 `CGEvent.tapIsEnabled`가 true인 경우에만 `running`으로 게시한다.

tap health가 불확실하거나 degraded인 동안 TrackPinch는 event를 소비하지 않는다.

### 13.3 Privacy

- Screen Recording 권한을 요청하지 않는다.
- keyDown/keyUp event를 tap mask에 넣지 않는다.
- flagsChanged에서 문자나 key content를 수집하지 않는다.
- scroll delta, 대상 앱 및 window 정보를 영구 저장하거나 외부 전송하지 않는다.

## 14. 메뉴 막대와 설정

AppKit `NSStatusItem`이 SwiftUI 설정 view를 담은 transient `NSPopover`를 표시한다. status item 표시와 popover lifecycle만 AppKit이 담당하고, 설정과 runtime 상태의 source of truth는 SwiftUI observable model에 둔다.

### 14.1 메뉴 기능

- `LSUIElement` menu bar utility로 실행하며 기본 상태에서 Dock icon을 표시하지 않음
- TrackPinch enabled toggle
- modifier 설정
- 0.5x부터 3.0x까지의 공통 sensitivity slider와 기본값 reset
- Accessibility 상태
- Input Listening 상태
- Event Tap health와 retry
- 접을 수 있는 runtime diagnostics와 AX resize test
- Quit

첫 실행에서는 설정 popover를 한 번 자동으로 표시하고 다음 2단계 onboarding을 제공한다.

1. Accessibility와 Input Monitoring의 용도, 현재 승인 상태 및 Settings 진입
2. modifier와 수평/수직/대각선 gesture 결과 안내

onboarding을 완료하기 전에도 status toggle과 diagnostics에는 접근할 수 있다. 권한이 준비되지 않은 동안에는 TrackPinch가 새 scroll sequence를 소비하지 않는다.

### 14.2 설정 저장

다음 값은 `UserDefaults`를 source of truth로 사용한다.

- enabled
- modifier set
- sensitivity
- onboarding 최초 표시 여부
- onboarding 완료 여부

로그인 시 실행은 단순 Boolean만 저장하지 않는다.

- `SMAppService.mainApp`으로 register/unregister한다.
- UI는 `SMAppService.status`를 source of truth로 표시한다.
- requested setting과 실제 status가 다르면 `requiresApproval`, error 또는 external change를 표시한다.
- 앱 활성화 시 actual status를 다시 읽는다.

## 15. Component topology

```text
NSWorkspace notifications
  -> FrontmostAppTracker
  -> atomic PID snapshot

CGEventTap thread
  -> EventDecoder
  -> CaptureStateMachine
  -> synchronous consume/pass
       |
       +-> AXExecutor (generation-tagged async work)
       +-> RuntimeStateStore

NSStatusItem / SwiftUI Popover
  -> SettingsStore
  -> PermissionManager
  -> LoginItemController
  -> RuntimeStateStore
```

### 15.1 Ownership

| Component | 단일 책임 |
| --- | --- |
| `FrontmostAppTracker` | main-thread app activation을 cached PID로 변환 |
| `EventDecoder` | CG/NSEvent를 normalized modifier, phase, `fingerDelta`로 변환 |
| `CaptureStateMachine` | gesture ownership, state transition, consume/pass 결정 |
| `AXExecutor` | target eligibility, size set/readback, timeout과 stale result 처리 |
| `SettingsStore` | 사용자 interaction 설정 |
| `PermissionManager` | AX/listen/tap capability와 health 제공 |
| `LoginItemController` | `SMAppService` lifecycle |
| `RuntimeStateStore` | 메뉴 UI에 비동기 runtime 상태 전달 |

## 16. 성능 기준

`os_signpost`로 다음 구간을 측정한다.

- `captureClaimed`: 첫 event를 consume한 시점
- `targetResolved`: eligible window 확인 시점
- `firstSizeApplied`: 첫 successful set/readback 완료 시점
- `captureEnded`: state가 idle로 돌아온 시점

지원 앱과 기준 개발 Mac에서 다음을 만족해야 한다.

- event-tap callback duration p99가 1 ms 미만
- `captureClaimed`에서 `firstSizeApplied`까지 median 50 ms 이하
- 같은 구간 p95 100 ms 이하
- AX logical queue depth 최대 1
- 10초 resize 중 main-thread hang 0회

대상 앱 자체의 AX 응답 지연은 signpost 결과에 별도로 표시한다. 성능 기준을 충족하지 못하는 앱은 지원 matrix에 예외로 기록하고 전체 callback을 느리게 만들지 않는다.

## 17. Test strategy

### 17.1 Unit tests

table-driven fixture로 다음을 검증한다.

- `.mayBegin -> .began -> .changed -> .ended`와 no-momentum drain
- physical end 후 momentum begin/change/end
- modifier release 중간 발생
- target resolution success, unsupported, delayed stale result
- AX timeout과 invalid element
- event stream이 `.changed`부터 관찰된 경우 pass
- `.none` phase legacy event pass
- Natural scrolling on/off에서 동일한 `fingerDelta`
- exact modifier normalization과 Caps Lock 무시
- dead zone 이후 mode lock과 dead-zone delta discard
- horizontal, vertical, diagonal mapping
- app clamp readback 후 overshoot discard
- 5초 recovery timeout
- tap disable recovery와 degraded 전이

### 17.2 Integration tests

fake `WindowController`/AX adapter로 다음을 검증한다.

- 한 번에 하나의 logical AX request만 실행
- in-flight 중 latest desired size replacement
- stale generation response가 다음 window에 적용되지 않음
- modifier release 후 pending update 폐기
- unsupported capture에서도 physical/momentum 전체 consume
- set 성공/readback 실패 시 swallowing 전이
- event-tap retry가 기존 thread teardown 완료 뒤 한 번만 재시작
- 첫 timeout 복구 중 physical/momentum tail 소유권 유지

### 17.3 Signed-build manual QA

#### 앱

- Safari
- Finder
- Terminal
- Notes
- Xcode
- Chromium 기반 앱

#### 입력 장치

- 내장 MacBook trackpad
- Magic Trackpad
- Magic Mouse의 허용된 동작 기록
- Natural scrolling on/off
- built-in Fn/Globe
- 외장 Apple keyboard의 Fn/Globe
- 내장 및 Bluetooth keyboard의 Control+Option+Command chord

#### Window 상태

- focused standard window
- 복수 window를 가진 앱
- 앱 최소/최대 size clamp
- minimized window
- dialog, sheet, panel
- fullscreen 및 tiled window
- gesture 도중 window close와 앱 종료

#### Gesture sequence

- 느린 horizontal, vertical, diagonal gesture
- 빠른 flick와 momentum
- modifier를 먼저 놓는 경우
- finger를 먼저 놓는 경우
- modifier를 누른 채 연속 두 gesture
- target resolution 전에 gesture가 끝나는 경우

### 17.4 Scroll suppression test

1. 대상 앱에서 content offset을 수치로 확인할 수 있는 긴 test document를 연다.
2. 시작 offset과 window size를 기록한다.
3. TrackPinch gesture를 수행하고 physical 및 momentum 종료를 기다린다.
4. window size는 예상 축과 방향으로 변경돼야 한다.
5. content offset은 시작값과 같아야 한다.
6. modifier 없이 같은 gesture를 수행하면 content가 정상 scroll돼야 한다.

### 17.5 Multi-display test

TrackPinch는 AX position을 쓰지 않는다. 단일/복수 display와 서로 다른 scale에서 resize 전후 position을 읽어 TrackPinch가 position write를 발생시키지 않았음을 log로 확인한다. 대상 앱이 자체적으로 position을 변경한 경우에는 별도 관찰 결과로 기록한다.

## 18. MVP acceptance criteria

- Phase 0 TCC matrix가 지원 OS에서 기록되고 필요한 capability가 통과한다.
- matching gesture의 첫 claimed event부터 physical/momentum 끝까지 content offset이 변하지 않는다.
- modifier 없는 scroll event는 content offset을 정상적으로 변경한다.
- horizontal mode에서 width만, vertical mode에서 height만 변경된다.
- diagonal mode에서 width와 height가 각각 입력 부호대로 변경된다.
- Natural scrolling on/off가 resize 방향을 바꾸지 않는다.
- modifier release 즉시 새 AX update가 중단되며 남은 gesture는 원래 앱으로 새지 않는다.
- unsupported window와 AX error에서 crash 또는 main-thread hang이 없다.
- 앱 clamp 후 반대 방향 입력이 즉시 크기를 되돌리며 overshoot hysteresis가 없다.
- event tap timeout/user disable이 무한 retry loop를 만들지 않는다.
- 로그인 시 실행 UI가 `SMAppService.status`와 일치한다.
- 성능 기준과 signed-build manual QA 결과가 release artifact에 연결된다.

## 19. 구현 순서

### Phase 0. Capability probe

- signed unsandboxed app identity 확정
- TCC matrix 실행
- 기본 modifier chord와 precision scroll sign 기록
- Fn/Globe의 keyboard별 전달 여부 기록
- active suppression과 AX resize 확인

### Phase 1. Pure input core

- `EventDecoder`
- `CaptureStateMachine`
- table-driven unit tests
- fake AX adapter

### Phase 2. macOS integration

- production `CGEventTap`
- `FrontmostAppTracker`
- `AXExecutor`
- permission/runtime health

### Phase 3. Utility UI

- NSStatusItem과 SwiftUI settings popover
- onboarding
- `SMAppService` login item

### Phase 4. Release QA

- supported OS/device/app matrix
- performance signposts
- Developer ID archive, notarization, stapling

## 20. 후속 후보

- [Axis-aware pinch spike](./spikes/axis-aware-pinch.md)
- cursor 아래 window를 대상으로 선택하는 mode
- 중앙 기준 대칭 resize 또는 cursor 위치 기반 anchor
- resize 중 현재 크기를 표시하는 HUD
- window 이동 및 snap gesture
- 앱별 sensitivity와 제외 목록
- 키보드 shortcut을 이용한 정확한 크기 입력

## 21. 참고 자료

- [Apple - Handling Trackpad Events](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/HandlingTouchEvents/HandlingTouchEvents.html)
- [Apple - NSEvent phase](https://developer.apple.com/documentation/appkit/nsevent/phase-swift.property)
- [Apple - NSEvent momentumPhase](https://developer.apple.com/documentation/appkit/nsevent/momentumphase)
- [Apple - NSEvent direction inversion](https://developer.apple.com/documentation/appkit/nsevent/isdirectioninvertedfromdevice)
- [Apple - CGEventTapCreate](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate%28tap%3Aplace%3Aoptions%3Aeventsofinterest%3Acallback%3Auserinfo%3A%29)
- [Apple - CGEvent tap locations](https://developer.apple.com/documentation/coregraphics/cgeventtaplocation)
- [Apple - CG listen preflight](https://developer.apple.com/documentation/coregraphics/cgpreflightlisteneventaccess%28%29)
- [Apple - AX trust](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions)
- [Apple - AXUIElement](https://developer.apple.com/documentation/applicationservices/axuielement_h)
- [Apple - AX messaging timeout](https://developer.apple.com/documentation/applicationservices/1459345-axuielementsetmessagingtimeout)
- [Apple - SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [Apple - App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)
