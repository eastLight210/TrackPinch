# Phase 0 capability probe 사용법

## 목적

TrackPinch 전체 기능을 구현하기 전에 현재 Mac에서 다음 capability를 실제 app bundle identity로 검증한다.

- Accessibility trust와 AX focused-window size write
- Input Monitoring listen access
- active `CGEventTap` 생성
- Control+Option+Command modifier chord와 precision scroll event 관찰
- Control+Option+Command-modified scroll sequence 전체 suppression
- captured foreground window의 연속 AX size 변경

## Build와 실행 gate

현재는 Xcode 27 beta와 macOS 27 SDK로 compile과 bundle 생성을 먼저 확인한다.

```bash
./script/build_and_run.sh --build-only
```

Xcode 26.6과 macOS 26.5 SDK로 비교하려면 다음 명령을 사용한다.

```bash
TRACKPINCH_XCODE=stable ./script/build_and_run.sh --build-only
```

`DEVELOPER_DIR`를 직접 지정하면 `TRACKPINCH_XCODE`보다 우선한다.

기본 build script는 설치된 identity를 다음 순서로 선택한다.

1. Developer ID Application
2. ad hoc

로컬 실행에서는 다음처럼 opt-in한다.

```bash
TRACKPINCH_LOCAL_DEVELOPMENT=1 ./script/build_and_run.sh --verify
```

이 모드는 `security find-identity`에서 `CSSMERR` 또는 `REVOKED`가 없는 Apple Development identity만 선택한다. 실행 전 bundle signature를 다시 검증하고 quarantine attribute가 있으면 앱을 열지 않는다. `CODESIGN_IDENTITY`로 identity를 직접 지정할 수도 있다.

현재 선택된 identity와 SDK는 build 마지막에 출력된다. ad hoc build는 compile과 test 확인에만 사용한다. Apple Development는 이 Mac의 로컬 probe에만 사용한다. 외부 배포 capability gate는 trusted Developer ID Application signature, Hardened Runtime, secure timestamp, notarization을 갖춘 뒤 별도로 진행한다.

Developer ID Application으로 서명된 경우 다음 명령은 build 후 Gatekeeper 평가를 먼저 수행한다. 평가가 실패하면 app을 열지 않는다.

```bash
./script/build_and_run.sh --verify
```

2026-08-06 사용했던 Apple Development identity는 `CSSMERR_TP_CERT_REVOKED`로 거부되었다. 2026-08-07 Personal Team에서 이 Mac용 identity를 새로 발급했으며, build script는 revoked identity를 선택하지 않는다.

## 권한 요청

앱 실행 후 menu bar의 TrackPinch resize icon을 눌러 설정 popover를 연다.

1. `Grant Missing Permissions`를 선택한다.
2. 아직 허용되지 않은 첫 번째 권한의 System Settings pane이 열린다.
3. System Settings에서 TrackPinch를 허용한다.
4. 다른 권한도 아직 허용되지 않았다면 `Grant Missing Permissions`를 다시 선택한다.
5. 필요하면 각 권한 옆의 `Open Settings`로 해당 pane을 직접 연다.
6. TrackPinch popover를 다시 열어 두 권한 상태를 확인한다.
7. 필요하면 `Diagnostics`를 펼쳐 `Retry Monitor`를 선택한다.

권한 prompt는 비동기이고 TCC가 이미 판단한 app에는 다시 표시되지 않을 수 있다. 그래서 probe는 prompt API 호출 후에도 권한이 없으면 해당 System Settings pane을 직접 연다. 두 권한이 모두 허용되면 `Grant Missing Permissions` button은 popover에서 사라진다.

## Live resize와 input suppression probe

1. Safari 같은 앱에서 긴 scrollable document를 연다.
2. window의 시작 크기와 content 위치를 기억한다.
3. TrackPinch toggle을 켜고 modifier가 Control+Option+Command인지 확인한다.
4. Control+Option+Command를 모두 누른 채 트랙패드로 한 번 scroll한다.
5. 첫 8 pt dead zone 이후 가로 입력은 폭만, 세로 입력은 높이만, 대각선 입력은 두 축을 변경하는지 확인한다. 손가락을 오른쪽/아래로 움직이면 크기가 증가하고 왼쪽/위로 움직이면 감소해야 한다.
6. `Diagnostics`를 펼쳐 `Last input`이 `consume`인지, `Live resize`가 mode와 적용된 size를 기록했는지 확인한다.
7. 원래 document가 움직이지 않았는지 확인한다.
8. modifier 없이 scroll해 정상적으로 움직이는지 확인한다.
9. probe가 끝나면 TrackPinch toggle을 끈다.

live resize는 사용자가 toggle을 켠 동안에만 새 gesture를 소유한다. 이미 소유한 gesture는 toggle을 끄거나 modifier chord를 놓더라도 끝까지 배출해 event 일부가 원래 앱으로 새지 않게 한다. modifier chord를 먼저 놓으면 새 AX update는 중단된다.

## AX resize probe

1. 크기 변경 가능한 일반 window를 활성화한다.
2. TrackPinch popover를 열고 `Diagnostics`를 펼친다.
3. `Target`이 원하는 앱인지 확인한다.
4. `Test Resize`를 선택한다.
5. window가 가로·세로로 20 pt 커졌다가 약 0.4초 뒤 원래 크기로 돌아오는지 확인한다.
6. `Last AX probe`에서 requested, applied, restore 결과를 확인한다.

이 action은 사용자가 명시적으로 선택했을 때만 실행한다. 대상 window가 닫히거나 앱이 응답하지 않으면 restore가 실패할 수 있으므로 중요한 작업 중인 window에서는 실행하지 않는다.

## Log 확인

```bash
TRACKPINCH_LOCAL_DEVELOPMENT=1 ./script/build_and_run.sh --telemetry
```

event delta, phase, momentum, modifier와 consume/pass 결과가 `dev.badgerworks.trackpinch` subsystem에 기록된다. 문자 key event는 수집하지 않는다.
