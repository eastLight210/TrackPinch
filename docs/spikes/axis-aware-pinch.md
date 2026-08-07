# Axis-aware pinch 기술 실험

- 상태: Deferred
- MVP 포함 여부: 포함하지 않음
- Release gate 여부: 아님
- 마지막 갱신: 2026-08-05

## 1. 목적

두 손가락을 같은 방향으로 이동하는 precision scroll 대신, 두 손가락 사이의 실제 X/Y 간격 변화로 윈도우의 폭과 높이를 조절할 수 있는지 공개 macOS API만으로 검증한다.

```text
X 간격 증가/감소 -> width 증가/감소
Y 간격 증가/감소 -> height 증가/감소
X/Y 동시 변화   -> diagonal resize
```

표준 magnify event는 하나의 `magnification` scalar만 제공하므로 축별 간격을 구분할 수 없다. 이 실험은 raw `NSTouch` position을 안정적으로 받을 수 있는지를 확인한다.

## 2. 가설

modifier down 시 cursor가 있는 display 위에 투명한 non-activating `NSPanel`을 표시하면 원래 앱의 activation을 바꾸지 않으면서 panel의 custom `NSView`가 raw touch sequence를 받을 수 있다.

## 3. 실험 범위

1. modifier down 전에 현재 focused window와 frontmost PID를 snapshot한다.
2. cursor가 있는 display 위에 투명한 non-activating panel을 표시한다.
3. panel의 custom view에서 touch event를 허용한다.
4. 두 `NSTouch`의 `identity`와 `normalizedPosition`을 sequence 전체에서 추적한다.
5. 두 touch 사이 X/Y distance delta를 기록한다.
6. modifier up 또는 touch end에서 panel을 제거한다.
7. 원래 app focus, menu bar, scroll/zoom 동작과 event leakage를 측정한다.

이 단계에서는 실제 window resize를 구현하지 않는다. 먼저 입력 capture의 안정성만 검증한다.

## 4. 통과 조건

- 원래 앱의 focus와 menu bar가 바뀌지 않는다.
- 첫 finger down부터 마지막 finger up까지 두 touch identity를 안정적으로 유지한다.
- horizontal, vertical, diagonal separation을 반복해서 구분할 수 있다.
- 원래 앱의 zoom, scroll 또는 gesture가 동시에 실행되지 않는다.
- modifier를 놓는 즉시 panel이 제거되고 일반 입력이 복구된다.
- 복수 display와 Space에서 보이지 않는 입력 차단 영역을 남기지 않는다.
- Mission Control, fullscreen Space 및 screen lock 전환 후 capture가 정상 복구된다.
- private framework 없이 Developer ID signing과 notarization이 가능하다.

## 5. 실패 조건

다음 중 하나라도 발생하면 이 접근은 제품 기능으로 채택하지 않는다.

- panel을 표시할 때 app activation 또는 keyboard focus가 바뀜
- raw touch가 active app에만 전달돼 panel에서 sequence를 받지 못함
- 원래 앱과 TrackPinch가 동일 gesture를 함께 처리함
- touch identity 또는 phase가 반복적으로 손실됨
- 복수 display/Space에서 panel이 입력을 가로막은 채 남음
- private API나 undocumented framework가 필요함

## 6. 명시적 금지 사항

- private `MultitouchSupport` framework 사용
- undocumented IOHID multitouch packet parsing
- Mac App Store review를 피하기 위한 동작 은폐
- MVP core에 실험용 overlay component를 미리 추가

## 7. 결과 기록 형식

실험을 실행하면 이 문서에 결론을 바로 덮어쓰지 않고 별도 결과 문서를 추가한다.

```text
docs/spikes/results/axis-aware-pinch-YYYY-MM-DD.md
```

결과에는 다음을 포함한다.

- macOS version과 hardware
- signed build identity
- permission 상태
- 각 통과 조건의 관찰 결과
- focus와 event routing log
- 채택/보류/폐기 결론

## 8. 참고 자료

- [Apple - Handling Trackpad Events](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/HandlingTouchEvents/HandlingTouchEvents.html)
- [Apple - NSEvent magnification](https://developer.apple.com/documentation/appkit/nsevent/magnification)
- [Apple - NSTouch](https://developer.apple.com/documentation/appkit/nstouch)
